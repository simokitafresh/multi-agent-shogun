#!/usr/bin/env bats
# test_necessity: Another agent uncommitted dirty edit never leaks into the live hook (GA-222); violation is BLOCK.
# test_sync_git_hooks.bats - unit tests for scripts/sync_git_hooks.sh (GA-222)
#
# GA-222: .git/hooks/pre-commit is a direct (non-symlink) copy of the tracked
# scripts/hooks/git-pre-commit.sh and never gets re-synced when the tracked
# source changes. This left a real production hook 21 days / 3 commits stale
# (2026-06-20 install vs 2026-07-07 GA-190 auto-fix + 2026-07-09 GA-205 fix),
# causing a real BLOCK on 2026-07-11 that should have silently auto-fixed.
#
# GA-222 REQUEST_CHANGES (2026-07-11 karo): the initial fix (commit e1390c602)
# copied the *working tree* content of the tracked source unconditionally,
# which meant another agent's uncommitted (even unstaged) WIP edit to
# scripts/hooks/git-pre-commit.sh could leak into the live hook during a
# completely unrelated ninja's commit. This rewrite sources content from git
# objects only (HEAD, or the index when the source is explicitly declared
# in-scope via --scope-path), resolves the installed path via
# `git rev-parse --git-path` (worktree-safe), and installs atomically
# (tmp file -> chmod -> rename) so a mid-write failure can never truncate
# the live hook.

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/sync_git_hooks.XXXXXX")"
    HELPER="$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh"

    (
        cd "$TEST_ROOT"
        git init -q
        git config user.email test@example.com
        git config user.name "Test User"
        printf 'unrelated\n' > own.txt
        git add own.txt
        git commit -qm init
    )
    # sync_git_hooks.sh unconditionally sources scripts/lib/scope_path.sh
    # (SSOT for scope path normalization); every sandbox repo needs a copy.
    # This is intentionally NOT under scripts/hooks/, so it does not affect
    # the "no-ops when scripts/hooks/ convention is unused" test below.
    mkdir -p "$TEST_ROOT/scripts/lib"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/scope_path.sh" "$TEST_ROOT/scripts/lib/scope_path.sh"
}

teardown() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

# test_necessity: GA-309 pre-push must select and execute tests from the pushed
# commit snapshot; unrelated shared-worktree WIP must never create a false BLOCK.
@test "GA-309 pre-push runs selector and runner from local_sha clean snapshot" {
    mkdir -p "$TEST_ROOT/.githooks" "$TEST_ROOT/scripts" "$TEST_ROOT/logs/test_receipts"
    cp "$BATS_TEST_DIRNAME/../../.githooks/pre-push" "$TEST_ROOT/.githooks/pre-push"
    # The tracked production hook is mode100644 and is invoked through bash.
    [ "$(stat -c '%a' "$TEST_ROOT/.githooks/pre-push")" = "644" ]
    cp "$BATS_TEST_DIRNAME/../../scripts/safe_shared_main_ff.sh" "$TEST_ROOT/scripts/safe_shared_main_ff.sh"
    [ "$(stat -c '%a' "$TEST_ROOT/scripts/safe_shared_main_ff.sh")" = "644" ]
    cat > "$TEST_ROOT/scripts/test_select.sh" <<'EOF'
#!/usr/bin/env bash
echo tests/unit/clean.bats
EOF
    cat > "$TEST_ROOT/scripts/run_tests.sh" <<'EOF'
#!/usr/bin/env bash
printf 'clean-run\n' >> "$GA309_TRACE"
exit 0
EOF
    chmod +x "$TEST_ROOT/scripts/test_select.sh" "$TEST_ROOT/scripts/run_tests.sh"
    printf 'base\n' > "$TEST_ROOT/changed.txt"
    (cd "$TEST_ROOT" && git add . && git commit -qm ga309-base)
    printf 'pushed\n' > "$TEST_ROOT/changed.txt"
    (cd "$TEST_ROOT" && git add changed.txt && git commit -qm ga309-pushed)
    local local_sha base_sha trace
    local_sha="$(git -C "$TEST_ROOT" rev-parse HEAD)"
    base_sha="$(git -C "$TEST_ROOT" rev-parse HEAD^)"
    trace="$BATS_TMPDIR/ga309-trace.$BATS_TEST_NUMBER"
    : > "$trace"

    # Dirty sentinels would fail or leave a distinct trace if the shared root
    # leaked into either selection or execution.
    printf '#!/usr/bin/env bash\necho tests/unit/dirty-sentinel.bats\n' > "$TEST_ROOT/scripts/test_select.sh"
    printf '#!/usr/bin/env bash\nprintf "DIRTY_SENTINEL\\n" >> "$GA309_TRACE"\nexit 91\n' > "$TEST_ROOT/scripts/run_tests.sh"
    chmod +x "$TEST_ROOT/scripts/test_select.sh" "$TEST_ROOT/scripts/run_tests.sh"

    run env GA309_TRACE="$trace" PREPUSH_LOCK_WAIT_SECONDS=2 \
        bash -c "cd '$TEST_ROOT' && printf 'refs/heads/main $local_sha refs/heads/main $base_sha\\n' | bash .githooks/pre-push origin example.invalid"

    [ "$status" -eq 0 ]
    [ "$(cat "$trace")" = "clean-run" ]
    [[ "$output" != *"DIRTY_SENTINEL"* ]]
    [ "$(git -C "$TEST_ROOT" worktree list --porcelain | grep -c '^worktree ')" -eq 1 ]
}

commit_hook_source() {
    local content="$1"
    mkdir -p "$TEST_ROOT/scripts/hooks" "$TEST_ROOT/.githooks"
    printf '%s\n' "$content" > "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    if [ ! -f "$TEST_ROOT/.githooks/pre-push" ]; then
        printf '#!/usr/bin/env bash\necho PRE_PUSH_HEAD\n' > "$TEST_ROOT/.githooks/pre-push"
    fi
    if [ ! -f "$TEST_ROOT/.githooks/post-commit" ]; then
        printf '#!/usr/bin/env bash\necho POST_COMMIT_HEAD\n' > "$TEST_ROOT/.githooks/post-commit"
    fi
    (
        cd "$TEST_ROOT"
        git add scripts/hooks/git-pre-commit.sh .githooks/pre-push .githooks/post-commit
        git commit -qm "hook source: $content"
    )
}

@test "installs hook from HEAD when missing" {
    commit_hook_source "echo v1"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    [[ "$output" == *"SYNCED"* ]]
    [ -x "$TEST_ROOT/.git/hooks/pre-commit" ]
    run cat "$TEST_ROOT/.git/hooks/pre-commit"
    [[ "$output" == *"echo v1"* ]]
}

# test_necessity: The tracked post-commit source is installed into the active worktree-isolated hooksPath.
@test "tracked post-commit is part of the hook manifest" {
    commit_hook_source "echo v1"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    [ -x "$TEST_ROOT/.git/hooks/post-commit" ]
    grep -q POST_COMMIT_HEAD "$TEST_ROOT/.git/hooks/post-commit"
}

# test_necessity: A newly introduced tracked hook can install from the current private index before it exists in HEAD.
@test "new in-scope post-commit installs from index on its first commit" {
    commit_hook_source "echo v1"
    (cd "$TEST_ROOT" && git rm -q .githooks/post-commit && git commit -qm without-post-commit)
    printf '#!/usr/bin/env bash\necho FIRST_INDEX_POST_COMMIT\n' > "$TEST_ROOT/.githooks/post-commit"
    (cd "$TEST_ROOT" && git add .githooks/post-commit)

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    grep -q FIRST_INDEX_POST_COMMIT "$TEST_ROOT/.git/hooks/post-commit"
}

@test "overwrites stale installed hook to match HEAD (regression proof for GA-222)" {
    commit_hook_source "echo NEW_FIXED_VERSION"
    printf '#!/usr/bin/env bash\necho OLD_STALE_VERSION\n' > "$TEST_ROOT/.git/hooks/pre-commit"
    chmod +x "$TEST_ROOT/.git/hooks/pre-commit"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    [[ "$output" == *"SYNCED"* ]]
    run cat "$TEST_ROOT/.git/hooks/pre-commit"
    [[ "$output" == *"NEW_FIXED_VERSION"* ]]
    [[ "$output" != *"OLD_STALE_VERSION"* ]]
}

@test "is idempotent and a no-op when already in sync" {
    commit_hook_source "echo v1"
    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"
    [ "$status" -eq 0 ]
    before_mtime="$(stat -c '%Y' "$TEST_ROOT/.git/hooks/pre-commit")"
    sleep 1

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    [[ "$output" != *"SYNCED"* ]]
    after_mtime="$(stat -c '%Y' "$TEST_ROOT/.git/hooks/pre-commit")"
    [ "$before_mtime" = "$after_mtime" ]
}

@test "hash fast path skips git show and temporary install when already in sync" {
    commit_hook_source "echo v1"
    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"
    [ "$status" -eq 0 ]

    mkdir -p "$TEST_ROOT/mockbin"
    real_git="$(command -v git)"
    cat > "$TEST_ROOT/mockbin/git" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == *" show "* ]]; then
    echo unexpected-show >&2
    exit 97
fi
exec "$real_git" "\$@"
EOF
    chmod +x "$TEST_ROOT/mockbin/git"

    run env PATH="$TEST_ROOT/mockbin:$PATH" bash -c "cd '$TEST_ROOT' && bash '$HELPER'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"unexpected-show"* ]]
    [[ "$output" != *"SYNCED"* ]]
}

@test "no-ops safely when this repo does not use the scripts/hooks/ convention" {
    # No scripts/hooks/ directory tracked at all in HEAD.
    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/.git/hooks/pre-commit" ]
}

@test "a repo using only scripts/hooks is not forced to adopt the separate .githooks convention" {
    mkdir -p "$TEST_ROOT/scripts/hooks"
    printf '#!/usr/bin/env bash\necho PRE_COMMIT_ONLY\n' >"$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    (
        cd "$TEST_ROOT"
        git add scripts/hooks/git-pre-commit.sh
        git commit -qm pre-commit-only
    )

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    grep -q PRE_COMMIT_ONLY "$TEST_ROOT/.git/hooks/pre-commit"
    [ ! -e "$TEST_ROOT/.git/hooks/pre-push" ]
}

@test "AC1 regression proof: the pre-fix version (commit e1390c602) leaked another agent's uncommitted dirty edit into the live hook" {
    # Embeds the pre-REQUEST_CHANGES sync_git_hooks.sh logic verbatim (as
    # committed in e1390c602) to concretely prove the bug this rewrite fixes,
    # rather than merely asserting it from memory.
    OLD_HELPER="$TEST_ROOT/old_sync_git_hooks_v1.sh"
    cat > "$OLD_HELPER" <<'OLDSCRIPT'
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "BLOCK: not inside a git repository" >&2; exit 1; }
HOOK_MANIFEST=(
    "pre-commit:scripts/hooks/git-pre-commit.sh"
)
sync_one_hook() {
    local hook_name="$1" source_rel="$2"
    local source_full="$repo_root/$source_rel"
    local installed="$repo_root/.git/hooks/$hook_name"
    [[ -f "$source_full" ]] || return 0
    if [[ -f "$installed" ]] && cmp -s "$source_full" "$installed"; then
        return 0
    fi
    if ! cp "$source_full" "$installed" 2>/dev/null; then
        echo "BLOCK(GA-222): failed to sync .git/hooks/$hook_name from $source_rel" >&2
        return 1
    fi
    chmod +x "$installed" 2>/dev/null || true
    echo "SYNCED(GA-222): .git/hooks/$hook_name <- $source_rel" >&2
    return 0
}
status=0
for entry in "${HOOK_MANIFEST[@]}"; do
    hook_name="${entry%%:*}"
    source_rel="${entry#*:}"
    sync_one_hook "$hook_name" "$source_rel" || status=1
done
exit "$status"
OLDSCRIPT
    chmod +x "$OLD_HELPER"

    commit_hook_source "echo COMMITTED_V1"
    # Another agent's uncommitted, unstaged WIP edit — unrelated to this scope.
    printf '#!/usr/bin/env bash\necho OTHER_AGENT_UNCOMMITTED_WIP\n' > "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$TEST_ROOT' && bash '$OLD_HELPER'"
    [ "$status" -eq 0 ]
    run cat "$TEST_ROOT/.git/hooks/pre-commit"
    [[ "$output" == *"OTHER_AGENT_UNCOMMITTED_WIP"* ]]   # the bug: dirty WIP leaked into the live hook

    # The current (fixed) helper must NOT reproduce this leak on the same fixture.
    rm -f "$TEST_ROOT/.git/hooks/pre-commit"
    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"
    [ "$status" -eq 0 ]
    run cat "$TEST_ROOT/.git/hooks/pre-commit"
    [[ "$output" == *"COMMITTED_V1"* ]]
    [[ "$output" != *"OTHER_AGENT_UNCOMMITTED_WIP"* ]]
}

@test "does not touch hook files absent from the tracked manifest" {
    commit_hook_source "echo v1"
    printf '#!/usr/bin/env bash\necho commit-msg-untouched\n' > "$TEST_ROOT/.git/hooks/commit-msg"
    chmod +x "$TEST_ROOT/.git/hooks/commit-msg"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    run cat "$TEST_ROOT/.git/hooks/commit-msg"
    [[ "$output" == *"commit-msg-untouched"* ]]
}

@test "pre-push tracked source is installed and stale active hook is overwritten" {
    commit_hook_source "echo v1"
    printf '#!/usr/bin/env bash\necho STALE_PRE_PUSH\n' > "$TEST_ROOT/.git/hooks/pre-push"
    chmod +x "$TEST_ROOT/.git/hooks/pre-push"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    run cat "$TEST_ROOT/.git/hooks/pre-push"
    [[ "$output" == *"PRE_PUSH_HEAD"* ]]
    [[ "$output" != *"STALE_PRE_PUSH"* ]]
}

@test "pre-push working-tree WIP stays out of active hook unless explicitly in scope" {
    commit_hook_source "echo v1"
    printf '#!/usr/bin/env bash\necho PRE_PUSH_WIP\n' > "$TEST_ROOT/.githooks/pre-push"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"
    [ "$status" -eq 0 ]
    run cat "$TEST_ROOT/.git/hooks/pre-push"
    [[ "$output" == *"PRE_PUSH_HEAD"* ]]
    [[ "$output" != *"PRE_PUSH_WIP"* ]]

    (cd "$TEST_ROOT" && git add .githooks/pre-push)
    run bash -c "cd '$TEST_ROOT' && bash '$HELPER' --scope-path .githooks/pre-push"
    [ "$status" -eq 0 ]
    run cat "$TEST_ROOT/.git/hooks/pre-push"
    [[ "$output" == *"PRE_PUSH_WIP"* ]]
}

# test_necessity: runtime-only publication commits must not re-run the
# affected-test lane, while a commit mixing runtime records with source code
# must remain fail-closed and execute it.
@test "runtime-only pre-push commit skips affected tests but mixed source does not" {
    trace="$TEST_ROOT/logs/pre_push_runtime_trace"
    mkdir -p "$TEST_ROOT/.githooks" "$TEST_ROOT/scripts" \
        "$TEST_ROOT/context" "$TEST_ROOT/projects/infra" "$TEST_ROOT/tasks"
    cp "$BATS_TEST_DIRNAME/../../.githooks/pre-push" "$TEST_ROOT/.githooks/pre-push"
    cp "$BATS_TEST_DIRNAME/../../scripts/safe_shared_main_ff.sh" "$TEST_ROOT/scripts/safe_shared_main_ff.sh"
    [ "$(stat -c '%a' "$TEST_ROOT/scripts/safe_shared_main_ff.sh")" = "644" ]
    cat > "$TEST_ROOT/scripts/test_select.sh" <<'EOF'
#!/usr/bin/env bash
printf 'tests/unit/runtime-marker.bats\n'
EOF
    cat > "$TEST_ROOT/scripts/run_tests.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PRE_PUSH_RUNTIME_TRACE"
EOF
    chmod +x "$TEST_ROOT/scripts/test_select.sh" "$TEST_ROOT/scripts/run_tests.sh"
    (
        cd "$TEST_ROOT"
        git add .githooks/pre-push scripts/test_select.sh scripts/run_tests.sh
        git commit -qm pre-push-runtime-baseline
    )

    printf '# runtime context\n' > "$TEST_ROOT/context/infrastructure.md"
    printf 'lessons: []\n' > "$TEST_ROOT/projects/infra/lessons.yaml"
    printf '# runtime lessons\n' > "$TEST_ROOT/tasks/lessons.md"
    (
        cd "$TEST_ROOT"
        git add context/infrastructure.md projects/infra/lessons.yaml tasks/lessons.md
        git commit -qm runtime-only-publish
    )
    runtime_sha="$(git -C "$TEST_ROOT" rev-parse HEAD)"
    runtime_base="$(git -C "$TEST_ROOT" rev-parse 'HEAD^')"

    run env PRE_PUSH_RUNTIME_TRACE="$trace" bash -c \
        "cd '$TEST_ROOT' && printf 'refs/heads/main $runtime_sha refs/heads/main $runtime_base\\n' | bash .githooks/pre-push origin example.invalid"
    [ "$status" -eq 0 ]
    [ ! -f "$trace" ]

    printf '#!/usr/bin/env bash\necho source\n' > "$TEST_ROOT/scripts/source.sh"
    printf '# mixed runtime and source\n' >> "$TEST_ROOT/context/infrastructure.md"
    (
        cd "$TEST_ROOT"
        git add scripts/source.sh context/infrastructure.md
        git commit -qm runtime-with-source
    )
    mixed_sha="$(git -C "$TEST_ROOT" rev-parse HEAD)"
    mixed_base="$(git -C "$TEST_ROOT" rev-parse 'HEAD^')"

    run env PRE_PUSH_RUNTIME_TRACE="$trace" bash -c \
        "cd '$TEST_ROOT' && printf 'refs/heads/main $mixed_sha refs/heads/main $mixed_base\\n' | bash .githooks/pre-push origin example.invalid"
    [ "$status" -eq 0 ]
    [ -s "$trace" ]
    grep -q '^affected ' "$trace"
}

@test "GA-222 REQUEST_CHANGES: another agent's uncommitted working-tree edit never leaks into the live hook" {
    commit_hook_source "echo COMMITTED_V1"
    # Simulate another, unrelated agent mid-edit: unstaged, uncommitted change
    # to the tracked hook source while THIS commit does not touch it at all.
    printf '#!/usr/bin/env bash\necho OTHER_AGENT_UNCOMMITTED_WIP\n' > "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    run cat "$TEST_ROOT/.git/hooks/pre-commit"
    [[ "$output" == *"COMMITTED_V1"* ]]
    [[ "$output" != *"OTHER_AGENT_UNCOMMITTED_WIP"* ]]
}

@test "GA-222 REQUEST_CHANGES: staged-but-out-of-scope content is ignored; HEAD is used" {
    commit_hook_source "echo COMMITTED_V1"
    # Another agent HAS staged (git add, not committed) a change to the shared
    # index, but THIS ninja's own commit scope does not include this file.
    printf '#!/usr/bin/env bash\necho STAGED_BY_OTHER_AGENT\n' > "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    (cd "$TEST_ROOT" && git add scripts/hooks/git-pre-commit.sh)

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"   # no --scope-path passed

    [ "$status" -eq 0 ]
    run cat "$TEST_ROOT/.git/hooks/pre-commit"
    [[ "$output" == *"COMMITTED_V1"* ]]
    [[ "$output" != *"STAGED_BY_OTHER_AGENT"* ]]
}

@test "GA-222 REQUEST_CHANGES: staged content IS used when the source is declared in-scope" {
    commit_hook_source "echo COMMITTED_V1"
    printf '#!/usr/bin/env bash\necho STAGED_FOR_THIS_COMMIT\n' > "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    (cd "$TEST_ROOT" && git add scripts/hooks/git-pre-commit.sh)

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER' --scope-path scripts/hooks/git-pre-commit.sh"

    [ "$status" -eq 0 ]
    run cat "$TEST_ROOT/.git/hooks/pre-commit"
    [[ "$output" == *"STAGED_FOR_THIS_COMMIT"* ]]
}

@test "GA-222 followup: staged content IS used when a parent directory is declared in-scope" {
    # ninja_scope_commit.sh permits directory scopes (e.g. -- scripts/hooks),
    # which git add stages recursively. sync_git_hooks.sh must treat a file
    # under an in-scope directory as in-scope too, not just exact matches.
    commit_hook_source "echo COMMITTED_V1"
    printf '#!/usr/bin/env bash\necho STAGED_VIA_DIRECTORY_SCOPE\n' > "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    (cd "$TEST_ROOT" && git add scripts/hooks/git-pre-commit.sh)

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER' --scope-path scripts/hooks"

    [ "$status" -eq 0 ]
    run cat "$TEST_ROOT/.git/hooks/pre-commit"
    [[ "$output" == *"STAGED_VIA_DIRECTORY_SCOPE"* ]]
}

@test "GA-222 final edge RC: staged content IS used when scope path has a trailing '/.' (pathspec-equivalent to the directory)" {
    # "scripts/hooks/." is pathspec-equivalent to "scripts/hooks" for git add,
    # but is a different string. is_in_scope must lexically normalize before
    # comparing, or this re-introduces the same re-drift bug via another
    # path spelling.
    commit_hook_source "echo COMMITTED_V1"
    printf '#!/usr/bin/env bash\necho STAGED_VIA_TRAILING_DOT\n' > "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    (cd "$TEST_ROOT" && git add scripts/hooks/git-pre-commit.sh)

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER' --scope-path scripts/hooks/."

    [ "$status" -eq 0 ]
    run cat "$TEST_ROOT/.git/hooks/pre-commit"
    [[ "$output" == *"STAGED_VIA_TRAILING_DOT"* ]]
}

@test "GA-222 followup: a similarly-prefixed scope path is not treated as in-scope" {
    # "scripts/hook" (no trailing s) must not match "scripts/hooks/..." — the
    # boundary must require an actual "/" separator, not just a string prefix.
    commit_hook_source "echo COMMITTED_V1"
    printf '#!/usr/bin/env bash\necho SHOULD_NOT_BE_USED\n' > "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    (cd "$TEST_ROOT" && git add scripts/hooks/git-pre-commit.sh)

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER' --scope-path scripts/hook"

    [ "$status" -eq 0 ]
    run cat "$TEST_ROOT/.git/hooks/pre-commit"
    [[ "$output" == *"COMMITTED_V1"* ]]
    [[ "$output" != *"SHOULD_NOT_BE_USED"* ]]
}

@test "fails closed when tracked source vanishes from HEAD while scripts/hooks/ convention is in use" {
    commit_hook_source "echo v1"
    # Simulate the source file disappearing from HEAD while scripts/hooks/
    # itself (and thus the convention) remains tracked.
    (
        cd "$TEST_ROOT"
        git rm -q scripts/hooks/git-pre-commit.sh
        mkdir -p scripts/hooks
        printf 'placeholder\n' > scripts/hooks/keepdir.txt
        git add scripts/hooks/keepdir.txt
        git commit -qm "remove hook source, keep dir tracked"
    )
    printf '#!/usr/bin/env bash\necho ORIGINAL_INSTALLED\n' > "$TEST_ROOT/.git/hooks/pre-commit"
    chmod +x "$TEST_ROOT/.git/hooks/pre-commit"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK(GA-222)"* ]]
    run cat "$TEST_ROOT/.git/hooks/pre-commit"
    [[ "$output" == *"ORIGINAL_INSTALLED"* ]]
}

@test "fails closed and leaves installed hook byte-unchanged when the hooks dir cannot be written to" {
    commit_hook_source "echo NEW_VERSION"
    printf '#!/usr/bin/env bash\necho ORIGINAL_INSTALLED\n' > "$TEST_ROOT/.git/hooks/pre-commit"
    chmod +x "$TEST_ROOT/.git/hooks/pre-commit"
    original_sum="$(cksum "$TEST_ROOT/.git/hooks/pre-commit")"
    chmod 555 "$TEST_ROOT/.git/hooks"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    chmod 755 "$TEST_ROOT/.git/hooks"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK(GA-222)"* ]]
    new_sum="$(cksum "$TEST_ROOT/.git/hooks/pre-commit")"
    [ "$original_sum" = "$new_sum" ]
}

@test "GA-222 AC4: stale and new linked worktrees keep isolated hooks in either sync order" {
    commit_hook_source "echo STALE_MAIN_HOOK"
    printf '#!/usr/bin/env bash\necho STALE_MAIN_HOOK\n' > "$TEST_ROOT/.githooks/pre-push"
    (cd "$TEST_ROOT" && git add .githooks/pre-push && git commit -qm stale-main-hook)
    WORKTREE="$(mktemp -d "$BATS_TMPDIR/sync_git_hooks_wt.XXXXXX")"
    rmdir "$WORKTREE"
    current_branch="$(cd "$TEST_ROOT" && git rev-parse --abbrev-ref HEAD)"
    (
        cd "$TEST_ROOT"
        git worktree add -q -b sync-git-hooks-wt-branch "$WORKTREE" "$current_branch"
    )
    # scripts/lib/scope_path.sh was copied into TEST_ROOT's working tree but
    # never committed, so `git worktree add` (which checks out a commit) does
    # not carry it over. Mirror the same uncommitted-fixture copy here.
    mkdir -p "$WORKTREE/scripts/lib"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/scope_path.sh" "$WORKTREE/scripts/lib/scope_path.sh"

    # Advance only the linked branch. Main remains intentionally stale.
    printf '#!/usr/bin/env bash\necho NEW_LINKED_HOOK\n' > "$WORKTREE/.githooks/pre-push"
    (cd "$WORKTREE" && git add .githooks/pre-push && git commit -qm new-linked-hook)

    main_hook="$TEST_ROOT/.git/hooks/pre-push"
    linked_git_dir="$(git -C "$WORKTREE" rev-parse --absolute-git-dir)"
    linked_hook="$linked_git_dir/hooks/pre-push"

    # New then stale: syncing main must not downgrade the linked runtime hook.
    run bash -c "cd '$WORKTREE' && bash '$HELPER'"
    [ "$status" -eq 0 ]
    grep -q NEW_LINKED_HOOK "$linked_hook"
    linked_before="$(sha256sum "$linked_hook" | awk '{print $1}')"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"
    [ "$status" -eq 0 ]
    grep -q STALE_MAIN_HOOK "$main_hook"
    grep -q NEW_LINKED_HOOK "$linked_hook"
    [ "$linked_before" = "$(sha256sum "$linked_hook" | awk '{print $1}')" ]

    # Stale then new: syncing linked must not upgrade/change main either.
    main_before="$(sha256sum "$main_hook" | awk '{print $1}')"
    run bash -c "cd '$WORKTREE' && bash '$HELPER'"
    [ "$status" -eq 0 ]
    grep -q NEW_LINKED_HOOK "$linked_hook"
    grep -q STALE_MAIN_HOOK "$main_hook"
    [ "$main_before" = "$(sha256sum "$main_hook" | awk '{print $1}')" ]

    [ "$(git -C "$TEST_ROOT" config --worktree core.hooksPath)" = "$TEST_ROOT/.git/hooks" ]
    [ "$(git -C "$WORKTREE" config --worktree core.hooksPath)" = "$linked_git_dir/hooks" ]

    (cd "$TEST_ROOT" && git worktree remove --force "$WORKTREE" 2>/dev/null || true)
}
