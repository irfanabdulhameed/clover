#!/bin/bash
# Builds Clover.app and packs it into build/Clover.dmg, the file people download: a disk image
# named Clover holding the app and a shortcut to Applications to drag it onto.
#   ./scripts/make-dmg.sh                                   build, then pack
#   APP=some/Clover.app DMG=out.dmg ./scripts/make-dmg.sh   pack an app that is already built
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${APP:-}" ]; then
  INSTALL=0 ./scripts/build.sh
  APP=build/Clover.app
fi
DMG="${DMG:-build/Clover.dmg}"
[ -f "$APP/Contents/Info.plist" ] || { echo "No app at $APP" >&2; exit 1; }
codesign --verify --strict "$APP"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/Clover"
ditto "$APP" "$STAGE/Clover/Clover.app"
ln -s /Applications "$STAGE/Clover/Applications"

mkdir -p "$(dirname "$DMG")"
rm -f "$DMG"
hdiutil create -volname Clover -srcfolder "$STAGE/Clover" -fs HFS+ -format UDZO -imagekey zlib-level=9 -quiet "$DMG"
hdiutil verify -quiet "$DMG"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
echo "Made $DMG: Clover $VERSION, $(du -h "$DMG" | cut -f1 | tr -d ' ')"
