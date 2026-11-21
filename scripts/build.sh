#!/bin/bash
# Builds Clover.app into build/ and installs it in ~/Applications.
#   CONFIG=debug ./scripts/build.sh   debug build
#   INSTALL=0 ./scripts/build.sh      build only, don't install
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
swift build -c "$CONFIG" --product Clover
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Clover"

APP="build/Clover.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Clover"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/Clover.icns ] && cp Resources/Clover.icns "$APP/Contents/Resources/Clover.icns"
# The distortion wave's shaders, compiled by .github/workflows/shaders.yml (no Metal compiler here).
[ -f Resources/DistortionWaves.metallib ] && cp Resources/DistortionWaves.metallib "$APP/Contents/Resources/DistortionWaves.metallib"

# Clover needs no special permission, so an ad-hoc signature is enough.
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${INSTALL:-1}" = 1 ]; then
  DEST="$HOME/Applications/Clover.app"
  if pgrep -x Clover >/dev/null; then
    pkill -x Clover || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Clover >/dev/null || break; sleep 0.3; done
  fi
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  # Let Finder see the "Convert with Clover" service.
  /System/Library/CoreServices/pbs -update 2>/dev/null || true
  echo "Installed $DEST"
fi
