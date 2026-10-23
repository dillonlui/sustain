#!/bin/bash
set -euo pipefail
CANONICAL_APP="${1:?canonical app required}"
DMG="${2:?dmg required}"
ARCHIVE="${3:?archive required}"
MODE="${4:-}"
MOUNT_POINT="$(mktemp -d)"
ZIP_POINT="$(mktemp -d)"
cleanup() {
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
    rm -rf "$MOUNT_POINT" "$ZIP_POINT"
}
trap cleanup EXIT

hdiutil verify "$DMG" >/dev/null
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT_POINT" >/dev/null
build/dmg-tools/bin/python scripts/verify-dmg-layout.py "$MOUNT_POINT"
ditto -x -k "$ARCHIVE" "$ZIP_POINT"
scripts/compare-app-manifests.sh "$CANONICAL_APP" "$MOUNT_POINT/Sustain.app"
scripts/compare-app-manifests.sh "$CANONICAL_APP" "$ZIP_POINT/Sustain.app"
scripts/verify-release-artifact.sh "$MOUNT_POINT/Sustain.app" "$MODE"
scripts/verify-release-artifact.sh "$ZIP_POINT/Sustain.app" "$MODE"
