#!/usr/bin/env bats
# test_ninja_monitor_stall.bats - cmd_500 stall recovery behavior tests

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "check_stall: same ninja x task re-notifies after 5-minute debounce" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TEST_MESSAGES"; }
check_idle() { return 0; }
yaml_field_get() {
    case "$2" in
        status) echo "assigned" ;;
        subtask_id) echo "subtask_500_impl_stall_enforcement" ;;
        task_id) echo "" ;;
        progress_updated_at) echo "" ;;
        *) echo "${3:-}" ;;
    esac
}
cli_profile_get() { echo ""; }

PANE_TARGETS[kagemaru]="shogun:2.5"
now=$(date +%s)
stall_key="kagemaru:subtask_500_impl_stall_enforcement"

STALL_FIRST_SEEN[kagemaru]=$((now - 16 * 60))
STALL_NOTIFIED["$stall_key"]=$((now - 120))
check_stall kagemaru

STALL_FIRST_SEEN[kagemaru]=$((now - 16 * 60))
STALL_NOTIFIED["$stall_key"]=$((now - 301))
check_stall kagemaru

echo "ALERT_COUNT=$(grep -c "|stall_alert|" "$TEST_MESSAGES" || true)"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT_COUNT=1"* ]]
}

@test "check_stall: in_progress stall sends task_assigned recovery and log" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TEST_MESSAGES"; }
check_idle() { return 0; }
yaml_field_get() {
    case "$2" in
        status) echo "in_progress" ;;
        subtask_id) echo "subtask_500_impl_stall_enforcement" ;;
        task_id) echo "" ;;
        progress_updated_at) echo "" ;;
        *) echo "${3:-}" ;;
    esac
}
cli_profile_get() {
    case "$2" in
        in_progress_stall_min) echo "1" ;;
        *) echo "" ;;
    esac
}

PANE_TARGETS[kagemaru]="shogun:2.5"
now=$(date +%s)
STALL_FIRST_SEEN[kagemaru]=$((now - 2 * 60))
check_stall kagemaru

cat "$TEST_MESSAGES"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo|stall_alert|"* ]]
    [[ "$output" == *"kagemaru|task_assigned|"* ]]
    [[ "$output" == *"STALL-RECOVERY-SEND:"* ]]
}

@test "check_stall: repeated same-task stalls trigger stall_escalate with mandatory replacement" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TEST_MESSAGES"; }
check_idle() { return 0; }
yaml_field_get() {
    case "$2" in
        status) echo "in_progress" ;;
        subtask_id) echo "subtask_500_impl_stall_enforcement" ;;
        task_id) echo "" ;;
        progress_updated_at) echo "" ;;
        *) echo "${3:-}" ;;
    esac
}
cli_profile_get() {
    case "$2" in
        in_progress_stall_min) echo "1" ;;
        *) echo "" ;;
    esac
}

PANE_TARGETS[kagemaru]="shogun:2.5"
now=$(date +%s)
stall_key="kagemaru:subtask_500_impl_stall_enforcement"
STALL_COUNT["$stall_key"]=1
STALL_NOTIFIED["$stall_key"]=$((now - 301))
STALL_FIRST_SEEN[kagemaru]=$((now - 2 * 60))
check_stall kagemaru

cat "$TEST_MESSAGES"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo|stall_escalate|"* ]]
    [[ "$output" == *"差し替え必須"* ]]
}
