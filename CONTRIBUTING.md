# Contributing to MacIsland

Thanks for taking the time to contribute. This page covers the local setup, the commit
convention and the release process.

## Setup

```bash
git clone https://github.com/HarenaFiantso/MacIsland.git
cd MacIsland
open MacIsland.xcodeproj          # Xcode 16 or later, ⌘R with the MacIsland scheme
cd Packages/IslandCore && swift test
```

Logic that does not need AppKit or SwiftUI (state machine, geometry, springs) belongs in
`Packages/IslandCore` and must come with tests. Everything else lives in `MacIsland/`
(see `ARCHITECTURE.md`). Debug builds accept commands from
`Scripts/island-cmd.swift`, which makes most behaviours reproducible without a mouse.

## Commit messages

This project follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>(<scope>): <subject>

<body — what changed and why, wrapped at 72 columns>

<footer — BREAKING CHANGE: …, Closes #123>
```

**Types**

| Type | Use for |
|---|---|
| `feat` | a new user-facing capability |
| `fix` | a bug fix |
| `perf` | a change that only improves performance |
| `refactor` | a code change that is neither a fix nor a feature |
| `docs` | README, ARCHITECTURE, the Pages site, code comments |
| `test` | adding or fixing tests only |
| `build` | Xcode project settings, packaging, DMG script |
| `chore` | maintenance that touches no source behaviour |
| `style` | formatting only |

**Scopes** (optional, lower-case): `core`, `app`, `window`, `ui`, `media`, `shelf`,
`calendar`, `battery`, `timer`, `activities`, `settings`, `services`, `package`, `site`.

**Subject**: imperative mood, lower-case first letter, no trailing period, at most
72 characters — `feat(media): add seeking from the live activity`, not
`Added seeking…`. The body explains the motivation and anything non-obvious (an AppKit
quirk, a measurement, a trade-off). Reference issues in the footer. A breaking change
in preferences or persisted data gets a `BREAKING CHANGE:` footer.

Keep commits small and self-contained: one logical change per commit, each one
building on its own when possible.

## Pull requests

Branch from `main` (`feat/…`, `fix/…`, `docs/…`), keep the branch rebased, and make sure
`swift test` passes and the app builds in Release before opening the PR. Describe what
you verified by hand on a real notch (hover, drag and drop, external displays…), since
those paths are not covered by automated tests.

## Releases

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in the Xcode project.
2. `package/make-dmg.sh` — builds Release and writes `package/MacIsland-<version>.dmg`
   (set `CODESIGN_IDENTITY` to sign with a Developer ID; notarize separately).
3. `git tag -a v<version> -m "MacIsland <version>"` and push the tag.
4. `gh release create v<version> package/MacIsland-<version>.dmg --title "MacIsland <version>" --notes-file <notes>`
   — include the DMG's SHA-256 in the notes.
