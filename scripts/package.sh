#!/bin/bash
#
# Produces a distributable zip of Sustain.app for web/GitHub download.
#
# This is the FREE distribution path: the app is ad-hoc signed (not notarized,
# which requires a paid Apple Developer ID). Downloaders will see Gatekeeper's
# "Apple could not verify..." warning on first launch and must approve it once
# via System Settings > Privacy & Security > Open Anyway. See INSTALL.md — ship
# that alongside the download.
#
# Usage: scripts/package.sh [debug|release]   (default: release)
# Output: dist/Sustain-<version>.zip

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
ZIP="dist/${APP_NAME}-${VERSION}.zip"
rm -f "$ZIP"

# ditto is Apple's recommended archiver for .app bundles: it preserves symlinks,
# resource forks, and the code signature (plain `zip` can corrupt the signature).
echo "==> Zipping -> $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Verifying signature on the staged app"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/   /' || true

SIZE="$(du -h "$ZIP" | cut -f1)"
echo ""
echo "==> Done: $ZIP ($SIZE)"
echo "    Attach INSTALL.md (or its contents) to the download so users know how"
echo "    to approve the app on first launch."
