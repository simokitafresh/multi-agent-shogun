#!/usr/bin/env bats

# test_necessity: U4 preserves the legacy report identity while introducing
# publisher-owned published_sha/path-blob evidence and an explicit retry state.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    TEST_ROOT="$BATS_TEST_TMPDIR/fixture"
    REPO="$TEST_ROOT/repo"
    STATE_DIR="$TEST_ROOT/state"
    mkdir -p "$REPO" "$STATE_DIR/publish_queue"
    git init -q -b main "$REPO"
    git -C "$REPO" config user.email test@example.com
    git -C "$REPO" config user.name test
    printf 'fixture-state\n' | git -C "$REPO" hash-object -w --stdin > "$TEST_ROOT/blob"
    blob="$(<"$TEST_ROOT/blob")"
    printf '100644 blob %s\tstate\n' "$blob" | git -C "$REPO" mktree > "$TEST_ROOT/tree"
    tree="$(<"$TEST_ROOT/tree")"
    commit="$(printf 'fixture\n' | git -C "$REPO" commit-tree "$tree")"
    git -C "$REPO" update-ref refs/heads/main "$commit"
    git -C "$REPO" update-ref refs/remotes/origin/main "$commit"
    printf '%s\n' "$commit" > "$TEST_ROOT/commit"
    printf '%s\n' "$blob" > "$TEST_ROOT/blob_value"
}

run_gate() {
    local report="$1"
    local task="${2:-}"
    run env SHOGUN_STATE_DIR="$STATE_DIR" \
        CMD_COMPLETE_GATE_REPORT_MAIN_ANCESTRY_ONLY=1 \
        CMD_COMPLETE_GATE_CI_REPORT="$report" \
        CMD_COMPLETE_GATE_CI_REPO_DIR="$REPO" \
        CMD_COMPLETE_GATE_TASK_FILE="$task" \
        bash "$GATE_SCRIPT" cmd_gate_dual_read
}

@test "legacy commit_hash report remains accepted" {
    report="$TEST_ROOT/legacy.yaml"
    printf 'verdict: PASS\ncommit_hash: %s\n' "$(<"$TEST_ROOT/commit")" > "$report"
    run_gate "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == "PASS: PUSHED: report commit "* ]]
}

@test "published_sha with path/blob receipt is accepted without commit_hash" {
    report="$TEST_ROOT/published.yaml"
    printf 'verdict: PASS\npublished_sha: %s\npath_blob_receipt:\n  - path: state\n    blob: %s\n' \
        "$(<"$TEST_ROOT/commit")" "$(<"$TEST_ROOT/blob_value")" > "$report"
    run_gate "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == "PASS: published_sha="*" paths=1 contained_by="* ]]
}

@test "publisher request for the task is reported as WAIT with its path" {
    report="$TEST_ROOT/pending.yaml"
    task="$TEST_ROOT/task.yaml"
    printf 'verdict: PASS\ntask_id: task_dual_read\n' > "$report"
    printf 'task:\n  task_id: task_dual_read\n' > "$task"
    request="$STATE_DIR/publish_queue/001_task_dual_read.request"
    printf 'task_id: task_dual_read\n' > "$request"
    run_gate "$report" "$task"
    [ "$status" -eq 0 ]
    [ "$output" = "WAIT:publisher_pending(request=$request)" ]
    [[ "$output" != *"BLOCK"* ]]
}

@test "published path/blob mismatch fails closed" {
    report="$TEST_ROOT/mismatch.yaml"
    printf 'verdict: PASS\npublished_sha: %s\npath_blob_receipt:\n  - path: state\n    blob: "%040d"\n' \
        "$(<"$TEST_ROOT/commit")" 0 > "$report"
    run_gate "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == "BLOCK: path/blob receipt mismatch:state" ]]
}

@test "published report without a path/blob receipt fails closed" {
    report="$TEST_ROOT/missing-receipt.yaml"
    printf 'verdict: PASS\npublished_sha: %s\n' "$(<"$TEST_ROOT/commit")" > "$report"
    run_gate "$report"
    [ "$status" -eq 1 ]
    [ "$output" = "BLOCK: path/blob receipt missing" ]
}

@test "autopush helper functions are outside the U4 diff" {
    run bash -c 'git diff -U0 -- scripts/cmd_complete_gate.sh | grep -E "^@@.*source_only_(path_snapshot_generic|cumulative_equivalence|insights_id_merge|lessons_id_merge)"'
    [ "$status" -eq 1 ]
}

