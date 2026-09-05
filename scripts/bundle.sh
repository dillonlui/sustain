#!/bin/bash
#
# Packages the SwiftPM executable into a distributable-shaped Sustain.app bundle:
# proper Info.plist (so it has a menu bar and Preferences/Cmd-,), the bundled pad
# resources, an app icon rendered from the brand SVG, and a local or Developer ID
# signature.
# The executable is Universal 2 so the same bundle runs natively on Apple
# silicon and Intel Macs.
#
# Usage: scripts/bundle.sh [debug|release]   (default: release)
#
# Note: this is a local/dev bundle. It is ad-hoc signed; the official release
# process re-signs it with a Developer ID certificate and notarizes it before
# publishing.

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="Sustain"
BUNDLE_ID="com.sustain.app"
RELEASE_METADATA="${SUSTAIN_RELEASE_METADATA:-config/release.json}"
SIGN_IDENTITY="${SUSTAIN_SIGN_IDENTITY:--}"
ENTITLEMENTS="${SUSTAIN_ENTITLEMENTS:-config/Sustain.entitlements}"
OFFICIAL_UPDATES="${SUSTAIN_OFFICIAL_STABLE_UPDATES:-0}"

if [ ! -f "$RELEASE_METADATA" ]; then
    echo "ERROR: release metadata not found: $RELEASE_METADATA" >&2
    exit 1
fi
VERSION="$(plutil -extract version raw "$RELEASE_METADATA")"
BUILD_NUMBER="$(plutil -extract build raw "$RELEASE_METADATA")"
MINIMUM_SYSTEM_VERSION="$(plutil -extract minimumSystemVersion raw "$RELEASE_METADATA")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
   [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] ||
   [[ ! "$MINIMUM_SYSTEM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: release metadata must contain semantic version, positive numeric build, and three-part minimumSystemVersion" >&2
    exit 1
fi

UPDATE_PLIST_LINES=""
if [ "$OFFICIAL_UPDATES" = "1" ]; then
    if [ "$SIGN_IDENTITY" = "-" ]; then
        echo "ERROR: official updates require a Developer ID signing identity" >&2
        exit 1
    fi
    UPDATE_FEED_URL="${SUSTAIN_UPDATE_FEED_URL:-}"
    UPDATE_PUBLIC_KEY="${SUSTAIN_UPDATE_PUBLIC_ED_KEY:-}"
    if [[ ! "$UPDATE_FEED_URL" =~ ^https://[^[:space:]]+$ ]] || [ -z "$UPDATE_PUBLIC_KEY" ] ||
       [[ "$UPDATE_FEED_URL" == *['<>&"']* ]] || [[ "$UPDATE_PUBLIC_KEY" == *['<>&"']* ]]; then
        echo "ERROR: official updates require an HTTPS feed URL and public EdDSA key" >&2
        exit 1
    fi
    UPDATE_PLIST_LINES="
    <key>SustainOfficialStableUpdatesEnabled</key><true/>
    <key>SUFeedURL</key><string>$UPDATE_FEED_URL</string>
    <key>SUPublicEDKey</key><string>$UPDATE_PUBLIC_KEY</string>"
fi

if [ ! -f "$ENTITLEMENTS" ]; then
    echo "ERROR: entitlement file not found: $ENTITLEMENTS" >&2
    exit 1
fi

BUILD_ROOT=".build/universal"
ARCHS=(arm64 x86_64)
BINARIES=()
RES_BUNDLE=""
SPARKLE_FRAMEWORK_SOURCE=""
SPARKLE_LICENSE_SOURCE=""
SWIFT_BUILD_SANDBOX_FLAG=""
if [ "${SUSTAIN_DISABLE_SWIFTPM_SANDBOX:-0}" = "1" ]; then
    SWIFT_BUILD_SANDBOX_FLAG="--disable-sandbox"
fi

for ARCH in "${ARCHS[@]}"; do
    TRIPLE="${ARCH}-apple-macosx14.0"
    SCRATCH="$BUILD_ROOT/$ARCH"
    BIN_DIR="$SCRATCH/${ARCH}-apple-macosx/$CONFIG"

    echo "==> Building $ARCH ($CONFIG, macOS 14+)"
    swift build \
        -c "$CONFIG" \
        --triple "$TRIPLE" \
        --scratch-path "$SCRATCH" \
        ${SWIFT_BUILD_SANDBOX_FLAG:+"$SWIFT_BUILD_SANDBOX_FLAG"}

    BINARIES+=("$BIN_DIR/$APP_NAME")
    if [ "$ARCH" = "arm64" ]; then
        RES_BUNDLE="$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle"
        SPARKLE_FRAMEWORK_SOURCE="$BIN_DIR/Sparkle.framework"
        SPARKLE_LICENSE_SOURCE="$SCRATCH/checkouts/Sparkle/LICENSE"
    fi
done
# The .app must live OUTSIDE ~/Documents: a bundle inside Documents makes macOS
# prompt for "access to your Documents folder" whenever the app reads its own
# resources, and (being ad-hoc signed) that grant resets on every rebuild.
# Override with SUSTAIN_APP_DIR if you want it elsewhere.
APP_DIR="${SUSTAIN_APP_DIR:-$HOME/Applications}"
mkdir -p "$APP_DIR"
APP="$APP_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

echo "==> Creating Universal 2 executable"
lipo -create "${BINARIES[@]}" -output "$CONTENTS/MacOS/$APP_NAME"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/$APP_NAME"

for ARCH in "${ARCHS[@]}"; do
    if ! lipo "$CONTENTS/MacOS/$APP_NAME" -verify_arch "$ARCH" >/dev/null; then
        echo "ERROR: bundled executable is missing the $ARCH architecture" >&2
        exit 1
    fi
done
echo "   Architectures: $(lipo -archs "$CONTENTS/MacOS/$APP_NAME")"

# Resources live in the standard, signable Contents/Resources location. The app
# finds them via Bundle.sustainResources (see PadAssetResolver), which looks in
# Contents/Resources first so it never falls back to SwiftPM's baked-in .build
# path (that path is inside ~/Documents and would trigger a TCC prompt).
if [ -d "$RES_BUNDLE" ]; then
    cp -R "$RES_BUNDLE" "$CONTENTS/Resources/"
    # SwiftPM's copied resource directory can contain ignored Finder metadata from a
    # developer checkout. Keep it out of the signed canonical app and distribution
    # containers; some sandboxed runners cannot read its extended attributes later.
    find "$CONTENTS/Resources/$(basename "$RES_BUNDLE")" -type f -name .DS_Store -delete
fi

if [ ! -d "$SPARKLE_FRAMEWORK_SOURCE" ]; then
    echo "ERROR: SwiftPM did not produce Sparkle.framework at $SPARKLE_FRAMEWORK_SOURCE" >&2
    exit 1
fi
echo "==> Embedding Sparkle.framework"
ditto "$SPARKLE_FRAMEWORK_SOURCE" "$CONTENTS/Frameworks/Sparkle.framework"
if [ ! -f "$SPARKLE_LICENSE_SOURCE" ]; then
    echo "ERROR: Sparkle license notice missing at $SPARKLE_LICENSE_SOURCE" >&2
    exit 1
fi
ditto "$SPARKLE_LICENSE_SOURCE" "$CONTENTS/Resources/Sparkle-LICENSE.txt"
# Sustain already has outbound network access, so the Downloader service is unnecessary.
# Installer.xpc remains mandatory for this sandboxed app.
rm -rf "$CONTENTS/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"

# ---- App icon (best effort) ----
ICON_SVG="docs/sustain_brand_assets_final/sustain-icon.svg"
ICONSET="build/AppIcon.iconset"
if [ -f "$ICON_SVG" ]; then
    echo "==> Rendering app icon"
    rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    TMP_PNG="build/icon-1024.png"
    if qlmanage -t -s 1024 -o build "$ICON_SVG" >/dev/null 2>&1 && \
       mv "build/$(basename "$ICON_SVG").png" "$TMP_PNG" 2>/dev/null; then
        for size in 16 32 64 128 256 512; do
            sips -z "$size" "$size" "$TMP_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1 || true
            dbl=$((size * 2))
            sips -z "$dbl" "$dbl" "$TMP_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1 || true
        done
        if iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns" 2>/dev/null; then
            ICON_LINE="<key>CFBundleIconFile</key><string>AppIcon</string>"
        fi
    fi
fi
ICON_LINE="${ICON_LINE:-}"

echo "==> Writing Info.plist"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>$MINIMUM_SYSTEM_VERSION</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
    <key>SUAutomaticallyUpdate</key><false/>
    <key>SUAllowsAutomaticUpdates</key><false/>
    <key>SUEnableSystemProfiling</key><false/>
    <key>SUShowReleaseNotes</key><true/>
    <key>SUVerifyUpdateBeforeExtraction</key><true/>
    <key>SURequireSignedFeed</key><true/>
    <key>SUSignedFeedFailureExpirationInterval</key><integer>0</integer>
    <key>SUEnableInstallerLauncherService</key><true/>
    $UPDATE_PLIST_LINES
    $ICON_LINE
</dict>
</plist>
PLIST

SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "==> Ad-hoc signing"
else
    echo "==> Developer ID signing"
    # Hardened runtime is mandatory for notarized distribution. Do not enable it
    # for ad-hoc builds: library validation cannot establish a common Team ID for
    # independently ad-hoc-signed app and framework code, so dyld rejects Sparkle.
    SIGN_ARGS+=(--options runtime --timestamp)
fi

# Sparkle's documented manual inside-out signing order. Keeping this explicit makes a
# newly introduced helper fail packaging review instead of being silently deep-signed.
SPARKLE_VERSION="$CONTENTS/Frameworks/Sparkle.framework/Versions/B"
for NESTED_CODE in \
    "$SPARKLE_VERSION/XPCServices/Installer.xpc" \
    "$SPARKLE_VERSION/Autoupdate" \
    "$SPARKLE_VERSION/Updater.app" \
    "$CONTENTS/Frameworks/Sparkle.framework"; do
    if [ ! -e "$NESTED_CODE" ]; then
        echo "ERROR: required Sparkle component missing: $NESTED_CODE" >&2
        exit 1
    fi
    echo "   Signing nested code: ${NESTED_CODE#$CONTENTS/}"
    codesign "${SIGN_ARGS[@]}" "$NESTED_CODE" 2>&1 | sed 's/^/   /'
done

codesign "${SIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$APP" 2>&1 | sed 's/^/   /'

echo "==> Verifying signature and applied entitlements"
codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/   /'
APPLIED_ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
for REQUIRED_KEY in \
    com.apple.security.app-sandbox \
    com.apple.security.files.bookmarks.app-scope \
    com.apple.security.files.user-selected.read-only \
    com.apple.security.network.client \
    com.apple.security.temporary-exception.mach-lookup.global-name; do
    if ! grep -q "<key>$REQUIRED_KEY</key>" <<<"$APPLIED_ENTITLEMENTS"; then
        echo "ERROR: signed app is missing required entitlement $REQUIRED_KEY" >&2
        exit 1
    fi
done

if [ -e "$SPARKLE_VERSION/XPCServices/Downloader.xpc" ]; then
    echo "ERROR: unused Sparkle Downloader.xpc was embedded" >&2
    exit 1
fi
for COMPONENT in \
    "$SPARKLE_VERSION/XPCServices/Installer.xpc" \
    "$SPARKLE_VERSION/Autoupdate" \
    "$SPARKLE_VERSION/Updater.app" \
    "$CONTENTS/Frameworks/Sparkle.framework"; do
    codesign --verify --strict --verbose=2 "$COMPONENT" 2>&1 | sed 's/^/   /'
done
LINKED_LIBRARIES="$(otool -L "$CONTENTS/MacOS/$APP_NAME")"
if ! grep -q '@rpath/Sparkle.framework/Versions/B/Sparkle' <<<"$LINKED_LIBRARIES"; then
    echo "ERROR: app executable is not linked to the embedded Sparkle framework" >&2
    exit 1
fi

echo "==> Done: $APP"
