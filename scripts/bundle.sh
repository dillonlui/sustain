#!/bin/bash
#
# Packages the SwiftPM executable into a distributable-shaped Sustain.app bundle:
# proper Info.plist (so it has a menu bar and Preferences/Cmd-,), the bundled pad
# resources, an app icon rendered from the brand SVG, and an ad-hoc signature.
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
VERSION="1.0.0"
BUILD_NUMBER="1"

BUILD_ROOT=".build/universal"
ARCHS=(arm64 x86_64)
BINARIES=()
RES_BUNDLE=""

for ARCH in "${ARCHS[@]}"; do
    TRIPLE="${ARCH}-apple-macosx14.0"
    SCRATCH="$BUILD_ROOT/$ARCH"
    BIN_DIR="$SCRATCH/${ARCH}-apple-macosx/$CONFIG"

    echo "==> Building $ARCH ($CONFIG, macOS 14+)"
    swift build \
        -c "$CONFIG" \
        --triple "$TRIPLE" \
        --scratch-path "$SCRATCH"

    BINARIES+=("$BIN_DIR/$APP_NAME")
    if [ "$ARCH" = "arm64" ]; then
        RES_BUNDLE="$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle"
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
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

echo "==> Creating Universal 2 executable"
lipo -create "${BINARIES[@]}" -output "$CONTENTS/MacOS/$APP_NAME"

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
fi

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
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    $ICON_LINE
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP" 2>&1 | sed 's/^/   /' || echo "   (codesign skipped)"

echo "==> Done: $APP"
