#!/usr/bin/env bats
# test_necessity: U1b wrapperのroot境界、単一flock、同期失敗fail-closed、
# Published-By trailer、成功時origin同期を二値で固定する(§9.1 U1b)。

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
    BASE_ROOT="$BATS_TEST_TMPDIR/publish_direct_base"
    REMOTE="$BATS_TEST_TMPDIR/publish_direct_remote.git"
    ROOT="$BATS_TEST_TMPDIR/publish_direct_root"
    STATE_DIR="$(mktemp -d --tmpdir="$HOME" publish_direct_state.XXXXXX)"
    export SHOGUN_STATE_DIR="$STATE_DIR"

    mkdir -p "$BASE_ROOT/scripts/lib"
    cp "$PROJECT_ROOT/scripts/publish_direct_commit.sh" "$BASE_ROOT/scripts/"
    cp "$PROJECT_ROOT/scripts/publisher_queue.sh" "$BASE_ROOT/scripts/"
    cp "$PROJECT_ROOT/scripts/ninja_scope_commit.sh" "$BASE_ROOT/scripts/"
    cp "$PROJECT_ROOT/scripts/publisher_c2a_merge.sh" "$BASE_ROOT/scripts/"
    cp "$PROJECT_ROOT/scripts/lib/defense_overhead_writer.sh" "$BASE_ROOT/scripts/lib/"
    cp "$PROJECT_ROOT/scripts/lib/lock_run_shim.sh" "$BASE_ROOT/scripts/lib/"
    cp "$PROJECT_ROOT/scripts/lib/publisher_event.sh" "$BASE_ROOT/scripts/lib/"
    cp "$PROJECT_ROOT/scripts/lib/scope_path.sh" "$BASE_ROOT/scripts/lib/"
    cp "$PROJECT_ROOT/scripts/lib/lock_path.sh" "$BASE_ROOT/scripts/lib/"
    chmod +x "$BASE_ROOT/scripts/"*.sh "$BASE_ROOT/scripts/lib/"*.sh
    printf 'base\n' > "$BASE_ROOT/payload.txt"
    git -C "$BASE_ROOT" init -q
    git -C "$BASE_ROOT" config user.email test@example.com
    git -C "$BASE_ROOT" config user.name test
    git -C "$BASE_ROOT" add -A
    git -C "$BASE_ROOT" commit -qm 'initial fixture'
    git -C "$BASE_ROOT" branch -M main

    git init --bare -q "$REMOTE"
    git clone -q "$BASE_ROOT" "$ROOT"
    git -C "$ROOT" remote remove origin
    git -C "$ROOT" remote add origin "$REMOTE"
    git -C "$ROOT" config user.email test@example.com
    git -C "$ROOT" config user.name test
    git -C "$ROOT" push -q -u origin main
    WRAPPER="$ROOT/scripts/publish_direct_commit.sh"
}

teardown() {
    if [[ -n "${STATE_DIR:-}" && -d "$STATE_DIR" ]]; then
        find "$STATE_DIR" -depth -delete 2>/dev/null || true
    fi
    for fixture in "$BATS_TEST_TMPDIR"/publish_direct_*; do
        [[ -e "$fixture" ]] || continue
        find "$fixture" -depth -delete 2>/dev/null || true
    done
    [[ -d "$REMOTE" ]] && find "$REMOTE" -depth -delete 2>/dev/null || true
}

@test "non-root cwd and linked worktree both return rc=7 without changing HEAD" {
    before="$(git -C "$ROOT" rev-parse HEAD)"
    mkdir "$ROOT/subdir"
    run bash -c 'cd "$1/subdir" && bash "$1/scripts/publish_direct_commit.sh" -m bad -- payload.txt' _ "$ROOT"
    [ "$status" -eq 7 ]
    [ "$(git -C "$ROOT" rev-parse HEAD)" = "$before" ]

    LINKED="$BATS_TEST_TMPDIR/publish_direct_linked"
    git -C "$ROOT" worktree add -q "$LINKED" -b linked-test
    run bash -c 'cd "$1" && bash "$1/scripts/publish_direct_commit.sh" -m bad -- payload.txt' _ "$LINKED"
    [ "$status" -eq 7 ]
    [ "$(git -C "$ROOT" rev-parse HEAD)" = "$before" ]
    git -C "$ROOT" worktree remove "$LINKED"
}

@test "six concurrent wrappers share one lock critical section" {
    COUNTER="$BATS_TEST_TMPDIR/counter"
    ACTIVE="$BATS_TEST_TMPDIR/active"
    MAX="$BATS_TEST_TMPDIR/max"
    printf '0\n' > "$COUNTER"
    printf '0\n' > "$ACTIVE"
    printf '0\n' > "$MAX"
    cat > "$ROOT/scripts/ninja_scope_commit.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exec 9>"$COUNTER.lock"
flock -x 9
active=$(( $(<"$ACTIVE") + 1 )); printf '%s\n' "$active" > "$ACTIVE"
max=$(<"$MAX"); (( active > max )) && printf '%s\n' "$active" > "$MAX"
printf '%s\n' "$(( $(<"$COUNTER") + 1 ))" > "$COUNTER"
sleep 0.2
printf '%s\n' "$(( $(<"$ACTIVE") - 1 ))" > "$ACTIVE"
flock -u 9
SH
    chmod +x "$ROOT/scripts/ninja_scope_commit.sh"
    export COUNTER ACTIVE MAX
    local i
    for i in 1 2 3 4 5 6; do
        printf 'owned-%s\n' "$i" > "$ROOT/owned_$i.txt"
        (cd "$ROOT" && bash "$WRAPPER" -m "parallel $i" -- "owned_$i.txt") &
    done
    wait
    [ "$(<"$COUNTER")" -eq 6 ]
    [ "$(<"$MAX")" -eq 1 ]
}

# test_necessity: a diverged shared root (local commit not on origin) must not
# block publication; the wrapper commits locally and the content reaches origin
# via the c2a 3-way merge, while the root's own divergence is left to the drain
# lane. Before 2026-09-05 this path returned rc=8 and forced commit batching.
@test "diverged root still publishes via c2a and creates the wrapper commit" {
    printf 'local\n' >> "$ROOT/payload.txt"
    git -C "$ROOT" add payload.txt
    git -C "$ROOT" commit -qm 'local divergence'
    ADVANCE="$BATS_TEST_TMPDIR/publish_direct_advance"
    git clone -q --branch main "$REMOTE" "$ADVANCE"
    git -C "$ADVANCE" config user.email test@example.com
    git -C "$ADVANCE" config user.name test
    printf 'remote\n' > "$ADVANCE/remote.txt"
    git -C "$ADVANCE" add remote.txt
    git -C "$ADVANCE" commit -qm 'remote advance'
    git -C "$ADVANCE" push -q origin main
    before="$(git -C "$ROOT" rev-parse HEAD)"
    printf 'unpublished\n' > "$ROOT/unpublished.txt"

    run bash -c 'cd "$1" && bash "$1/scripts/publish_direct_commit.sh" -m "diverged publish" -- unpublished.txt' _ "$ROOT"
    [ "$status" -eq 0 ]
    [ "$(git -C "$ROOT" rev-parse HEAD)" != "$before" ]
    git -C "$ROOT" log -5 --format=%s | grep -qx "diverged publish"
    # content is on origin even though root is still diverged
    git -C "$ROOT" fetch -q origin
    [ "$(git -C "$ROOT" show origin/main:unpublished.txt)" = "unpublished" ]
    [ "$(git -C "$ROOT" show origin/main:remote.txt)" = "remote" ]
}

# test_necessity: when the root carries a foreign local commit that conflicts
# with origin (so a c2a 3-way merge of the branch cannot apply), the wrapper
# must still publish its own single commit via an isolated cherry-pick, and
# --republish must publish an already-committed root sha the same way. Its
# second invocation must detect the already-applied patch by `git cherry`'s
# `-` patch-id match and return an explicit no-op success.
@test "foreign conflicting root commit does not block publish; cherry-pick and --republish reach origin" {
    # foreign commit on root edits payload.txt one way; origin edits it another way
    printf 'foreign
' > "$ROOT/payload.txt"
    git -C "$ROOT" add payload.txt
    git -C "$ROOT" commit -qm 'foreign unmerged commit'
    ADVANCE="$BATS_TEST_TMPDIR/publish_direct_advance"
    git clone -q --branch main "$REMOTE" "$ADVANCE"
    git -C "$ADVANCE" config user.email test@example.com
    git -C "$ADVANCE" config user.name test
    printf 'origin-side
' > "$ADVANCE/payload.txt"
    git -C "$ADVANCE" add payload.txt
    git -C "$ADVANCE" commit -qm 'origin conflicting advance'
    git -C "$ADVANCE" push -q origin main
    printf 'mine
' > "$ROOT/mine.txt"

    run bash -c 'cd "$1" && bash "$1/scripts/publish_direct_commit.sh" -m "mine via cherry-pick" -- mine.txt' _ "$ROOT"
    [ "$status" -eq 0 ]
    git -C "$ROOT" fetch -q origin
    [ "$(git -C "$ROOT" show origin/main:mine.txt)" = "mine" ]
    # the foreign commit's content must NOT have been dragged onto origin
    [ "$(git -C "$ROOT" show origin/main:payload.txt)" = "origin-side" ]
    git -C "$ROOT" log -3 --format=%s origin/main | grep -q "mine via cherry-pick"

    # --republish: an existing root commit that never reached origin
    printf 'second
' > "$ROOT/second.txt"
    git -C "$ROOT" add second.txt
    git -C "$ROOT" commit -qm 'second local only'
    sha="$(git -C "$ROOT" rev-parse HEAD)"
    run bash -c 'cd "$1" && bash "$1/scripts/publish_direct_commit.sh" --republish "$2"' _ "$ROOT" "$sha"
    [ "$status" -eq 0 ]
    git -C "$ROOT" fetch -q origin
    [ "$(git -C "$ROOT" show origin/main:second.txt)" = "second" ]
    # idempotent: second call is a no-op success
    run bash -c 'cd "$1" && bash "$1/scripts/publish_direct_commit.sh" --republish "$2"' _ "$ROOT" "$sha"
    [ "$status" -eq 0 ]
}

@test "successful wrapper commit has exactly one Published-By wrapper trailer" {
    printf 'changed\n' >> "$ROOT/payload.txt"
    started="$(date +%s)"
    run timeout 60 bash -c 'cd "$1" && bash "$1/scripts/publish_direct_commit.sh" -m "cmd_4452 wrapper" -- payload.txt' _ "$ROOT"
    elapsed=$(( $(date +%s) - started ))
    [ "$status" -eq 0 ]
    [ "$elapsed" -lt 60 ]
    [ "$(git -C "$ROOT" rev-parse HEAD)" = "$(git -C "$ROOT" rev-parse origin/main)" ]
    [ "$(git -C "$ROOT" log -1 --format='%(trailers:key=Published-By,valueonly)' | sed '/^$/d' | wc -l)" -eq 1 ]
    [ "$(git -C "$ROOT" log -1 --format='%(trailers:key=Published-By,valueonly)' | sed '/^$/d')" = wrapper ]
}

@test "successful wrapper leaves root synchronized within the 60 second contract" {
    printf 'sync-check\n' >> "$ROOT/payload.txt"
    run timeout 60 bash -c 'cd "$1" && bash "$1/scripts/publish_direct_commit.sh" -m "sync contract" -- payload.txt && test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"' _ "$ROOT"
    [ "$status" -eq 0 ]
}
