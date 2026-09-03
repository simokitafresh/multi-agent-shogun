#!/usr/bin/env bats

setup() {
  export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

# test_necessity: reflux resolution tasks must have zero commit scope and must
# instruct the worker to emit a publisher-applied ledger operation, preventing
# the queue/insights.yaml base-blob mismatch recurrence.
@test "generated reflux insight task uses ledger resolve without shared queue scope" {
  run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -r -- \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
mkdir -p "$TMP_ROOT/queue/tasks" "$TMP_ROOT/queue" "$TMP_ROOT/scripts" "$TMP_ROOT/logs" "$STATE_DIR"
printf "insights:\n- id: INS-TEMPLATE\n  status: pending\n" > "$TMP_ROOT/queue/insights.yaml"
printf "task:\n  status: idle\n" > "$TMP_ROOT/queue/tasks/hayate.yaml"
printf "#!/usr/bin/env bash\nexit 0\n" > "$TMP_ROOT/scripts/causal_backlink_counts.sh"
chmod +x "$TMP_ROOT/scripts/causal_backlink_counts.sh"
cat > "$TMP_ROOT/scripts/deploy_task.sh" <<SH
#!/usr/bin/env bash
cp "\$3" "$TMP_ROOT/generated.yaml"
SH
chmod +x "$TMP_ROOT/scripts/deploy_task.sh"
log() { :; }
_training_pipeline_has_work() { return 1; }
declare -gA REFLUX_IDLE_FIRST_SEEN
REFLUX_IDLE_FIRST_SEEN[hayate]=0
REFLUX_AUTO_DEPLOY_IDLE_THRESHOLD=1
REFLUX_AUTO_DEPLOY_COOLDOWN=1
REFLUX_AUTO_DEPLOY_STATE_PREFIX="$TMP_ROOT/state/reflux_auto"
REFLUX_BACKLINK_SCAN_LIMIT=5
REFLUX_BACKLINK_TIMEOUT=5

_handle_reflux_auto_deploy hayate 100
python3 - "$TMP_ROOT/generated.yaml" <<PY
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
assert task["target_path"] == "queue/insights.yaml"
assert task["planned_paths"] == []
assert task["reflux_resolution_only"] is True
assert task["commit_contract"]["required"] is False
assert "queue/insights.yaml" not in task["commit_contract"]["planned_paths"]
checks = " ".join(str(item) for item in task["acceptance_criteria"])
assert "insight_resolve.sh" in checks
assert "直接編集せず" in checks
print("REFLUX_TEMPLATE_CONTRACT_OK scope=0 queue_direct_edit=0 helper=1")
PY
'
  [ "$status" -eq 0 ]
  [[ "$output" == *"REFLUX_TEMPLATE_CONTRACT_OK scope=0 queue_direct_edit=0 helper=1"* ]]
}
