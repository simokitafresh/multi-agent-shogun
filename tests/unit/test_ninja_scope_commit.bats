#!/usr/bin/env bats

setup() {
    REPO="$(mktemp -d "$BATS_TMPDIR/ninja_scope_commit.XXXXXX")"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email test@example.com
    git -C "$REPO" config user.name test
    printf 'base\n' > "$REPO/own.txt"
    printf 'base\n' > "$REPO/other.txt"
    git -C "$REPO" add own.txt other.txt
    git -C "$REPO" commit -qm initial
    HELPER="$BATS_TEST_DIRNAME/../../scripts/ninja_scope_commit.sh"
}

teardown() {
    rm -rf "$REPO"
}

@test "修正前: 通常commitは事前stage済み他者fileも含め2件commitする" {
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    printf 'own change\n' >> "$REPO/own.txt"
    git -C "$REPO" add own.txt

    git -C "$REPO" commit -qm unsafe

    run git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]
}

@test "helperは対象1件だけcommitし他者stage1件を保持する" {
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    other_index_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m safe -- own.txt"
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = own.txt ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = other.txt ]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$other_index_before" ]
}

@test "空scopeはBLOCKする" {
    run bash -c "cd '$REPO' && bash '$HELPER' -m empty --"
    [ "$status" -eq 2 ]
    [[ "$output" == *"commit scope is empty"* ]]
}

@test "存在しないpathはBLOCKする" {
    run bash -c "cd '$REPO' && bash '$HELPER' -m missing -- absent.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"scope path does not exist"* ]]
}

@test "pre-commit hookを実行する" {
    mkdir -p "$REPO/.git/hooks"
    printf '#!/usr/bin/env bash\nprintf hook-ran > .git/hook-marker\n' > "$REPO/.git/hooks/pre-commit"
    chmod +x "$REPO/.git/hooks/pre-commit"
    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m hooked -- own.txt"
    [ "$status" -eq 0 ]
    [ "$(cat "$REPO/.git/hook-marker")" = hook-ran ]
}

@test "GA-222: 正本が無いrepoではsync_git_hooks呼び出しが無害にno-opする" {
    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m no-sync-source -- own.txt"
    [ "$status" -eq 0 ]
}

@test "GA-222: commit前にstale/未配備の.git/hooks/pre-commitを正本と同期する" {
    SYNC_SCRIPT="$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh"
    mkdir -p "$REPO/scripts" "$REPO/scripts/hooks" "$REPO/.git/hooks"
    cp "$SYNC_SCRIPT" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"

    printf '#!/usr/bin/env bash\nprintf hook-ran-fixed > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    printf '#!/usr/bin/env bash\nprintf hook-ran-stale > .git/hook-marker\n' \
        > "$REPO/.git/hooks/pre-commit"
    chmod +x "$REPO/.git/hooks/pre-commit"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m sync-then-commit -- own.txt"
    [ "$status" -eq 0 ]
    cmp -s "$REPO/scripts/hooks/git-pre-commit.sh" "$REPO/.git/hooks/pre-commit"
    [ "$(cat "$REPO/.git/hook-marker")" = hook-ran-fixed ]
}

@test "GA-222 REQUEST_CHANGES: another agent's uncommitted hook-source edit does not leak in via an unrelated ninja commit" {
    mkdir -p "$REPO/scripts/hooks"
    cp "$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"
    printf '#!/usr/bin/env bash\nprintf hook-ran-committed > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    # Another agent is mid-edit: unstaged, uncommitted change to the hook
    # source, unrelated to this ninja's own.txt-only commit scope.
    printf '#!/usr/bin/env bash\nprintf OTHER_AGENT_WIP > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m unrelated-commit -- own.txt"
    [ "$status" -eq 0 ]
    run cat "$REPO/.git/hooks/pre-commit"
    [[ "$output" == *"hook-ran-committed"* ]]
    [[ "$output" != *"OTHER_AGENT_WIP"* ]]
}

@test "GA-222 REQUEST_CHANGES: committing the hook source itself installs the newly staged content" {
    mkdir -p "$REPO/scripts/hooks"
    cp "$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"
    printf '#!/usr/bin/env bash\nprintf OLD_VERSION > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    # This ninja's own commit scope IS the hook source itself.
    printf '#!/usr/bin/env bash\nprintf NEW_VERSION > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$REPO' && bash '$HELPER' -m update-hook-source -- scripts/hooks/git-pre-commit.sh"
    [ "$status" -eq 0 ]
    run cat "$REPO/.git/hooks/pre-commit"
    [[ "$output" == *"NEW_VERSION"* ]]
}

@test "GA-222 followup: committing a directory scope that contains the hook source installs the newly staged content" {
    mkdir -p "$REPO/scripts/hooks"
    cp "$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"
    printf '#!/usr/bin/env bash\nprintf OLD_VERSION > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    # This ninja commits the whole scripts/hooks directory (not the exact
    # file path). git add stages git-pre-commit.sh recursively, and the
    # committed tree includes the new content — the live hook must match
    # that same new content immediately after commit, not the stale HEAD
    # value from before this commit (which would otherwise cause an
    # immediate re-drift right after the commit completes).
    printf '#!/usr/bin/env bash\nprintf NEW_VERSION_VIA_DIR_SCOPE > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$REPO' && bash '$HELPER' -m update-hook-source-dir-scope -- scripts/hooks"
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" show HEAD:scripts/hooks/git-pre-commit.sh)" = "$(cat "$REPO/scripts/hooks/git-pre-commit.sh")" ]
    run cat "$REPO/.git/hooks/pre-commit"
    [[ "$output" == *"NEW_VERSION_VIA_DIR_SCOPE"* ]]
}
