#!/usr/bin/env bats
# test_necessity: CI completion readiness must BLOCK only on a real red verdict; every "no evaluation for this code" case (head SHA mismatch / predates review / pending / cancelled on either result) resolves to a single WAIT state that does not block the gate (push通過+CI後追い方式, 殿裁可 2026-07-25).
# regression_justification: A run whose jobs were all cancelled reports conclusion=failure yet contains no evaluation; it must resolve to WAIT, never to a red verdict that demands a ninja fix.

setup() {
    GATE="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"
}

evaluate() {
    run env CMD_COMPLETE_GATE_CI_EVAL_ONLY=1 bash "$GATE" <<<"$1"
}

@test "target GREEN keeps global workflow failure in asynchronous WAIT" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"success","head_sha":"abc","passed":8,"total":8},"workflow_result":{"conclusion":"failure","head_sha":"abc","created_at":"2026-07-19T08:43:00+09:00"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WAIT: ci_evaluation_external_pending=workflow_result_not_green"* ]]
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

@test "head SHA mismatch is WAIT, not BLOCK" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"def","created_at":"2026-07-19T08:43:00+09:00"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WAIT: ci_evaluation_absent=[head_sha_mismatch]"* ]]
}

@test "missing typed result object is fail-closed" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":"success","workflow_result":{"conclusion":"success","head_sha":"abc","created_at":"2026-07-19T08:43:00+09:00"}}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"typed target_result/workflow_result required"* ]]
}

@test "workflow run older than SG7 review is WAIT, not BLOCK" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"abc","created_at":"2026-07-19T08:42:16+09:00"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WAIT: ci_evaluation_absent=[run_predates_review]"* ]]
}

@test "rerun started after SG7 review is ready even when original run predates review" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"abc","created_at":"2026-07-19T08:40:00+09:00","started_at":"2026-07-19T08:43:00+09:00"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"fresh_after_review"* ]]
}

@test "rerun started before SG7 review is WAIT, not BLOCK" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"abc","created_at":"2026-07-19T08:40:00+09:00","started_at":"2026-07-19T08:42:16+09:00"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WAIT: ci_evaluation_absent=[run_predates_review]"* ]]
}

@test "run whose jobs were all cancelled is WAIT, not a red verdict" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"failure","head_sha":"abc","created_at":"2026-07-19T08:43:00+09:00","jobs_conclusions":["cancelled","cancelled","cancelled","cancelled"]}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WAIT: ci_evaluation_absent=[workflow_all_jobs_cancelled]"* ]]
    [[ "$output" != *"is not GREEN"* ]]
}

@test "cancelled target_result is WAIT on the target side as well" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"cancelled","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"abc","created_at":"2026-07-19T08:43:00+09:00"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WAIT: ci_evaluation_absent=[target_no_verdict]"* ]]
    [[ "$output" != *"is not GREEN"* ]]
}

@test "a single failing job is followed asynchronously even when others cancelled" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"failure","head_sha":"abc","created_at":"2026-07-19T08:43:00+09:00","jobs_conclusions":["failure","cancelled"]}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WAIT: ci_evaluation_external_pending=workflow_result_not_green"* ]]
}

@test "missing invalid and unparseable freshness timestamps are fail-closed" {
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"abc"}}'
    [ "$status" -eq 1 ]
    evaluate '{"expected_head_sha":"abc","reviewed_at":"2026-07-19T08:42:17+09:00","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"abc","created_at":123}}'
    [ "$status" -eq 1 ]
    evaluate '{"expected_head_sha":"abc","reviewed_at":"not-a-date","target_result":{"conclusion":"success","head_sha":"abc"},"workflow_result":{"conclusion":"success","head_sha":"abc","created_at":"2026-07-19T08:43:00+09:00"}}'
    [ "$status" -eq 1 ]
}
