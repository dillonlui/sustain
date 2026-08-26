#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

METADATA="${1:-config/release.json}"
TAG="${2:-}"
APPCAST="${3:-}"
VERSION="$(plutil -extract version raw "$METADATA")"
BUILD="$(plutil -extract build raw "$METADATA")"
MINIMUM="$(plutil -extract minimumSystemVersion raw "$METADATA")"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "ERROR: invalid stable version" >&2; exit 1; }
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: invalid build number" >&2; exit 1; }
[[ "$MINIMUM" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "ERROR: minimum macOS must have three parts" >&2; exit 1; }
if [ -n "$TAG" ] && [ "$TAG" != "v$VERSION" ]; then
    echo "ERROR: tag $TAG does not match v$VERSION" >&2
    exit 1
fi

if [ -n "$APPCAST" ] && [ -s "$APPCAST" ]; then
    scripts/validate-appcast.sh "$APPCAST"
    NEWEST_BUILD="$(sed -nE 's#.*<sparkle:version>([0-9]+)</sparkle:version>.*#\1#p' "$APPCAST" | sort -n | tail -1)"
    if [ -n "$NEWEST_BUILD" ] && [ "$BUILD" -le "$NEWEST_BUILD" ]; then
        echo "ERROR: build $BUILD must be greater than stable appcast build $NEWEST_BUILD" >&2
        exit 1
    fi
fi
