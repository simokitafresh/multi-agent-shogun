#!/usr/bin/env bats

setup() {
    REPO="$(mktemp -d "$BATS_TMPDIR/ninja_scope_commit_concurrency.XXXXXX")"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email test@example.com
    git -C "$REPO" config user.name test
    printf 'base-a\n' > "$REPO/a.txt"
    printf 'base-b\n' > "$REPO/b.txt"
    git -C "$REPO" add a.txt b.txt
    git -C "$REPO" commit -qm initial
    HELPER="$BATS_TEST_DIRNAME/../../scripts/ninja_scope_commit.sh"
}

teardown() {
    rm -rf "$REPO"
}

@test "two concurrent scoped commits converge HEAD index and worktree with terminal evidence" {
    printf 'worker-a\n' >> "$REPO/a.txt"
    printf 'worker-b\n' >> "$REPO/b.txt"
    git -C "$REPO" add a.txt b.txt
    before_count="$(git -C "$REPO" status --short -- a.txt b.txt | wc -l)"
    [ "$before_count" -ge 1 ]

    (cd "$REPO" && bash "$HELPER" -m worker-a -- a.txt) >"$REPO/a.stdout" 2>"$REPO/a.stderr" &
    pid_a=$!
    (cd "$REPO" && bash "$HELPER" -m worker-b -- b.txt) >"$REPO/b.stdout" 2>"$REPO/b.stderr" &
    pid_b=$!
    wait "$pid_a"
    wait "$pid_b"

    for worker in a b; do
        hash="$(cat "$REPO/$worker.stdout")"
        [[ "$hash" =~ ^[0-9a-f]{40}$ ]]
        [ "$(wc -l < "$REPO/$worker.stdout")" -eq 1 ]
        git -C "$REPO" cat-file -e "${hash}^{commit}"
        grep -Eq "^event=completed lock_wait_ms=[0-9]+ acquired_at=[0-9]+ finished_at=[0-9]+ commit_hash=$hash$" "$REPO/$worker.stderr"
        [ "$(grep -c '^event=completed ' "$REPO/$worker.stderr")" -eq 1 ]
    done
    [ "$(git -C "$REPO" status --short -- a.txt b.txt)" = "" ]
    for path in a.txt b.txt; do
        head_blob="$(git -C "$REPO" rev-parse "HEAD:$path")"
        index_blob="$(git -C "$REPO" ls-files -s -- "$path" | awk '{print $2}')"
        worktree_blob="$(git -C "$REPO" hash-object "$REPO/$path")"
        [ "$head_blob" = "$index_blob" ]
        [ "$index_blob" = "$worktree_blob" ]
    done
}

@test "stale private cleanup preserves shared index and success object" {
    printf 'foreign-stage\n' >> "$REPO/b.txt"
    git -C "$REPO" add b.txt
    shared_before="$(git -C "$REPO" ls-files -s -- b.txt)"
    printf 'owned\n' >> "$REPO/a.txt"

    run bash -c 'cd "$1" && bash "$2" -m owned -- a.txt 2>terminal.err' _ "$REPO" "$HELPER"
    [ "$status" -eq 0 ]
    hash="$output"
    [[ "$hash" =~ ^[0-9a-f]{40}$ ]]
    git -C "$REPO" cat-file -e "${hash}^{commit}"
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$hash" ]
    [ "$(git -C "$REPO" ls-files -s -- b.txt)" = "$shared_before" ]
    [ "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'ninja-scope-index.*' -type f -newer "$REPO/terminal.err" 2>/dev/null | wc -l)" -eq 0 ]
}

@test "failure never publishes completed event" {
    mkdir -p "$REPO/.git/hooks"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$REPO/.git/hooks/pre-commit"
    chmod +x "$REPO/.git/hooks/pre-commit"
    printf 'blocked\n' >> "$REPO/a.txt"

    run bash -c 'cd "$1" && bash "$2" -m blocked -- a.txt 2>&1' _ "$REPO" "$HELPER"
    [ "$status" -ne 0 ]
    [[ "$output" != *"event=completed"* ]]
}

@test "repair-index converges residual MM without changing unrelated shared index" {
    printf 'staged-old-a\n' > "$REPO/a.txt"
    printf 'foreign-b\n' >> "$REPO/b.txt"
    git -C "$REPO" add a.txt b.txt
    foreign_before="$(git -C "$REPO" ls-files -s -- b.txt)"
    git -C "$REPO" show HEAD:a.txt > "$REPO/a.txt"
    [ "$(git -C "$REPO" status --short -- a.txt)" = 'MM a.txt' ]
    git -C "$REPO" diff HEAD --quiet -- a.txt

    run bash -c 'cd "$1" && bash "$2" --repair-index -- a.txt 2>repair.err' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f]{40}$ ]]
    [ "$(git -C "$REPO" status --short -- a.txt)" = "" ]
    [ "$(git -C "$REPO" ls-files -s -- b.txt)" = "$foreign_before" ]
    grep -Eq "^event=completed .*commit_hash=$output$" "$REPO/repair.err"
}

@test "repair-index blocks when worktree differs from HEAD" {
    printf 'real-worktree-change\n' >> "$REPO/a.txt"

    run bash -c 'cd "$1" && bash "$2" --repair-index -- a.txt 2>&1' _ "$REPO" "$HELPER"

    [ "$status" -ne 0 ]
    [[ "$output" == *"repair would hide worktree content differing from HEAD"* ]]
    [[ "$output" != *"event=completed"* ]]
}
