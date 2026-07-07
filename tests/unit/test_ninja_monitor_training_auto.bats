#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "training recent gate stats counts each report file once" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/logs"

cat > "$SCRIPT_DIR/logs/gate_fire_log.yaml" <<LOG
- ts: "2026-05-21T21:00:00+09:00", file: "queue/reports/hayate_report_cmd_a.yaml", gate: "gate_report_format", result: FAIL
- ts: "2026-05-21T21:01:00+09:00", file: "queue/reports/hayate_report_cmd_a.yaml", gate: "gate_report_format", result: PASS
- ts: "2026-05-21T21:02:00+09:00", file: "queue/reports/hayate_report_cmd_b.yaml", gate: "gate_report_format", result: FAIL
LOG

TRAINING_AUTO_DEPLOY_RECENT=50
read -r total fail pct < <(_training_recent_gate_stats hayate)
printf "%s %s %s\n" "$total" "$fail" "$pct"
'
    [ "$status" -eq 0 ]
    [ "$output" = "2 1 50" ]
}

@test "training auto deploy stops when state dir cannot be prepared" {
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
touch "$STATE_DIR"

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

grep -q "failed to prepare state dir" "$TMP_ROOT/test.log"
test ! -f "$TMP_ROOT/deploy.log"
echo "STATE_DIR_GUARD_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATE_DIR_GUARD_OK"* ]]
}

@test "training auto deploy creates missing state dir before temporary YAML" {
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
_handle_training_auto_deploy hayate "$now"

test -d "$STATE_DIR"
test -f "$TMP_ROOT/deploy.log"
echo "STATE_DIR_CREATED_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATE_DIR_CREATED_OK"* ]]
}

@test "reflux auto deploy skips when another ninja already owns target_path" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$STATE_DIR"

cat > "$SCRIPT_DIR/queue/insights.yaml" <<YAML
- id: INS-test
  status: pending
YAML
cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<YAML
task:
  status: assigned
  parent_cmd: cmd_reflux_active
  target_path: queue/insights.yaml
YAML
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<YAML
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
_reflux_zero_backlink_inventory() { printf "0\t-\tok\n"; }

declare -gA REFLUX_IDLE_FIRST_SEEN
REFLUX_IDLE_FIRST_SEEN[kagemaru]=0
REFLUX_AUTO_DEPLOY_IDLE_THRESHOLD=1
REFLUX_AUTO_DEPLOY_COOLDOWN=1
REFLUX_AUTO_DEPLOY_STATE_PREFIX="$TMP_ROOT/state/reflux_auto"

now=100
_handle_reflux_auto_deploy kagemaru "$now" && exit 1

grep -q "REFLUX-AUTO-SKIP: kagemaru target_path already active (saizo status=assigned parent_cmd=cmd_reflux_active): queue/insights.yaml" "$TMP_ROOT/test.log"
test ! -f "$TMP_ROOT/deploy.log"
echo "REFLUX_TARGET_ACTIVE_SKIP_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_TARGET_ACTIVE_SKIP_OK"* ]]
}

@test "training auto deploy stops when cooldown state dir cannot be prepared" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$STATE_DIR"
touch "$TMP_ROOT/cooldown-parent"

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
TRAINING_AUTO_DEPLOY_STATE_PREFIX="$TMP_ROOT/cooldown-parent/training_auto"

now=100
_handle_training_auto_deploy hayate "$now" && exit 1

grep -q "failed to prepare cooldown state dir" "$TMP_ROOT/test.log"
test ! -f "$TMP_ROOT/deploy.log"
echo "COOLDOWN_STATE_DIR_GUARD_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"COOLDOWN_STATE_DIR_GUARD_OK"* ]]
}

@test "training auto deploy accepts readable deploy_task.sh without executable bit" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$STATE_DIR"

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: idle
YAML

cat > "$SCRIPT_DIR/scripts/deploy_task.sh" <<SH
echo "DEPLOY_CALLED:\$*" >> "$TMP_ROOT/deploy.log"
SH
chmod 0644 "$SCRIPT_DIR/scripts/deploy_task.sh"

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
_handle_training_auto_deploy hayate "$now"

grep -q "DEPLOY_CALLED:--direct --yaml" "$TMP_ROOT/deploy.log"
grep -q "TRAINING-AUTO-DEPLOY-DONE: hayate" "$TMP_ROOT/test.log"
echo "READABLE_DEPLOY_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"READABLE_DEPLOY_OK"* ]]
}

@test "training auto deploy stops when cooldown state path is a directory" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$STATE_DIR" "$TMP_ROOT/state/training_auto_hayate.last"

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

grep -q "cooldown state path is not a regular file" "$TMP_ROOT/test.log"
test ! -f "$TMP_ROOT/deploy.log"
echo "COOLDOWN_STATE_PATH_GUARD_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"COOLDOWN_STATE_PATH_GUARD_OK"* ]]
}

@test "reflux auto deploy fires for pending insight inventory and logs before after counts" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -r \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$STATE_DIR"

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: idle
YAML

cat > "$SCRIPT_DIR/queue/insights.yaml" <<YAML
insights:
- id: INS-001
  status: pending
YAML

cat > "$SCRIPT_DIR/scripts/causal_backlink_counts.sh" <<SH
#!/usr/bin/env bash
exit 0
SH
chmod +x "$SCRIPT_DIR/scripts/causal_backlink_counts.sh"

cat > "$SCRIPT_DIR/scripts/deploy_task.sh" <<SH
#!/usr/bin/env bash
echo "DEPLOY_CALLED:\$*" >> "$TMP_ROOT/deploy.log"
cp "\$3" "$TMP_ROOT/deployed.yaml"
SH
chmod +x "$SCRIPT_DIR/scripts/deploy_task.sh"

log() { echo "$1" >> "$TMP_ROOT/test.log"; }
yaml_field_get() {
    grep -m1 -E "^[[:space:]]*$2:" "$1" | sed "s/.*:[[:space:]]*//; s/[\"'"'"' ]//g" || true
}
_training_pipeline_has_work() { return 1; }

declare -gA REFLUX_IDLE_FIRST_SEEN
REFLUX_IDLE_FIRST_SEEN[hayate]=0
REFLUX_AUTO_DEPLOY_IDLE_THRESHOLD=1
REFLUX_AUTO_DEPLOY_COOLDOWN=1
REFLUX_AUTO_DEPLOY_STATE_PREFIX="$TMP_ROOT/state/reflux_auto"
REFLUX_BACKLINK_SCAN_LIMIT=5
REFLUX_BACKLINK_TIMEOUT=5

_handle_reflux_auto_deploy hayate 100

grep -q "DEPLOY_CALLED:--direct --yaml" "$TMP_ROOT/deploy.log"
grep -q "target_path: queue/insights.yaml" "$TMP_ROOT/deployed.yaml"
grep -q "REFLUX-AUTO-INVENTORY-BEFORE: hayate insights_pending=1 zero_backlinks=0 total=1" "$TMP_ROOT/test.log"
grep -q "REFLUX-AUTO-INVENTORY-AFTER: hayate insights_pending=1 zero_backlinks=0 total=1" "$TMP_ROOT/test.log"
echo "REFLUX_INSIGHT_DEPLOY_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_INSIGHT_DEPLOY_OK"* ]]
}

@test "reflux auto deploy fires for zero backlink inventory when no pending insights" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -r \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$STATE_DIR"

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: idle
YAML

cat > "$SCRIPT_DIR/queue/insights.yaml" <<YAML
insights:
- id: INS-001
  status: resolved
YAML

cat > "$SCRIPT_DIR/scripts/causal_backlink_counts.sh" <<SH
#!/usr/bin/env bash
printf "0\tdocs/research/orphan.md\torphan\n"
SH
chmod +x "$SCRIPT_DIR/scripts/causal_backlink_counts.sh"

cat > "$SCRIPT_DIR/scripts/deploy_task.sh" <<SH
#!/usr/bin/env bash
echo "DEPLOY_CALLED:\$*" >> "$TMP_ROOT/deploy.log"
cp "\$3" "$TMP_ROOT/deployed.yaml"
SH
chmod +x "$SCRIPT_DIR/scripts/deploy_task.sh"

log() { echo "$1" >> "$TMP_ROOT/test.log"; }
yaml_field_get() {
    grep -m1 -E "^[[:space:]]*$2:" "$1" | sed "s/.*:[[:space:]]*//; s/[\"'"'"' ]//g" || true
}
_training_pipeline_has_work() { return 1; }

declare -gA REFLUX_IDLE_FIRST_SEEN
REFLUX_IDLE_FIRST_SEEN[hayate]=0
REFLUX_AUTO_DEPLOY_IDLE_THRESHOLD=1
REFLUX_AUTO_DEPLOY_COOLDOWN=1
REFLUX_AUTO_DEPLOY_STATE_PREFIX="$TMP_ROOT/state/reflux_auto"
REFLUX_BACKLINK_SCAN_LIMIT=5
REFLUX_BACKLINK_TIMEOUT=5

_handle_reflux_auto_deploy hayate 100

grep -q "DEPLOY_CALLED:--direct --yaml" "$TMP_ROOT/deploy.log"
grep -q "target_path: docs/research/orphan.md" "$TMP_ROOT/deployed.yaml"
grep -q "REFLUX-AUTO-INVENTORY-BEFORE: hayate insights_pending=0 zero_backlinks=1 total=1" "$TMP_ROOT/test.log"
echo "REFLUX_BACKLINK_DEPLOY_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_BACKLINK_DEPLOY_OK"* ]]
}

@test "reflux auto deploy does not fire when inventory is empty" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -r \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$STATE_DIR"

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: idle
YAML

cat > "$SCRIPT_DIR/queue/insights.yaml" <<YAML
insights:
- id: INS-001
  status: resolved
YAML

cat > "$SCRIPT_DIR/scripts/causal_backlink_counts.sh" <<SH
#!/usr/bin/env bash
exit 0
SH
chmod +x "$SCRIPT_DIR/scripts/causal_backlink_counts.sh"

cat > "$SCRIPT_DIR/scripts/deploy_task.sh" <<SH
#!/usr/bin/env bash
echo "DEPLOY_CALLED" >> "$TMP_ROOT/deploy.log"
SH
chmod +x "$SCRIPT_DIR/scripts/deploy_task.sh"

log() { echo "$1" >> "$TMP_ROOT/test.log"; }
yaml_field_get() {
    grep -m1 -E "^[[:space:]]*$2:" "$1" | sed "s/.*:[[:space:]]*//; s/[\"'"'"' ]//g" || true
}
_training_pipeline_has_work() { return 1; }

declare -gA REFLUX_IDLE_FIRST_SEEN
REFLUX_IDLE_FIRST_SEEN[hayate]=0
REFLUX_AUTO_DEPLOY_IDLE_THRESHOLD=1
REFLUX_AUTO_DEPLOY_COOLDOWN=1
REFLUX_AUTO_DEPLOY_STATE_PREFIX="$TMP_ROOT/state/reflux_auto"
REFLUX_BACKLINK_SCAN_LIMIT=5
REFLUX_BACKLINK_TIMEOUT=5

_handle_reflux_auto_deploy hayate 100 && exit 1

test ! -f "$TMP_ROOT/deploy.log"
grep -q "REFLUX-AUTO-SKIP: hayate no reflux inventory" "$TMP_ROOT/test.log"
echo "REFLUX_EMPTY_SKIP_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_EMPTY_SKIP_OK"* ]]
}
