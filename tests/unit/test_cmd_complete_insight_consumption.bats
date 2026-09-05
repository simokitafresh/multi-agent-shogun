#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export FIXTURE="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$FIXTURE/queue/tasks" "$FIXTURE/queue/reports"
  cat > "$FIXTURE/queue/tasks/kotaro.yaml" <<'YAML'
task:
  parent_cmd: cmd_test
  remediated_insight_ids: [INS-ROOT]
YAML
  cat > "$FIXTURE/queue/reports/kotaro.yaml" <<'YAML'
parent_cmd: cmd_test
result:
  details: "発生元 INS-ROOT を修正"
YAML
  cat > "$FIXTURE/queue/insights.yaml" <<'YAML'
insights:
- id: INS-ROOT
  status: pending
  insight: root cause
- id: INS-FOLLOW
  status: pending
  source_cmd: cmd_test
  insight: follow-up generated during completion
- id: INS-OTHER
  status: pending
  action_cmd: cmd_other
  insight: unrelated
YAML
  awk '/^auto_resolve_cmd_related_insights\(\)/,/^}/' \
    "$REPO_ROOT/scripts/cmd_complete_gate.sh" > "$FIXTURE/function.sh"
}

run_resolver() {
  SCRIPT_DIR="$REPO_ROOT" \
  INSIGHTS_FILE="$FIXTURE/queue/insights.yaml" \
  INSIGHT_TASKS_DIR="$FIXTURE/queue/tasks" \
  INSIGHT_REPORTS_DIR="$FIXTURE/queue/reports" \
  bash -c 'log_gate_stderr_file() { :; }; source "$1"; auto_resolve_cmd_related_insights cmd_test' _ \
    "$FIXTURE/function.sh"
}

@test "clean checkout tracks insight_resolve.sh as executable" {
  run git -C "$REPO_ROOT" ls-files -s scripts/insight_resolve.sh
  [ "$status" -eq 0 ]
  [[ "$output" == 100755\ * ]]
}

@test "explicit remediation is resolved with complete evidence while follow-up and unrelated stay pending" {
  run run_resolver
  [ "$status" -eq 0 ]
  run python3 - "$FIXTURE/queue/insights.yaml" <<'PY'
import sys, yaml
items = {item["id"]: item for item in yaml.safe_load(open(sys.argv[1]))["insights"]}
root = items["INS-ROOT"]
assert root["status"] == "resolved"
assert root["resolved_reason"]
assert root["action_artifact"] == "cmd=cmd_test;gate=cmd_complete_gate;result=CLEAR"
assert root["resolved_at"]
assert items["INS-FOLLOW"]["status"] == "pending"
assert items["INS-OTHER"]["status"] == "pending"
print("produced=1 consumed=1 invalid=0 false_positive=0")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"produced=1 consumed=1 invalid=0 false_positive=0"* ]]
}

@test "legacy resolve entry point fails closed without evidence" {
  run env INSIGHTS_FILE="$FIXTURE/queue/insights.yaml" \
    bash "$REPO_ROOT/scripts/insight_write.sh" --resolve INS-ROOT
  [ "$status" -ne 0 ]
  run python3 - "$FIXTURE/queue/insights.yaml" <<'PY'
import sys, yaml
item = yaml.safe_load(open(sys.argv[1]))["insights"][0]
consumed = int(item.get("status") == "resolved" and bool(item.get("resolved_reason")) and bool(item.get("action_artifact")))
invalid = int(item.get("status") == "done" and not consumed)
print(f"produced=1 consumed={consumed} invalid={invalid}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"produced=1 consumed=0 invalid=0"* ]]
}

@test "declared missing insight fails closed" {
  sed -i 's/INS-ROOT/INS-MISSING/g' "$FIXTURE/queue/tasks/kotaro.yaml" "$FIXTURE/queue/reports/kotaro.yaml"
  run run_resolver
  [ "$status" -ne 0 ]
  # cmd_karo_hotfix_post_clear_fail_open_20260725 (AC1): 呼出し元がfail-open化された
  # ためメッセージも実態に合わせWARNへ変更(このfunction自体はreturn 1のまま=fails closed)。
  [[ "$output" == *"[WARN] insight declaration selection failed (non-blocking)"* ]]
}

@test "structured action_cmd exact match resolves without substring matching" {
  sed -i 's/remediated_insight_ids: \[INS-ROOT\]/remediated_insight_ids: []/' "$FIXTURE/queue/tasks/kotaro.yaml"
  sed -i 's/INS-ROOT/NO-DECLARATION/' "$FIXTURE/queue/reports/kotaro.yaml"
  sed -i '/id: INS-ROOT/a\  action_cmd: cmd_test' "$FIXTURE/queue/insights.yaml"
  run run_resolver
  [ "$status" -eq 0 ]
  run python3 - "$FIXTURE/queue/insights.yaml" <<'PY'
import sys, yaml
items = yaml.safe_load(open(sys.argv[1]))["insights"]
print(sum(item.get("status") == "resolved" for item in items))
PY
  [ "$output" = "1" ]
}
