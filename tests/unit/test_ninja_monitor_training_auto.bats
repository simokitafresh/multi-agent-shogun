#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "training auto deploy stops when temporary task YAML cannot be created" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/missing-state"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs"

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: idle
YAML

cat > "$SCRIPT_DIR/scripts/deploy_task.sh" <<SH
#!/bin/bash
echo DEPLOY_CALLED >> "$TMP_ROOT/deploy.log"
SH
chmod +x "$SCRIPT_DIR/scripts/deploy_task.sh"

log() { echo "$1" >> "$TMP_ROOT/test.log"; }
yaml_field_get() {
    grep -m1 -E "^[[:space:]]*$2:" "$1" | sed "s/.*:[[:space:]]*//; s/[\"'"'"' ]//g" || true
}
_training_pipeline_has_work() { return 1; }
_training_condition_met() { return 0; }

declare -gA TRAINING_IDLE_FIRST_SEEN
TRAINING_IDLE_FIRST_SEEN[hayate]=0
TRAINING_AUTO_DEPLOY_IDLE_THRESHOLD=1
TRAINING_AUTO_DEPLOY_COOLDOWN=1
TRAINING_AUTO_DEPLOY_STATE_PREFIX="$TMP_ROOT/state/training_auto"

now=100
_handle_training_auto_deploy hayate "$now" && exit 1

grep -q "failed to create temporary task YAML" "$TMP_ROOT/test.log"
test ! -f "$TMP_ROOT/deploy.log"
echo "MKTEMP_GUARD_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MKTEMP_GUARD_OK"* ]]
}
