#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SHOGUN_STARTUP_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh"
    export DAEMON_WATCHDOG_HEARTBEAT_FILE="$BATS_TEST_TMPDIR/heartbeat"
    export DAEMON_WATCHDOG_GATE_FIRE_LOG="$BATS_TEST_TMPDIR/gate_fire_log.yaml"
    export DAEMON_WATCHDOG_HEARTBEAT_NOW=1000
    export DAEMON_WATCHDOG_HEARTBEAT_MAX_AGE_SEC=300
}

@test "fresh heartbeat is OK and records PASS" {
    printf '900\n' > "$DAEMON_WATCHDOG_HEARTBEAT_FILE"
    run check_daemon_watchdog_heartbeat "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: daemon_watchdog heartbeat fresh (age=100s < 300s)"* ]]
    grep -q 'gate: "daemon_watchdog_heartbeat", result: PASS' "$DAEMON_WATCHDOG_GATE_FIRE_LOG"
}

@test "heartbeat at threshold is WARN and records fire" {
    printf '700\n' > "$DAEMON_WATCHDOG_HEARTBEAT_FILE"
    run check_daemon_watchdog_heartbeat "$BATS_TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"WARN: daemon_watchdog heartbeat_stale_age_300s"* ]]
    grep -q 'result: WARN.*heartbeat_stale_age_300s' "$DAEMON_WATCHDOG_GATE_FIRE_LOG"
}

@test "missing heartbeat is WARN and records fire" {
    run check_daemon_watchdog_heartbeat "$BATS_TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"WARN: daemon_watchdog heartbeat_missing"* ]]
    grep -q 'result: WARN.*heartbeat_missing' "$DAEMON_WATCHDOG_GATE_FIRE_LOG"
}
