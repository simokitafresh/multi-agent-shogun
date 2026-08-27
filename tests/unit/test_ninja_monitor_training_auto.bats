#!/usr/bin/env bats
# test_necessity: 自動修行配備は所有scope競合・cooldown・部分配備失敗時に新taskを残さない

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

# test_necessity: reflux global pause markerは解除条件未成立時に維持し、file_exists/cmd_clear成立時だけcooldown stateを復元・解除し、
# marker無し時の従来経路へ影響を与えない不変量を守る。
@test "reflux auto-deploy pause marker auto-unpauses on file or clear condition" {
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
LOG="$TMP_ROOT/monitor.log"
REFLUX_AUTO_DEPLOY_PAUSE_MARKER="$TMP_ROOT/queue/gates/reflux_auto_deploy.paused"
REFLUX_AUTO_DEPLOY_STATE_PREFIX="$TMP_ROOT/state/reflux_auto"
mkdir -p "$TMP_ROOT/queue/gates" "$TMP_ROOT/scripts" "$STATE_DIR"
cat > "$TMP_ROOT/scripts/bulletin_write.sh" <<SH
#!/usr/bin/env bash
printf "%s\\n" "\$*" >> "$TMP_ROOT/bulletins.log"
SH
chmod +x "$TMP_ROOT/scripts/bulletin_write.sh"
_training_pipeline_has_work() { return 1; }

# Condition unmet: keep marker and cooldown directory.
cat > "$REFLUX_AUTO_DEPLOY_PAUSE_MARKER" <<YAML
unpause_when:
  file_exists: queue/gates/release.signal
YAML
mkdir -p "$REFLUX_AUTO_DEPLOY_STATE_PREFIX"_hayate.last
REFLUX_IDLE_FIRST_SEEN[hayate]=0
! _handle_reflux_auto_deploy hayate 100
[ -f "$REFLUX_AUTO_DEPLOY_PAUSE_MARKER" ]
[ -d "$REFLUX_AUTO_DEPLOY_STATE_PREFIX"_hayate.last ]
grep -q "REFLUX-AUTO-PAUSED: hayate .*condition_unmet=1" "$LOG"

# file_exists condition: restore numeric sibling backup, remove marker, post one bulletin.
echo 77 > "$REFLUX_AUTO_DEPLOY_STATE_PREFIX"_hayate.last.pre_9p_freeze
touch "$TMP_ROOT/queue/gates/release.signal"
REFLUX_IDLE_FIRST_SEEN[hayate]=0
! _handle_reflux_auto_deploy hayate 200
[ ! -e "$REFLUX_AUTO_DEPLOY_PAUSE_MARKER" ]
[ -f "$REFLUX_AUTO_DEPLOY_STATE_PREFIX"_hayate.last ]
grep -qx '77' "$REFLUX_AUTO_DEPLOY_STATE_PREFIX"_hayate.last
test "$(grep -c 'REFLUX-AUTO-UNPAUSE:' "$TMP_ROOT/bulletins.log")" -eq 1

# cmd_clear condition: require the canonical clear receipt and restore another state file.
cat > "$REFLUX_AUTO_DEPLOY_PAUSE_MARKER" <<YAML
unpause_when:
  cmd_clear: cmd_release
YAML
mkdir -p "$REFLUX_AUTO_DEPLOY_STATE_PREFIX"_kotaro.last
echo 88 > "$REFLUX_AUTO_DEPLOY_STATE_PREFIX"_kotaro.last.pre_9p_freeze
mkdir -p "$TMP_ROOT/queue/gates/cmd_release"
python3 - "$TMP_ROOT/queue/gates/cmd_release/gate_worker.clear.json" <<PY
import json,sys,time
json.dump({"version": 1, "state": "clear", "cmd_id": "cmd_release", "completion_generation": "a" * 64, "persisted_at_ns": time.time_ns()}, open(sys.argv[1], "w"))
PY
REFLUX_IDLE_FIRST_SEEN[kotaro]=0
! _handle_reflux_auto_deploy kotaro 300
[ ! -e "$REFLUX_AUTO_DEPLOY_PAUSE_MARKER" ]
[ -f "$REFLUX_AUTO_DEPLOY_STATE_PREFIX"_kotaro.last ]
grep -qx '88' "$REFLUX_AUTO_DEPLOY_STATE_PREFIX"_kotaro.last
test "$(grep -c 'REFLUX-AUTO-UNPAUSE:' "$TMP_ROOT/bulletins.log")" -eq 2

# Marker absent: no unpause event is emitted; normal handler remains callable.
REFLUX_IDLE_FIRST_SEEN[saizo]=0
! _handle_reflux_auto_deploy saizo 400
test "$(grep -c 'REFLUX-AUTO-UNPAUSE:' "$TMP_ROOT/bulletins.log")" -eq 2
echo "REFLUX_AUTO_UNPAUSE_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_AUTO_UNPAUSE_OK"* ]]
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
insights:
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

@test "cmd_karo_hotfix_reflux_deploy_race: reflux auto deploy does not overwrite a done/PASS ninja (RUNTIME=idle but GATE CLEAR/archive pending)" {
    # blt_20260725_130045: RUNTIME=idleだけを見て配備すると、家老の手動配備や忍者の
    # 報告作成中にstatus=done/PASSのtask YAMLを上書きしていた(cmd_4165実証)。
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

REFLUX_AUTO_DEPLOY_IDLE_THRESHOLD=1
REFLUX_AUTO_DEPLOY_COOLDOWN=1
REFLUX_AUTO_DEPLOY_STATE_PREFIX="$TMP_ROOT/state/reflux_auto"

for pair in "hayate:done" "kagemaru:PASS"; do
    name="${pair%%:*}"
    st="${pair##*:}"
    cat > "$SCRIPT_DIR/queue/tasks/${name}.yaml" <<YAML
task:
  status: ${st}
  parent_cmd: cmd_old_${name}
YAML
    declare -gA REFLUX_IDLE_FIRST_SEEN=()
    REFLUX_IDLE_FIRST_SEEN[$name]=0
    _handle_reflux_auto_deploy "$name" 100 && exit 1
    grep -q "REFLUX-AUTO-SKIP: ${name} task status=${st}" "$TMP_ROOT/test.log"
    test ! -f "$TMP_ROOT/deploy.log"
done
echo "REFLUX_DONE_PASS_SKIP_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_DONE_PASS_SKIP_OK"* ]]
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

for run in 1 2 3; do
    REFLUX_IDLE_FIRST_SEEN[hayate]=0
    _handle_reflux_auto_deploy hayate "$((100 * run))"
    # Simulate a worker terminal receipt: the dispatch lease is released
    # only after terminal completion, so the next cycle may select the ID.
    _reflux_insight_release_reservation INS-001 hayate
    log "REFLUX-AUTO-TERMINAL: hayate insight=INS-001 lease_released=1"
done

deploy_count=0
while IFS= read -r line; do
    case "$line" in
        *DEPLOY_CALLED:*--yaml*) deploy_count=$((deploy_count + 1));;
    esac
done < "$TMP_ROOT/deploy.log"
test "$deploy_count" -eq 3
grep -q "target_path: queue/insights.yaml" "$TMP_ROOT/deployed.yaml"
python3 - "$TMP_ROOT/deployed.yaml" <<'PY'
import sys
import yaml

task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
assert task["planned_paths"] == ["queue/insights.yaml"]
print("REFLUX_INSIGHT_GENERATOR_OK runs=3")
PY
(
    export DEPLOY_TASK_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/deploy_task.sh"
    SCRIPT_DIR="$PROJECT_ROOT"
    inject_reflux_commit_contract "$TMP_ROOT/deployed.yaml"
)
python3 - "$TMP_ROOT/deployed.yaml" <<'PY'
import sys
import yaml

task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
contract = task["reflux_commit_contract"]
assert contract["scope"] == ["queue/insights.yaml"]
assert contract["producer"] == {"field": "source", "value": "self_retro"}
assert contract["post_commit_allowed_fields"] == ["occurrence_count", "last_seen"]
print("REFLUX_INSIGHT_CONTRACT_OK")
PY
grep -q "REFLUX-AUTO-INVENTORY-BEFORE: hayate insights_pending=1 zero_backlinks=0 promotions=0 total=1" "$TMP_ROOT/test.log"
grep -q "REFLUX-AUTO-INVENTORY-AFTER: hayate insights_pending=1 zero_backlinks=0 promotions=0 total=1" "$TMP_ROOT/test.log"
done_count=0
while IFS= read -r line; do
    case "$line" in
        *REFLUX-AUTO-DEPLOY-DONE:*) done_count=$((done_count + 1));;
    esac
done < "$TMP_ROOT/test.log"
test "$done_count" -eq 3
test "$(grep -c "REFLUX-AUTO-TERMINAL: hayate insight=INS-001 lease_released=1" "$TMP_ROOT/test.log")" -eq 3
test ! -s "$TMP_ROOT/logs/reflux_insight_reservations.tsv"
echo "REFLUX_INSIGHT_DEPLOY_OK runs=3 published=3 terminal_releases=3"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_INSIGHT_GENERATOR_OK runs=3"* ]]
    [[ "$output" == *"REFLUX_INSIGHT_CONTRACT_OK"* ]]
    [[ "$output" == *"REFLUX_INSIGHT_DEPLOY_OK runs=3 published=3 terminal_releases=3"* ]]
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

# test_necessity: backlink還流taskはゼロ対象自身ではなく外部索引文書をtarget_pathにする不変量を守る。
# ゼロ対象自身を編集対象にすると、causal_backlink_counts.shのsources.discard(rel)が
# 自己参照を除外しincomingが0→0のまま同一対象へ再配備し続ける負のループへ戻る
# (実証: hanzo/saizo/kotaro 3件、対象context/shogun-awakening-check.md)。
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
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/context" "$SCRIPT_DIR/docs/semantic-index" "$STATE_DIR"

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: idle
YAML

cat > "$SCRIPT_DIR/queue/insights.yaml" <<YAML
insights:
- id: INS-001
  status: resolved
YAML

# SSOTと正規生成物を実在させる。編集起点はSSOT、commit scopeは両方とする。
: > "$SCRIPT_DIR/context/semantic-map.md"
: > "$SCRIPT_DIR/docs/semantic-index/index.md"

cat > "$SCRIPT_DIR/scripts/causal_backlink_counts.sh" <<SH
#!/usr/bin/env bash
printf "0\tdocs/research/orphan.md\torphan\n"
SH
chmod +x "$SCRIPT_DIR/scripts/causal_backlink_counts.sh"
mkdir -p "$SCRIPT_DIR/docs/research"
: > "$SCRIPT_DIR/docs/research/orphan.md"
git -C "$SCRIPT_DIR" init -q
git -C "$SCRIPT_DIR" add docs/research/orphan.md

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
grep -q "target_path: docs/semantic-index/index.md" "$TMP_ROOT/deployed.yaml"
python3 - "$TMP_ROOT/deployed.yaml" <<PY
import sys, yaml
task = yaml.safe_load(open(sys.argv[1]))["task"]
assert task["planned_paths"] == [
    "docs/semantic-index/index.md",
    "context/semantic-map.md",
]
assert "SSOT docs/semantic-index/index.md" in task["purpose"]
assert "semantic_map_generate.sh" in task["acceptance_criteria"][0]["checks"][0]["check"]
PY
grep -q "inspection_path: .\[\"docs/research/orphan.md\"\]." "$TMP_ROOT/deployed.yaml"
! grep -q "target_path: docs/research/orphan.md" "$TMP_ROOT/deployed.yaml"
grep -q "REFLUX-AUTO-INVENTORY-BEFORE: hayate insights_pending=0 zero_backlinks=1 promotions=0 total=1" "$TMP_ROOT/test.log"
echo "REFLUX_BACKLINK_DEPLOY_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_BACKLINK_DEPLOY_OK"* ]]
}

# test_necessity: reflux自動配備が他cloneに存在しないuntracked文書を候補へ
# 混入させず、tracked候補の順序と上限を維持する不変量を守る。
@test "reflux zero backlink inventory filters untracked documents before applying limit" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -r \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/docs/research"
cat > "$SCRIPT_DIR/scripts/causal_backlink_counts.sh" <<SH
#!/usr/bin/env bash
printf "0\tdocs/research/untracked.md\tuntracked\n"
printf "0\tdocs/research/tracked.md\ttracked\n"
SH
chmod +x "$SCRIPT_DIR/scripts/causal_backlink_counts.sh"
: > "$SCRIPT_DIR/docs/research/untracked.md"
: > "$SCRIPT_DIR/docs/research/tracked.md"
git -C "$SCRIPT_DIR" init -q
git -C "$SCRIPT_DIR" add docs/research/tracked.md
REFLUX_BACKLINK_SCAN_LIMIT=1
REFLUX_BACKLINK_TIMEOUT=5

[ "$(_reflux_zero_backlink_inventory)" = $'"'"'1\tdocs/research/tracked.md\tok'"'"' ]
git -C "$SCRIPT_DIR" rm --cached -q docs/research/tracked.md
[ "$(_reflux_zero_backlink_inventory)" = $'"'"'0\t-\tok'"'"' ]
echo REFLUX_TRACKED_ONLY_OK
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_TRACKED_ONLY_OK"* ]]
}

# test_necessity: 適切な外部索引sourceを決定できない場合は配備0件を維持する不変量を守る。
# 決定不能なまま配備すると自己参照または誤った対象への配備が発生しうるため、
# 未決定はBLOCKログを残し配備しないことを二値証明する(家老中間レビュー2026-07-28 16:24)。
@test "reflux auto deploy BLOCKs (no deploy) when no external backlink source candidate exists" {
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
# 意図的にcontext/semantic-map.md, docs/semantic-index/index.md, context/infrastructure.md
# のいずれも作成しない → 外部source決定不能

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
mkdir -p "$SCRIPT_DIR/docs/research"
: > "$SCRIPT_DIR/docs/research/orphan.md"
git -C "$SCRIPT_DIR" init -q
git -C "$SCRIPT_DIR" add docs/research/orphan.md

cat > "$SCRIPT_DIR/scripts/deploy_task.sh" <<SH
#!/usr/bin/env bash
echo "DEPLOY_CALLED:\$*" >> "$TMP_ROOT/deploy.log"
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

[ ! -f "$TMP_ROOT/deploy.log" ]
grep -q "REFLUX-AUTO-BLOCK: hayate backlink SSOT/regenerated output pair unavailable for docs/research/orphan.md" "$TMP_ROOT/test.log"
echo "REFLUX_BACKLINK_BLOCK_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_BACKLINK_BLOCK_OK"* ]]
}

# test_necessity: ゼロ対象自身が通常候補(context/semantic-map.md)と一致する場合でも、
# 自己参照を配備先へ選ばず既存の別索引sourceへフォールバックする不変量を守る。
@test "reflux auto deploy backlink kind falls back to alternate external source when zero target is semantic-map itself" {
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
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/context" "$SCRIPT_DIR/docs/semantic-index" "$STATE_DIR"

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: idle
YAML

cat > "$SCRIPT_DIR/queue/insights.yaml" <<YAML
insights:
- id: INS-001
  status: resolved
YAML

# 通常候補context/semantic-map.mdは実在するが、それ自身がゼロ対象なので自己参照禁止。
# 次点候補docs/semantic-index/index.mdのみ実在させ、そちらへフォールバックすることを検証する。
: > "$SCRIPT_DIR/context/semantic-map.md"
: > "$SCRIPT_DIR/docs/semantic-index/index.md"

cat > "$SCRIPT_DIR/scripts/causal_backlink_counts.sh" <<SH
#!/usr/bin/env bash
printf "0\tcontext/semantic-map.md\tsemantic-map\n"
SH
chmod +x "$SCRIPT_DIR/scripts/causal_backlink_counts.sh"
git -C "$SCRIPT_DIR" init -q
git -C "$SCRIPT_DIR" add context/semantic-map.md

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
grep -q "target_path: docs/semantic-index/index.md" "$TMP_ROOT/deployed.yaml"
python3 - "$TMP_ROOT/deployed.yaml" <<PY
import sys, yaml
task = yaml.safe_load(open(sys.argv[1]))["task"]
assert task["planned_paths"] == [
    "docs/semantic-index/index.md",
    "context/semantic-map.md",
]
PY
grep -q "inspection_path: .\[\"context/semantic-map.md\"\]." "$TMP_ROOT/deployed.yaml"
! grep -q "target_path: context/semantic-map.md" "$TMP_ROOT/deployed.yaml"
echo "REFLUX_BACKLINK_SELFREF_FALLBACK_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_BACKLINK_SELFREF_FALLBACK_OK"* ]]
}

# test_necessity: pause中promotionだけを止め、他refluxを維持する不変量を、marker不在時のpromotion互換性も含めて守る。
@test "reflux promotion pause suppresses promotion only and marker absence preserves promotion" {
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
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/gates" "$SCRIPT_DIR/scripts/gates" "$SCRIPT_DIR/logs" "$STATE_DIR"

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: idle
YAML

cat > "$SCRIPT_DIR/queue/insights.yaml" <<YAML
insights:
- id: INS-1
  status: resolved
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

# No marker: existing promotion behavior remains.
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

# Marker present: promotion-only inventory neither claims nor deploys.
: > "$SCRIPT_DIR/queue/gates/reflux_promotion.paused"
: > "$TMP_ROOT/deploy.log"
REFLUX_IDLE_FIRST_SEEN[hayate]=0
_reflux_promotion_claim_next() { echo CLAIM_CALLED >> "$TMP_ROOT/claim.log"; return 1; }
! _handle_reflux_auto_deploy hayate 200
[ ! -s "$TMP_ROOT/deploy.log" ]
[ ! -e "$TMP_ROOT/claim.log" ]
grep -q "REFLUX-PROMOTION-PAUSED: hayate .* suppressed=1; insight/backlink remain eligible" "$TMP_ROOT/test.log"

# The same marker does not stop insight reflux.
sed -i "s/status: resolved/status: pending/" "$SCRIPT_DIR/queue/insights.yaml"
_reflux_inventory_snapshot() { printf "1\t0\t9\t10\tINS-1\t-\t[infra] L999 (L2)\tok\tok\n"; }
_reflux_select_kind() {
    [ "$1" -eq 1 ] && [ "$3" -eq 0 ] && [ "$5" -eq 0 ]
    printf "insight\n"
}
REFLUX_IDLE_FIRST_SEEN[hayate]=0
_handle_reflux_auto_deploy hayate 300
_reflux_insight_release_reservation INS-1 hayate
log "REFLUX-AUTO-TERMINAL: hayate insight=INS-1 lease_released=1"
grep -q "target_path: queue/insights.yaml" "$TMP_ROOT/deployed.yaml"

# Backlink reflux also remains eligible. target_path is the semantic SSOT and
# the regenerated map shares commit scope; zero target flows through inspection_path.
mkdir -p "$SCRIPT_DIR/context" "$SCRIPT_DIR/docs/semantic-index"
: > "$SCRIPT_DIR/context/semantic-map.md"
: > "$SCRIPT_DIR/docs/semantic-index/index.md"
_reflux_inventory_snapshot() { printf "0\t1\t9\t10\t-\tdocs/research/orphan.md\t[infra] L999 (L2)\tok\tok\n"; }
_reflux_select_kind() {
    [ "$1" -eq 0 ] && [ "$3" -eq 1 ] && [ "$5" -eq 0 ]
    printf "backlink\n"
}
REFLUX_IDLE_FIRST_SEEN[hayate]=0
_handle_reflux_auto_deploy hayate 400
grep -q "target_path: docs/semantic-index/index.md" "$TMP_ROOT/deployed.yaml"
grep -q "planned_paths:" "$TMP_ROOT/deployed.yaml"
grep -q "inspection_path: .\[\"docs/research/orphan.md\"\]." "$TMP_ROOT/deployed.yaml"
echo "REFLUX_PROMOTION_DEPLOY_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFLUX_PROMOTION_DEPLOY_OK"* ]]
}

# test_necessity: promotion claim後の全pre-deploy失敗出口でleaseを解放し、後続cycleの在庫を永久BLOCKしない不変量を守る。
@test "reflux promotion releases claim on every pre-deploy failure exit" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        set -euo pipefail
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        root="$BATS_TEST_TMPDIR/root"
        mkdir -p "$root/queue/tasks" "$root/scripts" "$root/logs"
        printf "task:\n  status: idle\n" >"$root/queue/tasks/hayate.yaml"

        for mode in deploy_missing state_dir mktemp task_write parse; do
            (
                SCRIPT_DIR="$root"; STATE_DIR="$root/state-$mode"; LOG="$root/$mode.log"
                REFLUX_AUTO_DEPLOY_STATE_PREFIX="$root/reflux_auto"
                REFLUX_AUTO_DEPLOY_IDLE_THRESHOLD=1; REFLUX_AUTO_DEPLOY_COOLDOWN=1
                declare -gA REFLUX_IDLE_FIRST_SEEN=([hayate]=0)
                : >"$LOG"; : >"$root/releases-$mode"
                _training_pipeline_has_work() { return 1; }
                yaml_field_get() { printf "idle\n"; }
                _reflux_inventory_snapshot() { printf "0\t0\t1\t1\t-\t-\t[infra] L999 (L1)\tok\tok\n"; }
                _reflux_select_kind() { printf "promotion\n"; }
                _reflux_promotion_claim_next() { printf "[infra] L999 (L1)\tprojects/infra/lessons.yaml\n"; }
                _reflux_active_target_owner() { return 1; }
                _reflux_promotion_release_reservation() { printf "%s\t%s\n" "$1" "$2" >>"$root/releases-$mode"; }
                log() { printf "%s\n" "$1" >>"$LOG"; }

                if [ "$mode" != deploy_missing ]; then
                    printf "#!/usr/bin/env bash\nexit 0\n" >"$root/scripts/deploy_task.sh"
                    chmod +x "$root/scripts/deploy_task.sh"
                else
                    command rm -f "$root/scripts/deploy_task.sh"
                fi
                if [ "$mode" = state_dir ]; then
                    mkdir() { [ "${*: -1}" = "$STATE_DIR" ] && return 1; command mkdir "$@"; }
                elif [ "$mode" = mktemp ]; then
                    mktemp() { return 1; }
                elif [ "$mode" = task_write ]; then
                    cat() { return 1; }
                elif [ "$mode" = parse ]; then
                    python3() { return 1; }
                fi

                ! _handle_reflux_auto_deploy hayate 100
                [ "$(wc -l <"$root/releases-$mode")" -eq 1 ]
                grep -Fq "[infra] L999 (L1)" "$root/releases-$mode"
            )
        done
    '
    [ "$status" -eq 0 ]
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
    "CLEAR_BLOCKED_TS": "bounded agent-name keys; window-pruned in _record_clear_blocked_and_maybe_notify, unset on success via _reset_clear_blocked_counter",
    "CLEAR_BLOCKED_NOTIFIED": "bounded agent-name keys; unset on success via _reset_clear_blocked_counter",
    "GATE_STALL_ACTIVE_CMDS": "bounded active command set; rebuilt each gate-stall scan",
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
    "CLEAR_BLOCKED_TS", "CLEAR_BLOCKED_NOTIFIED",
    "GATE_STALL_LAST_NOTIFIED", "GATE_STALL_ACTIVE_CMDS",
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
    [[ "$output" == *"MISSING_PRUNE_COVERAGE:UNREGISTERED_PRUNE_LEAK"* ]]
    [[ "$output" == *"UNREGISTERED_PRUNE_LEAK"* ]]
}

@test "T114 monitor task_assigned caller prefixes current task_id" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -r \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts"
cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  task_id: cmd_monitor_identity_001_normal
  parent_cmd: cmd_monitor_identity_001
  status: assigned
YAML
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<SH
#!/usr/bin/env bash
printf "%s\\n" "\$*" > "$TMP_ROOT/inbox-call"
SH
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

send_inbox_message hayate "タスクを読め" task_assigned ninja_monitor
grep -q "hayate task_id=cmd_monitor_identity_001_normal タスクを読め task_assigned ninja_monitor" "$TMP_ROOT/inbox-call"
echo "MONITOR_TASK_ID_PREFIX_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MONITOR_TASK_ID_PREFIX_OK"* ]]
}
