#!/usr/bin/env bats
# test_ninja_monitor_auto_deploy_done.bats - cmd_575 auto deploy trigger regression

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

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

declare -A AUTO_DEPLOY_DONE PANE_TARGETS
TEST_LOG="$(mktemp)"
LOG="$TEST_LOG"
CALLED=0
PANE_TARGETS[saizo]=""
AUTO_DEPLOY_DONE["saizo:subtask_575_impl_a"]=""

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  status: done
  task_id: subtask_575_impl_a
  parent_cmd: cmd_575
EOF

log() { echo "$1" >> "$TEST_LOG"; }
check_and_update_done_task() { CALLED=$((CALLED + 1)); return 0; }
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
sleep 0.2

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
