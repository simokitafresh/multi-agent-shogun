#!/usr/bin/env bats
# test_necessity: CI readiness must keep in-progress runs fail-closed without recommending code-fix redeployment, while completed failures still recommend repair and only completed success can clear.

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

@test "in-progress workflow remains BLOCK and requests wait plus re-gate without repair redeployment" {
    evaluate "{\"expected_head_sha\":\"abc\",\"reviewed_at\":\"$REVIEWED\",\"target_result\":{\"conclusion\":\"success\",\"head_sha\":\"abc\"},\"workflow_result\":{\"status\":\"in_progress\",\"conclusion\":\"\",\"head_sha\":\"abc\",\"created_at\":\"$CREATED\"}}"
    [ "$status" -eq 1 ]
    [[ "$output" == *"workflow_result pending status=in_progress"* ]]

    block_message "ci_readiness:$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI完了通知を待機"* ]]
    [[ "$output" == *"再ゲート"* ]]
    [[ "$output" != *"修正再配備せよ"* ]]
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

@test "unknown workflow status fails closed without being mistaken for repairable CI failure" {
    evaluate "{\"expected_head_sha\":\"abc\",\"reviewed_at\":\"$REVIEWED\",\"target_result\":{\"conclusion\":\"success\",\"head_sha\":\"abc\"},\"workflow_result\":{\"status\":\"unknown\",\"conclusion\":\"\",\"head_sha\":\"abc\",\"created_at\":\"$CREATED\"}}"
    [ "$status" -eq 1 ]
    [[ "$output" == *"workflow_result pending status=unknown"* ]]
}
