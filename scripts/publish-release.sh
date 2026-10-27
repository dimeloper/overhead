#!/bin/bash
# Publishes a release built by scripts/release.sh: tags v<version>, uploads the DMG to GitHub Releases with
# docs/release-notes/<version>.md, checks the upload, then points the Homebrew cask at it and pushes the tap.
# Usage: scripts/publish-release.sh [--dry-run]
#
# --dry-run runs every check and shows the cask change, but tags, uploads and pushes nothing.
# OVERHEAD_TAP_DIR is a clone of the tap (default ../homebrew-tap); OVERHEAD_REPO the GitHub repo.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1
REPO="${OVERHEAD_REPO:-dimeloper/overhead}"
TAP="${OVERHEAD_TAP_DIR:-../homebrew-tap}"
CASK="$TAP/Casks/overhead.rb"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist)"
TAG="v$VERSION"
NAME="Overhead-$VERSION.dmg"
DMG="build/$NAME"
NOTES="docs/release-notes/$VERSION.md"

fail() { echo "$1" >&2; exit 1; }
[ -f "$DMG" ] || fail "No $DMG. Run scripts/release.sh first."
xcrun stapler validate "$DMG" >/dev/null 2>&1 || fail "$DMG is not notarised and stapled. Run scripts/release.sh."
[ -f "$NOTES" ] || fail "No $NOTES. Write the release notes first."
[ -f "$CASK" ] || fail "No cask at $CASK. Clone the tap there or set OVERHEAD_TAP_DIR."

# The DMG must be built from what the tag will point at: committed, on main, pushed.
[ -z "$(git status --porcelain)" ] || fail "Uncommitted changes. Commit them, rebuild, then publish."
[ "$(git branch --show-current)" = main ] || fail "Not on main."
git fetch -q origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main is not the same as origin/main. Push or pull first."
# The DMG must be newer than the last commit, or it was built from older sources.
COMMITTED="$(git log -1 --format=%ct)"
BUILT="$(stat -f %m "$DMG")"
[ "$BUILT" -ge "$COMMITTED" ] || fail "$DMG is older than the last commit. Run scripts/release.sh again."

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  fail "$TAG is already released on $REPO. A new build needs a new version in scripts/Info.plist."
fi
if [ -n "$(git -C "$TAP" status --porcelain)" ]; then fail "The tap at $TAP has uncommitted changes."; fi

SHA="$(shasum -a 256 < "$DMG" | cut -c1-64)"
echo "Publishing Overhead $VERSION ($SHA)"

if [ "$DRY_RUN" = 1 ]; then
  echo "Dry run: would tag $TAG at $(git rev-parse --short HEAD), upload $DMG to $REPO, and set the cask to:"
  sed -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK" | diff "$CASK" - || true
  exit 0
fi

if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then git tag -a "$TAG" -m "Overhead $VERSION"; fi
[ "$(git rev-parse "$TAG^{commit}")" = "$(git rev-parse HEAD)" ] || fail "Tag $TAG exists and points at another commit."
git push -q origin "$TAG"

gh release create "$TAG" "$DMG#$NAME" --repo "$REPO" --title "Overhead $VERSION" --notes-file "$NOTES" --verify-tag
# Read the upload back before the cask points at it.
GOT="$(curl -fsSL "https://github.com/$REPO/releases/download/$TAG/$NAME" | shasum -a 256 | cut -c1-64)"
[ "$GOT" = "$SHA" ] || fail "The upload of $NAME does not match $DMG ($GOT vs $SHA). The cask was not changed."

git -C "$TAP" pull -q --ff-only
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
git -C "$TAP" commit -q -am "overhead $VERSION"
git -C "$TAP" push -q
echo "Published $TAG: https://github.com/$REPO/releases/tag/$TAG, and the cask in $TAP."
