#!/bin/bash
# Renders the README screenshots from made-up projects (--demo), never from this Mac's.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
bin="$(swift build --show-bin-path)/Overhead"
out=docs/images
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$out"

"$bin" --demo --snapshot "$tmp/popover.png" --full
"$bin" --demo --snapshot "$tmp/park.png" --park trail-app

cp "$tmp/popover.png" "$out/popover.png"
cp "$tmp/popover.menubar.png" "$out/menubar.png"
cp "$tmp/popover.settings.png" "$out/settings.png"
# Only the project list, where the Park panel opens.
sips --cropOffset 575 0 -c 880 880 "$tmp/park.png" --out "$out/park.png" >/dev/null

echo "screenshots → $out"
