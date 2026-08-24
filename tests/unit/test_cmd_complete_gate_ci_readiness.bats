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

@test "completed workflow failure is WAIT and does not block gate decision" {
    evaluate "{\"expected_head_sha\":\"abc\",\"reviewed_at\":\"$REVIEWED\",\"target_result\":{\"conclusion\":\"success\",\"head_sha\":\"abc\"},\"workflow_result\":{\"status\":\"completed\",\"conclusion\":\"failure\",\"head_sha\":\"abc\",\"created_at\":\"$CREATED\"}}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WAIT: ci_evaluation_external_pending=workflow_result_not_green"* ]]

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

@test "billing annotation with no started jobs falls back only when local evidence is green" {
    evaluate "{\"expected_head_sha\":\"abc\",\"reviewed_at\":\"$REVIEWED\",\"target_result\":{\"conclusion\":\"success\",\"head_sha\":\"abc\"},\"workflow_result\":{\"status\":\"completed\",\"conclusion\":\"failure\",\"head_sha\":\"abc\",\"created_at\":\"$CREATED\",\"external_unavailable\":true,\"jobs_not_started\":true}}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"local_test=PASS external_unavailable=github_billing"* ]]
}

@test "billing annotation with no started jobs remains BLOCK for local test RED" {
    evaluate "{\"expected_head_sha\":\"abc\",\"reviewed_at\":\"$REVIEWED\",\"target_result\":{\"conclusion\":\"failure\",\"head_sha\":\"abc\"},\"workflow_result\":{\"status\":\"completed\",\"conclusion\":\"failure\",\"head_sha\":\"abc\",\"created_at\":\"$CREATED\",\"external_unavailable\":true,\"jobs_not_started\":true}}"
    [ "$status" -eq 1 ]
    [[ "$output" == *"local test evidence is not GREEN"* ]]
}

@test "billing annotation without a job-start absence remains BLOCK" {
    evaluate "{\"expected_head_sha\":\"abc\",\"reviewed_at\":\"$REVIEWED\",\"target_result\":{\"conclusion\":\"success\",\"head_sha\":\"abc\"},\"workflow_result\":{\"status\":\"completed\",\"conclusion\":\"failure\",\"head_sha\":\"abc\",\"created_at\":\"$CREATED\",\"external_unavailable\":true,\"jobs_not_started\":false}}"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a job-start absence"* ]]
}

# cmd_karo_* has no SG7 bundle.  Exercise the production resolver with a
# mocked report/approval boundary so this test covers the fingerprint binding
# and timestamp selection without mutating the repository queue.
load_karo_reviewed_at_resolver() {
    local helper="$BATS_TEST_TMPDIR/resolve_karo_reviewed_at.sh"
    sed -n '/^resolve_karo_reviewed_at()/,/^}$/p' "$GATE" > "$helper"
    # shellcheck disable=SC1090
    source "$helper"
}

write_karo_approval() {
    local role="$1" result="$2" timestamp="$3" fingerprint="${4:-fp-current}"
    mkdir -p "$BATS_TEST_TMPDIR/queue/gates/cmd_karo_fixture/review_approvals/reports/key-current"
    printf 'timestamp: %s\nresult: %s\nfingerprint: %s\n' \
        "$timestamp" "$result" "$fingerprint" \
        >"$BATS_TEST_TMPDIR/queue/gates/cmd_karo_fixture/review_approvals/reports/key-current/$role.yaml"
}

mock_karo_review_boundary() {
    review_report_fingerprint() { printf 'fp-current\n'; }
    review_report_logical_path() { printf 'queue/reports/report.yaml\n'; }
    review_report_key() { printf 'key-current\n'; }
    review_approval_value() {
        awk -F': ' -v key="$2" '$1 == key {print $2; exit}' "$1"
    }
}

@test "cmd_karo review boundary uses the later matching approval timestamp" {
    load_karo_reviewed_at_resolver
    mock_karo_review_boundary
    write_karo_approval gunshi LGTM '2026-08-08T12:00:00+09:00'
    write_karo_approval karo ACCEPT '2026-08-08T12:05:00+09:00'

    run resolve_karo_reviewed_at cmd_karo_fixture "$BATS_TEST_TMPDIR" report.yaml
    [ "$status" -eq 0 ]
    [ "$output" = '2026-08-08T03:05:00Z' ]
}

@test "cmd_karo review boundary fails closed on missing or mismatched approval evidence" {
    load_karo_reviewed_at_resolver
    mock_karo_review_boundary
    write_karo_approval gunshi LGTM '2026-08-08T12:00:00+09:00'
    write_karo_approval karo ACCEPT '2026-08-08T12:05:00+09:00' wrong-fingerprint

    run resolve_karo_reviewed_at cmd_karo_fixture "$BATS_TEST_TMPDIR" report.yaml
    [ "$status" -eq 1 ]
    [[ "$output" == *'review_approval_fingerprint_mismatch'* ]]
}

@test "cmd_karo review boundary rejects a timezone-less approval timestamp" {
    load_karo_reviewed_at_resolver
    mock_karo_review_boundary
    write_karo_approval gunshi LGTM '2026-08-08T12:00:00'
    write_karo_approval karo ACCEPT '2026-08-08T12:05:00+09:00'

    run resolve_karo_reviewed_at cmd_karo_fixture "$BATS_TEST_TMPDIR" report.yaml
    [ "$status" -eq 1 ]
    [[ "$output" == *'timezone missing'* ]]
}

@test "cmd_karo CI states keep WAIT READY and BLOCK semantics after review timestamp resolution" {
    load_karo_reviewed_at_resolver
    mock_karo_review_boundary
    write_karo_approval gunshi LGTM '2026-08-08T12:00:00+09:00'
    write_karo_approval karo ACCEPT '2026-08-08T12:05:00+09:00'
    run resolve_karo_reviewed_at cmd_karo_fixture "$BATS_TEST_TMPDIR" report.yaml
    [ "$status" -eq 0 ]
    local resolved="$output"

    evaluate "{\"expected_head_sha\":\"abc\",\"reviewed_at\":\"$resolved\",\"target_result\":{\"conclusion\":\"success\",\"head_sha\":\"abc\"},\"workflow_result\":{\"status\":\"in_progress\",\"conclusion\":\"\",\"head_sha\":\"abc\",\"created_at\":\"2026-08-08T03:06:00Z\"}}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WAIT: ci_evaluation_absent="* ]]

    evaluate "{\"expected_head_sha\":\"abc\",\"reviewed_at\":\"$resolved\",\"target_result\":{\"conclusion\":\"success\",\"head_sha\":\"abc\"},\"workflow_result\":{\"status\":\"completed\",\"conclusion\":\"success\",\"head_sha\":\"abc\",\"created_at\":\"2026-08-08T03:06:00Z\"}}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"target_result=GREEN workflow_result=GREEN"* ]]

    evaluate "{\"expected_head_sha\":\"abc\",\"reviewed_at\":\"$resolved\",\"target_result\":{\"conclusion\":\"success\",\"head_sha\":\"abc\"},\"workflow_result\":{\"status\":\"completed\",\"conclusion\":\"failure\",\"head_sha\":\"abc\",\"created_at\":\"2026-08-08T03:06:00Z\"}}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WAIT: ci_evaluation_external_pending=workflow_result_not_green"* ]]
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

@test "workflow failure is WAITとして記録される" {
    classify "ci_readiness:BLOCK: workflow_result is not GREEN"
    [ "$output" = "WAIT" ]
    classify "missing_gates:lesson,review"
    [ "$output" = "BLOCK" ]
}

@test "CI WAIT理由はworkflow確認でBLOCKへ昇格しない" {
    classify "ci_readiness:WAIT: ci_evaluation_absent=[head_sha_mismatch]|ci_readiness:BLOCK: workflow_result is not GREEN"
    [ "$output" = "WAIT" ]
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
