#!/bin/bash
# Builds Overhead.app into ./build from the SwiftPM product. Usage: scripts/build-app.sh [debug|release]
# OVERHEAD_UNIVERSAL=1 builds for Apple silicon and Intel; OVERHEAD_SIGN_IDENTITY signs with that certificate
# (scripts/release.sh sets both). Without an identity the app is signed ad-hoc, which is enough to run it locally.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
ARCHS=()
if [ "${OVERHEAD_UNIVERSAL:-0}" = 1 ]; then ARCHS=(--arch arm64 --arch x86_64); fi
swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"
APP="build/Overhead.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Overhead" "$APP/Contents/MacOS/Overhead"
cp scripts/Info.plist "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"
if [ ! -f build/AppIcon.icns ] || [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset >/dev/null
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Hardened runtime always, as notarisation requires; a secure timestamp only for a real certificate (it needs the
# network).
IDENTITY="${OVERHEAD_SIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
  codesign --force --options runtime --timestamp=none --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
echo "$APP"
