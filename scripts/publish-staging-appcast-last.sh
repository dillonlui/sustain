#!/bin/bash
# Publish a signed rehearsal feed on the dedicated staging branch only.
set -euo pipefail
[ "${SUSTAIN_PUBLISH_STAGING:-0}" = "1" ] || {
    echo "ERROR: staging feed publication was not explicitly enabled" >&2; exit 1;
}
APPCAST="${1:?signed appcast required}"
REPOSITORY="${SUSTAIN_STAGING_REPOSITORY:?owner/repository required}"
BRANCH="${SUSTAIN_STAGING_BRANCH:?staging branch required}"
[ "$BRANCH" = staging-updates ] || {
    echo "ERROR: staging publication requires the staging-updates branch" >&2; exit 1;
}
scripts/validate-appcast.sh "$APPCAST"

if ! HEAD_SHA="$(gh api "repos/$REPOSITORY/git/ref/heads/$BRANCH" --jq .object.sha 2>/dev/null)"; then
    gh api "repos/$REPOSITORY/git/refs" --method POST \
        -f "ref=refs/heads/$BRANCH" -f "sha=$GITHUB_SHA" >/dev/null
    HEAD_SHA="$GITHUB_SHA"
fi
BASE_TREE="$(gh api "repos/$REPOSITORY/git/commits/$HEAD_SHA" --jq .tree.sha)"
BLOB_SHA="$(base64 < "$APPCAST" | gh api "repos/$REPOSITORY/git/blobs" --method POST -f encoding=base64 -F content=@- --jq .sha)"
TREE_SHA="$(gh api "repos/$REPOSITORY/git/trees" --method POST -f base_tree="$BASE_TREE" \
    -f 'tree[][path]=appcast.xml' -f 'tree[][mode]=100644' -f 'tree[][type]=blob' \
    -f "tree[][sha]=$BLOB_SHA" --jq .sha)"
COMMIT_SHA="$(gh api "repos/$REPOSITORY/git/commits" --method POST \
    -f message='Publish signed Sustain staging appcast' -f tree="$TREE_SHA" \
    -f 'parents[]'="$HEAD_SHA" --jq .sha)"
gh api "repos/$REPOSITORY/git/refs/heads/$BRANCH" --method PATCH -f sha="$COMMIT_SHA" >/dev/null
