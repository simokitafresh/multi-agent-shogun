#!/usr/bin/env bats
# test_necessity: CI completion readiness must accept only typed GREEN results for the reviewed commit and a workflow run created no earlier than SG7 review; violation is BLOCK.
# regression_justification: A pre-push historical GREEN run previously satisfied readiness after a later SG7 review and falsely cleared completion.

setup() {
    GATE="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"
}

evaluate() {
    run env CMD_COMPLETE_GATE_CI_EVAL_ONLY=1 bash "$GATE" <<<"$1"
}

@test "target GREEN does not hide global workflow failure" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"success","head_sha":"abc","passed":8,"total":8},"workflow_result":{"conclusion":"failure","head_sha":"abc","created_at":"2026-07-19T08:43:00+09:00"}}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"workflow_result is not GREEN"* ]]
}

@test "target failure is fail-closed" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"failure","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"abc","created_at":"2026-07-19T08:43:00+09:00"}}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"target_result is not GREEN"* ]]
}

@test "separate target and workflow GREEN results are ready" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"abc","created_at":"2026-07-19T08:43:00+09:00"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"target_result=GREEN workflow_result=GREEN"* ]]
}

@test "head SHA mismatch is fail-closed" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"def","created_at":"2026-07-19T08:43:00+09:00"}}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"head SHA mismatch"* ]]
}

@test "missing typed result object is fail-closed" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":"success","workflow_result":{"conclusion":"success","head_sha":"abc","created_at":"2026-07-19T08:43:00+09:00"}}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"typed target_result/workflow_result required"* ]]
}

@test "workflow run older than SG7 review is fail-closed" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"abc","created_at":"2026-07-19T08:42:16+09:00"}}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"predates SG7 review"* ]]
}

@test "missing invalid and unparseable freshness timestamps are fail-closed" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"abc"}}'
    [ "$status" -eq 1 ]
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"abc","created_at":123}}'
    [ "$status" -eq 1 ]
    evaluate '{"expected_head_sha":"abc","reviewed_at":"not-a-date","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"abc","created_at":"2026-07-19T08:43:00+09:00"}}'
    [ "$status" -eq 1 ]
}
