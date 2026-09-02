#!/usr/bin/env bats

setup_reclaim_fixture() {
    REPO="$BATS_TEST_TMPDIR/repo"
    WORKTREE_ROOT="$BATS_TEST_TMPDIR/worktrees"
    TASK_DIR="$BATS_TEST_TMPDIR/tasks"
    mkdir -p "$REPO/queue/gates" "$WORKTREE_ROOT" "$TASK_DIR"
    git init -q "$REPO"
    git -C "$REPO" config user.email test@example.invalid
    git -C "$REPO" config user.name fixture
    git -C "$REPO" switch -c main -q
    printf 'base\n' > "$REPO/file"
    git -C "$REPO" add file
    git -C "$REPO" commit -q -m base
}

reclaim() {
    env TASK_WORKTREE_RECLAIM_REPO="$REPO" \
        DEPLOY_TASK_WORKTREE_ROOT="$WORKTREE_ROOT" \
        TASK_WORKTREE_RECLAIM_TASK_DIR="$TASK_DIR" \
        TASK_WORKTREE_RECLAIM_GATES_DIR="$REPO/queue/gates" \
        bash "$BATS_TEST_DIRNAME/../../scripts/task_worktree_reclaim.sh" "$@"
}

# test_necessity: active marker + matching in-progress task pointer is the
# safety boundary; a dry-run and sweep must both retain the linked worktree.
@test "active task worktree is retained by dry-run and sweep" {
    setup_reclaim_fixture
    WT="$WORKTREE_ROOT/active"
    git -C "$REPO" worktree add -q --detach "$WT" HEAD
    mkdir -p "$REPO/queue/gates/cmd_active"
    python3 - "$REPO/queue/gates/cmd_active/task_worktree.json" "$REPO" "$WT" <<'PY'
import json
import sys

marker, repo, worktree = sys.argv[1:]
with open(marker, "w", encoding="utf-8") as handle:
    json.dump({
        "version": 1,
        "state": "active",
        "task_id": "task_active",
        "parent_cmd": "cmd_active",
        "repo": repo,
        "worktree": worktree,
    }, handle)
PY
    printf 'task:\n  task_id: task_active\n  parent_cmd: cmd_active\n  status: in_progress\n  task_worktree_workdir: %s\n' "$WT" > "$TASK_DIR/active.yaml"

    run reclaim --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"retain path=$WT reason=active_task"* ]]
    [[ "$output" == *"summary linked=1 candidates=0 removed=0"* ]]

    run reclaim --sweep
    [ "$status" -eq 0 ]
    [ -d "$WT" ]
    [[ "$output" == *"summary linked=1 candidates=0 removed=0"* ]]
}

# test_necessity: a clean linked worktree without a durable marker is an
# orphan; dry-run must expose it and sweep must remove only that linked path.
@test "clean orphan is listed by dry-run and reclaimed by sweep" {
    setup_reclaim_fixture
    WT="$WORKTREE_ROOT/orphan"
    git -C "$REPO" worktree add -q --detach "$WT" HEAD

    run reclaim --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"candidate path=$WT reason=missing_marker dirty=0"* ]]
    [[ "$output" == *"summary linked=1 candidates=1 removed=0"* ]]
    [ -d "$WT" ]

    run reclaim --sweep
    [ "$status" -eq 0 ]
    [ ! -e "$WT" ]
    [[ "$output" == *"remove path=$WT reason=missing_marker dirty=0"* ]]
    [[ "$output" == *"summary linked=1 candidates=1 removed=1"* ]]
    [ "$(git -C "$REPO" worktree list --porcelain | grep -c '^worktree ')" -eq 1 ]
}

# test_necessity: dirty orphan content is user work and must remain untouched;
# sweep reports the path instead of forcing removal.
@test "dirty orphan is retained and reported" {
    setup_reclaim_fixture
    WT="$WORKTREE_ROOT/dirty"
    git -C "$REPO" worktree add -q --detach "$WT" HEAD
    printf 'uncommitted\n' > "$WT/uncommitted.txt"

    run reclaim --sweep
    [ "$status" -eq 0 ]
    [ -d "$WT" ]
    [ -f "$WT/uncommitted.txt" ]
    [[ "$output" == *"retain path=$WT reason=missing_marker dirty=1"* ]]
    [[ "$output" == *"summary linked=1 candidates=1 removed=0 dirty_retained=1"* ]]
}
