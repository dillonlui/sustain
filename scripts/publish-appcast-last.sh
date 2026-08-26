#!/bin/bash
# Atomically commits the already-signed appcast to a dedicated static-feed branch.
# This script deliberately refuses to run without an explicit production release gate.
set -euo pipefail
[ "${SUSTAIN_PUBLISH_PRODUCTION:-0}" = "1" ] || {
    echo "ERROR: production feed publication was not explicitly enabled" >&2; exit 1;
}
APPCAST="${1:?signed appcast required}"
REPOSITORY="${SUSTAIN_FEED_REPOSITORY:?owner/repository required}"
BRANCH="${SUSTAIN_FEED_BRANCH:-main}"
PATH_IN_REPO="${SUSTAIN_FEED_PATH:-appcast.xml}"
scripts/validate-appcast.sh "$APPCAST"

HEAD_SHA="$(gh api "repos/$REPOSITORY/git/ref/heads/$BRANCH" --jq .object.sha)"
BASE_TREE="$(gh api "repos/$REPOSITORY/git/commits/$HEAD_SHA" --jq .tree.sha)"
BLOB_SHA="$(base64 < "$APPCAST" | gh api "repos/$REPOSITORY/git/blobs" --method POST -f encoding=base64 -F content=@- --jq .sha)"
TREE_SHA="$(gh api "repos/$REPOSITORY/git/trees" --method POST -f base_tree="$BASE_TREE" \
    -f "tree[][path]=$PATH_IN_REPO" -f 'tree[][mode]=100644' -f 'tree[][type]=blob' \
    -f "tree[][sha]=$BLOB_SHA" --jq .sha)"
COMMIT_SHA="$(gh api "repos/$REPOSITORY/git/commits" --method POST \
    -f message='Publish signed Sustain stable appcast' -f tree="$TREE_SHA" -f 'parents[]'="$HEAD_SHA" --jq .sha)"
gh api "repos/$REPOSITORY/git/refs/heads/$BRANCH" --method PATCH -f sha="$COMMIT_SHA" >/dev/null
