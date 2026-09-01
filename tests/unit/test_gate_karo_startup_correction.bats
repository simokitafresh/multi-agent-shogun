#!/usr/bin/env bats
# test_necessity: the karo startup escalation must propose an executable repair
# for "completed_unarchived … clear_receipt_required" alerts (the alert text has
# no " report=" token), never the `false` placeholder that only produces
# "是正コマンドが非0終了したが出力なし" CRITICAL escalations to Shogun.
# regression_justification: 2026-09-01 four such escalations (hayate/tobisaru/
# saizo) reached Shogun with `false # report generation unavailable` as the
# tried command (lord audit 13:22).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  eval "$(sed -n '/^karo_startup_correction_command()/,/^}/p' "$ROOT/scripts/gates/gate_karo_startup.sh")"
  SCRIPT_DIR="$BATS_TEST_TMPDIR/root"
  mkdir -p "$SCRIPT_DIR/queue/reports"
  KARO_STARTUP_ESCALATION_CORRECTION_COMMAND=""
  printf 'status: completed\n' > "$SCRIPT_DIR/queue/reports/tobisaru_report_cmd_reflux_insight_x.yaml"
}

@test "completed_unarchived + clear_receipt_required with a report present → run the GATE" {
  run karo_startup_correction_command "tobisaru: completed_unarchived task=cmd_reflux_insight_x clear_receipt_required task_reverted_in_progress=0"
  [ "$status" -eq 0 ]
  [ "$output" = "bash scripts/cmd_complete_gate.sh cmd_reflux_insight_x" ]
}

@test "completed_unarchived without any report file keeps the explicit non-executable marker" {
  run karo_startup_correction_command "zzz: completed_unarchived task=cmd_missing_y clear_receipt_required task_reverted_in_progress=0"
  [ "$status" -eq 0 ]
  [[ "$output" == false*"report generation unavailable"* ]]
}
