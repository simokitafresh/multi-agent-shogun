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
