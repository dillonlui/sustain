#!/bin/bash
#
# Produces a drag-to-install disk image for web/GitHub download.
#
# This is the FREE distribution path: the app is ad-hoc signed (not notarized,
# which requires a paid Apple Developer ID). Downloaders will see Gatekeeper's
# "Apple could not verify..." warning on first launch and must approve it once
# via System Settings > Privacy & Security > Open Anyway. See INSTALL.md — ship
# that alongside the download.
#
# Usage: scripts/package.sh [debug|release]   (default: release)
# Output: dist/Sustain-<version>.dmg

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="Sustain"
VERSION="$(grep -E '^VERSION=' scripts/bundle.sh | head -1 | sed -E 's/VERSION="?([^"]*)"?/\1/')"

# Build the .app into a local staging dir (not ~/Applications) so packaging is
# self-contained and repeatable.
STAGE="build/stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
echo "==> Building app bundle ($CONFIG, v$VERSION)"
SUSTAIN_APP_DIR="$STAGE" scripts/bundle.sh "$CONFIG"

APP="$STAGE/$APP_NAME.app"
if [ ! -d "$APP" ]; then
    echo "ERROR: expected $APP to exist after bundle.sh" >&2
    exit 1
fi

mkdir -p dist
DMG="dist/${APP_NAME}-${VERSION}.dmg"
DMG_STAGE="build/dmg-stage"
rm -f "$DMG"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"

# A disk image opens as a Finder window.  Its Applications alias gives people the
# familiar macOS installation gesture: drag Sustain.app onto Applications.
# ditto preserves the nested bundle's signature, metadata, symlinks, and resource
# forks while moving it into the image's staging directory.
echo "==> Preparing drag-to-install disk image"
ditto "$APP" "$DMG_STAGE/$APP_NAME.app"
ln -s /Applications "$DMG_STAGE/Applications"

echo "==> Creating -> $DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGE" \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

echo "==> Verifying signature on the staged app"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/   /' || true

SIZE="$(du -h "$DMG" | cut -f1)"
echo ""
echo "==> Done: $DMG ($SIZE)"
echo "    Open it, then drag Sustain.app onto the Applications folder shortcut."
