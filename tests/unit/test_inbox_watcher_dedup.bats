#!/usr/bin/env bats
# test_inbox_watcher_dedup.bats - inbox_watcher singleton + atomic nudge dedup

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "T-IWD-001: same-agent second inbox_watcher exits on singleton lock" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/state"

cat > "$TMP_ROOT/bin/inotifywait" <<'"'"'SH'"'"'
#!/usr/bin/env bash
sleep 60
SH
chmod +x "$TMP_ROOT/bin/inotifywait"

export PATH="$TMP_ROOT/bin:$PATH"
export SHOGUN_STATE_DIR="$TMP_ROOT/state"
LOCK_FILE="$TMP_ROOT/state/inbox_watcher_singleton_saizo.lock"

(
    flock -n 209
    bash "$PROJECT_ROOT/scripts/inbox_watcher.sh" saizo dummy-pane 2>"$TMP_ROOT/err"
) 209>"$LOCK_FILE"

grep -q "already running for saizo" "$TMP_ROOT/err"
echo "SINGLETON_EXIT=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"SINGLETON_EXIT=yes"* ]]
}

@test "T-IWD-002: concurrent send_wakeup for one unread fingerprint sends once" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
mkdir -p "$TMP_ROOT/state"
touch "$TMP_ROOT/tmux.log"

export SHOGUN_STATE_DIR="$TMP_ROOT/state"
export PROJECT_ROOT TMP_ROOT

run_sender() {
    bash -c '"'"'
set -euo pipefail
export SHOGUN_STATE_DIR="$TMP_ROOT/state"
export INBOX_WATCHER_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/inbox_watcher.sh" saizo dummy-pane
unset INBOX_WATCHER_LIB_ONLY

get_effective_cli_type() { echo codex; }
agent_has_self_watch() { return 1; }
check_agent_busy() { return 0; }
sleep() { :; }
timeout() { shift; "$@"; }
tmux() {
    case "$1" in
        display-message)
            case "${*: -1}" in
                *pane_in_mode*) echo 0 ;;
                *) echo idle ;;
            esac
            ;;
        set-buffer) echo "SET_BUFFER $*" >> "$TMP_ROOT/tmux.log" ;;
        paste-buffer) echo "PASTE $*" >> "$TMP_ROOT/tmux.log" ;;
        send-keys) echo "ENTER $*" >> "$TMP_ROOT/tmux.log" ;;
        set-option) echo "SET_OPTION $*" >> "$TMP_ROOT/tmux.log" ;;
        *) ;;
    esac
}

send_wakeup 1 true msg_same
'"'"'
}

run_sender &
pid1=$!
run_sender &
pid2=$!
wait "$pid1"
wait "$pid2"

sent_count="$(grep -c "^PASTE " "$TMP_ROOT/tmux.log" || true)"
[ "$sent_count" = "1" ]
echo "WAKEUP_SENT_ONCE=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WAKEUP_SENT_ONCE=yes"* ]]
}
