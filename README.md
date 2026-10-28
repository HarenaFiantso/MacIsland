# MacIsland

A native Dynamic Island for the MacBook notch.

MacIsland turns the notch into a small control centre: media controls for Apple Music
and Spotify, a drop shelf for files, upcoming calendar events, a timer, battery status
and live activities (volume, power, timer, drops) — all inside a pure-black shape that
grows out of the notch with interruptible spring animations, then disappears back into
it. Inspired by NotchNook, written from scratch in Swift.

- macOS 14 Sonoma or later, Apple silicon and Intel
- Swift · SwiftUI · AppKit · Core Animation · EventKit · IOKit · Core Audio · Quick Look
- No private APIs, no third-party dependencies, no analytics

## Features

**Lives in the notch.** Collapsed, the island is exactly the notch. Hover it and it
peeks; keep hovering and it opens (click opens immediately). It closes when the pointer
leaves, on Escape, on a click elsewhere or on a click in its header. Displays without a
notch get a virtual one, sized to taste.

**Media.** Artwork, title and artist (scrolling when long), play/pause, previous/next,
a scrubber with elapsed and remaining time, and playback bars tinted with the artwork
colour. Apple Music and Spotify are driven through their public scripting interfaces
and their playback notifications: nothing polls while idle.

**File shelf.** Drag files onto the notch: the island opens on the shelf, drop to park
them. Drag them back out into the Finder or any app, reorder by dragging, click for
Quick Look, double-click to open. The shelf survives relaunches.

**Calendar.** Today's date, the next seven days of events with calendar colours, and a
"Now" badge for what is happening.

**Timer.** Presets, start/pause/resume, ±1 minute, a progress ring, a sound and a
notification at the end, and a persistent live activity while it runs.

**Battery.** Level, charging state, power source, remaining time when macOS has a
reliable estimate, adapter wattage.

**Live activities.** The collapsed island grows symmetric wings for a few seconds:
track change (artwork + bars), volume or mute, power connected/disconnected, low
battery (20 / 10 / 5 %), running timer, timer finished, files dropped.

**Settings.** Hover behaviour and delays, panel size, animation speed, displays,
virtual notch size, modules on/off, preferred player, live-activity toggles and
durations, launch at login, reset. Everything persists.

## Install

1. Download `MacIsland-<version>.dmg` from the
   [latest release](https://github.com/HarenaFiantso/MacIsland/releases/latest).
2. Drag **MacIsland** to **Applications**.
3. The app is signed ad hoc and not notarized, so on first launch right-click it and
   choose **Open** (or run `xattr -d com.apple.quarantine /Applications/MacIsland.app`).

MacIsland has no Dock icon. Its status-bar icon (a notch) offers Open/Close Island,
Settings (⌘,), Launch at Login and Quit.

## Build from source

Requirements: Xcode 16 or later (built with Xcode 27.1 / Swift 6.4).

```bash
git clone https://github.com/HarenaFiantso/MacIsland.git
cd MacIsland
open MacIsland.xcodeproj      # then ⌘R with the MacIsland scheme
```

Command line:

```bash
xcodebuild -project MacIsland.xcodeproj -scheme MacIsland -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/MacIsland.app
```

Unit tests for the UI-free core (state machine, geometry, springs — 27 tests):

```bash
cd Packages/IslandCore && swift test
```

### Signing

The project uses **Sign to Run Locally** (`CODE_SIGN_IDENTITY = "-"`) so it builds
without a developer account. Each ad-hoc build has a new code identity, so macOS asks
for the Automation and Calendar permissions again after every rebuild. For daily use,
pick your team under *Signing & Capabilities* (an *Apple Development* certificate is
enough): permissions then stick.

The app is **not sandboxed** (see `MacIsland/Resources/MacIsland.entitlements`); the
hardened runtime is on, so each protected resource needs its entitlement:
`com.apple.security.automation.apple-events` to control Music and Spotify, and
`com.apple.security.personal-information.calendars` for the Calendar permission prompt.
Without them the hardened runtime denies access silently, without asking the user.

### Packaging a DMG

```bash
package/make-dmg.sh            # builds Release and writes package/MacIsland-<version>.dmg
CODESIGN_IDENTITY="Developer ID Application: …" package/make-dmg.sh   # optional: sign for distribution
```

## Permissions

| Permission | Asked when | Info.plist key |
|---|---|---|
| Automation → Music / Spotify | the first time a running player is queried | `NSAppleEventsUsageDescription` |
| Calendars (full access) | *Allow Access* in the Calendar tab or in Settings | `NSCalendarsFullAccessUsageDescription` |
| Notifications | the first timer starts | — (`UNUserNotificationCenter`) |
| Login items | *Launch at login* toggle | — (`SMAppService`) |

No Accessibility or Screen Recording permission is needed: outside clicks are detected
with a global mouse-event monitor, which macOS allows without consent.

## How it works

See [ARCHITECTURE.md](ARCHITECTURE.md) for the details. In short:

- `Packages/IslandCore` holds the UI-free logic — a pure state machine (`IslandStateMachine`),
  the notch geometry and every layout (`IslandMetrics`), and spring definitions
  (`SpringSpec`) — all unit tested.
- One borderless, non-activating `NSPanel` per display floats above the menu bar. The
  SwiftUI island is drawn on a fixed-size canvas; the panel is only a viewport that
  shrinks to the notch when idle, so nothing outside the notch can intercept clicks.
- The island shape (`IslandShape`) has animatable top fillets and bottom corners, so
  collapsed, peek, live-activity and expanded states morph into each other with
  interpolating springs that keep their velocity when interrupted.
- Services are event-driven: distributed notifications for players, `EKEventStoreChanged`
  for calendars, IOKit power-source callbacks, Core Audio property listeners. Idle CPU is
  0 %.

## Known limitations

- **Other players** (browsers, VLC, Podcasts…): macOS has no public "now playing" API
  for third-party apps; `MediaRemote` is private and locked down since macOS 15.4.
  Adding a player means adding a `MediaProvider`.
- **Brightness**: there is no public API to observe display brightness, so there is no
  brightness activity.
- **Playback bars** are an animation, not a spectrum analyser (that would need a Core
  Audio process tap and the System Audio Recording permission).
- **Dragging several shelf items at once** is not supported (one item per drag).
- **Full-screen apps**: the island stays visible above them (`.fullScreenAuxiliary`);
  games that capture the display may hide it. Behaviour during Mission Control depends
  on macOS.
- **Virtual notch** on external displays covers the centre of the menu bar, like
  NotchNook's.

## Status

Built and exercised on a 16" MacBook Pro (2021) running macOS 27.2. Verified so far:
pixel-exact placement over the 185 × 32 pt notch (measured with `CGWindowList`), the
state machine and viewport resizing, live activities, Spotify metadata/artwork/position
and real pause/resume, timer with notification, shelf persistence, settings window,
idle CPU 0.0–0.2 %. Not yet verified with a real pointer: hover and drag & drop,
visual rendering, external displays, full-screen apps, Apple Music, Calendar
authorisation. Please open an issue for anything that misbehaves.

## Debugging

Debug builds accept commands over a distributed notification, so the island can be
driven without a mouse:

```bash
swift Scripts/island-cmd.swift open | close | hover:in | hover:out | tab:shelf | media:toggle | activity:volume:0.6 | timer:start:60 | dump
swift Scripts/list-windows.swift         # real frame of the island window
/usr/bin/log stream --predicate 'subsystem == "com.macisland.MacIsland"' --level debug
```

## Contributing

Issues and pull requests are welcome. Commits follow
[Conventional Commits](https://www.conventionalcommits.org/) — see
[CONTRIBUTING.md](CONTRIBUTING.md) for the types, scopes and release steps.

## Project layout

```
MacIsland.xcodeproj/        Xcode project (synchronized folders, shared scheme)
MacIsland/
  App/        app entry, coordinator, status menu, logging
  Core/       screen detection, panel, hosting view, view model, event monitor, motion
  UI/         island shape, container, collapsed / expanded views, components
  Features/   Media, FileShelf, Calendar, Battery, Timer, LiveActivities
  Services/   AppleScript, media, files, calendar, battery, volume, login, notifications
  Settings/   preferences store, settings window
  Resources/  Info.plist, entitlements, asset catalog
Packages/IslandCore/        UI-free logic + tests
Scripts/                    icon generator, debug command sender, window lister
package/                    DMG packaging script (output is git-ignored)
docs/                       GitHub Pages site
```
