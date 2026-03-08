#!/usr/bin/env bats
# test_ntfy_listener.bats - ntfy_listener watchdog/message activity tests

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export LISTENER_SCRIPT="$PROJECT_ROOT/scripts/ntfy_listener.sh"
    [ -f "$LISTENER_SCRIPT" ] || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/ntfy_listener_test.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export INBOX_FILE="$TEST_PROJECT/queue/ntfy_inbox.yaml"
    export SCREENSHOT_DIR_TEST="$TEST_PROJECT/screenshots"
    export CURL_LOG="$TEST_TMPDIR/curl.log"
    export INBOX_WRITE_LOG="$TEST_TMPDIR/inbox_write.log"

    mkdir -p "$TEST_PROJECT/scripts" "$TEST_PROJECT/queue" "$SCREENSHOT_DIR_TEST" "$TEST_TMPDIR/bin"
    printf 'inbox:\n' > "$INBOX_FILE"
    : > "$INBOX_WRITE_LOG"

    cat > "$TEST_PROJECT/scripts/inbox_write.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$INBOX_WRITE_LOG"
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/inbox_write.sh"

    cat > "$TEST_TMPDIR/bin/curl" <<'EOF'
#!/bin/bash
echo "$@" >> "$CURL_LOG"
outfile=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o)
            outfile="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [ -n "$outfile" ]; then
    printf 'image-bytes' > "$outfile"
fi
EOF
    chmod +x "$TEST_TMPDIR/bin/curl"

    export PATH="$TEST_TMPDIR/bin:$PATH"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "T-NTFY-001: keepalive/open events do not update LAST_MESSAGE_ACTIVITY" {
    run bash -lc '
set -euo pipefail
LISTENER_SCRIPT="'"$LISTENER_SCRIPT"'"
TEST_PROJECT="'"$TEST_PROJECT"'"
INBOX_FILE="'"$INBOX_FILE"'"
SCREENSHOT_DIR_TEST="'"$SCREENSHOT_DIR_TEST"'"

export NTFY_LISTENER_LIB_ONLY=1
source "$LISTENER_SCRIPT"
unset NTFY_LISTENER_LIB_ONLY

SCRIPT_DIR="$TEST_PROJECT"
INBOX="$INBOX_FILE"
SCREENSHOT_DIR="$SCREENSHOT_DIR_TEST"
AUTH_ARGS=()
tmux() { return 1; }

LAST_MESSAGE_ACTIVITY=123
process_stream_line "{\"event\":\"open\"}"
[ "$LAST_MESSAGE_ACTIVITY" -eq 123 ]
process_stream_line "{\"event\":\"keepalive\"}"
[ "$LAST_MESSAGE_ACTIVITY" -eq 123 ]
'
    [ "$status" -eq 0 ]
}

@test "T-NTFY-002: inbound message updates LAST_MESSAGE_ACTIVITY only after processing" {
    run bash -lc '
set -euo pipefail
LISTENER_SCRIPT="'"$LISTENER_SCRIPT"'"
TEST_PROJECT="'"$TEST_PROJECT"'"
INBOX_FILE="'"$INBOX_FILE"'"
SCREENSHOT_DIR_TEST="'"$SCREENSHOT_DIR_TEST"'"

export NTFY_LISTENER_LIB_ONLY=1
source "$LISTENER_SCRIPT"
unset NTFY_LISTENER_LIB_ONLY

SCRIPT_DIR="$TEST_PROJECT"
INBOX="$INBOX_FILE"
SCREENSHOT_DIR="$SCREENSHOT_DIR_TEST"
AUTH_ARGS=()
tmux() { return 1; }

LAST_MESSAGE_ACTIVITY=123
process_stream_line "{\"event\":\"message\",\"id\":\"msg-1\",\"message\":\"hello from ntfy\"}"
[ "$LAST_MESSAGE_ACTIVITY" -gt 123 ]
grep -q "hello from ntfy" "$INBOX"
'
    [ "$status" -eq 0 ]
}

@test "T-NTFY-003: message watchdog triggers reconnect even when stream bytes are recent" {
    run bash -lc '
set -euo pipefail
LISTENER_SCRIPT="'"$LISTENER_SCRIPT"'"

export NTFY_LISTENER_LIB_ONLY=1
source "$LISTENER_SCRIPT"
unset NTFY_LISTENER_LIB_ONLY

STREAM_WATCHDOG_SECS=1800
STREAM_READ_WATCHDOG_SECS=120
RECONNECT_REASON=""
WATCHDOG_LOG_MSG=""

should_restart_stream 2000 1950 100
[ "$?" -eq 0 ]
[ "$RECONNECT_REASON" = "Message activity timeout" ]
echo "$WATCHDOG_LOG_MSG" | grep -q "no inbound messages"
'
    [ "$status" -eq 0 ]
}

@test "T-NTFY-004: attachment download curl is bounded by --max-time 30" {
    run bash -lc '
set -euo pipefail
LISTENER_SCRIPT="'"$LISTENER_SCRIPT"'"
TEST_PROJECT="'"$TEST_PROJECT"'"
INBOX_FILE="'"$INBOX_FILE"'"
SCREENSHOT_DIR_TEST="'"$SCREENSHOT_DIR_TEST"'"
CURL_LOG="'"$CURL_LOG"'"
PATH="'"$TEST_TMPDIR"'/bin:$PATH"

export CURL_LOG
export NTFY_LISTENER_LIB_ONLY=1
source "$LISTENER_SCRIPT"
unset NTFY_LISTENER_LIB_ONLY

SCRIPT_DIR="$TEST_PROJECT"
INBOX="$INBOX_FILE"
SCREENSHOT_DIR="$SCREENSHOT_DIR_TEST"
AUTH_ARGS=()

download_attachment_image "https://example.com/test.png" >/dev/null
grep -q -- "--max-time 30" "$CURL_LOG"
'
    [ "$status" -eq 0 ]
}

@test "T-NTFY-005: image attachment is saved with timestamped original name and notifies shogun" {
    run bash -lc '
set -euo pipefail
LISTENER_SCRIPT="'"$LISTENER_SCRIPT"'"
TEST_PROJECT="'"$TEST_PROJECT"'"
INBOX_FILE="'"$INBOX_FILE"'"
SCREENSHOT_DIR_TEST="'"$SCREENSHOT_DIR_TEST"'"
INBOX_WRITE_LOG="'"$INBOX_WRITE_LOG"'"
PATH="'"$TEST_TMPDIR"'/bin:$PATH"

export INBOX_WRITE_LOG
export NTFY_LISTENER_LIB_ONLY=1
source "$LISTENER_SCRIPT"
unset NTFY_LISTENER_LIB_ONLY

SCRIPT_DIR="$TEST_PROJECT"
INBOX="$INBOX_FILE"
SCREENSHOT_DIR="$SCREENSHOT_DIR_TEST"
AUTH_ARGS=()
tmux() { return 1; }

process_stream_line "{\"event\":\"message\",\"id\":\"msg-img-1\",\"message\":\"\",\"attachment\":{\"type\":\"image/png\",\"url\":\"https://example.com/test.png\",\"name\":\"screen cap.png\"}}"
saved_file=$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f -name "*screen_cap.png" ! -name latest.png | head -n 1)
[ -n "$saved_file" ]
[ -f "$SCREENSHOT_DIR/latest.png" ]
grep -q "shogun" "$INBOX_WRITE_LOG"
grep -q "screenshot_received" "$INBOX_WRITE_LOG"
'
    [ "$status" -eq 0 ]
}
