#!/bin/bash
set -euo pipefail
LEFT="${1:?left app required}"
RIGHT="${2:?right app required}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

manifest() {
    local ROOT="$1"
    local OUTPUT="$2"
    (
        cd "$ROOT"
        find . -type f -print0 | sort -z | xargs -0 shasum -a 256
        find . -type l -print0 | sort -z | while IFS= read -r -d '' LINK; do
            printf 'SYMLINK %s -> %s\n' "$LINK" "$(readlink "$LINK")"
        done
    ) > "$OUTPUT"
}
manifest "$LEFT" "$TMP_DIR/left"
manifest "$RIGHT" "$TMP_DIR/right"
diff -u "$TMP_DIR/left" "$TMP_DIR/right"
