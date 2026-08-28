#!/usr/bin/env bats

# test_necessity: when source_only_publish.receipt.json is absent, cleanup may
# publish exactly one recovered commit only if the task worktree HEAD equals
# the terminal report commit_hash and that commit is an ancestor of remote main.
# Any identity or ancestry mismatch must retain the worktree and publish zero.
# regression_justification: the existing no-code fallback accepted only the
# marker base and could not recover a valid source-changing task after the
# source publication receipt was lost.
# origin: [[GA491_ancestry_without_blob_gap]] -> [[receipt_missing_source_recovery]] -> [[exact_report_remote_identity]]

setup() {
    REPO_ROOT="$BATS_TEST_DIRNAME/../.."
    FIX="$(mktemp -d "$BATS_TEST_TMPDIR/project.XXXXXX")"
    CMD="cmd_archive_source_receipt_${BATS_TEST_NUMBER:-0}_$(basename "$FIX")"
    GEN="$(printf 'a%.0s' {1..64})"
    mkdir -p "$FIX/queue/gates/$CMD" "$FIX/queue/reports" "$FIX/queue/archive/reports"

    git init -q --bare "$FIX/remote.git"
    git init -q -b main "$FIX/repo"
    git -C "$FIX/repo" config user.email fixture@example.invalid
    git -C "$FIX/repo" config user.name fixture
    printf 'base\n' > "$FIX/repo/source.txt"
    git -C "$FIX/repo" add source.txt
    git -C "$FIX/repo" commit -q -m base
    git -C "$FIX/repo" remote add origin "$FIX/remote.git"
    git -C "$FIX/repo" push -q -u origin main
    BASE="$(git -C "$FIX/repo" rev-parse HEAD)"

    git -C "$FIX/repo" worktree add -q --detach "$FIX/task-wt" "$BASE"
    printf 'source change\n' >> "$FIX/task-wt/source.txt"
    git -C "$FIX/task-wt" add source.txt
    git -C "$FIX/task-wt" commit -q -m source-change
    SOURCE="$(git -C "$FIX/task-wt" rev-parse HEAD)"
    git -C "$FIX/task-wt" push -q origin HEAD:main
    git -C "$FIX/repo" fetch -q origin main

    printf '{"version":1,"state":"active","task_id":"%s_normal","parent_cmd":"%s","repo":"%s","worktree":"%s","remote_tip":"%s","published_commit":"","generation":"%s","created_at_ns":1}\n' \
        "$CMD" "$CMD" "$FIX/repo" "$FIX/task-wt" "$BASE" "$GEN" \
        > "$FIX/queue/gates/$CMD/task_worktree.json"
    printf '{"version":1,"state":"clear","cmd_id":"%s","completion_generation":"%s","persisted_at_ns":1}\n' \
        "$CMD" "$GEN" > "$FIX/queue/gates/$CMD/gate_worker.clear.json"
    printf '{"reviews":[{"cmd":"%s","report":"queue/reports/worker_report_%s.yaml"}]}\n' \
        "$CMD" "$CMD" > "$FIX/queue/gates/$CMD/single_review_manifest.json"
}

write_report() {
    local commit="$1"
    printf 'worker_id: kagemaru\ntask_id: %s_normal\nparent_cmd: %s\ntask_type: hotfix\nstatus: completed\nverdict: PASS\ncommit_hash: %s\ncommit_contract:\n  required: true\n  task_type: hotfix\n' \
        "$CMD" "$CMD" "$commit" > "$FIX/queue/reports/worker_report_${CMD}.yaml"
}

run_cleanup() {
    run env ARCHIVE_COMPLETED_PROJECT_DIR="$FIX" \
        ARCHIVE_TASK_WORKTREE_CLEANUP_ONLY=1 \
        ARCHIVE_REQUIRE_CLEAR_RECEIPT=1 \
        SHOGUN_COMPLETION_GENERATION="$GEN" \
        timeout 30 bash "$REPO_ROOT/scripts/archive_completed.sh" 3 "$CMD"
}

assert_blocked_without_publication() {
    [ "$status" -ne 0 ]
    [[ "$output" == *"published commit receipt missing, mismatched, or unresolved"* ]]
    [ -d "$FIX/task-wt" ]
    [ ! -e "$FIX/queue/gates/$CMD/archive.done" ]
    python3 - "$FIX/queue/gates/$CMD/task_worktree.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["state"] == "active"
assert data.get("published_commit", "") == ""
PY
}

@test "missing source receipt recovers report commit contained by remote main" {
    setup
    write_report "$SOURCE"

    run_cleanup
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"publication recovered from verified_report_commit"* ]]
    [ ! -d "$FIX/task-wt" ]
    python3 - "$FIX/queue/gates/$CMD/task_worktree.json" "$SOURCE" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["state"] == "cleaned"
assert data["published_commit"] == sys.argv[2]
assert data["published_recovery_source"] == "verified_report_commit"
PY
}

@test "missing source receipt blocks when report commit differs from worktree HEAD" {
    setup
    write_report "$BASE"

    run_cleanup
    echo "$output"
    assert_blocked_without_publication
}

@test "missing source receipt blocks when report commit is not in remote main ancestry" {
    setup
    SIDE="$(printf 'side\n' | git -C "$FIX/repo" commit-tree "${BASE}^{tree}" -p "$BASE")"
    git -C "$FIX/task-wt" checkout -q --detach "$SIDE"
    write_report "$SIDE"

    run_cleanup
    echo "$output"
    assert_blocked_without_publication
}

@test "missing source receipt blocks when report commit_hash is absent" {
    setup
    write_report ""

    run_cleanup
    echo "$output"
    assert_blocked_without_publication
}
