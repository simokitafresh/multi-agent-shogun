#!/usr/bin/env bats

setup() {
    GATE="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"
}

evaluate() {
    run env CMD_COMPLETE_GATE_CI_EVAL_ONLY=1 bash "$GATE" <<<"$1"
}

@test "target GREEN does not hide global workflow failure" {
    evaluate '{"expected_head_sha":"abc","target_result":{"conclusion":"success","head_sha":"abc","passed":8,"total":8},"workflow_result":{"conclusion":"failure","head_sha":"abc"}}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"workflow_result is not GREEN"* ]]
}

@test "target failure is fail-closed" {
    evaluate '{"expected_head_sha":"abc","target_result":{"conclusion":"failure","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"abc"}}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"target_result is not GREEN"* ]]
}

@test "separate target and workflow GREEN results are ready" {
    evaluate '{"expected_head_sha":"abc","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"abc"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"target_result=GREEN workflow_result=GREEN"* ]]
}

@test "head SHA mismatch is fail-closed" {
    evaluate '{"expected_head_sha":"abc","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"def"}}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"head SHA mismatch"* ]]
}

@test "missing typed result object is fail-closed" {
    evaluate '{"expected_head_sha":"abc","target_result":"success","workflow_result":{"conclusion":"success","head_sha":"abc"}}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"typed target_result/workflow_result required"* ]]
}
