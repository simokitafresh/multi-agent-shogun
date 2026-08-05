#!/usr/bin/env bats
# Commit reservation ledger Phase1 contract.
# test_necessity: preserve FIFO reservation, stale-GC, index-lock fail-close,
# and abnormal-exit release invariants for the shared commit serialization lane.
# overlaps_existing: false

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TMPROOT="$(mktemp -d)"
    QUEUE="$TMPROOT/queue.tsv"
    export COMMIT_QUEUE_PATH="$QUEUE"
    export COMMIT_QUEUE_LOCK_PATH="$QUEUE.lock"
    export COMMIT_QUEUE_POLL_SECONDS=1
    export COMMIT_QUEUE_WAIT_SECONDS=10
    export COMMIT_QUEUE_INDEX_WAIT_ATTEMPTS=1
    export COMMIT_QUEUE_INDEX_POLL_SECONDS=1
    mkdir -p "$TMPROOT/repo"
    git -C "$TMPROOT/repo" init -q
    git -C "$TMPROOT/repo" config user.email test@example.invalid
    git -C "$TMPROOT/repo" config user.name test
}

teardown() {
    rm -rf -- "$TMPROOT"
}

queue() {
    bash "$ROOT/scripts/commit_queue.sh" "$@"
}

@test "reserve rejects duplicate agent and release removes only its row" {
    first="$(queue reserve kagemaru "$TMPROOT/repo")"
    run queue reserve kagemaru "$TMPROOT/repo"
    [ "$status" -eq 3 ]
    run queue release "$first"
    [ "$status" -eq 0 ]
    [ ! -s "$QUEUE" ]
}

@test "FIFO wait_turn and mark_running preserve reservation order" {
    first="$(queue reserve first "$TMPROOT/repo")"
    second="$(queue reserve second "$TMPROOT/repo")"
    run queue wait_turn "$first"
    [ "$status" -eq 0 ]
    run queue mark_running "$first"
    [ "$status" -eq 0 ]
    run queue wait_turn "$second"
    [ "$status" -eq 124 ]
    queue release "$first"
    run queue wait_turn "$second"
    [ "$status" -eq 0 ]
}

@test "gc removes expired waiting reservations" {
    now="$(date +%s)"
    printf 'expired\texpired\t%s\t%s\twaiting\t%s\n' "$TMPROOT/repo" "$((now - 601))" "$((now - 601))" >"$QUEUE"
    queue gc
    [ ! -s "$QUEUE" ]
}

@test "check_index removes an orphan lock but does not assume it is safe blindly" {
    lock_path="$(git -C "$TMPROOT/repo" rev-parse --git-path index.lock)"
    [[ "$lock_path" = /* ]] || lock_path="$TMPROOT/repo/$lock_path"
    : >"$lock_path"
    run queue check_index "$TMPROOT/repo"
    [ "$status" -eq 0 ]
    [ ! -e "$lock_path" ]
}

@test "run releases reservation after abnormal child exit" {
    run queue run --agent trap-agent --repo "$TMPROOT/repo" -- bash -c 'exit 7'
    [ "$status" -eq 7 ]
    [ ! -s "$QUEUE" ]
}

@test "PRECOMMIT excludes the recursive scoped-commit contract test" {
    run bash -c 'source "$1/scripts/run_tests.sh"; PRECOMMIT=1 run_bats_files_parallel "$2"' \
        _ "$ROOT" "$ROOT/tests/unit/test_ninja_scope_commit.bats"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PRECOMMIT_EXCLUDED_SELF_TEST"* ]]
    [[ "$output" == *"files=0 excluded_self_test=1"* ]]
}
