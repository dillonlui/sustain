#!/bin/bash
set -euo pipefail
APPCAST="${1:?appcast path required}"
xmllint --noout "$APPCAST"

grep -q 'sparkle:signature=' "$APPCAST" || { echo "ERROR: signed appcast signature absent" >&2; exit 1; }
grep -q '<sparkle:version>[1-9][0-9]*</sparkle:version>' "$APPCAST" || { echo "ERROR: numeric build absent" >&2; exit 1; }
grep -Eq '<sparkle:shortVersionString>[0-9]+\.[0-9]+\.[0-9]+</sparkle:shortVersionString>' "$APPCAST" || { echo "ERROR: stable display version absent" >&2; exit 1; }
grep -Eq '<sparkle:minimumSystemVersion>[0-9]+\.[0-9]+\.[0-9]+</sparkle:minimumSystemVersion>' "$APPCAST" || { echo "ERROR: three-part minimum macOS absent" >&2; exit 1; }
grep -Eq '<enclosure[^>]+url="https://[^\"]+"' "$APPCAST" || { echo "ERROR: HTTPS enclosure absent" >&2; exit 1; }
grep -Eq '<enclosure[^>]+length="[1-9][0-9]*"' "$APPCAST" || { echo "ERROR: enclosure length absent" >&2; exit 1; }
grep -Eq '<enclosure[^>]+sparkle:edSignature="[^\"]+"' "$APPCAST" || { echo "ERROR: enclosure signature absent" >&2; exit 1; }
if grep -Eq '<sparkle:channel>|<sparkle:shortVersionString>[^<]*-[^<]*</sparkle:shortVersionString>|github\.com/.*/releases/download/(latest|main)/' "$APPCAST"; then
    echo "ERROR: prerelease/channel or mutable enclosure detected" >&2
    exit 1
fi
