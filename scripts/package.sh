#!/bin/bash
# Build one canonical app, notarize/staple it when release credentials are supplied,
# then derive both immutable distribution containers from that exact app.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="Sustain"
RELEASE_METADATA="${SUSTAIN_RELEASE_METADATA:-config/release.json}"
VERSION="$(plutil -extract version raw "$RELEASE_METADATA")"
BUILD_NUMBER="$(plutil -extract build raw "$RELEASE_METADATA")"
SIGN_IDENTITY="${SUSTAIN_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${SUSTAIN_NOTARY_PROFILE:-}"

if [ -n "$NOTARY_PROFILE" ] && [ "$SIGN_IDENTITY" = "-" ]; then
    echo "ERROR: SUSTAIN_SIGN_IDENTITY is required when notarizing" >&2
    exit 1
fi

STAGE="build/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE" dist
echo "==> Building canonical app ($CONFIG, v$VERSION, build $BUILD_NUMBER)"
SUSTAIN_APP_DIR="$STAGE" scripts/bundle.sh "$CONFIG"
APP="$STAGE/$APP_NAME.app"
scripts/verify-release-artifact.sh "$APP"

if [ -n "$NOTARY_PROFILE" ]; then
    NOTARY_CONTAINER="build/${APP_NAME}-${VERSION}-${BUILD_NUMBER}-notary.zip"
    rm -f "$NOTARY_CONTAINER"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY_CONTAINER"
    echo "==> Notarizing canonical app"
    xcrun notarytool submit "$NOTARY_CONTAINER" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    scripts/verify-release-artifact.sh "$APP" --distribution
fi

ARCHIVE="dist/${APP_NAME}-${VERSION}-${BUILD_NUMBER}.zip"
DMG="dist/${APP_NAME}-${VERSION}-${BUILD_NUMBER}.dmg"
DMG_STAGE="build/dmg-stage"
rm -f "$ARCHIVE" "$DMG"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"

echo "==> Creating Sparkle full archive"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
echo "==> Preparing drag-to-install disk image"
ditto "$APP" "$DMG_STAGE/$APP_NAME.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -format UDZO -ov "$DMG" >/dev/null

if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    codesign --verify --verbose=2 "$DMG"
fi
if [ -n "$NOTARY_PROFILE" ]; then
    echo "==> Notarizing disk image"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
fi

if [ -n "$NOTARY_PROFILE" ]; then
    scripts/verify-release-containers.sh "$APP" "$DMG" "$ARCHIVE" --distribution
else
    scripts/verify-release-containers.sh "$APP" "$DMG" "$ARCHIVE"
fi
CHECKSUMS="dist/${APP_NAME}-${VERSION}-${BUILD_NUMBER}-SHA256SUMS.txt"
shasum -a 256 "$DMG" "$ARCHIVE" > "$CHECKSUMS"
echo "==> Done: $DMG, $ARCHIVE, $CHECKSUMS"
