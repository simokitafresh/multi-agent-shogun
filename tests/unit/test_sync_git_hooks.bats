#!/usr/bin/env bats
# test_sync_git_hooks.bats - unit tests for scripts/sync_git_hooks.sh (GA-222)
#
# GA-222: .git/hooks/pre-commit is a direct (non-symlink) copy of the tracked
# scripts/hooks/git-pre-commit.sh and never gets re-synced when the tracked
# source changes. This left a real production hook 21 days / 3 commits stale
# (2026-06-20 install vs 2026-07-07 GA-190 auto-fix + 2026-07-09 GA-205 fix),
# causing a real BLOCK on 2026-07-11 that should have silently auto-fixed.

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/sync_git_hooks.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts/hooks" "$TEST_ROOT/.git/hooks"

    HELPER="$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh"

    (
        cd "$TEST_ROOT"
        git init -q
        git config user.email test@example.com
        git config user.name "Test User"
    )
}

teardown() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

@test "installs pre-commit hook when missing" {
    printf '#!/usr/bin/env bash\necho v1\n' > "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    chmod +x "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    [[ "$output" == *"SYNCED"* ]]
    [ -x "$TEST_ROOT/.git/hooks/pre-commit" ]
    cmp -s "$TEST_ROOT/scripts/hooks/git-pre-commit.sh" "$TEST_ROOT/.git/hooks/pre-commit"
}

@test "overwrites stale installed hook to match current source (regression proof for GA-222)" {
    printf '#!/usr/bin/env bash\necho OLD_STALE_VERSION\n' > "$TEST_ROOT/.git/hooks/pre-commit"
    chmod +x "$TEST_ROOT/.git/hooks/pre-commit"

    printf '#!/usr/bin/env bash\necho NEW_FIXED_VERSION\n' > "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    chmod +x "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    [[ "$output" == *"SYNCED"* ]]
    run cat "$TEST_ROOT/.git/hooks/pre-commit"
    [[ "$output" == *"NEW_FIXED_VERSION"* ]]
    [[ "$output" != *"OLD_STALE_VERSION"* ]]
}

@test "is idempotent and a no-op when already in sync" {
    printf '#!/usr/bin/env bash\necho v1\n' > "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    chmod +x "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    cp "$TEST_ROOT/scripts/hooks/git-pre-commit.sh" "$TEST_ROOT/.git/hooks/pre-commit"
    chmod +x "$TEST_ROOT/.git/hooks/pre-commit"

    before_mtime="$(stat -c '%Y' "$TEST_ROOT/.git/hooks/pre-commit")"
    sleep 1

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    [[ "$output" != *"SYNCED"* ]]
    after_mtime="$(stat -c '%Y' "$TEST_ROOT/.git/hooks/pre-commit")"
    [ "$before_mtime" = "$after_mtime" ]
}

@test "no-ops safely when this repo does not track scripts/hooks/git-pre-commit.sh" {
    printf '#!/usr/bin/env bash\necho unrelated-preexisting-hook\n' > "$TEST_ROOT/.git/hooks/pre-commit"
    chmod +x "$TEST_ROOT/.git/hooks/pre-commit"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    run cat "$TEST_ROOT/.git/hooks/pre-commit"
    [[ "$output" == *"unrelated-preexisting-hook"* ]]
}

@test "does not touch unrelated hook files (fail-closed scope isolation)" {
    printf '#!/usr/bin/env bash\necho v1\n' > "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    chmod +x "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    printf '#!/usr/bin/env bash\necho pre-push-untouched\n' > "$TEST_ROOT/.git/hooks/pre-push"
    chmod +x "$TEST_ROOT/.git/hooks/pre-push"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    [ "$status" -eq 0 ]
    run cat "$TEST_ROOT/.git/hooks/pre-push"
    [[ "$output" == *"pre-push-untouched"* ]]
}

@test "fails closed and leaves installed hook untouched when source cannot be read" {
    printf '#!/usr/bin/env bash\necho v1\n' > "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    chmod +x "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    printf '#!/usr/bin/env bash\necho ORIGINAL_INSTALLED\n' > "$TEST_ROOT/.git/hooks/pre-commit"
    chmod +x "$TEST_ROOT/.git/hooks/pre-commit"
    chmod 000 "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$TEST_ROOT' && bash '$HELPER'"

    chmod 755 "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK(GA-222)"* ]]
    run cat "$TEST_ROOT/.git/hooks/pre-commit"
    [[ "$output" == *"ORIGINAL_INSTALLED"* ]]
}
