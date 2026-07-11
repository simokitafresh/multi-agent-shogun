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
    # ninja_scope_commit.sh unconditionally sources scripts/lib/scope_path.sh
    # (SSOT for scope path normalization); every sandbox repo needs a copy.
    mkdir -p "$REPO/scripts/lib"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/scope_path.sh" "$REPO/scripts/lib/scope_path.sh"
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

make_shared_fixture() {
    : > "$REPO/shared.txt"
    for i in $(seq 1 36); do printf 'base-%02d\n' "$i" >> "$REPO/shared.txt"; done
    git -C "$REPO" add shared.txt
    git -C "$REPO" commit -qm shared-base
}

make_own_patch() {
    cp "$REPO/shared.txt" "$REPO/shared.working"
    for i in 2 9 16 23 30; do sed -i "${i}s/$/-own/" "$REPO/shared.txt"; done
    git -C "$REPO" diff -- shared.txt > "$REPO/own.patch"
    mv "$REPO/shared.working" "$REPO/shared.txt"
}

@test "patch modeは同一fileの自分5 hunkだけcommitし他者13 hunkと共有indexを完全保全する" {
    make_shared_fixture
    make_own_patch
    for i in 1 4 7 10 13 18 21 24 27 31 33 35 36; do sed -i "${i}s/$/-other/" "$REPO/shared.txt"; done
    printf 'other staged\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    other_index_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    worktree_before="$(cat "$REPO/shared.txt")"
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m own-five --patch '$REPO/own.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" show --format= --numstat HEAD -- shared.txt | awk '{print $1+$2}')" -eq 10 ]
    [ "$(git -C "$REPO" show HEAD:shared.txt | grep -c -- '-own')" -eq 5 ]
    [ "$(cat "$REPO/shared.txt")" = "$worktree_before" ]
    [ "$(grep -c -- '-other' "$REPO/shared.txt")" -eq 13 ]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$other_index_before" ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = other.txt ]
}

@test "patch modeはbase blob不一致をcommit前にBLOCKする" {
    make_shared_fixture; make_own_patch
    run bash -c "cd '$REPO' && bash '$HELPER' -m stale --patch '$REPO/own.patch' --base-blob 0000000000000000000000000000000000000000 -- shared.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"base blob mismatch"* ]]
}

@test "patch modeはscope外path混入をcommit前にBLOCKする" {
    make_shared_fixture; make_own_patch
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" diff -- shared.txt other.txt > "$REPO/mixed.patch"
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    run bash -c "cd '$REPO' && bash '$HELPER' -m mixed --patch '$REPO/mixed.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"out-of-scope path"* ]]
}

@test "patch modeは空patchと適用不能patchをcommit前にBLOCKする" {
    make_shared_fixture
    : > "$REPO/empty.patch"
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    run bash -c "cd '$REPO' && bash '$HELPER' -m empty-patch --patch '$REPO/empty.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"missing or empty"* ]]

    printf '%s\n' 'diff --git a/shared.txt b/shared.txt' '--- a/shared.txt' '+++ b/shared.txt' '@@ -1 +1 @@' '-not-the-base' '+changed' > "$REPO/bad.patch"
    run bash -c "cd '$REPO' && bash '$HELPER' -m bad-patch --patch '$REPO/bad.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"does not apply cleanly"* ]]
}

@test "patch modeは削除・新規file・改行境界のpatchを扱う" {
    make_shared_fixture
    printf 'tail-no-newline' >> "$REPO/shared.txt"
    git -C "$REPO" add shared.txt && git -C "$REPO" commit -qm newline-base
    printf '\nchanged-tail\n' >> "$REPO/shared.txt"
    git -C "$REPO" diff -- shared.txt > "$REPO/newline.patch"
    git -C "$REPO" checkout -q -- shared.txt
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    run bash -c "cd '$REPO' && bash '$HELPER' -m newline --patch '$REPO/newline.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 0 ]

    printf 'new file\n' > "$REPO/new.txt"
    git -C "$REPO" diff --no-index /dev/null new.txt > "$REPO/new.patch" || true
    run bash -c "cd '$REPO' && bash '$HELPER' -m new --patch '$REPO/new.patch' --base-blob 0000000000000000000000000000000000000000 -- new.txt"
    [ "$status" -eq 0 ]

    # patch modeはworking treeを意図的に不変に保つ。次の独立edge fixture前に
    # sandbox内だけHEADへ同期する（本番helperは他者差分へ触れない）。
    git -C "$REPO" checkout -q -- shared.txt
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    git -C "$REPO" rm -q shared.txt
    git -C "$REPO" diff --cached -- shared.txt > "$REPO/delete.patch"
    git -C "$REPO" reset -q HEAD -- shared.txt
    git -C "$REPO" checkout -q -- shared.txt
    run bash -c "cd '$REPO' && bash '$HELPER' -m delete --patch '$REPO/delete.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 0 ]
    ! git -C "$REPO" cat-file -e HEAD:shared.txt
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

@test "GA-222 final edge RC: root scope '.' はBLOCKされindex/working treeが不変のまま" {
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    other_index_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    other_worktree_before="$(cat "$REPO/other.txt")"
    printf 'own change\n' >> "$REPO/own.txt"
    own_worktree_before="$(cat "$REPO/own.txt")"
    head_before="$(git -C "$REPO" rev-parse HEAD)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m root-scope -- ."

    [ "$status" -eq 2 ]
    [[ "$output" == *"repository root"* ]]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$other_index_before" ]
    [ "$(cat "$REPO/other.txt")" = "$other_worktree_before" ]
    [ "$(cat "$REPO/own.txt")" = "$own_worktree_before" ]
    [ "$(git -C "$REPO" status --porcelain -- own.txt)" = " M own.txt" ]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
}

@test "GA-222 4回目RC: root scope別名'subdir/..'はBLOCKされindex/working treeが不変のまま" {
    mkdir -p "$REPO/subdir"
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    other_index_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    printf 'own change\n' >> "$REPO/own.txt"
    own_worktree_before="$(cat "$REPO/own.txt")"
    head_before="$(git -C "$REPO" rev-parse HEAD)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m subdir-dotdot -- subdir/.."

    [ "$status" -eq 2 ]
    [[ "$output" == *"'..'"* ]]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$other_index_before" ]
    [ "$(cat "$REPO/own.txt")" = "$own_worktree_before" ]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
}

@test "GA-222 4回目RC: 単独'..'はBLOCKされindex/working treeが不変のまま" {
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    other_index_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    printf 'own change\n' >> "$REPO/own.txt"
    own_worktree_before="$(cat "$REPO/own.txt")"
    head_before="$(git -C "$REPO" rev-parse HEAD)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m bare-dotdot -- .."

    [ "$status" -eq 2 ]
    [[ "$output" == *"'..'"* ]]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$other_index_before" ]
    [ "$(cat "$REPO/own.txt")" = "$own_worktree_before" ]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
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

@test "GA-222 final edge RC: 'scripts/hooks/.' (trailing /.) scope path installs the newly staged content" {
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

    # "scripts/hooks/." is pathspec-equivalent to "scripts/hooks" for git add,
    # but is a distinct string — is_in_scope must normalize before comparing.
    printf '#!/usr/bin/env bash\nprintf NEW_VERSION_VIA_TRAILING_DOT > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$REPO' && bash '$HELPER' -m update-hook-source-trailing-dot -- scripts/hooks/."
    [ "$status" -eq 0 ]
    run cat "$REPO/.git/hooks/pre-commit"
    [[ "$output" == *"NEW_VERSION_VIA_TRAILING_DOT"* ]]
}

@test "GA-222 4回目RC: 'scripts//hooks' (double slash) scope path installs the newly staged content" {
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

    # "scripts//hooks" is pathspec-equivalent to "scripts/hooks" for git add.
    printf '#!/usr/bin/env bash\nprintf NEW_VERSION_VIA_DOUBLE_SLASH > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$REPO' && bash '$HELPER' -m update-hook-source-double-slash -- scripts//hooks"
    [ "$status" -eq 0 ]
    run cat "$REPO/.git/hooks/pre-commit"
    [[ "$output" == *"NEW_VERSION_VIA_DOUBLE_SLASH"* ]]
}
