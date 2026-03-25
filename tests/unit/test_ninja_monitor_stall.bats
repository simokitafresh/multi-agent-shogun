#!/usr/bin/env bats
# test_ninja_monitor_stall.bats - ninja_monitor stall recovery + misc behavior tests
# Merged: auto_deploy_done + snapshot_idle tests

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

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: assigned
  subtask_id: subtask_500_impl_stall_enforcement
EOF

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

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: in_progress
  subtask_id: subtask_500_impl_stall_enforcement
EOF

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

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: in_progress
  subtask_id: subtask_500_impl_stall_enforcement
EOF

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

# =============================================================================
# auto_deploy_done tests (merged from test_ninja_monitor_auto_deploy_done.bats)
# =============================================================================

@test "is_task_deployed: status=doneでもcheck_and_update_done_task経由でauto_deploy発火" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts"

declare -A AUTO_DEPLOY_DONE PANE_TARGETS UNCOMMITTED_BLOCK_SENT REPORT_GATE_SENT
TEST_LOG="$(mktemp)"
LOG="$TEST_LOG"
CALLED=0
PANE_TARGETS[saizo]=""
AUTO_DEPLOY_DONE["saizo:subtask_575_impl_a"]=""
UNCOMMITTED_BLOCK_SENT["saizo:cmd_575"]=""
REPORT_GATE_SENT["saizo:cmd_575"]=""

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  status: done
  task_id: subtask_575_impl_a
  parent_cmd: cmd_575
EOF

log() { echo "$1" >> "$TEST_LOG"; }
check_and_update_done_task() { CALLED=$((CALLED + 1)); return 0; }
find_matching_report_file() { echo ""; return 1; }
yaml_field_get() {
    case "$2" in
        status) echo "done" ;;
        task_id) echo "subtask_575_impl_a" ;;
        parent_cmd) echo "cmd_575" ;;
        *) echo "${3:-}" ;;
    esac
}
timeout() { echo "TIMEOUT:$*" >> "$TEST_LOG"; return 0; }

if is_task_deployed saizo; then
    echo "DEPLOYED=1"
else
    echo "DEPLOYED=0"
fi
sleep 0.05

if grep -q "TIMEOUT:30 bash $SCRIPT_DIR/scripts/auto_deploy_next.sh cmd_575 subtask_575_impl_a" "$TEST_LOG"; then
    echo "AUTO_DEPLOY_CALL=1"
else
    echo "AUTO_DEPLOY_CALL=0"
fi

echo "CALLED=$CALLED"
echo "AUTO_DEPLOY_KEY=${AUTO_DEPLOY_DONE[saizo:subtask_575_impl_a]:-0}"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEPLOYED=0"* ]]
    [[ "$output" == *"AUTO_DEPLOY_CALL=1"* ]]
    [[ "$output" == *"CALLED=1"* ]]
    [[ "$output" == *"AUTO_DEPLOY_KEY=1"* ]]
}

@test "is_task_deployed: status=doneかつ未完了判定ならauto_deploy発火しない" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A AUTO_DEPLOY_DONE PANE_TARGETS
TEST_LOG="$(mktemp)"
LOG="$TEST_LOG"
CALLED=0
PANE_TARGETS[saizo]=""

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  status: done
  task_id: subtask_575_impl_a
  parent_cmd: cmd_575
EOF

log() { echo "$1" >> "$TEST_LOG"; }
check_and_update_done_task() { CALLED=$((CALLED + 1)); return 1; }
yaml_field_get() {
    case "$2" in
        status) echo "done" ;;
        *) echo "${3:-}" ;;
    esac
}
timeout() { echo "TIMEOUT:$*" >> "$TEST_LOG"; return 0; }

if is_task_deployed saizo; then
    echo "DEPLOYED=1"
else
    echo "DEPLOYED=0"
fi

if grep -q "^TIMEOUT:" "$TEST_LOG"; then
    echo "AUTO_DEPLOY_CALL=1"
else
    echo "AUTO_DEPLOY_CALL=0"
fi

echo "CALLED=$CALLED"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEPLOYED=0"* ]]
    [[ "$output" == *"AUTO_DEPLOY_CALL=0"* ]]
    [[ "$output" == *"CALLED=1"* ]]
}

# =============================================================================
# snapshot_idle tests (merged from test_ninja_monitor_snapshot_idle.bats)
# =============================================================================

@test "write_karo_snapshot: assigned系タスクはidle行から除外し done/未配備のみ残す" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

NINJA_NAMES=(sasuke kirimaru hayate saizo kagemaru)
declare -A PREV_STATE
PREV_STATE[sasuke]="idle"
PREV_STATE[kirimaru]="idle"
PREV_STATE[hayate]="idle"
PREV_STATE[saizo]="idle"
PREV_STATE[kagemaru]="idle"

get_latest_report_file() { return 1; }
log() { :; }

cat > "$SCRIPT_DIR/queue/tasks/sasuke.yaml" <<'"'"'EOF'"'"'
task:
  task_id: cmd_634
  status: in_progress
  project: infra
EOF

cat > "$SCRIPT_DIR/queue/tasks/kirimaru.yaml" <<'"'"'EOF'"'"'
task:
  task_id: cmd_635
  status: acknowledged
  project: infra
EOF

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<'"'"'EOF'"'"'
task:
  task_id: cmd_636
  status: assigned
  project: infra
EOF

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  task_id: cmd_637
  status: done
  project: infra
EOF

write_karo_snapshot

snapshot="$SCRIPT_DIR/queue/karo_snapshot.txt"
grep "^ninja|sasuke|cmd_634|in_progress|infra|CTX:" "$snapshot"
grep "^ninja|kirimaru|cmd_635|acknowledged|infra|CTX:" "$snapshot"
grep "^ninja|hayate|cmd_636|assigned|infra|CTX:" "$snapshot"
grep "^ninja|saizo|cmd_637|done|infra|CTX:" "$snapshot"
grep "^ninja|kagemaru|none|idle|none|CTX:" "$snapshot"
grep "^idle|saizo,kagemaru$" "$snapshot"
'
    [ "$status" -eq 0 ]
}
