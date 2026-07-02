#!/usr/bin/env bats
# test_inbox_watcher_delivery_latency.bats — cmd_3646 AC1
# busy gatingで保留されたnudgeの「保留開始(first-unread)→実配達完了」レイテンシがログ出力され、
# しきい値超過時は警告行として記録されることを確認する。

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "T-DL-001: delivery latency is logged on successful nudge" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
mkdir -p "$TMP_ROOT/state"
touch "$TMP_ROOT/tmux.log"

export SHOGUN_STATE_DIR="$TMP_ROOT/state"
export INBOX_WATCHER_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/inbox_watcher.sh" saizo dummy-pane
unset INBOX_WATCHER_LIB_ONLY

# 保留開始(first-unread)を5秒前に固定 — しきい値(60s)未満
printf "%s" "$(( $(date +%s) - 5 ))" > "$FIRST_UNREAD_SEEN"

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

send_wakeup 1 true msg_latency_ok 2> "$TMP_ROOT/stderr.log"

grep -qE "\[DELIVERY-LATENCY\] saizo: [0-9]+s from first-unread to delivery" "$TMP_ROOT/stderr.log"
! grep -q "DELIVERY-LATENCY-WARN" "$TMP_ROOT/stderr.log"
echo "LATENCY_LOGGED_NO_WARN=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"LATENCY_LOGGED_NO_WARN=yes"* ]]
}

@test "T-DL-002: delivery latency over threshold emits WARN line" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
mkdir -p "$TMP_ROOT/state"
touch "$TMP_ROOT/tmux.log"

export SHOGUN_STATE_DIR="$TMP_ROOT/state"
export DELIVERY_LATENCY_WARN_SEC=60
export INBOX_WATCHER_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/inbox_watcher.sh" saizo dummy-pane
unset INBOX_WATCHER_LIB_ONLY

# 保留開始(first-unread)を65秒前に固定 — しきい値(60s)超過。
# 実運用でも観測された値(logs/inbox_watcher_hayate.log 2026-07-02 13:43:33→13:44:29 の56s保留)を上回る水準。
printf "%s" "$(( $(date +%s) - 65 ))" > "$FIRST_UNREAD_SEEN"

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

send_wakeup 1 true msg_latency_warn 2> "$TMP_ROOT/stderr.log"

grep -qE "\[DELIVERY-LATENCY\] saizo: (6[5-9]|[7-9][0-9])s from first-unread to delivery" "$TMP_ROOT/stderr.log"
grep -qE "\[DELIVERY-LATENCY-WARN\] saizo: held (6[5-9]|[7-9][0-9])s >= 60s threshold" "$TMP_ROOT/stderr.log"
echo "LATENCY_WARN_EMITTED=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"LATENCY_WARN_EMITTED=yes"* ]]
}
