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
