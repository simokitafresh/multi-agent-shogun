#!/usr/bin/env bats

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  REPORT="$BATS_TEST_TMPDIR/report.yaml"
  base_report
}

base_report() {
  cat > "$REPORT" <<'YAML'
worker_id: hayate
parent_cmd: cmd_test
task_type: normal
status: pending
files_modified:
  - {path: queue/reports/hayate_report_cmd_test.yaml, change: runtime report}
  - {path: logs/loop_ledger.yaml, change: runtime ledger}
binary_checks:
  commit:
    - {check: 運用データのみのためcommit不要, result: yes}
YAML
}

@test "report_field_set accepts explicit no-commit for queue and logs only" {
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash no-code-change
  [ "$status" -eq 0 ]
  grep -q '^commit_hash: no-code-change$' "$REPORT"
}

@test "report_field_set blocks no-code identity when source is mixed" {
  sed -i 's#logs/loop_ledger.yaml#scripts/report_field_set.sh#' "$REPORT"
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash no-code-change
  [ "$status" -ne 0 ]
}

@test "report_field_set blocks short hash" {
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash ae15fc385
  [ "$status" -ne 0 ]
}

@test "report_field_set blocks no-code identity without affirmative evidence" {
  sed -i 's/result: yes/result: no/' "$REPORT"
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash no-code-change
  [ "$status" -ne 0 ]
}

@test "format validator accepts the same operational no-code contract" {
  printf '\ncommit_hash: no-code-change\n' >> "$REPORT"
  run python3 "$ROOT/scripts/gates/gate_report_format_main.py" "$REPORT"
  [[ "$output" != *"commit_hash: 'no-code-change'"* ]]
}

@test "review fingerprint accepts operational no-code without unrelated HEAD" {
  printf '\ncommit_hash: no-code-change\n' >> "$REPORT"
  source "$ROOT/scripts/lib/review_approval.sh"
  fp=$(PROJECT_ROOT="$ROOT" review_report_fingerprint "$REPORT")
  [[ "$fp" == *":no-code-change" ]]
}
