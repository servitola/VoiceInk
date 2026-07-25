#!/bin/bash
# Reproduces the crash that got the local wake word engine reverted in c61cdc7.
#
# With the detector capturing audio, opening the main window killed the app with
# EXC_BAD_ACCESS in swift_task_isCurrentExecutor while SwiftData's @Query checked
# its executor - a heap-corruption signature with no VoiceInk frame in the trace.
# The bisect in AGENTS.md established that it needs live capture and is
# independent of the recognition backend.
#
# Usage: scripts/wake-word-crash-repro.sh [app-path] [iterations]
#
# Exits non-zero if the app dies, so it can gate an install.

set -uo pipefail

APP="${1:-/Applications/VoiceInk.app}"
ITERATIONS="${2:-6}"
BIN="$APP/Contents/MacOS/VoiceInk"

if [ ! -x "$BIN" ]; then
    echo "No VoiceInk binary at $BIN"
    exit 2
fi

pid_of_app() { pgrep -f "^$BIN$" | head -1; }

echo "==> Restarting $APP"
pkill -f "^$BIN$" 2>/dev/null
sleep 2
open "$APP"

# The detector waits for AudioDeviceManager to publish its device list before it
# binds, so give it time to actually hold the microphone. Testing before capture
# starts is how you get a false pass: the bisect showed a build with the
# microphone missing was clean 6/6 while the same build crashed with it present.
echo "==> Waiting for wake word capture to start"
CAPTURING=0
for _ in $(seq 1 20); do
    sleep 1
    if log show --last 30s --predicate 'subsystem == "com.prakashjoshipax.voiceink" AND category == "WakeWordListeningService"' --level debug 2>/dev/null \
        | grep -q "Wake word listening on device"; then
        CAPTURING=1
        break
    fi
done

if [ "$CAPTURING" -eq 0 ]; then
    echo "WARNING: never saw the detector bind a device - this run proves nothing"
fi

PID=$(pid_of_app)
if [ -z "$PID" ]; then
    echo "FAIL: app is not running before the test even started"
    exit 1
fi
echo "==> App is pid $PID; opening the main window ${ITERATIONS}x"

for i in $(seq 1 "$ITERATIONS"); do
    open "$APP"
    sleep 3

    NOW=$(pid_of_app)
    if [ -z "$NOW" ]; then
        echo "FAIL: app died on window open #$i"
        exit 1
    fi
    if [ "$NOW" != "$PID" ]; then
        echo "FAIL: app restarted on window open #$i (was $PID, now $NOW) - it crashed"
        exit 1
    fi
    echo "  #$i ok (pid $NOW)"

    # Close it again so the next `open` really re-presents the window rather
    # than no-opping on an already-visible one. Scoped to VoiceInk's own process
    # so a stray cmd-W cannot land in whatever else the user has open.
    osascript -e 'tell application "System Events" to tell process "VoiceInk" to keystroke "w" using command down' >/dev/null 2>&1
    sleep 1
done

echo "PASS: ${ITERATIONS}/${ITERATIONS} window opens clean, app still pid $PID"
