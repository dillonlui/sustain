#!/bin/bash
#
# Produces a local drag-to-install disk image.
#
# The app assembled by bundle.sh is ad-hoc signed, so this artifact is for local
# testing only. Before publishing a GitHub release, re-sign the app with the
# Developer ID certificate and notarize it; published releases then open through
# macOS's normal first-launch confirmation without an "Open Anyway" workaround.
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

EXECUTABLE="$APP/Contents/MacOS/$APP_NAME"
echo "==> Verifying Universal 2 app bundle"
for ARCH in arm64 x86_64; do
    if ! lipo "$EXECUTABLE" -verify_arch "$ARCH" >/dev/null; then
        echo "ERROR: $EXECUTABLE is missing the $ARCH architecture" >&2
        exit 1
    fi

    BINARY_MINIMUM_SYSTEM_VERSION="$(vtool -show-build -arch "$ARCH" "$EXECUTABLE" | awk '$1 == "minos" { print $2; exit }')"
    if [ "$BINARY_MINIMUM_SYSTEM_VERSION" != "14.0" ]; then
        echo "ERROR: expected $ARCH deployment target 14.0, got $BINARY_MINIMUM_SYSTEM_VERSION" >&2
        exit 1
    fi
done

MINIMUM_SYSTEM_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
if [ "$MINIMUM_SYSTEM_VERSION" != "14.0" ]; then
    echo "ERROR: expected LSMinimumSystemVersion 14.0, got $MINIMUM_SYSTEM_VERSION" >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/   /'

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

SIZE="$(du -h "$DMG" | cut -f1)"
echo ""
echo "==> Done: $DMG ($SIZE)"
echo "    Open it, then drag Sustain.app onto the Applications folder shortcut."
