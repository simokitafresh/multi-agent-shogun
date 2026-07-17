#!/usr/bin/env bats

setup() {
    TMP_ROOT="$(mktemp -d)"
    mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/tests/unit"
    git -C "$TMP_ROOT" init -q
    for name in fail slow queued; do
        printf '@test "%s" { true; }\n' "$name" >"$TMP_ROOT/tests/unit/$name.bats"
    done
    cat >"$TMP_ROOT/bin/bats" <<'FAKE'
#!/usr/bin/env bash
name="$(basename "$1")"
case "$name" in
  fail.bats)
    sleep 0.2
    printf '1..1\nnot ok 1 reproducible failure\n'
    exit 7
    ;;
  slow.bats)
    sleep 2
    printf '1..1\nok 1 slow natural completion\n'
    ;;
  queued.bats)
    printf 'queued-launched\n' >>"$FAILFAST_EVENTS"
    printf '1..1\nok 1 queued\n'
    ;;
esac
FAKE
    chmod +x "$TMP_ROOT/bin/bats"
}

teardown() {
    rm -r "$TMP_ROOT"
}

@test "first nonzero stops launches, naturally drains admitted light file, and preserves failure" {
    export FAILFAST_EVENTS="$TMP_ROOT/events"
    : >"$FAILFAST_EVENTS"
    started=$SECONDS

    scheduler_status=0
    env PATH="$TMP_ROOT/bin:$PATH" REPO_ROOT="$TMP_ROOT" \
        BATS_CACHE=0 BATS_MAX_TEST_JOBS=2 BATS_FILE_TIMEOUT_SECONDS=60 \
        bash -c 'sleep 4 </dev/null >/dev/null 2>&1 3>&- & echo $! >"$5"; source "$1"; run_bats_files_parallel "$2" "$3" "$4"' sh \
        "$BATS_TEST_DIRNAME/../../scripts/run_tests.sh" \
        "$TMP_ROOT/tests/unit/fail.bats" \
        "$TMP_ROOT/tests/unit/slow.bats" \
        "$TMP_ROOT/tests/unit/queued.bats" "$TMP_ROOT/unrelated.pid" \
        >"$TMP_ROOT/scheduler.out" 2>&1 || scheduler_status=$?
    elapsed=$((SECONDS - started))
    unrelated_pid="$(cat "$TMP_ROOT/unrelated.pid")"
    output="$(cat "$TMP_ROOT/scheduler.out")"

    printf 'scheduler-status=%s output=%q\n' "$scheduler_status" "$output" >&3
    [ "$scheduler_status" -ne 0 ]
    [ "$elapsed" -le 30 ]
    [[ "$output" == *"DONE: fail.bats rc=7"* ]]
    [[ "$output" == *"DONE: slow.bats rc=0"* ]]
    [[ "$output" == *"==== $TMP_ROOT/tests/unit/fail.bats ===="* ]]
    [[ "$output" == *"not ok 1 reproducible failure"* ]]
    ! grep -q 'queued-launched' "$FAILFAST_EVENTS"
    [ -d "/proc/$unrelated_pid" ]
    # The unrelated process and admitted light file both complete naturally.
    for _ in 1 2 3 4 5; do
        [ -d "/proc/$unrelated_pid" ] || break
        sleep 1
    done
    [ ! -d "/proc/$unrelated_pid" ]
}
