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
# Sparkle, for updates. ditto keeps the framework's symlinks, which codesign requires. The build adds an rpath to its
# own products folder on this Mac; only @executable_path/../Frameworks belongs in a shipped app.
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
otool -l "$APP/Contents/MacOS/Overhead" | awk '/LC_RPATH/ { getline; getline; print $2 }' | { grep "^$PWD/" || true; } | while read -r path; do
  install_name_tool -delete_rpath "$path" "$APP/Contents/MacOS/Overhead"
done
# Hardened runtime always, as notarisation requires; a secure timestamp only for a real certificate (it needs the
# network).
IDENTITY="${OVERHEAD_SIGN_IDENTITY:--}"
TIMESTAMP=--timestamp
if [ "$IDENTITY" = "-" ]; then TIMESTAMP=--timestamp=none; fi
sign() { codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" "$@"; }
# Inside out, as Sparkle documents for apps not built by Xcode: its helpers, the framework, then the app.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP"
echo "$APP"
