#!/bin/bash
set -euo pipefail
APP="${1:?usage: verify-release-artifact.sh APP [--distribution]}"
MODE="${2:-}"
EXECUTABLE="$APP/Contents/MacOS/Sustain"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION="$FRAMEWORK/Versions/B"
PLIST="$APP/Contents/Info.plist"

for REQUIRED in "$EXECUTABLE" "$FRAMEWORK" "$SPARKLE_VERSION/XPCServices/Installer.xpc" \
    "$SPARKLE_VERSION/Autoupdate" "$SPARKLE_VERSION/Updater.app"; do
    [ -e "$REQUIRED" ] || { echo "ERROR: missing $REQUIRED" >&2; exit 1; }
done
[ ! -e "$SPARKLE_VERSION/XPCServices/Downloader.xpc" ] || {
    echo "ERROR: unused Downloader.xpc is present" >&2; exit 1;
}

for ARCH in arm64 x86_64; do
    lipo "$EXECUTABLE" -verify_arch "$ARCH" >/dev/null
    lipo "$SPARKLE_VERSION/Sparkle" -verify_arch "$ARCH" >/dev/null
    BINARY_MINIMUM="$(vtool -show-build -arch "$ARCH" "$EXECUTABLE" | awk '$1 == "minos" { print $2; exit }')"
    case "$BINARY_MINIMUM" in
        *.*.*) NORMALIZED_BINARY_MINIMUM="$BINARY_MINIMUM" ;;
        *.*) NORMALIZED_BINARY_MINIMUM="$BINARY_MINIMUM.0" ;;
        *) NORMALIZED_BINARY_MINIMUM="$BINARY_MINIMUM.0.0" ;;
    esac
    PLIST_MINIMUM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"
    [ "$NORMALIZED_BINARY_MINIMUM" = "$PLIST_MINIMUM" ] || {
        echo "ERROR: $ARCH minimum $NORMALIZED_BINARY_MINIMUM differs from plist $PLIST_MINIMUM" >&2; exit 1;
    }
done
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "ERROR: invalid display version" >&2; exit 1; }
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: invalid build version" >&2; exit 1; }
LINKED_LIBRARIES="$(otool -L "$EXECUTABLE")"
LOAD_COMMANDS="$(otool -l "$EXECUTABLE")"
grep -q '@rpath/Sparkle.framework/Versions/B/Sparkle' <<<"$LINKED_LIBRARIES"
grep -q '@executable_path/../Frameworks' <<<"$LOAD_COMMANDS"

for COMPONENT in "$SPARKLE_VERSION/XPCServices/Installer.xpc" \
    "$SPARKLE_VERSION/Autoupdate" "$SPARKLE_VERSION/Updater.app" "$FRAMEWORK" "$APP"; do
    codesign --verify --strict --verbose=2 "$COMPONENT"
done

ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
for KEY in com.apple.security.app-sandbox com.apple.security.files.bookmarks.app-scope \
    com.apple.security.files.user-selected.read-only com.apple.security.network.client \
    com.apple.security.temporary-exception.mach-lookup.global-name; do
    grep -q "<key>$KEY</key>" <<<"$ENTITLEMENTS" || {
        echo "ERROR: missing entitlement $KEY" >&2; exit 1;
    }
done

if [ "$MODE" = "--distribution" ]; then
    [ "$(/usr/libexec/PlistBuddy -c 'Print :SustainOfficialStableUpdatesEnabled' "$PLIST")" = true ] || {
        echo "ERROR: distribution updater eligibility flag absent" >&2; exit 1;
    }
    FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$PLIST")"
    [[ "$FEED_URL" =~ ^https:// ]] || { echo "ERROR: stable HTTPS feed absent" >&2; exit 1; }
    [ -n "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST")" ] || { echo "ERROR: Sparkle public key absent" >&2; exit 1; }
    for COMPONENT in "$SPARKLE_VERSION/XPCServices/Installer.xpc" \
        "$SPARKLE_VERSION/Autoupdate" "$SPARKLE_VERSION/Updater.app" "$FRAMEWORK" "$APP"; do
        DETAILS="$(codesign -dvv "$COMPONENT" 2>&1)"
        grep -q 'flags=.*runtime' <<<"$DETAILS" || { echo "ERROR: hardened runtime absent: $COMPONENT" >&2; exit 1; }
        grep -q '^Timestamp=' <<<"$DETAILS" || { echo "ERROR: secure timestamp absent: $COMPONENT" >&2; exit 1; }
        grep -q '^Authority=Developer ID Application:' <<<"$DETAILS" || { echo "ERROR: Developer ID authority absent: $COMPONENT" >&2; exit 1; }
    done
    spctl --assess --type execute --verbose=2 "$APP"
    xcrun stapler validate "$APP"
fi
