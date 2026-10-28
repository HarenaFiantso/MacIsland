#!/bin/bash
# Builds MacIsland in Release and packages it as a compressed DMG in package/.
#
#   package/make-dmg.sh [version]
#   CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" package/make-dmg.sh
#
# Without CODESIGN_IDENTITY the app keeps its ad-hoc signature (users must right-click →
# Open on first launch). With it, the app is re-signed for distribution; notarization is
# left to you (xcrun notarytool submit … --wait && xcrun stapler staple).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/MacIsland.xcodeproj"
VERSION="${1:-$(sed -n 's/.*MARKETING_VERSION = \([0-9.]*\);.*/\1/p' "$PROJECT/project.pbxproj" | head -1)}"
DERIVED="$ROOT/build/DerivedDataRelease"
STAGE="$ROOT/build/dmg-stage"
OUT_DIR="$ROOT/package"
DMG="$OUT_DIR/MacIsland-$VERSION.dmg"
APP="$DERIVED/Build/Products/Release/MacIsland.app"

echo "▸ Building MacIsland $VERSION (Release)…"
xcodebuild -project "$PROJECT" -scheme MacIsland -configuration Release \
    -derivedDataPath "$DERIVED" -quiet build

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "▸ Signing with '$CODESIGN_IDENTITY'…"
    codesign --force --deep --options runtime --timestamp \
        --entitlements "$ROOT/MacIsland/Resources/MacIsland.entitlements" \
        --sign "$CODESIGN_IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"

echo "▸ Staging…"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$OUT_DIR"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "▸ Creating $DMG…"
rm -f "$DMG"
hdiutil create -volname "MacIsland" -srcfolder "$STAGE" -ov -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null
rm -rf "$STAGE"

echo "▸ Done:"
ls -lh "$DMG" | awk '{print "   " $5 "  " $9}'
shasum -a 256 "$DMG" | awk '{print "   sha256 " $1}'
