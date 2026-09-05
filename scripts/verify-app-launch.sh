#!/bin/bash
set -euo pipefail

APP="${1:?usage: verify-app-launch.sh APP}"
EXECUTABLE="$APP/Contents/MacOS/Sustain"
[ -x "$EXECUTABLE" ] || { echo "ERROR: app executable is missing: $EXECUTABLE" >&2; exit 1; }

LOG_FILE="$(mktemp -t sustain-launch.XXXXXX)"
PID=""
cleanup() {
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
    fi
    rm -f "$LOG_FILE"
}
trap cleanup EXIT

"$EXECUTABLE" >"$LOG_FILE" 2>&1 &
PID="$!"

# A dyld/signing failure exits immediately. Keeping the process alive for three
# seconds proves the packaged executable can load its embedded frameworks and
# reach the normal application run loop.
for _ in $(seq 1 30); do
    if ! kill -0 "$PID" 2>/dev/null; then
        set +e
        wait "$PID"
        STATUS="$?"
        set -e
        cat "$LOG_FILE" >&2
        echo "ERROR: packaged app exited during launch smoke test (status $STATUS)" >&2
        exit 1
    fi
    sleep 0.1
done

echo "Packaged app launch smoke test passed"
