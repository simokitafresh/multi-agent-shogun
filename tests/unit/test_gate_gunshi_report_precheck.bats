#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ENGINE="$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck_engine.py"
  TMP_DIR="$(mktemp -d)"
  mkdir -p "$TMP_DIR/tasks"
  cat > "$TMP_DIR/tasks/kagemaru.yaml" <<'YAML'
task:
  binary_checks:
    AC1:
      - check: concrete check
        result: yes
YAML
}

teardown() {
  rm -rf "$TMP_DIR"
}

run_engine() {
  local assumption_check="$1"
  cat > "$TMP_DIR/report.yaml" <<YAML
worker_id: kagemaru
parent_cmd: cmd_fixture
assumption_check: "$assumption_check"
task_clarity:
  score: 100
  unclear_points: なし
  discretion_fills: なし
binary_checks:
  AC1:
    - check: concrete check
      result: yes
YAML
  run python3 "$ENGINE" --report "$TMP_DIR/report.yaml" --tasks-dir "$TMP_DIR/tasks"
}

@test "LG043 ignores completed negative expression for unverified assumptions" {
  run_engine "未確認前提なし"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
}

@test "LG043 ignores completed negative expression for unresolved items" {
  run_engine "未解決事項なし"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
}

@test "LG043 keeps blocking actual unverified work" {
  run_engine "本番動作は未確認"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
  [[ "$output" == *"BC_YES_CLARITY_TERMS="*"未確認"* ]]
}

@test "LG043 keeps blocking actual incomplete work" {
  run_engine "実装は未完了"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
  [[ "$output" == *"BC_YES_CLARITY_TERMS="*"未完了"* ]]
}

@test "LG043 keeps blocking deferred work" {
  run_engine "確認を保留"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
  [[ "$output" == *"BC_YES_CLARITY_TERMS="*"保留"* ]]
}

@test "SG-PRE35 blocks unclassified new test and accepts necessity plus control groups" {
  gate="$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh"
  task="$TMP_DIR/tasks/kagemaru.yaml"
  printf 'worker_id: kagemaru\nparent_cmd: cmd_fixture\n' > "$TMP_DIR/report.yaml"

  printf 'task:\n  planned_paths: [tests/unit/test_never_existing_contract.bats]\n' > "$task"
  run env GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test_lifecycle=transient"* ]]

  cat > "$task" <<'YAML'
task:
  planned_paths: [tests/unit/test_never_existing_contract.bats, scripts/deploy_task.sh]
  test_necessity:
    defense_target: deployment rejects tests without unique production defense
    overlap_evidence: existing tests and added commit paths have no equivalent assertion
    overlaps_existing: false
    fixture_self_reference: false
    deprecated_mechanism: false
YAML
  run env GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test_lifecycle=persistent test_necessity"* ]]

  printf 'task:\n  planned_paths: [tests/unit/test_gate_gunshi_report_precheck.bats]\n' > "$task"
  run env GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -eq 0 ]
  printf 'task:\n  planned_paths: [scripts/deploy_task.sh]\n' > "$task"
  run env GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -eq 0 ]

  for path in logs/test_timing_ledger.tsv docs/test-plan.md contest/data.tsv; do
    printf 'task:\n  planned_paths: [%s]\n' "$path" > "$task"
    run env GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
    [ "$status" -eq 0 ]
  done

  for path in tests/unit/test_new.bats tests/test_new.sh test_new.py; do
    printf 'task:\n  planned_paths: [%s]\n' "$path" > "$task"
    run env GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test_lifecycle=transient"* ]]
  done
}
