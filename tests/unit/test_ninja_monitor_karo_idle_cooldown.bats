#!/usr/bin/env bats

# test_necessity: cooldown is bound to the durable successful-delivery epoch,
# not a ninja_monitor process lifetime, across reload/respawn and concurrency.

setup() {
    export TEST_ROOT="$BATS_TEST_TMPDIR/runtime"
    export MONITOR_SCRIPT="$BATS_TEST_DIRNAME/../../scripts/ninja_monitor.sh"
    mkdir -p "$TEST_ROOT/logs" "$TEST_ROOT/state"
}

run_delivery() {
    local now="$1"
    local out="$2"
    NINJA_MONITOR_LIB_ONLY=1 SHOGUN_STATE_DIR="$TEST_ROOT/state" \
        KARO_IDLE_NUDGE_STATE_FILE="$TEST_ROOT/state/karo.last" \
        KARO_IDLE_COOLDOWN=1800 bash -c '
            source "$1"
            LOG="$2"
            deliver_karo_idle_nudge_with_cooldown "$3" bash -c '\''printf "delivered\n" >> "$1"'\'' _ "$4"
        ' _ "$MONITOR_SCRIPT" "$TEST_ROOT/logs/monitor.log" "$now" "$out"
}

@test "durable successful epoch survives re-source and expires after 1800 seconds" {
    local deliveries="$TEST_ROOT/deliveries"
    run run_delivery 1000 "$deliveries"
    [ "$status" -eq 0 ]
    run run_delivery 1100 "$deliveries"
    [ "$status" -eq 2 ]
    run run_delivery 2801 "$deliveries"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$deliveries")" -eq 2 ]
}

@test "two concurrent processes serialize to exactly one delivery" {
    local deliveries="$TEST_ROOT/concurrent"
    run_delivery 5000 "$deliveries" &
    local p1=$!
    run_delivery 5000 "$deliveries" &
    local p2=$!
    wait "$p1" || [ "$?" -eq 2 ]
    wait "$p2" || [ "$?" -eq 2 ]
    [ "$(wc -l < "$deliveries")" -eq 1 ]
}

@test "failed delivery does not advance epoch and missing state retries" {
    run env NINJA_MONITOR_LIB_ONLY=1 SHOGUN_STATE_DIR="$TEST_ROOT/state" bash -c '
        source "$1"
        LOG="$2"
        KARO_IDLE_NUDGE_STATE_FILE="$3"
        deliver_karo_idle_nudge_with_cooldown 7000 false
    ' _ "$MONITOR_SCRIPT" "$TEST_ROOT/logs/monitor.log" "$TEST_ROOT/state/fail.last"
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_ROOT/state/fail.last" ]
    run run_delivery 7000 "$TEST_ROOT/retry"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TEST_ROOT/retry")" -eq 1 ]
}

@test "corrupt and future epochs repair to now without delivery" {
    local deliveries="$TEST_ROOT/invalid"
    printf 'broken\n' > "$TEST_ROOT/state/karo.last"
    run run_delivery 8000 "$deliveries"
    [ "$status" -eq 2 ]
    [ "$(cat "$TEST_ROOT/state/karo.last")" = 8000 ]
    [ ! -e "$deliveries" ]
    printf '9999\n' > "$TEST_ROOT/state/karo.last"
    run run_delivery 9000 "$deliveries"
    [ "$status" -eq 2 ]
    [ "$(cat "$TEST_ROOT/state/karo.last")" = 9000 ]
    [ ! -e "$deliveries" ]
}
