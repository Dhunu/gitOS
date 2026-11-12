#!/bin/zsh
# Builds a shareable disk image: build/GitOS-<version>.dmg, with GitOS.app and an Applications shortcut.
# The app isn't notarized, so other Macs need the first-launch step in the README.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

APP="build/GitOS.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/GitOS-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/GitOS.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname GitOS -srcfolder "$STAGE" -format UDZO -ov "$DMG"
hdiutil verify -quiet "$DMG"
echo "Built $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
