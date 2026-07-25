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
