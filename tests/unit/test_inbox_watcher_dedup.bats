#!/usr/bin/env bats
# test_inbox_watcher_dedup.bats - inbox_watcher singleton + atomic nudge dedup

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "T-IWD-000: input guard ignores non-prompt log lines" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
mkdir -p "$TMP_ROOT/state"

export SHOGUN_STATE_DIR="$TMP_ROOT/state"
export INBOX_WATCHER_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/inbox_watcher.sh" kirimaru dummy-pane
unset INBOX_WATCHER_LIB_ONLY

tmux() {
    case "$1" in
        capture-pane)
            cat <<'"'"'PANE'"'"'
Codex CLI (mock)
? for shortcuts                100% context left
› [mock_cli:kirimaru] STATE IDLE
[mock_cli:kirimaru] READY
PANE
            ;;
        *) return 1 ;;
    esac
}

if pane_input_line_has_text dummy-pane; then
    echo "INPUT_GUARD_FALSE_POSITIVE=yes"
    exit 1
fi
echo "INPUT_GUARD_IGNORES_LOG_LINE=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"INPUT_GUARD_IGNORES_LOG_LINE=yes"* ]]
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
echo "CI-DEBUG test1120 sent_count=$sent_count tmux_log_contents=$(cat "$TMP_ROOT/tmux.log" 2>/dev/null || echo EMPTY)" >&2
[ "$sent_count" = "1" ]
echo "WAKEUP_SENT_ONCE=yes"
'
    echo "CI-DEBUG test1120 status=$status output=$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"WAKEUP_SENT_ONCE=yes"* ]]
}

@test "T-IWD-003: unread fingerprint is stable across mtime and content-only changes" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
mkdir -p "$TMP_ROOT/root/scripts/lib" "$TMP_ROOT/root/lib" "$TMP_ROOT/root/queue/inbox" "$TMP_ROOT/state"
ln -s "$PROJECT_ROOT/scripts/lib/lock_path.sh" "$TMP_ROOT/root/scripts/lib/lock_path.sh"
ln -s "$PROJECT_ROOT/scripts/lib/cli_lookup.sh" "$TMP_ROOT/root/scripts/lib/cli_lookup.sh"
ln -s "$PROJECT_ROOT/scripts/lib/tmux_utils.sh" "$TMP_ROOT/root/scripts/lib/tmux_utils.sh"
ln -s "$PROJECT_ROOT/scripts/lib/script_update.sh" "$TMP_ROOT/root/scripts/lib/script_update.sh"
ln -s "$PROJECT_ROOT/lib/agent_state.sh" "$TMP_ROOT/root/lib/agent_state.sh"
ln -s "$PROJECT_ROOT/scripts/inbox_watcher.sh" "$TMP_ROOT/root/scripts/inbox_watcher.sh"

AGENT_ID="unit_fp_$$"
INBOX_FILE="$TMP_ROOT/root/queue/inbox/${AGENT_ID}.yaml"

cat > "$INBOX_FILE" <<'"'"'YAML'"'"'
messages:
- content: "first body"
  from: "karo"
  id: "msg_b"
  read: false
  timestamp: "2026-06-03T00:00:00"
  type: "task_assigned"
- content: "second body"
  from: "gunshi"
  id: "msg_a"
  read: false
  timestamp: "2026-06-03T00:00:01"
  type: "task_supplement"
YAML

export SHOGUN_STATE_DIR="$TMP_ROOT/state"
export INBOX_WATCHER_LIB_ONLY=1
source "$TMP_ROOT/root/scripts/inbox_watcher.sh" "$AGENT_ID" dummy-pane
unset INBOX_WATCHER_LIB_ONLY

first="$(get_unread_info)"
sed -i "s/first body/changed body/" "$INBOX_FILE"
touch "$INBOX_FILE"
second="$(get_unread_info)"

IFS=$'\''\t'\'' read -r first_count first_special first_fp first_specials first_task first_priority <<< "$first"
IFS=$'\''\t'\'' read -r second_count second_special second_fp second_specials second_task second_priority <<< "$second"

[ "$first_count" = "2" ]
[ "$second_count" = "2" ]
[ "$first_task" = "true" ]
[ "$second_task" = "true" ]
[ "$first_priority" = "high" ]
[ "$second_priority" = "high" ]
[ "$first_fp" = "$second_fp" ]
[[ "$first_fp" =~ ^[0-9a-f]{64}$ ]]
echo "MSG_ID_HASH_STABLE=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MSG_ID_HASH_STABLE=yes"* ]]
}

@test "T-IWD-004: nudge cooldown suppresses changed fingerprint within 30 seconds" {
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

send_wakeup 1 true "$(printf msg_a | sha256sum | cut -d " " -f1)"
send_wakeup 2 true "$(printf msg_a,msg_b | sha256sum | cut -d " " -f1)"

sent_count="$(grep -c "^PASTE " "$TMP_ROOT/tmux.log" || true)"
[ "$sent_count" = "1" ]
echo "COOLDOWN_30S_SUPPRESSED=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"COOLDOWN_30S_SUPPRESSED=yes"* ]]
}

@test "T-IWD-005: stale unread forces nudge even before fingerprint file exists" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
mkdir -p "$TMP_ROOT/state"
touch "$TMP_ROOT/tmux.log"

export SHOGUN_STATE_DIR="$TMP_ROOT/state"
export INBOX_WATCHER_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/inbox_watcher.sh" karo dummy-pane
unset INBOX_WATCHER_LIB_ONLY

get_effective_cli_type() { echo codex; }
agent_has_self_watch() { return 1; }
check_agent_busy() { return 1; }
cli_profile_get() { echo 30; }
sleep() { :; }
timeout() { shift; "$@"; }
tmux() {
    case "$1" in
        display-message)
            case "${*: -1}" in
                *pane_in_mode*) echo 0 ;;
                *) echo active ;;
            esac
            ;;
        set-buffer) echo "SET_BUFFER $*" >> "$TMP_ROOT/tmux.log" ;;
        paste-buffer) echo "PASTE $*" >> "$TMP_ROOT/tmux.log" ;;
        send-keys) echo "ENTER $*" >> "$TMP_ROOT/tmux.log" ;;
        set-option) echo "SET_OPTION $*" >> "$TMP_ROOT/tmux.log" ;;
        *) ;;
    esac
}

printf "%s" "$(( $(date +%s) - 65 ))" > "$FIRST_UNREAD_SEEN"
rm -f "$FINGERPRINT_FILE"

send_wakeup 1 false "$(printf msg_stale | sha256sum | cut -d " " -f1)" high

sent_count="$(grep -c "^PASTE " "$TMP_ROOT/tmux.log" || true)"
[ "$sent_count" = "1" ]
echo "STALE_UNREAD_FORCED_NUDGE=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"STALE_UNREAD_FORCED_NUDGE=yes"* ]]
}

@test "T-IWD-005A: input-guard deferred nudge retries same fingerprint instead of debounce-skip" {
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

get_effective_cli_type() { echo codex; }
agent_has_self_watch() { return 1; }
check_agent_busy() { return 0; }
sleep() { :; }
timeout() { shift; "$@"; }

input_has_text=1
tmux() {
    case "$1" in
        capture-pane)
            if [ "$input_has_text" = "1" ]; then
                printf "%s\n" "Codex CLI (mock)" "› partial input"
            else
                printf "%s\n" "Codex CLI (mock)" "›"
            fi
            ;;
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

fp="msg_input_guard"
send_wakeup 1 true "$fp" 2>"$TMP_ROOT/first.err" && exit 1
first_rc=$?
[ "$first_rc" = "2" ]
[ -s "$DEFERRED_NUDGE_FILE" ]
[ ! -f "$DEBOUNCE_FILE" ]

input_has_text=0
send_wakeup 1 true "$fp" 2>"$TMP_ROOT/second.err"

grep -q "DEFERRED-RETRY" "$TMP_ROOT/second.err"
sent_count="$(grep -c "^PASTE " "$TMP_ROOT/tmux.log" || true)"
[ "$sent_count" = "1" ]
[ ! -f "$DEFERRED_NUDGE_FILE" ]
echo "DEFERRED_RETRY_SENT=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEFERRED_RETRY_SENT=yes"* ]]
}

@test "T-IWD-005B: Codex active busy sends immediately despite nonempty generated UI line" {
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

get_effective_cli_type() { echo codex; }
agent_has_self_watch() { return 1; }
check_agent_busy() { return 1; }
cli_profile_get() { echo 30; }
sleep() { :; }
timeout() { shift; "$@"; }
tmux() {
    case "$1" in
        capture-pane) printf "%s\n" "Codex CLI (mock)" "› generated suggestion text" ;;
        display-message)
            case "${*: -1}" in
                *pane_in_mode*) echo 0 ;;
                *) echo active ;;
            esac
            ;;
        set-buffer) echo "SET_BUFFER $*" >> "$TMP_ROOT/tmux.log" ;;
        paste-buffer) echo "PASTE $*" >> "$TMP_ROOT/tmux.log" ;;
        send-keys) echo "ENTER $*" >> "$TMP_ROOT/tmux.log" ;;
        set-option) echo "SET_OPTION $*" >> "$TMP_ROOT/tmux.log" ;;
        *) ;;
    esac
}

send_wakeup 1 true "$(printf msg_codex_busy | sha256sum | cut -d " " -f1)" normal 2>"$TMP_ROOT/stderr.log"

grep -q "BUSY-CODEX-QUEUE" "$TMP_ROOT/stderr.log"
grep -q "INPUT-GUARD-BYPASS" "$TMP_ROOT/stderr.log"
sent_count="$(grep -c "^PASTE " "$TMP_ROOT/tmux.log" || true)"
[ "$sent_count" = "1" ]
echo "CODEX_BUSY_NONEMPTY_SENT=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"CODEX_BUSY_NONEMPTY_SENT=yes"* ]]
}

@test "T-IWD-005C: non-Codex active busy still defers before deadline" {
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

get_effective_cli_type() { echo kimi; }
agent_has_self_watch() { return 1; }
check_agent_busy() { return 1; }
cli_profile_get() { echo 30; }
sleep() { :; }
timeout() { shift; "$@"; }
tmux() {
    case "$1" in
        capture-pane) printf "%s\n" "Other CLI (mock)" "› typed input" ;;
        display-message)
            case "${*: -1}" in
                *pane_in_mode*) echo 0 ;;
                *) echo active ;;
            esac
            ;;
        set-buffer) echo "SET_BUFFER $*" >> "$TMP_ROOT/tmux.log" ;;
        paste-buffer) echo "PASTE $*" >> "$TMP_ROOT/tmux.log" ;;
        send-keys) echo "ENTER $*" >> "$TMP_ROOT/tmux.log" ;;
        set-option) echo "SET_OPTION $*" >> "$TMP_ROOT/tmux.log" ;;
        *) ;;
    esac
}

set +e
send_wakeup 1 true "$(printf msg_kimi_busy | sha256sum | cut -d " " -f1)" normal 2>"$TMP_ROOT/stderr.log"
rc=$?
set -e

[ "$rc" = "2" ]
grep -q "deferring nudge" "$TMP_ROOT/stderr.log"
sent_count="$(grep -c "^PASTE " "$TMP_ROOT/tmux.log" || true)"
[ "$sent_count" = "0" ]
echo "NON_CODEX_BUSY_DEFERRED=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NON_CODEX_BUSY_DEFERRED=yes"* ]]
}

@test "T-IWD-005D: Codex actual busy sends even when tmux agent_state is stale idle" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
mkdir -p "$TMP_ROOT/state"
touch "$TMP_ROOT/tmux.log"

export SHOGUN_STATE_DIR="$TMP_ROOT/state"
export INBOX_WATCHER_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/inbox_watcher.sh" karo dummy-pane
unset INBOX_WATCHER_LIB_ONLY

get_effective_cli_type() { echo codex; }
agent_has_self_watch() { return 1; }
check_agent_busy() { return 1; }
cli_profile_get() { echo 30; }
sleep() { :; }
timeout() { shift; "$@"; }
tmux() {
    case "$1" in
        capture-pane) printf "%s\n" "Codex CLI (mock)" "› generated suggestion text" ;;
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

send_wakeup 1 true "$(printf msg_codex_busy_stale_idle | sha256sum | cut -d " " -f1)" normal 2>"$TMP_ROOT/stderr.log"

grep -q "BUSY-CODEX-QUEUE" "$TMP_ROOT/stderr.log"
grep -q "INPUT-GUARD-BYPASS" "$TMP_ROOT/stderr.log"
sent_count="$(grep -c "^PASTE " "$TMP_ROOT/tmux.log" || true)"
[ "$sent_count" = "1" ]
echo "CODEX_BUSY_STALE_IDLE_SENT=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"CODEX_BUSY_STALE_IDLE_SENT=yes"* ]]
}

@test "T-IWD-006: same unread fingerprint does not retry before backoff" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
mkdir -p "$TMP_ROOT/state"
touch "$TMP_ROOT/tmux.log"

export SHOGUN_STATE_DIR="$TMP_ROOT/state"
export NUDGE_COOLDOWN_SEC=1
export BACKOFF_SEC=120
export INBOX_WATCHER_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/inbox_watcher.sh" karo dummy-pane
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

fp="$(printf msg_same | sha256sum | cut -d " " -f1)"
send_wakeup 1 false "$fp"
printf "%s" "$(( $(date +%s) - 5 ))" > "$DEBOUNCE_FILE"
send_wakeup 1 false "$fp"

sent_count="$(grep -c "^PASTE " "$TMP_ROOT/tmux.log" || true)"
[ "$sent_count" = "1" ]
echo "SAME_FP_NO_IMMEDIATE_RETRY=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"SAME_FP_NO_IMMEDIATE_RETRY=yes"* ]]
}

@test "T-IWD-007: inbox_watcher self-restart releases the actual singleton fd" {
    grep -q 'exec 209>"$SINGLETON_LOCK_FILE"' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    grep -q 'SCRIPT_UPDATE_SINGLETON_FD=209' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    grep -q 'SCRIPT_UPDATE_SINGLETON_FD' "$PROJECT_ROOT/scripts/lib/script_update.sh"
}

@test "T-IWD-008: unread priority is derived from message type" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
mkdir -p "$TMP_ROOT/root/scripts/lib" "$TMP_ROOT/root/lib" "$TMP_ROOT/root/queue/inbox" "$TMP_ROOT/state"
ln -s "$PROJECT_ROOT/scripts/lib/lock_path.sh" "$TMP_ROOT/root/scripts/lib/lock_path.sh"
ln -s "$PROJECT_ROOT/scripts/lib/cli_lookup.sh" "$TMP_ROOT/root/scripts/lib/cli_lookup.sh"
ln -s "$PROJECT_ROOT/scripts/lib/tmux_utils.sh" "$TMP_ROOT/root/scripts/lib/tmux_utils.sh"
ln -s "$PROJECT_ROOT/scripts/lib/script_update.sh" "$TMP_ROOT/root/scripts/lib/script_update.sh"
ln -s "$PROJECT_ROOT/lib/agent_state.sh" "$TMP_ROOT/root/lib/agent_state.sh"
ln -s "$PROJECT_ROOT/scripts/inbox_watcher.sh" "$TMP_ROOT/root/scripts/inbox_watcher.sh"

AGENT_ID="unit_priority_$$"
INBOX_FILE="$TMP_ROOT/root/queue/inbox/${AGENT_ID}.yaml"

cat > "$INBOX_FILE" <<'"'"'YAML'"'"'
messages:
- content: "review"
  from: "gunshi"
  id: "msg_review"
  read: false
  timestamp: "2026-07-08T00:00:00"
  type: "report_review"
YAML

export SHOGUN_STATE_DIR="$TMP_ROOT/state"
export INBOX_WATCHER_LIB_ONLY=1
source "$TMP_ROOT/root/scripts/inbox_watcher.sh" "$AGENT_ID" dummy-pane
unset INBOX_WATCHER_LIB_ONLY

info="$(get_unread_info)"
IFS=$'\''\t'\'' read -r count specials fp special_payload has_task priority <<< "$info"
[ "$count" = "1" ]
[ "$priority" = "high" ]

cat > "$INBOX_FILE" <<'"'"'YAML'"'"'
messages:
- content: "clear"
  from: "karo"
  id: "msg_gate"
  read: false
  timestamp: "2026-07-08T00:00:00"
  type: "gate_clear"
YAML

info="$(get_unread_info)"
IFS=$'\''\t'\'' read -r count specials fp special_payload has_task priority <<< "$info"
[ "$count" = "1" ]
[ "$priority" = "low" ]
echo "PRIORITY_DERIVED=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PRIORITY_DERIVED=yes"* ]]
}

@test "T-IWD-009: busy high-priority unread sends after deadline but low-priority defers" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
mkdir -p "$TMP_ROOT/state"
touch "$TMP_ROOT/tmux.log"

export SHOGUN_STATE_DIR="$TMP_ROOT/state"
export HIGH_PRIORITY_NUDGE_DEADLINE_SEC=60
export LOW_PRIORITY_NUDGE_DEADLINE_SEC=600
export INBOX_WATCHER_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/inbox_watcher.sh" saizo dummy-pane
unset INBOX_WATCHER_LIB_ONLY

get_effective_cli_type() { echo kimi; }
agent_has_self_watch() { return 1; }
check_agent_busy() { return 1; }
cli_profile_get() { echo 30; }
sleep() { :; }
timeout() { shift; "$@"; }
tmux() {
    case "$1" in
        display-message)
            case "${*: -1}" in
                *pane_in_mode*) echo 0 ;;
                *) echo active ;;
            esac
            ;;
        set-buffer) echo "SET_BUFFER $*" >> "$TMP_ROOT/tmux.log" ;;
        paste-buffer) echo "PASTE $*" >> "$TMP_ROOT/tmux.log" ;;
        send-keys) echo "ENTER $*" >> "$TMP_ROOT/tmux.log" ;;
        set-option) echo "SET_OPTION $*" >> "$TMP_ROOT/tmux.log" ;;
        *) ;;
    esac
}

printf "%s" "$(( $(date +%s) - 65 ))" > "$FIRST_UNREAD_SEEN"
send_wakeup 1 false "$(printf msg_high | sha256sum | cut -d " " -f1)" high
high_sent="$(grep -c "^PASTE " "$TMP_ROOT/tmux.log" || true)"
[ "$high_sent" = "1" ]

: > "$TMP_ROOT/tmux.log"
rm -f "$FINGERPRINT_FILE" "$DEBOUNCE_FILE" "$STATE_DIR"/inbox_watcher_sent_saizo_*
printf "%s" "$(( $(date +%s) - 65 ))" > "$FIRST_UNREAD_SEEN"
set +e
send_wakeup 1 false "$(printf msg_low | sha256sum | cut -d " " -f1)" low
rc=$?
set -e
low_sent="$(grep -c "^PASTE " "$TMP_ROOT/tmux.log" || true)"
[ "$rc" = "2" ]
[ "$low_sent" = "0" ]
echo "PRIORITY_BUSY_DEADLINE_OK=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PRIORITY_BUSY_DEADLINE_OK=yes"* ]]
}

@test "T-IWD-010: input guard defers nudge when pane input line has unsent text" {
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
        capture-pane) printf "› honbannwo" ;;
        set-buffer) echo "SET_BUFFER $*" >> "$TMP_ROOT/tmux.log" ;;
        paste-buffer) echo "PASTE $*" >> "$TMP_ROOT/tmux.log" ;;
        send-keys) echo "ENTER $*" >> "$TMP_ROOT/tmux.log" ;;
        set-option) echo "SET_OPTION $*" >> "$TMP_ROOT/tmux.log" ;;
        *) ;;
    esac
}

set +e
send_wakeup 1 true "$(printf msg_input_guard | sha256sum | cut -d " " -f1)" high 2> "$TMP_ROOT/stderr.log"
rc=$?
set -e

paste_count="$(grep -c "^PASTE " "$TMP_ROOT/tmux.log" || true)"
enter_count="$(grep -c "^ENTER " "$TMP_ROOT/tmux.log" || true)"
[ "$rc" = "2" ]
[ "$paste_count" = "0" ]
[ "$enter_count" = "0" ]
grep -q "\[INPUT-GUARD\] Deferring nudge for saizo" "$TMP_ROOT/stderr.log"
echo "INPUT_GUARD_DEFERRED=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"INPUT_GUARD_DEFERRED=yes"* ]]
}

@test "T-IWD-010A: Codex dim idle suggestion is not treated as unsent input" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export INBOX_WATCHER_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/inbox_watcher.sh" hanzo dummy-pane
unset INBOX_WATCHER_LIB_ONLY

tmux() {
    if [[ "$*" == *" -e "* ]]; then
        printf "\\033[1m›\\033[0m \\033[2mImprove documentation in @filename\\033[0m\\n"
    else
        printf "› Improve documentation in @filename\\n"
    fi
}

if pane_input_line_has_text dummy-pane codex; then
    echo "DIM_SUGGESTION_MISCLASSIFIED=yes"
    exit 1
fi
echo "DIM_SUGGESTION_ALLOWED=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"DIM_SUGGESTION_ALLOWED=yes"* ]]
}

@test "T-IWD-011: input guard allows nudge when pane input line is empty prompt" {
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
        capture-pane) printf "› 95%% context left" ;;
        set-buffer) echo "SET_BUFFER $*" >> "$TMP_ROOT/tmux.log" ;;
        paste-buffer) echo "PASTE $*" >> "$TMP_ROOT/tmux.log" ;;
        send-keys) echo "ENTER $*" >> "$TMP_ROOT/tmux.log" ;;
        set-option) echo "SET_OPTION $*" >> "$TMP_ROOT/tmux.log" ;;
        *) ;;
    esac
}

send_wakeup 1 true "$(printf msg_empty_prompt | sha256sum | cut -d " " -f1)" high

paste_count="$(grep -c "^PASTE " "$TMP_ROOT/tmux.log" || true)"
enter_count="$(grep -c "^ENTER " "$TMP_ROOT/tmux.log" || true)"
[ "$paste_count" = "1" ]
[ "$enter_count" = "1" ]
echo "INPUT_GUARD_ALLOWED_EMPTY_PROMPT=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"INPUT_GUARD_ALLOWED_EMPTY_PROMPT=yes"* ]]
}

@test "T-IWD-012: input guard allows Claude idle prompt with NBSP" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
mkdir -p "$TMP_ROOT/state"
touch "$TMP_ROOT/tmux.log"

export SHOGUN_STATE_DIR="$TMP_ROOT/state"
export INBOX_WATCHER_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/inbox_watcher.sh" gunshi dummy-pane
unset INBOX_WATCHER_LIB_ONLY
touch "$TMP_ROOT/state/shogun_idle_gunshi"

get_effective_cli_type() { echo claude; }
agent_has_self_watch() { return 1; }
check_agent_busy() { return 0; }
sleep() { :; }
timeout() { shift; "$@"; }
tmux() {
    case "$1" in
        display-message)
            case "${*: -1}" in
                *pane_in_mode*) echo 0 ;;
                *agent_id*) echo gunshi ;;
                *) echo idle ;;
            esac
            ;;
        capture-pane)
            printf "%b" "─────────────────────────────────────────────────────────────\n❯\302\240\n─────────────────────────────────────────────────────────────\n  CTX:42%%\n  ⏵⏵ bypass permissions on (shift+tab to cycle)\n"
            ;;
        set-buffer) echo "SET_BUFFER $*" >> "$TMP_ROOT/tmux.log" ;;
        paste-buffer) echo "PASTE $*" >> "$TMP_ROOT/tmux.log" ;;
        send-keys) echo "ENTER $*" >> "$TMP_ROOT/tmux.log" ;;
        set-option) echo "SET_OPTION $*" >> "$TMP_ROOT/tmux.log" ;;
        *) ;;
    esac
}

send_wakeup 1 true "$(printf msg_claude_nbsp_prompt | sha256sum | cut -d " " -f1)" high

paste_count="$(grep -c "^PASTE " "$TMP_ROOT/tmux.log" || true)"
enter_count="$(grep -c "^ENTER " "$TMP_ROOT/tmux.log" || true)"
[ "$paste_count" = "1" ]
[ "$enter_count" = "1" ]
echo "INPUT_GUARD_ALLOWED_CLAUDE_NBSP_PROMPT=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"INPUT_GUARD_ALLOWED_CLAUDE_NBSP_PROMPT=yes"* ]]
}
