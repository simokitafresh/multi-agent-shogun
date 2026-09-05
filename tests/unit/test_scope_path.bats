#!/usr/bin/env bats
# test_necessity: Absolute paths and parent traversal (..) are blocked; violation is BLOCK.
# test_scope_path.bats - unit tests for scripts/lib/scope_path.sh (GA-222 SSOT)
#
# GA-222: ninja_scope_commit.sh and sync_git_hooks.sh each had their own
# ad-hoc scope-path normalization logic. Across four rounds of review, new
# path representations kept slipping through one script while being fixed in
# the other (directory scope, trailing "/.", root scope ".", "subdir/..",
# plain "..", double slashes). This library is now the single source of
# truth both scripts source, so every representation only needs to be
# handled correctly once, here.

setup() {
    # shellcheck source=scripts/lib/scope_path.sh
    source "$BATS_TEST_DIRNAME/../../scripts/lib/scope_path.sh"
}

@test "normalizes a plain relative path unchanged" {
    run scope_path_normalize "scripts/hooks/git-pre-commit.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "scripts/hooks/git-pre-commit.sh" ]
}

@test "normalizes a single-segment path unchanged" {
    run scope_path_normalize "own.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "own.txt" ]
}

@test "collapses double slashes" {
    run scope_path_normalize "scripts//hooks"
    [ "$status" -eq 0 ]
    [ "$output" = "scripts/hooks" ]
}

@test "strips a trailing '/.'" {
    run scope_path_normalize "scripts/hooks/."
    [ "$status" -eq 0 ]
    [ "$output" = "scripts/hooks" ]
}

@test "collapses repeated trailing '/./.'" {
    run scope_path_normalize "scripts/hooks/./."
    [ "$status" -eq 0 ]
    [ "$output" = "scripts/hooks" ]
}

@test "strips a leading './'" {
    run scope_path_normalize "./scripts/hooks"
    [ "$status" -eq 0 ]
    [ "$output" = "scripts/hooks" ]
}

@test "collapses an internal '/./'" {
    run scope_path_normalize "scripts/./hooks/git-pre-commit.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "scripts/hooks/git-pre-commit.sh" ]
}

@test "blocks an absolute path" {
    run scope_path_normalize "/etc/passwd"
    [ "$status" -eq 1 ]
    [[ "$output" == *"absolute"* ]]
}

@test "blocks an empty path" {
    run scope_path_normalize ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"empty"* ]]
}

@test "blocks root scope '.'" {
    run scope_path_normalize "."
    [ "$status" -eq 1 ]
    [[ "$output" == *"repository root"* ]]
}

@test "blocks a leading '..' traversal" {
    run scope_path_normalize "../etc/passwd"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'..'"* ]]
}

@test "blocks a mid-path '..' traversal (a/../b)" {
    run scope_path_normalize "a/../b"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'..'"* ]]
}

@test "blocks a trailing '..' traversal (subdir/..)" {
    run scope_path_normalize "subdir/.."
    [ "$status" -eq 1 ]
    [[ "$output" == *"'..'"* ]]
}

@test "blocks a bare '..'" {
    run scope_path_normalize ".."
    [ "$status" -eq 1 ]
    [[ "$output" == *"'..'"* ]]
}

@test "is_in_scope: exact match" {
    run scope_path_is_in_scope "scripts/hooks/git-pre-commit.sh" "scripts/hooks/git-pre-commit.sh"
    [ "$status" -eq 0 ]
}

@test "is_in_scope: file under an in-scope directory" {
    run scope_path_is_in_scope "scripts/hooks/git-pre-commit.sh" "scripts/hooks"
    [ "$status" -eq 0 ]
}

@test "is_in_scope: normalizes both target and scope path before comparing (double slash + trailing /.)" {
    run scope_path_is_in_scope "scripts/hooks/git-pre-commit.sh" "scripts//hooks/."
    [ "$status" -eq 0 ]
}

@test "is_in_scope: a similarly-prefixed scope path does not match (boundary requires '/')" {
    run scope_path_is_in_scope "scripts/hooks/git-pre-commit.sh" "scripts/hook"
    [ "$status" -eq 1 ]
}

@test "is_in_scope: unrelated path is out of scope" {
    run scope_path_is_in_scope "scripts/hooks/git-pre-commit.sh" "own.txt"
    [ "$status" -eq 1 ]
}

@test "is_in_scope: empty scope list is always out of scope" {
    run scope_path_is_in_scope "scripts/hooks/git-pre-commit.sh"
    [ "$status" -eq 1 ]
}

# test_necessity: an active ninja task with a provisioned linked worktree must
# never let a helper launched from the shared root advance main.  The fixture
# asserts the irreversible boundary numerically: task ref advances once while
# shared-root main advances zero times.
@test "active ninja task auto-binds its worktree when task file env is unset" {
    fixture="$BATS_TEST_TMPDIR/root-guard"
    shared="$fixture/shared"
    task_wt="$fixture/task-wt"
    fake_bin="$fixture/bin"
    mkdir -p "$shared/scripts/lib" "$shared/docs" "$shared/queue/tasks" "$fake_bin"

    cp "$BATS_TEST_DIRNAME/../../scripts/ninja_scope_commit.sh" "$shared/scripts/ninja_scope_commit.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/lock_path.sh" "$shared/scripts/lib/lock_path.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/scope_path.sh" "$shared/scripts/lib/scope_path.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/report_commit_nonoverlap_filter.sh" "$shared/scripts/lib/report_commit_nonoverlap_filter.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/test_necessity_contract.py" "$shared/scripts/lib/test_necessity_contract.py"
    printf 'base\n' > "$shared/docs/general.md"
    git -C "$shared" init -q
    git -C "$shared" config user.email test@example.com
    git -C "$shared" config user.name test
    git -C "$shared" add scripts docs
    git -C "$shared" commit -qm initial
    git -C "$shared" worktree add -q -d "$task_wt" HEAD

    printf 'task change\n' > "$task_wt/docs/general.md"
    cat > "$shared/queue/tasks/kagemaru.yaml" <<YAML
task:
  task_id: task-auto-bind-root-guard
  parent_cmd: cmd-auto-bind-root-guard
  status: acknowledged
  task_worktree_required: true
  task_worktree_status: active
  task_worktree_path: $task_wt
  planned_paths: [docs/general.md]
YAML
    cat > "$fake_bin/tmux" <<'SH'
#!/usr/bin/env bash
printf 'kagemaru\n'
SH
    chmod +x "$fake_bin/tmux"

    main_before="$(git -C "$shared" rev-parse HEAD)"
    task_before="$(git -C "$task_wt" rev-parse HEAD)"
    run bash -c 'cd "$1" && PATH="$2:$PATH" TMUX_PANE=fixture-pane env -u NINJA_SCOPE_TASK_FILE bash scripts/ninja_scope_commit.sh -m "general docs" -- docs/general.md' _ "$shared" "$fake_bin"

    [ "$status" -eq 0 ]
    main_after="$(git -C "$shared" rev-parse HEAD)"
    task_after="$(git -C "$task_wt" rev-parse HEAD)"
    [ "$main_after" = "$main_before" ]
    [ "$task_after" != "$task_before" ]
    [ "$(git -C "$task_wt" show --format= --name-only HEAD)" = "docs/general.md" ]
    [[ "$(git -C "$task_wt" log -1 --format=%s)" = "task-auto-bind-root-guard: general docs" ]]
    echo "shared_main_ref_delta=0 task_worktree_ref_delta=1"
}
