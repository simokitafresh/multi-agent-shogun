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

@test "ninja_scope_commit uses the reservation ledger and releases its row" {
    printf 'base\n' >"$TMPROOT/repo/owned.txt"
    git -C "$TMPROOT/repo" add owned.txt
    tree="$(git -C "$TMPROOT/repo" write-tree)"
    commit="$(printf 'initial\n' | git -C "$TMPROOT/repo" commit-tree "$tree")"
    git -C "$TMPROOT/repo" update-ref refs/heads/main "$commit"
    git -C "$TMPROOT/repo" symbolic-ref HEAD refs/heads/main
    printf 'queued-change\n' >"$TMPROOT/repo/owned.txt"
    queue_path="$TMPROOT/integration-queue.tsv"
    run env COMMIT_QUEUE_PATH="$queue_path" \
        COMMIT_QUEUE_LOCK_PATH="$queue_path.lock" \
        COMMIT_QUEUE_ACTIVE= \
        COMMIT_QUEUE_AGENT_ID=integration-agent \
        bash -c 'cd "$1" && bash "$2" -m "phase2 queue integration" -- owned.txt' \
        _ "$TMPROOT/repo" "$ROOT/scripts/ninja_scope_commit.sh"
    [ "$status" -eq 0 ]
    [ -e "$queue_path" ]
    [ ! -s "$queue_path" ]
    [ "$(git -C "$TMPROOT/repo" show --format= --name-only HEAD)" = owned.txt ]
    [ "$(git -C "$TMPROOT/repo" show HEAD:owned.txt)" = queued-change ]
}

@test "concurrent ledger mutations never publish a partial TSV row" {
    workers=()
    for agent in alpha beta gamma delta; do
        (
            for _ in {1..8}; do
                reservation="$(queue reserve "$agent" "$TMPROOT/repo")"
                queue mark_running "$reservation"
                queue release "$reservation"
            done
        ) &
        workers+=("$!")
    done

    malformed=0
    while :; do
        active=false
        for pid in "${workers[@]}"; do
            if ps -p "$pid" -o pid= >/dev/null 2>&1; then
                active=true
                break
            fi
        done
        if [ "$active" = true ] && [ -e "$QUEUE" ]; then
            while IFS= read -r row; do
                [ -z "$row" ] && continue
                fields="$(awk -F '\t' '{print NF}' <<<"$row")"
                [ "$fields" -eq 6 ] || malformed=1
            done <"$QUEUE"
        fi
        [ "$active" = true ] || break
    done
    for pid in "${workers[@]}"; do
        wait "$pid"
    done
    [ "$malformed" -eq 0 ]
    [ ! -s "$QUEUE" ]
}
