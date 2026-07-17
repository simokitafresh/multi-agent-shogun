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
        grep -Eq "^event=completed lock_wait_ms=[0-9]+ acquired_at=[0-9]+ finished_at=[0-9]+ commit_hash=$hash .*phase_read_tree_ms=" "$REPO/$worker.stderr"
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
    [[ "$output" == *"event=failed"* ]]
    [[ "$output" == *"last_phase=git_commit"* ]]
}

@test "slow pre-commitはgit_commit phaseだけに局所化される" {
    mkdir -p "$REPO/.git/hooks"
    printf '#!/usr/bin/env bash\nsleep 0.7\n' > "$REPO/.git/hooks/pre-commit"
    chmod +x "$REPO/.git/hooks/pre-commit"
    printf 'slow hook\n' >> "$REPO/a.txt"

    run bash -c 'cd "$1" && bash "$2" -m slow-hook -- a.txt 2>&1' _ "$REPO" "$HELPER"
    [ "$status" -eq 0 ]
    event="$(printf '%s\n' "$output" | grep '^event=completed ')"
    EVENT="$event" python3 - <<'PY'
import os, re
fields = dict(re.findall(r"([a-z0-9_]+)=([^ ]+)", os.environ["EVENT"]))
git_commit_ms = int(fields["phase_git_commit_ms"])
assert git_commit_ms >= 600
assert abs(int(fields["phase_unattributed_ms"])) <= 200
assert int(fields["telemetry_overhead_ms"]) <= 50
for phase in ("read_tree", "add", "scope_sync", "guard", "advance_shared_index", "post_check"):
    assert int(fields[f"phase_{phase}_ms"]) < git_commit_ms, (phase, fields[f"phase_{phase}_ms"])
PY
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
    grep -Eq "^event=completed .*commit_hash=$output .*phase_post_check_ms=" "$REPO/repair.err"
}

@test "repair-index blocks when worktree differs from HEAD" {
    printf 'real-worktree-change\n' >> "$REPO/a.txt"

    run bash -c 'cd "$1" && bash "$2" --repair-index -- a.txt 2>&1' _ "$REPO" "$HELPER"

    [ "$status" -ne 0 ]
    [[ "$output" == *"repair would hide worktree content differing from HEAD"* ]]
    [[ "$output" != *"event=completed"* ]]
}

@test "6 parallel identical invocations single-flight to one commit and six terminal receipts" {
    printf 'single-flight\n' >> "$REPO/a.txt"
    mkdir -p "$REPO/.git/hooks"
    printf '#!/usr/bin/env bash\nsleep 0.5\n' > "$REPO/.git/hooks/pre-commit"
    chmod +x "$REPO/.git/hooks/pre-commit"
    initial_count="$(git -C "$REPO" rev-list --count HEAD)"

    pids=()
    for worker in 1 2 3 4 5 6; do
        (
            cd "$REPO"
            NINJA_SCOPE_COMMIT_RUN_ID=fixture-run-1 bash "$HELPER" -m same-invocation -- a.txt
        ) >"$REPO/sf-$worker.out" 2>"$REPO/sf-$worker.err" &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do
        wait "$pid"
        ! kill -0 "$pid" 2>/dev/null
    done

    [ "$(( $(git -C "$REPO" rev-list --count HEAD) - initial_count ))" -eq 1 ]
    [ "$(git -C "$REPO" log --format=%s --grep='^same-invocation$' | wc -l)" -eq 1 ]
    for worker in 1 2 3 4 5 6; do
        [[ "$(cat "$REPO/sf-$worker.out")" =~ ^[0-9a-f]{40}$ ]]
        [ "$(grep -c '^event=terminal_receipt ' "$REPO/sf-$worker.err")" -eq 1 ]
    done
    [ "$(grep -h '^event=terminal_receipt role=owner ' "$REPO"/sf-*.err | wc -l)" -eq 1 ]
    [ "$(grep -h '^event=terminal_receipt role=follower ' "$REPO"/sf-*.err | wc -l)" -eq 5 ]
    [ -z "$(git -C "$REPO" status --porcelain -- a.txt)" ]
}

@test "different run or path is not falsely deduplicated" {
    printf 'run-a\n' >> "$REPO/a.txt"
    printf 'run-b\n' >> "$REPO/b.txt"

    run bash -c 'cd "$1" && NINJA_SCOPE_COMMIT_RUN_ID=task-a bash "$2" -m shared-message -- a.txt' _ "$REPO" "$HELPER"
    [ "$status" -eq 0 ]
    hash_a="$output"
    run bash -c 'cd "$1" && NINJA_SCOPE_COMMIT_RUN_ID=task-b bash "$2" -m shared-message -- b.txt' _ "$REPO" "$HELPER"
    [ "$status" -eq 0 ]
    hash_b="$output"

    [ "$hash_a" != "$hash_b" ]
    [ "$(git -C "$REPO" log --format=%s --grep='^shared-message$' | wc -l)" -eq 2 ]
}
