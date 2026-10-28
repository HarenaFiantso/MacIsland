# MacIsland — Architecture

MacIsland is a native macOS app (Swift 5 language mode, SwiftUI + AppKit, macOS 14+)
that turns the MacBook notch into a Dynamic Island. This document describes the layers,
the event flow and the technical decisions that matter.

## Overview

```
┌───────────────────────────────────────────────────────────────────────┐
│ MacIslandApp (SwiftUI App)        MenuBarExtra (status item)          │
│   └─ AppDelegate ─► AppCoordinator (composition root, @MainActor)     │
│         ├─ Preferences (UserDefaults, ObservableObject)               │
│         ├─ Services: MediaService · ShelfStore · CalendarService       │
│         │            BatteryService · AudioVolumeService · TimerModel  │
│         │            SoundService · ScreenStateService                 │
│         │            LaunchAtLoginService · NotificationService        │
│         ├─ LiveActivityCenter (transient + sticky activity queue)     │
│         ├─ CalendarAlertScheduler (event-start activity + sound)      │
│         ├─ EventMonitor (outside clicks, Escape)                      │
│         └─ NotchWindowManager ── one IslandWindowController per screen│
│                ├─ IslandSpace (private window-server Space)           │
│                                     ├─ IslandPanel (NSPanel)          │
│                                     ├─ IslandHostingView (NSHostingView)│
│                                     └─ IslandViewModel (@Observable)  │
│                                           └─ IslandStateMachine (IslandCore)│
└───────────────────────────────────────────────────────────────────────┘
```

- **`Packages/IslandCore`** — Swift package with no UI dependency: `IslandStateMachine`,
  `IslandGeometry` (`NotchGeometry`, `IslandMetrics`, `IslandLayout`), `SpringSpec`.
  Covered by `swift test` (27 tests, under 10 ms).
- **`MacIsland/Core`** — AppKit glue: screen detection, panel, hit testing, hover,
  event monitors, the per-screen view model, spring → `Animation` conversion.
- **`MacIsland/UI`** — island shape, animated container, header, shared components.
- **`MacIsland/Features`** — modules (Media, FileShelf, Calendar, Battery, Timer,
  LiveActivities): views plus their models.
- **`MacIsland/Services`** — system access (AppleScript, EventKit, IOKit, Core Audio,
  Quick Look, ServiceManagement, UserNotifications).
- **`MacIsland/Settings`** — persistent preferences and the settings window.

## Notch geometry

`ScreenDetector` reads `NSScreen.safeAreaInsets.top` (> 0 means a physical notch) and
`auxiliaryTopLeftArea` / `auxiliaryTopRightArea`: notch width = `right.minX − left.maxX`,
height = `safeAreaInsets.top`. On a 16" MacBook Pro (2021) that is 185 × 32 pt with a
33 pt menu bar. Displays without a notch get a virtual one (185 × 32 pt by default,
adjustable) centred at the top.

`IslandMetrics` derives every layout from `notchSize` + `PanelSize`:

| State | Body (without fillets) | Radii (top / bottom) |
|---|---|---|
| collapsed | notch | 6 / 12 |
| peek | notch + 24 × 8 | 7 / ≥ 15 |
| live activity | notch + 2 × wing (48–82) | 7 / 14 |
| expanded (regular) | 640 × (32 + 168) | 16 / 28 |

The top "fillet" (`topRadius`) is the concave curve that merges the island into the
screen edge; the total shape width is body + 2 × `topRadius`.

## Window strategy (the sensitive part)

`IslandPanel`: borderless `NSPanel`, `.nonactivatingPanel`, level `mainMenu + 3`,
`[.stationary, .fullScreenAuxiliary, .ignoresCycle]`, transparent, no shadow,
`constrainFrameRect` overridden to a no-op (otherwise AppKit pushes any window below
the menu bar — the first bug observed: the island appeared at y = 55).

**A Space of its own.** The panels do *not* use `.canJoinAllSpaces`. Such a window is
a member of every user Space, so during a desktop switch the WindowServer draws it
twice — sliding out with the old desktop and in with the new one — and the island
visibly moves while the notch does not (the second bug observed, by comparison with
Alcove). `IslandSpace` instead creates one private Space through the private CGS API
(`CGSSpaceCreate(cid, 1, nil)`, `CGSSpaceSetAbsoluteLevel(…, 400)`, `CGSShowSpaces`)
and moves every panel into it (`CGSAddWindowsToSpaces`, then
`CGSRemoveWindowsFromSpaces` for the user Space the window was created in). A Space at
absolute level 400 is composited above every desktop and full-screen app, ignores
Mission Control and takes no part in the switch animation — this is what the Dock,
Notification Center and Alcove 1.7.7 do (observed in its binary: same calls, same
level). The functions are resolved with `dlsym`, never linked; if one is missing,
`IslandSpace.isAvailable` is false and the panel falls back to `.canJoinAllSpaces`.
Ordering a window in puts it back into the active user Space, so `ensureVisible()`
re-attaches after every `orderFront`. While the screen is locked or the screen saver
runs the panels are ordered out (`ScreenStateService`), because that Space would
otherwise draw over the lock screen. `space:dump` (debug) logs each panel's Space
membership.

**Fixed canvas, moving viewport.** The `NSHostingView` always keeps the size of the
expanded panel (≈ 768 × 232 pt). The window is only a viewport over it: collapsed, it
measures exactly the notch (198 × 32 pt) and the SwiftUI view is offset so the island
stays glued to the top centre. Two reasons:

1. Collapsed, the window cannot intercept clicks or drags outside the notch, whatever
   the WindowServer does with transparent pixels.
2. Resizing an `NSHostingView` that is a window's `contentView` triggers an
   `updateConstraints` loop → `NSGenericException` (display-cycle limit) on macOS 14+.
   Reproduced and fixed here: the canvas never changes size.

The window grows *before* any animation (`footprintHandler(.full)`) and shrinks 900 ms
after the island returns to the collapsed state with no activity.

`IslandHostingView` returns `nil` from `hitTest` outside the current shape and owns an
`.activeAlways` `NSTrackingArea` that drives hover even while another app is frontmost.
**Only real pointer motion (`mouseMoved`) can start a hover**; the synthetic
`mouseEntered` / `mouseExited` pairs AppKit emits when the viewport changes size, and
programmatic re-checks, can only end one. Without this, a live activity widening the
notch under a motionless pointer opened the island (observed during testing with the
pointer parked in the notch).

## State machine

`IslandStateMachine` (pure, synchronous) receives `IslandEvent`s and returns
`IslandEffect`s (schedule/cancel timers, select a tab). The view model executes the
effects with cancellable `Task`s. Key rules:

- hover → `peek`; still hovering after `hoverOpenDelay` → `expanded`;
- pointer leaves → close after `closeDelay`, cancelled if the pointer comes back;
- click on the expanded header → close, and no reopening until the pointer has left
  (prevents ping-pong);
- incoming drag → open on the Shelf tab, no closing during the drag session; after a
  drop, delayed close (≥ 1.2 s);
- outside click / Escape → close.

Every transition is covered by `IslandStateMachineTests`.

## Animations

`SpringSpec` (mass, stiffness, damping, initial velocity) is converted to
`Animation.interpolatingSpring(Spring(…))`. Interpolating springs are additive: an
animation retargeted mid-flight keeps its velocity, so opening and closing can be
interrupted and reversed without a visual jump. `scaled(speed:)` multiplies stiffness by
s² and damping by s to keep the same damping ratio at any speed.

| Spring | k | c | ζ | period |
|---|---|---|---|---|
| open | 260 | 26 | 0.81 | 0.39 s |
| close | 320 | 32 | 0.89 | 0.35 s |
| peek | 420 | 28 | 0.68 | 0.31 s |
| activity | 280 | 26 | 0.78 | 0.38 s |
| micro | 600 | 40 | 0.82 | 0.26 s |

Content is laid out at its **final** size and revealed by the animated clip
(`IslandShape` has animatable radii): text never reflows mid-animation. Content enters
and leaves with opacity + scale + blur (`AnyTransition.islandContent`), slightly behind
the shape.

The playback bars and the scrolling title are Core Animation layers (`CALayer` keyframe
animations, `CATextLayer`): they run in the render server with no per-frame work on the
main thread.

## Live activities

`LiveActivityCenter` holds one *transient* activity (replaced by the next one; an
activity of the same kind keeps its identity so only its content animates, e.g. volume)
on top of at most one *sticky* activity (the timer). Observers (`willChange` /
`didChange`) let the window controller grow the viewport before the animation. Sources:
Core Audio (volume/mute), IOKit (power connected, fully charged, 20/10/5 % thresholds),
MediaService (track change), ShelfStore (drop), TimerModel.

## Sounds, haptics and the greeting

`SoundService` plays the cue set observed in Alcove (`volume`, `lock`, `unlock`,
`low-battery`, `low-power`, `chime`, `event`, `blips`…). File names are looked up in
the bundle first (`MacIsland/Resources/Sounds/`, git-ignored, filled by
`Scripts/import-alcove-sounds.sh` from a local Alcove — its files must not be
redistributed) and fall back to sounds that ship with macOS. Alcove's `volume.caf` carries
the same audio as the macOS feedback sound (`BezelServices.loginPlugin/…/volume.aiff`,
decoded samples correlate at 1.0), so that fallback is identical. Short CAF/AIFF files go through
`AudioServicesPlaySystemSound`: sound-effects output device, alert volume, exactly like
the system's feedback (inaudible at volume 0, as Apple's is). Compressed jingles go
through `AVAudioPlayer` (volume, start delay). The volume pop is gated by
`VolumeFeedbackGate` (IslandCore, tested): one pop per 1/16 step, none while muted,
at most ~12 per second, and never when macOS's own "Play feedback when volume is
changed" is on (`com.apple.sound.beep.feedback`), to avoid a double pop. The hourly
chime is an off-by-default timer; calendar events are announced by
`CalendarAlertScheduler` (activity + `event` sound at start time); lock/unlock come
from the `com.apple.screenIsLocked` / `screenIsUnlocked` distributed notifications;
Low Power Mode from `ProcessInfo`. `Haptics` performs an `.alignment` trackpad pattern
when the island opens or closes.

The launch greeting is a transient live activity of kind `.greeting`: the only
activity with `extraHeight` (50 pt), so the island becomes a bubble hanging under the
notch rather than two wings, and `IslandContainer` draws `GreetingView` instead of
`WingsView`. The view writes "hello" by hand, like a new Mac's setup assistant: one
continuous cursive stroke (`HelloStroke`, a Catmull-Rom spline through recorded pen
positions, scaled to the bubble) revealed with `trim` over 1.9 s at 1× speed. It plays
`blips` at 60 % volume 0.15 s in (Alcove's parameters), lasts 5.2 s and is dismissed
early if the user opens the island.

## Media

Two providers (`ScriptedMediaProvider`) for Music and Spotify, public APIs only:

- distributed notifications `com.apple.Music.playerInfo` and
  `com.spotify.client.PlaybackStateChanged` ⇒ one AppleScript round trip per change
  (no polling while idle);
- AppleScript through `NSAppleScript` on a serial queue off the main thread;
- `tell application id "…"` plus an `isRunning` check so a player is never launched;
- the position is extrapolated in the UI (`PlaybackState.position(at:)`) and re-synced
  every 5 s only while the panel is open and playing;
- artwork: HTTPS URL (Spotify) or `data of artwork 1` (Music), 12-entry cache, dominant
  tint through `CIAreaAverage` to colour the bars and the scrubber, and a palette of up
  to three dominant colours (most populated hue/saturation/brightness buckets of a
  32 × 32 downsample, colourful ones first) for the glow at the bottom of the Home
  panel. `ArtworkGlowView` draws that glow as radial `CAGradientLayer` blobs drifting
  and breathing under repeating Core Animation keyframes, masked by a vertical fade:
  like the playback bars, nothing runs on the main thread per frame.

Note: `st` is a reserved word in Spotify's scripting dictionary (error −2741); the
scripts use `playerState`.

## Preferences

`Preferences` is an `ObservableObject`; each property is a `@Pref` wrapper that reads
and writes `UserDefaults` (prefix `macisland.`) and publishes `objectWillChange` plus
the changed key (`didChange`) so `NotchWindowManager` reconciles displays when display
settings change.

## Debugging

In Debug builds, `DebugCommandService` listens to the distributed notification
`com.macisland.debug.command`; `Scripts/island-cmd.swift` sends it:

```
swift Scripts/island-cmd.swift open | close | toggle | hover:in | hover:out |
    tab:shelf | media:toggle | activity:volume:0.6 | activity:greeting | timer:start:90 |
    shelf:add:/path | hello | sound:lock | lock:on | lock:off | settings:media | space:dump | dump
```

Log: `/usr/bin/log stream --predicate 'subsystem == "com.macisland.MacIsland"' --level debug`.
