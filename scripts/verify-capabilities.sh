#!/bin/bash
# Verifies the capability shape actually applied to a built app. This is safe to
# run for ad-hoc development and Developer ID release artifacts; release QA adds
# physical file/MIDI/audio tests and notarization validation.

set -euo pipefail

APP="${1:-build/stage/Sustain.app}"
EXPECTED_ENTITLEMENTS="${SUSTAIN_ENTITLEMENTS:-config/Sustain.entitlements}"

if [ ! -d "$APP" ]; then
    echo "ERROR: app bundle not found: $APP" >&2
    exit 1
fi

codesign --verify --strict --verbose=2 "$APP"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
codesign -d --entitlements :- "$APP" 2>/dev/null > "$TMP_DIR/applied.plist"

for REQUIRED_KEY in \
    com.apple.security.app-sandbox \
    com.apple.security.files.bookmarks.app-scope \
    com.apple.security.files.user-selected.read-only \
    com.apple.security.network.client \
    com.apple.security.temporary-exception.mach-lookup.global-name; do
    EXPECTED="$(/usr/libexec/PlistBuddy -c "Print :$REQUIRED_KEY" "$EXPECTED_ENTITLEMENTS")"
    APPLIED="$(/usr/libexec/PlistBuddy -c "Print :$REQUIRED_KEY" "$TMP_DIR/applied.plist")"
    if [ "$EXPECTED" != "$APPLIED" ]; then
        echo "ERROR: $REQUIRED_KEY differs (expected $EXPECTED, applied $APPLIED)" >&2
        exit 1
    fi
done

for SERVICE in com.sustain.app-spks com.sustain.app-spki; do
    grep -q "<string>$SERVICE</string>" "$TMP_DIR/applied.plist" || {
        echo "ERROR: Sparkle installer communication service $SERVICE is absent" >&2
        exit 1
    }
done

if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q 'com.apple.security.device.audio-input'; then
    echo "ERROR: audio-input entitlement is forbidden; Sustain does not record" >&2
    exit 1
fi

echo "Verified signed sandbox capability shape for $APP"
