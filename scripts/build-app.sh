#!/bin/bash
# Builds Overhead.app into ./build from the SwiftPM product. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/Overhead.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Overhead" "$APP/Contents/MacOS/Overhead"
cp scripts/Info.plist "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"
# Ad-hoc for local builds; a Developer ID signature and notarisation come with the release script.
codesign --force --options runtime --sign - "$APP"
echo "$APP"
