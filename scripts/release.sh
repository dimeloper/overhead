#!/bin/bash
# Builds the downloadable Overhead: universal, signed with Developer ID, notarised and stapled, in a DMG.
# Usage: scripts/release.sh    → build/Overhead-<version>.dmg and its SHA-256
#
# Needs, once per Mac:
#   - a "Developer ID Application" certificate in the login keychain
#   - notarytool credentials saved under a keychain profile:
#       xcrun notarytool store-credentials overhead-notary --apple-id <you> --team-id <team>
# OVERHEAD_NOTARY_PROFILE overrides the profile name; OVERHEAD_SIGN_IDENTITY picks one of several certificates.
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${OVERHEAD_NOTARY_PROFILE:-overhead-notary}"
IDENTITY="${OVERHEAD_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)}"
if [[ "$IDENTITY" != "Developer ID Application:"* ]]; then
  echo "No Developer ID Application certificate in the keychain." >&2; exit 1
fi
if ! NOTARY_ERR=$(xcrun notarytool history --keychain-profile "$PROFILE" 2>&1 >/dev/null); then
  echo "No usable notarytool credentials under profile '$PROFILE'. notarytool said: $NOTARY_ERR" >&2; exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist)"
APP="build/Overhead.app"
ZIP="build/Overhead-$VERSION.zip"
DMG="build/Overhead-$VERSION.dmg"

OVERHEAD_UNIVERSAL=1 OVERHEAD_SIGN_IDENTITY="$IDENTITY" scripts/build-app.sh release
codesign --verify --strict --deep "$APP"
lipo -archs "$APP/Contents/MacOS/Overhead"

# The app first, so its ticket is stapled into the bundle and it opens offline once copied out of the DMG.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Notarising the app (a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"

# A plain DMG: the app and a link to /Applications to drag it onto.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Overhead $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
echo "Notarising the DMG…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

# What a downloader's Mac will decide.
spctl --assess --type execute --verbose "$APP"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
shasum -a 256 "$DMG"
echo "Ready: $DMG"
