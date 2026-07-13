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
grep -q "REFLUX-AUTO-INVENTORY-BEFORE: hayate insights_pending=1 zero_backlinks=0 promotions=0 total=1" "$TMP_ROOT/test.log"
grep -q "REFLUX-AUTO-INVENTORY-AFTER: hayate insights_pending=1 zero_backlinks=0 promotions=0 total=1" "$TMP_ROOT/test.log"
echo "REFLUX_INSIGHT_DEPLOY_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_INSIGHT_DEPLOY_OK"* ]]
}

@test "reflux auto deploy rolls back partial task when deploy_task fails" {
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
cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  parent_cmd: \$5
  task_id: \${5}_exact
  status: assigned
  report_path:
  ac_version:
YAML
exit 1
SH
chmod +x "$SCRIPT_DIR/scripts/deploy_task.sh"

log() { echo "$1" >> "$TMP_ROOT/test.log"; }
yaml_field_get() {
    grep -m1 -E "^[[:space:]]*$2:" "$1" | sed "s/.*:[[:space:]]*//; s/[\"'"'"' ]//g" || true
}
field_get() { yaml_field_get "$@"; }
yaml_field_set() {
    local file="$1" block="$2" field="$3" value="$4"
    python3 - "$file" "$field" "$value" <<PY
import sys
path, field, value = sys.argv[1:4]
lines = open(path, encoding="utf-8").read().splitlines()
out = []
done = False
for line in lines:
    if line.strip().startswith(field + ":"):
        indent = line[:len(line)-len(line.lstrip())]
        out.append(f"{indent}{field}: {value}")
        done = True
    else:
        out.append(line)
if not done:
    out.append(f"  {field}: {value}")
open(path, "w", encoding="utf-8").write("\\n".join(out) + "\\n")
PY
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

grep -q "REFLUX-AUTO-ROLLBACK: hayate partial task reset after deploy failure" "$TMP_ROOT/test.log"
grep -q "status: idle" "$SCRIPT_DIR/queue/tasks/hayate.yaml"
echo "REFLUX_DEPLOY_FAILURE_ROLLBACK_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_DEPLOY_FAILURE_ROLLBACK_OK"* ]]
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
grep -q "REFLUX-AUTO-INVENTORY-BEFORE: hayate insights_pending=0 zero_backlinks=1 promotions=0 total=1" "$TMP_ROOT/test.log"
echo "REFLUX_BACKLINK_DEPLOY_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_BACKLINK_DEPLOY_OK"* ]]
}

@test "reflux auto deploy fires for lesson promotion inventory when insights and backlinks are empty" {
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
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue" "$SCRIPT_DIR/scripts/gates" "$SCRIPT_DIR/logs" "$STATE_DIR"

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: idle
YAML

cat > "$SCRIPT_DIR/queue/insights.yaml" <<YAML
insights: []
YAML

cat > "$SCRIPT_DIR/scripts/causal_backlink_counts.sh" <<SH
#!/usr/bin/env bash
exit 0
SH
chmod +x "$SCRIPT_DIR/scripts/causal_backlink_counts.sh"

cat > "$SCRIPT_DIR/scripts/gates/gate_lesson_enforcement_level.sh" <<SH
#!/usr/bin/env bash
cat <<OUT
=== 昇格候補一覧(L4未満、恒久防御未到達) 1件 ===
  - [lessons_karo.yaml] L999 (L2:事前予防(doc)): doc-only lesson
##ENFORCEMENT_LEVEL_BELOW4_COUNT##
1
OUT
SH
chmod +x "$SCRIPT_DIR/scripts/gates/gate_lesson_enforcement_level.sh"

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

_handle_reflux_auto_deploy hayate 100

grep -q "DEPLOY_CALLED:--direct --yaml" "$TMP_ROOT/deploy.log"
grep -q "target_path: projects/infra/lessons_karo.yaml" "$TMP_ROOT/deployed.yaml"
grep -q "cmd_reflux_promotion_" "$TMP_ROOT/deployed.yaml"
grep -q "promotions: 1" "$TMP_ROOT/deployed.yaml"
python3 - "$TMP_ROOT/deployed.yaml" <<PY
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as fh:
    data = yaml.safe_load(fh)
check = data["task"]["acceptance_criteria"][0]["checks"][0]["check"]
assert "): doc-only lesson" in check, check
PY
grep -q "REFLUX-AUTO-INVENTORY-BEFORE: hayate insights_pending=0 zero_backlinks=0 promotions=1 total=1" "$TMP_ROOT/test.log"
echo "REFLUX_PROMOTION_DEPLOY_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_PROMOTION_DEPLOY_OK"* ]]
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

@test "_cleanup_stale_keys prunes TRAINING_COMPLETION_CHECKED for inactive agents" {
    # note: ninja_monitor.sh自体がset -uを使わない前提で書かれている(active[$agent_part]は
    # 全compound-keyループ共通で未設定キー参照を許容する)。本番実行条件を再現するため-uは付けない。
    run bash -c '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

NINJA_NAMES=(hayate)
declare -gA TRAINING_COMPLETION_CHECKED
TRAINING_COMPLETION_CHECKED["hayate:cmd_active"]="1"
TRAINING_COMPLETION_CHECKED["retired_ninja:cmd_stale"]="1"

_cleanup_stale_keys

[ "${TRAINING_COMPLETION_CHECKED[hayate:cmd_active]:-}" = "1" ] || { echo "ACTIVE_KEY_LOST"; exit 1; }
[ -z "${TRAINING_COMPLETION_CHECKED[retired_ninja:cmd_stale]:-}" ] || { echo "STALE_KEY_NOT_PRUNED"; exit 1; }
echo "CLEANUP_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLEANUP_OK"* ]]
}

@test "_cleanup_stale_keys coverage includes every persistent associative array or documented exclusion" {
    run bash -c '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
python3 - "$PROJECT_ROOT/scripts/ninja_monitor.sh" <<'"'"'PY'"'"'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

declared = set()
declaration_block = text[text.index("declare -A LAST_NOTIFIED"):text.index("_cleanup_stale_keys()")]
for match in re.finditer(r"^declare[ \t]+(?:-[^\n]*?A[^\n]*?)[ \t]+([A-Za-z_][A-Za-z0-9_]*(?:[ \t]+[A-Za-z_][A-Za-z0-9_]*)*)", declaration_block, re.M):
    declared.update(match.group(1).split())

cleanup_match = re.search(
    r"^_cleanup_stale_keys\(\) \{(?P<body>.*?)^\}",
    text,
    re.M | re.S,
)
if not cleanup_match:
    print("MISSING_CLEANUP_FUNCTION")
    sys.exit(1)
cleanup_body = cleanup_match.group("body")
pruned = set(re.findall(r"unset\s+\"([A-Za-z_][A-Za-z0-9_]*)\[", cleanup_body))

# Reasoned exclusions: these arrays are bounded by configured agents, pruned in
# domain-specific paths, or are one-cycle caches intentionally reset elsewhere.
excluded = {
    "LAST_NOTIFIED": "bounded agent-name keys; overwritten per cycle, not task/cmd unbounded",
    "PREV_STATE": "bounded agent-name keys initialized from NINJA_NAMES",
    "PANE_TARGETS": "bounded agent-name keys refreshed from tmux layout",
    "LAST_CLEARED": "bounded agent-name keys; clear debounce state",
    "STALE_CMD_NOTIFIED": "pruned in check_stale_cmds when cmd leaves pending set",
    "UNDEPLOYED_CMD_NOTIFIED": "pruned in check_undeployed_cmds when cmd leaves pending set",
    "PREV_PENDING_SET": "pruned in check_karo_pending_cmd for old pending ids",
    "CLEAR_SKIP_COUNT": "bounded agent-name keys; clear-loop counter",
    "RENUDGE_COUNT": "bounded agent-name keys; overwritten/reset with inbox fingerprint",
    "RENUDGE_FINGERPRINT": "bounded agent-name keys; explicitly reset on busy",
    "RENUDGE_LAST_SEND": "bounded agent-name keys; unread debounce state",
    "IDLE_NOTIFY_SENT": "bounded agent-name keys; unset on busy state transition",
    "POST_CLEAR_PENDING": "bounded agent-name keys; unset after post-clear command delivery",
    "TRAINING_IDLE_FIRST_SEEN": "bounded agent-name keys; unset on busy/non-idle branches",
    "REFLUX_IDLE_FIRST_SEEN": "bounded agent-name keys; unset on busy/non-idle branches",
    "_INBOX_COUNT_CACHE": "one-cycle cache guarded by _INBOX_COUNT_CACHE_CYCLE",
    "_INBOX_FP_CACHE": "one-cycle cache guarded by _INBOX_COUNT_CACHE_CYCLE",
    "CLI_DEAD_RESTART_TIMES": "bounded agent-name keys with rolling timestamp list",
    "CLI_DEAD_LOOP_LAST_NTFY": "bounded agent-name keys; alert debounce state",
}

covered = pruned | set(excluded)
missing = sorted(declared - covered)
stale_exclusions = sorted(set(excluded) - declared)
if missing:
    print("MISSING_PRUNE_COVERAGE:" + ",".join(missing))
if stale_exclusions:
    print("STALE_EXCLUSION:" + ",".join(stale_exclusions))
if missing or stale_exclusions:
    sys.exit(1)
print(f"PRUNE_COVERAGE_OK declared={len(declared)} pruned={len(pruned)} excluded={len(excluded)}")
PY
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PRUNE_COVERAGE_OK"* ]]
}

@test "_cleanup_stale_keys coverage fails when a persistent array is added without prune or exclusion" {
    run bash -c '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
cp "$PROJECT_ROOT/scripts/ninja_monitor.sh" "$TMP_ROOT/ninja_monitor.sh"
python3 - "$TMP_ROOT/ninja_monitor.sh" <<'"'"'PY'"'"'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = "declare -A TRAINING_COMPLETION_CHECKED"
replacement = "declare -A UNREGISTERED_PRUNE_LEAK\n" + needle
path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")
PY

set +e
python3 - "$TMP_ROOT/ninja_monitor.sh" <<'"'"'PY'"'"'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

declared = set()
declaration_block = text[text.index("declare -A LAST_NOTIFIED"):text.index("_cleanup_stale_keys()")]
for match in re.finditer(r"^declare[ \t]+(?:-[^\n]*?A[^\n]*?)[ \t]+([A-Za-z_][A-Za-z0-9_]*(?:[ \t]+[A-Za-z_][A-Za-z0-9_]*)*)", declaration_block, re.M):
    declared.update(match.group(1).split())

cleanup_body = re.search(r"^_cleanup_stale_keys\(\) \{(?P<body>.*?)^\}", text, re.M | re.S).group("body")
pruned = set(re.findall(r"unset\s+\"([A-Za-z_][A-Za-z0-9_]*)\[", cleanup_body))
excluded = {
    "LAST_NOTIFIED", "PREV_STATE", "PANE_TARGETS", "LAST_CLEARED",
    "STALE_CMD_NOTIFIED", "UNDEPLOYED_CMD_NOTIFIED", "PREV_PENDING_SET",
    "CLEAR_SKIP_COUNT", "RENUDGE_COUNT", "RENUDGE_FINGERPRINT",
    "RENUDGE_LAST_SEND", "IDLE_NOTIFY_SENT", "POST_CLEAR_PENDING", "TRAINING_IDLE_FIRST_SEEN",
    "REFLUX_IDLE_FIRST_SEEN", "_INBOX_COUNT_CACHE", "_INBOX_FP_CACHE",
    "CLI_DEAD_RESTART_TIMES", "CLI_DEAD_LOOP_LAST_NTFY",
}
missing = sorted(declared - pruned - excluded)
if missing:
    print("MISSING_PRUNE_COVERAGE:" + ",".join(missing))
    sys.exit(1)
print("UNEXPECTED_PASS")
PY
rc=$?
set -e
[ "$rc" -eq 1 ] || { echo "EXPECTED_EXIT_1_GOT_$rc"; exit 1; }
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MISSING_PRUNE_COVERAGE:"* ]]
    [[ "$output" == *"UNREGISTERED_PRUNE_LEAK"* ]]
}
