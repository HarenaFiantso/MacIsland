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
│         │            LaunchAtLoginService · NotificationService        │
│         ├─ LiveActivityCenter (transient + sticky activity queue)     │
│         ├─ EventMonitor (outside clicks, Escape)                      │
│         └─ NotchWindowManager ── one IslandWindowController per screen│
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
`[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`, transparent,
no shadow, `constrainFrameRect` overridden to a no-op (otherwise AppKit pushes any
window below the menu bar — the first bug observed: the island appeared at y = 55).

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
  tint through `CIAreaAverage` to colour the bars and the scrubber.

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
    tab:shelf | media:toggle | activity:volume:0.6 | timer:start:90 | shelf:add:/path | dump
```

Log: `/usr/bin/log stream --predicate 'subsystem == "com.macisland.MacIsland"' --level debug`.
