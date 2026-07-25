#!/usr/bin/env bats
# test_necessity: CI readiness must resolve to exactly three states — GREEN=READY, real red=BLOCK with repair guidance, and "no evaluation for this code" (pending/unknown/cancelled/mismatch/predates)=WAIT that never blocks the gate.

setup() {
    GATE="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"
    REVIEWED='2026-07-23T10:00:00+09:00'
    CREATED='2026-07-23T10:01:00+09:00'
}

evaluate() {
    run env CMD_COMPLETE_GATE_CI_EVAL_ONLY=1 bash "$GATE" <<<"$1"
}

block_message() {
    run env CMD_COMPLETE_GATE_BLOCK_MESSAGE_ONLY=1 \
        CMD_COMPLETE_GATE_BLOCK_CMD_ID=cmd_ci_fixture \
        CMD_COMPLETE_GATE_BLOCK_REASON="$1" bash "$GATE"
}

@test "in-progress workflow is WAIT and never demands repair redeployment" {
    evaluate "{\"expected_head_sha\":\"abc\",\"reviewed_at\":\"$REVIEWED\",\"target_result\":{\"conclusion\":\"success\",\"head_sha\":\"abc\"},\"workflow_result\":{\"status\":\"in_progress\",\"conclusion\":\"\",\"head_sha\":\"abc\",\"created_at\":\"$CREATED\"}}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WAIT: ci_evaluation_absent="* ]]
    [[ "$output" == *"run_pending:in_progress"* ]]
}

@test "completed failure remains BLOCK and retains repair redeployment guidance" {
    evaluate "{\"expected_head_sha\":\"abc\",\"reviewed_at\":\"$REVIEWED\",\"target_result\":{\"conclusion\":\"success\",\"head_sha\":\"abc\"},\"workflow_result\":{\"status\":\"completed\",\"conclusion\":\"failure\",\"head_sha\":\"abc\",\"created_at\":\"$CREATED\"}}"
    [ "$status" -eq 1 ]
    [[ "$output" == *"workflow_result is not GREEN"* ]]

    block_message "ci_readiness:$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"修正再配備せよ"* ]]
}

@test "completed success is the only GREEN state" {
    evaluate "{\"expected_head_sha\":\"abc\",\"reviewed_at\":\"$REVIEWED\",\"target_result\":{\"conclusion\":\"success\",\"head_sha\":\"abc\"},\"workflow_result\":{\"status\":\"completed\",\"conclusion\":\"success\",\"head_sha\":\"abc\",\"created_at\":\"$CREATED\"}}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"target_result=GREEN workflow_result=GREEN"* ]]
}

@test "unknown workflow status is WAIT, never mistaken for a repairable CI failure" {
    evaluate "{\"expected_head_sha\":\"abc\",\"reviewed_at\":\"$REVIEWED\",\"target_result\":{\"conclusion\":\"success\",\"head_sha\":\"abc\"},\"workflow_result\":{\"status\":\"unknown\",\"conclusion\":\"\",\"head_sha\":\"abc\",\"created_at\":\"$CREATED\"}}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WAIT: ci_evaluation_absent="* ]]
    [[ "$output" == *"run_pending:unknown"* ]]
    [[ "$output" != *"is not GREEN"* ]]
}

# ─── cmd_karo_impl_gate_metrics_record_split_20260725 (B20/B25) ───
# 判定が3状態でも、記録が全てBLOCKなら台帳は嘘をつく。判定→記録の写像を固定する。

classify() {
    run env CMD_COMPLETE_GATE_CLASSIFY_ONLY=1 \
        CMD_COMPLETE_GATE_CLASSIFY_REASON="$1" bash "$GATE"
}

raw_columns() {
    local helper="$BATS_TEST_TMPDIR/raw.sh"
    sed -n '/^format_ci_raw_columns()/,/^}/p' "$GATE" > "$helper"
    run bash -c "source '$helper'; format_ci_raw_columns \"\$1\" \"\$2\"" _ "$1" "$2"
}

@test "評価不在(absent集約トークン)はWAITとして記録される" {
    classify "ci_readiness:WAIT: ci_evaluation_absent=[head_sha_mismatch,run_predates_review] — 後追いで確認せよ"
    [ "$status" -eq 0 ]
    [ "$output" = "WAIT" ]
}

@test "旧表記のpending/predates/cancelledもWAITへ写像される" {
    classify "ci_readiness:BLOCK: workflow_result pending status=in_progress"
    [ "$output" = "WAIT" ]
    classify "ci_readiness:BLOCK: run predates SG7 review"
    [ "$output" = "WAIT" ]
    classify "ci_readiness:BLOCK: workflow_all_jobs_cancelled"
    [ "$output" = "WAIT" ]
}

@test "terminalな失敗はBLOCKのまま記録される" {
    classify "ci_readiness:BLOCK: workflow_result is not GREEN"
    [ "$output" = "BLOCK" ]
    classify "missing_gates:lesson,review"
    [ "$output" = "BLOCK" ]
}

@test "複合理由はterminalが1件でも混ざればBLOCK(fail-closed)" {
    classify "ci_readiness:WAIT: ci_evaluation_absent=[head_sha_mismatch]|ci_readiness:BLOCK: workflow_result is not GREEN"
    [ "$output" = "BLOCK" ]
}

@test "参考情報はINFO、理由が空なら分類不能としてBLOCK(fail-closed)" {
    classify "INFO: reference only"
    [ "$output" = "INFO" ]
    classify ""
    [ "$output" = "BLOCK" ]
}

@test "B25: run_id/conclusionの生値が併記され、欠落時もnoneで埋まる" {
    raw_columns "30149013181" "cancelled"
    [ "$output" = "$(printf 'ci_run_id=30149013181\tci_conclusion=cancelled')" ]
    raw_columns "" ""
    [ "$output" = "$(printf 'ci_run_id=none\tci_conclusion=none')" ]
}

@test "B25: gate_metrics書込みが生値列を付け、reasonは第4カラムのまま(後方互換)" {
    # WAIT/INFO/BLOCKの3経路すべてが raw 列を付けること
    [ "$(grep -c 'format_ci_raw_columns "\$ci_run_id" "\$ci_run_conclusion"' "$GATE")" -eq 2 ]
    grep -q 'format_ci_raw_columns "\${ci_run_id:-}" "\${ci_run_conclusion:-}"' "$GATE"
    # BLOCK行のカラム順: ts, cmd_id, category, reason, ...
    grep -q '"\$CMD_ID" "\$_gate_record_category" "\$block_reason"' "$GATE"
}
