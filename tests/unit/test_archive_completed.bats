#!/usr/bin/env bats

# test_necessity: archive_completed.sh must preserve the post-CLEAR bytes of
# the tracked defense-overhead runtime while restoring the published tree, so
# terminal cleanup remains lossless and ordinary source dirt stays fail-closed.
# regression_justification: the allowlist previously omitted this tracked
# runtime path, causing a valid post-CLEAR telemetry update to block cleanup.
# origin: [[cmd_karo_hotfix_ac4_runtime_preservation_20260826]] -> [[tracked-runtime-fixture-boundary]] -> [[runtime-loss-or-cleanup-block]]

setup_fixture() {
    FIX="$BATS_TEST_TMPDIR/project-${BATS_TEST_NUMBER:-0}"
    CMD="cmd_archive_runtime_${BATS_TEST_NUMBER:-0}"
    GEN="$(printf 'a%.0s' {1..64})"
    mkdir -p "$FIX"
    git init --bare -q "$FIX/remote.git"
    git clone -q "$FIX/remote.git" "$FIX/shared"
    git -C "$FIX/shared" config user.email test@example.invalid
    git -C "$FIX/shared" config user.name fixture
    git -C "$FIX/shared" switch -c main -q
    mkdir -p "$FIX/shared/queue/gates/$CMD" "$FIX/shared/src" "$FIX/shared/logs"
    printf 'event=baseline\n' > "$FIX/shared/logs/defense_overhead.jsonl"
    printf 'BASE=1\n' > "$FIX/shared/src/app.py"
    printf '# Dashboard\n\n## 最新更新\n\n' > "$FIX/shared/dashboard.md"
    git -C "$FIX/shared" add logs/defense_overhead.jsonl src/app.py dashboard.md
    git -C "$FIX/shared" commit -q -m base
    git -C "$FIX/shared" push -q -u origin main
    printf '# Dashboard\n\n## 最新更新\n\n' > "$FIX/dashboard.md"
    git -C "$FIX/shared" worktree add -q -b "task-${BATS_TEST_NUMBER:-0}" "$FIX/task-wt" HEAD

    PUB="$(git -C "$FIX/task-wt" rev-parse HEAD)"
    mkdir -p "$FIX/queue/gates/$CMD"
    python3 - "$FIX/queue/gates/$CMD/task_worktree.json" "$FIX/shared" "$FIX/task-wt" "$CMD" "$PUB" <<'PY'
import json
import sys

marker, repo, worktree, cmd, published = sys.argv[1:]
json.dump({
    "version": 1,
    "parent_cmd": cmd,
    "repo": repo,
    "worktree": worktree,
    "state": "active",
    "published_commit": published,
}, open(marker, "w", encoding="utf-8"))
PY
    python3 - "$FIX/queue/gates/$CMD/gate_worker.clear.json" "$CMD" "$GEN" <<'PY'
import json
import sys

path, cmd, generation = sys.argv[1:]
json.dump({
    "version": 1,
    "state": "clear",
    "cmd_id": cmd,
    "completion_generation": generation,
    "persisted_at_ns": 1,
}, open(path, "w", encoding="utf-8"))
PY
}

run_cleanup() {
    run env ARCHIVE_COMPLETED_PROJECT_DIR="$FIX" \
        ARCHIVE_TASK_WORKTREE_CLEANUP_ONLY=1 \
        ARCHIVE_REQUIRE_CLEAR_RECEIPT=1 \
        SHOGUN_COMPLETION_GENERATION="$GEN" \
        bash "$BATS_TEST_DIRNAME/../../scripts/archive_completed.sh" 3 "$CMD"
}

@test "tracked runtime is preserved and cleanup is idempotent" {
    setup_fixture
    printf 'event=runtime\n' > "$FIX/task-wt/logs/defense_overhead.jsonl"
    run_cleanup
    [ "$status" -eq 0 ]
    [ ! -e "$FIX/task-wt" ]
    [ "$(cat "$FIX/queue/archive/task-worktree-artifacts/$CMD/tracked/logs/defense_overhead.jsonl")" = 'event=runtime' ]
    python3 - "$FIX/queue/gates/$CMD/task_worktree.json" <<'PY'
import json
import sys

assert json.load(open(sys.argv[1], encoding="utf-8"))["state"] == "cleaned"
PY

    run_cleanup
    [ "$status" -eq 0 ]
    [ "$(cat "$FIX/queue/archive/task-worktree-artifacts/$CMD/tracked/logs/defense_overhead.jsonl")" = 'event=runtime' ]
    echo "runtime_bytes=preserved cleanup=1 idempotent=1"
}

@test "ordinary source dirt remains a cleanup BLOCK" {
    setup_fixture
    printf 'event=runtime\n' > "$FIX/task-wt/logs/defense_overhead.jsonl"
    printf 'UNCOMMITTED=1\n' > "$FIX/task-wt/src/app.py"
    run_cleanup
    [ "$status" -ne 0 ]
    [ -d "$FIX/task-wt" ]
    [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))["state"])' "$FIX/queue/gates/$CMD/task_worktree.json")" = active ]
    echo "target_runtime=allowed ordinary_source_dirty=blocked orphan=retained"
}

@test "completion generation mismatch remains a cleanup BLOCK" {
    setup_fixture
    printf 'event=runtime\n' > "$FIX/task-wt/logs/defense_overhead.jsonl"
    python3 - "$FIX/queue/gates/$CMD/gate_worker.clear.json" "$CMD" <<'PY'
import json
import sys

path, cmd = sys.argv[1:]
json.dump({
    "version": 1,
    "state": "clear",
    "cmd_id": cmd,
    "completion_generation": "b" * 64,
    "persisted_at_ns": 1,
}, open(path, "w", encoding="utf-8"))
PY
    run_cleanup
    [ "$status" -ne 0 ]
    [ -d "$FIX/task-wt" ]
    [ ! -e "$FIX/queue/archive/task-worktree-artifacts/$CMD/tracked/logs/defense_overhead.jsonl" ]
    echo "generation_mismatch=blocked runtime_archive=0 worktree=retained"
}

@test "full completion publishes archive.done after runtime preservation" {
    setup_fixture
    printf 'event=runtime\n' > "$FIX/task-wt/logs/defense_overhead.jsonl"
    run env ARCHIVE_COMPLETED_PROJECT_DIR="$FIX" \
        ARCHIVE_REQUIRE_CLEAR_RECEIPT=1 \
        SHOGUN_COMPLETION_GENERATION="$GEN" \
        DEFENSE_OVERHEAD_ENABLED=0 \
        QUEUE_FLAG_RETENTION_MODE=off \
        bash "$BATS_TEST_DIRNAME/../../scripts/archive_completed.sh" 3 "$CMD"
    [ "$status" -eq 0 ]
    [ ! -e "$FIX/task-wt" ]
    [ -f "$FIX/queue/gates/$CMD/archive.done" ]
    [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))["state"])' "$FIX/queue/gates/$CMD/task_worktree.json")" = cleaned ]
    [ "$(cat "$FIX/queue/archive/task-worktree-artifacts/$CMD/tracked/logs/defense_overhead.jsonl")" = 'event=runtime' ]
    echo "full_completion=1 archive_done=1 marker_cleaned=1 runtime_bytes=preserved"
}

# test_necessity: source publication recovery must use the canonical
# origin/main boundary even when the source repo tracks a maintenance branch.
# regression_justification: @{upstream} can point at a branch that is behind
# canonical publication and would keep a valid terminal cleanup permanently
# blocked.
# origin: [[cmd_karo_hotfix_archive_publication_receipt_reconcile_202608311401]] -> [[canonical-origin-main-boundary]] -> [[archive-recovery-progress]]
@test "source report recovery ignores a behind maintenance upstream" {
    FIX="$BATS_TEST_TMPDIR/source-recovery-project"
    CMD="cmd_archive_source_recovery_canonical"
    GEN="$(printf 'a%.0s' {1..64})"
    mkdir -p "$FIX/queue/gates/$CMD" "$FIX/queue/reports" "$FIX/queue/archive/reports"
    git init -q --bare "$FIX/remote.git"
    git init -q -b main "$FIX/repo"
    git -C "$FIX/repo" config user.email fixture@example.invalid
    git -C "$FIX/repo" config user.name fixture
    printf 'base\n' > "$FIX/repo/source.txt"
    git -C "$FIX/repo" add source.txt
    git -C "$FIX/repo" commit -q -m base
    BASE="$(git -C "$FIX/repo" rev-parse HEAD)"
    git -C "$FIX/repo" remote add origin "$FIX/remote.git"
    git -C "$FIX/repo" push -q -u origin main
    git -C "$FIX/repo" worktree add -q --detach "$FIX/task-wt" "$BASE"
    printf 'source\n' >> "$FIX/task-wt/source.txt"
    git -C "$FIX/task-wt" add source.txt
    git -C "$FIX/task-wt" commit -q -m source-change
    SOURCE="$(git -C "$FIX/task-wt" rev-parse HEAD)"
    git -C "$FIX/task-wt" push -q origin HEAD:main
    git -C "$FIX/repo" fetch -q origin main
    git -C "$FIX/repo" switch -q -c maintenance "$BASE"
    git -C "$FIX/repo" push -q -u origin maintenance
    printf '{"version":1,"state":"active","task_id":"%s_normal","parent_cmd":"%s","repo":"%s","worktree":"%s","remote_tip":"%s","published_commit":"","generation":"%s","created_at_ns":1}\n' \
        "$CMD" "$CMD" "$FIX/repo" "$FIX/task-wt" "$BASE" "$GEN" \
        > "$FIX/queue/gates/$CMD/task_worktree.json"
    printf '{"version":1,"state":"clear","cmd_id":"%s","completion_generation":"%s","persisted_at_ns":1}\n' \
        "$CMD" "$GEN" > "$FIX/queue/gates/$CMD/gate_worker.clear.json"
    printf 'worker_id: kagemaru\ntask_id: %s_normal\nparent_cmd: %s\ntask_type: hotfix\nstatus: completed\nverdict: PASS\ncommit_hash: %s\ncommit_contract:\n  required: true\n' \
        "$CMD" "$CMD" "$SOURCE" > "$FIX/queue/reports/worker_report_${CMD}.yaml"
    printf '{"reviews":[{"cmd":"%s","report":"queue/reports/worker_report_%s.yaml"}]}\n' \
        "$CMD" "$CMD" > "$FIX/queue/gates/$CMD/single_review_manifest.json"

    run env ARCHIVE_COMPLETED_PROJECT_DIR="$FIX" \
        ARCHIVE_TASK_WORKTREE_CLEANUP_ONLY=1 ARCHIVE_REQUIRE_CLEAR_RECEIPT=1 \
        SHOGUN_COMPLETION_GENERATION="$GEN" \
        timeout 30 bash "$BATS_TEST_DIRNAME/../../scripts/archive_completed.sh" 3 "$CMD"
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
