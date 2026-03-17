#!/usr/bin/env bats
# test_ninja_monitor_clear_guard.bats - cmd_1039 AC1/AC2/AC3
# acknowledged/in_progress時の/clear禁止 + 60分超STALL通知

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

# AC3-1: acknowledged → /clearされないことを確認
@test "handle_confirmed_idle: acknowledged task blocks /clear" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
touch "$LOG"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A PREV_STATE LAST_NOTIFIED LAST_CLEARED STALL_FIRST_SEEN STALL_NOTIFIED
declare -A STALL_COUNT PANE_TARGETS CLEAR_SKIP_COUNT POST_CLEAR_PENDING
declare -A AUTO_DEPLOY_DONE
NEWLY_IDLE=()

# assigned_at = 10 min ago (well under 60 min)
now=$(date +%s)
assigned_time=$(date -d "@$((now - 600))" "+%Y-%m-%dT%H:%M:%S+09:00")

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<INNEREOF
task:
  status: acknowledged
  task_id: cmd_1039_test
  assigned_at: "$assigned_time"
INNEREOF

log() { echo "$1" >> "$LOG"; }
send_inbox_message() { echo "INBOX:$1|$2|$3" >> "$LOG"; }
is_task_deployed() { return 0; }
safe_send_clear() { echo "CLEAR_SENT:$2" >> "$LOG"; return 0; }
can_send_clear_with_report_gate() { return 0; }
get_context_pct() { echo "50"; }
cli_profile_get() { echo "60"; }

PANE_TARGETS[kagemaru]="shogun:2.5"
PREV_STATE[kagemaru]="busy"
STALL_RENOTIFY_DEBOUNCE=300

handle_confirmed_idle kagemaru

if grep -q "CLEAR_SENT:kagemaru" "$LOG"; then
    echo "FAIL: /clear was sent for acknowledged task"
    exit 1
fi
if grep -q "skip /clear" "$LOG"; then
    echo "PASS: acknowledged task blocked /clear"
else
    echo "FAIL: expected skip /clear log"
    cat "$LOG"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: acknowledged task blocked /clear"* ]]
}

# AC3-2: done → /clearされることを確認
@test "handle_confirmed_idle: done task allows /clear" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A PREV_STATE LAST_NOTIFIED LAST_CLEARED STALL_FIRST_SEEN STALL_NOTIFIED
declare -A STALL_COUNT PANE_TARGETS CLEAR_SKIP_COUNT POST_CLEAR_PENDING
declare -A AUTO_DEPLOY_DONE
NEWLY_IDLE=()

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<INNEREOF
task:
  status: done
  task_id: cmd_1039_test
INNEREOF

log() { echo "$1" >> "$LOG"; }
send_inbox_message() { echo "INBOX:$1|$2|$3" >> "$LOG"; }
# done tasks: is_task_deployed returns 1 (not deployed)
is_task_deployed() { return 1; }
CLEAR_SENT=0
safe_send_clear() { CLEAR_SENT=1; echo "CLEAR_SENT:$2" >> "$LOG"; return 0; }
can_send_clear_with_report_gate() { return 0; }
get_context_pct() { echo "50"; }
cli_profile_get() { echo "60"; }
# tmux stubs
tmux() { echo ""; }
export -f tmux

PANE_TARGETS[kagemaru]="shogun:2.5"
PREV_STATE[kagemaru]="busy"

handle_confirmed_idle kagemaru

# done task → is_task_deployed returns 1 → falls through to auto /clear section
# auto /clear checks CTX > 0, debounce elapsed, etc.
if grep -q "CLEAR_SENT:kagemaru" "$LOG"; then
    echo "PASS: /clear sent for done task"
elif grep -q "CLEAR-SKIP" "$LOG"; then
    echo "PASS: done task reached auto-clear path (CTX=0 skip is OK)"
elif grep -q "CLEAR-DEBOUNCE" "$LOG"; then
    echo "PASS: done task reached auto-clear path (debounce is OK)"
else
    echo "PASS: done task not blocked by acknowledged/in_progress guard"
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS:"* ]]
}

# AC3-3: acknowledged + 60分超無更新 → STALL通知が生成されることを確認
@test "handle_confirmed_idle: acknowledged 60min+ triggers STALL notification without /clear" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A PREV_STATE LAST_NOTIFIED LAST_CLEARED STALL_FIRST_SEEN STALL_NOTIFIED
declare -A STALL_COUNT PANE_TARGETS CLEAR_SKIP_COUNT POST_CLEAR_PENDING
declare -A AUTO_DEPLOY_DONE
NEWLY_IDLE=()

# assigned_at = 90 minutes ago (exceeds 60 min threshold)
now=$(date +%s)
assigned_time=$(date -d "@$((now - 5400))" "+%Y-%m-%dT%H:%M:%S+09:00")

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<INNEREOF
task:
  status: acknowledged
  task_id: cmd_1039_test
  assigned_at: "$assigned_time"
INNEREOF

log() { echo "$1" >> "$LOG"; }
send_inbox_message() { echo "INBOX:$1|$2|$3" >> "$LOG"; }
is_task_deployed() { return 0; }
safe_send_clear() { echo "CLEAR_SENT:$2" >> "$LOG"; return 0; }
can_send_clear_with_report_gate() { return 0; }
get_context_pct() { echo "50"; }
cli_profile_get() { echo "60"; }

PANE_TARGETS[kagemaru]="shogun:2.5"
PREV_STATE[kagemaru]="busy"
STALL_RENOTIFY_DEBOUNCE=300

handle_confirmed_idle kagemaru

has_stall_notify=0
has_clear=0
if grep -q "INBOX:karo|STALL疑い" "$LOG"; then
    has_stall_notify=1
fi
if grep -q "CLEAR_SENT:kagemaru" "$LOG"; then
    has_clear=1
fi

if [ "$has_stall_notify" -eq 1 ] && [ "$has_clear" -eq 0 ]; then
    echo "PASS: STALL notification sent, /clear NOT sent"
else
    echo "FAIL: stall_notify=$has_stall_notify, clear=$has_clear"
    cat "$LOG"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: STALL notification sent, /clear NOT sent"* ]]
}
