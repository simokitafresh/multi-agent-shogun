#!/usr/bin/env bats
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

commit_hook_source() {
    local content="$1"
    mkdir -p "$TEST_ROOT/scripts/hooks"
    printf '%s\n' "$content" > "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    (
        cd "$TEST_ROOT"
        git add scripts/hooks/git-pre-commit.sh
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

@test "no-ops safely when this repo does not use the scripts/hooks/ convention" {
    # No scripts/hooks/ directory tracked at all in HEAD.
    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/.git/hooks/pre-commit" ]
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

@test "does not touch unrelated hook files" {
    commit_hook_source "echo v1"
    printf '#!/usr/bin/env bash\necho pre-push-untouched\n' > "$TEST_ROOT/.git/hooks/pre-push"
    chmod +x "$TEST_ROOT/.git/hooks/pre-push"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    run cat "$TEST_ROOT/.git/hooks/pre-push"
    [[ "$output" == *"pre-push-untouched"* ]]
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

@test "GA-222 AC4: resolves and syncs the shared hooks path correctly from a linked git worktree" {
    commit_hook_source "echo FROM_MAIN_WORKTREE"
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

    run bash -c "cd '$WORKTREE' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    [[ "$output" == *"SYNCED"* ]]
    # Hooks are shared across worktrees in the common .git dir, not per-worktree.
    run cat "$TEST_ROOT/.git/hooks/pre-commit"
    [[ "$output" == *"FROM_MAIN_WORKTREE"* ]]

    (cd "$TEST_ROOT" && git worktree remove --force "$WORKTREE" 2>/dev/null || true)
}
