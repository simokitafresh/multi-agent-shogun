#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_TMPDIR="$(mktemp -d "${BATS_TMPDIR}/gate-auto-cache.XXXXXX")"
    export STATE_DIR="$TEST_TMPDIR"
    sed -n '/^_gate_cached_run()/,/^}/p' "$PROJECT_ROOT/scripts/gate_auto_respond.sh" > "$TEST_TMPDIR/cache_function.sh"
    source "$TEST_TMPDIR/cache_function.sh"
}

teardown() {
    rm -f "$TEST_TMPDIR"/*
    rmdir "$TEST_TMPDIR"
}

@test "OK result is cached and skips a second gate process" {
    gate="$TEST_TMPDIR/gate.sh"
    count="$TEST_TMPDIR/count"
    printf '0\n' > "$count"
    printf '#!/usr/bin/env bash\nn=$(cat %q); echo $((n + 1)) > %q; echo OK\n' "$count" "$count" > "$gate"
    chmod +x "$gate"

    run _gate_cached_run sample "$gate" 300
    [ "$status" -eq 0 ]
    run _gate_cached_run sample "$gate" 300
    [ "$status" -eq 0 ]
    [ "$(cat "$count")" -eq 1 ]
}

@test "nonzero result is never cached" {
    gate="$TEST_TMPDIR/gate.sh"
    count="$TEST_TMPDIR/count"
    printf '0\n' > "$count"
    printf '#!/usr/bin/env bash\nn=$(cat %q); echo $((n + 1)) > %q; echo ALERT; exit 1\n' "$count" "$count" > "$gate"
    chmod +x "$gate"

    run _gate_cached_run sample "$gate" 300
    [ "$status" -eq 1 ]
    run _gate_cached_run sample "$gate" 300
    [ "$status" -eq 1 ]
    [ "$(cat "$count")" -eq 2 ]
}

@test "cmd_state and p_average handlers use the shared OK-only cache" {
    run grep -F '_gate_cached_run "cmd_state" "$GATES_DIR/gate_cmd_state.sh" 300' "$PROJECT_ROOT/scripts/gate_auto_respond.sh"
    [ "$status" -eq 0 ]
    run grep -F '_gate_cached_run "p_average_freshness" "$GATES_DIR/gate_p_average_freshness.sh" 300' "$PROJECT_ROOT/scripts/gate_auto_respond.sh"
    [ "$status" -eq 0 ]
}
