#!/usr/bin/env bats
# test_ninja_monitor_stale_grace.bats - cmd_1049 STALE-TASK deployed_at grace period tests

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "STALE-TASK-GRACE: deployed <5min ago bypasses STALE-TASK detection" {
    DEPLOYED_AT=$(date -d "2 minutes ago" "+%Y-%m-%dT%H:%M:%S")
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
DEPLOYED_AT="'"$DEPLOYED_AT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS AUTO_DEPLOY_DONE
TEST_LOG="$(mktemp)"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<EOF
task:
  status: assigned
  deployed_at: "$DEPLOYED_AT"
  parent_cmd: cmd_1049
EOF

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { :; }
check_idle() { return 0; }
check_and_update_done_task() { return 1; }
cli_profile_get() { echo ""; }

PANE_TARGETS[kagemaru]="shogun:2.5"

tmux() { echo ""; }
export -f tmux

is_task_deployed kagemaru
rc=$?
echo "RC=$rc"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"RC=0"* ]]
    [[ "$output" == *"STALE-TASK-GRACE: kagemaru deployed"* ]]
    [[ "$output" == *"within grace period"* ]]
}

@test "STALE-TASK: deployed >5min ago triggers normal STALE-TASK" {
    DEPLOYED_AT=$(date -d "10 minutes ago" "+%Y-%m-%dT%H:%M:%S")
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
DEPLOYED_AT="'"$DEPLOYED_AT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS AUTO_DEPLOY_DONE
TEST_LOG="$(mktemp)"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<EOF
task:
  status: assigned
  deployed_at: "$DEPLOYED_AT"
  parent_cmd: cmd_1049
EOF

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { :; }
check_idle() { return 0; }
check_and_update_done_task() { return 1; }
cli_profile_get() { echo ""; }

PANE_TARGETS[kagemaru]="shogun:2.5"

tmux() { echo ""; }
export -f tmux

is_task_deployed kagemaru
rc=$?
echo "RC=$rc"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"RC=1"* ]]
    [[ "$output" == *"STALE-TASK: kagemaru has YAML status=assigned but pane is idle"* ]]
}

@test "STALE-TASK: no deployed_at field triggers normal STALE-TASK" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS AUTO_DEPLOY_DONE
TEST_LOG="$(mktemp)"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<YAMLEOF
task:
  status: assigned
  parent_cmd: cmd_1049
YAMLEOF

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { :; }
check_idle() { return 0; }
check_and_update_done_task() { return 1; }
cli_profile_get() { echo ""; }

PANE_TARGETS[kagemaru]="shogun:2.5"

tmux() { echo ""; }
export -f tmux

is_task_deployed kagemaru
rc=$?
echo "RC=$rc"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"RC=1"* ]]
    [[ "$output" == *"STALE-TASK: kagemaru has YAML status=assigned but pane is idle"* ]]
}
