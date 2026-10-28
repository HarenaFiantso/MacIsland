#!/bin/bash
# Copies the sound files of a local Alcove install into MacIsland/Resources/Sounds/.
#
#   Scripts/import-alcove-sounds.sh [path/to/Alcove.app | path/to/Alcove.dmg]
#
# With no argument it looks for /Applications/Alcove.app, then ~/Downloads/Alcove.dmg
# (mounted read-only for the copy). The destination folder is git-ignored on purpose:
# these files belong to Alcove and must not be redistributed with the source. A build
# without them uses macOS's own sounds instead (see Services/SoundService.swift).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/MacIsland/Resources/Sounds"
SRC="${1:-}"
MOUNT=""

cleanup() { [[ -n "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet || true; }
trap cleanup EXIT

if [[ -z "$SRC" ]]; then
    if [[ -d /Applications/Alcove.app ]]; then SRC=/Applications/Alcove.app
    elif [[ -f "$HOME/Downloads/Alcove.dmg" ]]; then SRC="$HOME/Downloads/Alcove.dmg"
    else echo "No Alcove.app or Alcove.dmg found; pass a path." >&2; exit 1; fi
fi

if [[ "$SRC" == *.dmg ]]; then
    MOUNT="$(mktemp -d)"
    hdiutil attach -nobrowse -readonly -quiet -mountpoint "$MOUNT" "$SRC"
    SRC="$MOUNT/Alcove.app"
fi

RES="$SRC/Contents/Resources"
[[ -d "$RES" ]] || { echo "Not an app bundle: $SRC" >&2; exit 1; }

mkdir -p "$DEST"
count=0
for name in volume lock unlock low-battery low-power chime event directions sleep; do
    [[ -f "$RES/$name.caf" ]] && cp "$RES/$name.caf" "$DEST/" && count=$((count + 1))
done
for name in blips pad alt-jingle; do
    [[ -f "$RES/$name.m4a" ]] && cp "$RES/$name.m4a" "$DEST/" && count=$((count + 1))
done
echo "Copied $count sound files to $DEST (git-ignored). Rebuild MacIsland to bundle them."
