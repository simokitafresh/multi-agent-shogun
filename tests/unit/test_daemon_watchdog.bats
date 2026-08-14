#!/usr/bin/env bats
# test_necessity: only an actual restart_watchers owner may defer supervision;
# an inherited lock held by another daemon must fail open to health checking.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TEST_ROOT="$(mktemp -d)"
}

teardown() {
    rm -f "$TEST_ROOT/lock"
    rmdir "$TEST_ROOT"
}

@test "free lock is not reported as an active restart" {
    run bash -c 'DAEMON_WATCHDOG_LIB_ONLY=1 source "$1/scripts/daemon_watchdog.sh"; restart_watchers_lock_is_active "$2/lock"' _ "$PROJECT_ROOT" "$TEST_ROOT"
    [ "$status" -eq 1 ]
}

@test "canonical restart holder defers supervision" {
    lock="$TEST_ROOT/lock"
    ( exec 9>"$lock"; flock -n 9; exec -a "$PROJECT_ROOT/scripts/restart_watchers.sh" sleep 5 ) &
    holder=$!
    sleep 0.1
    run bash -c 'DAEMON_WATCHDOG_LIB_ONLY=1 source "$1/scripts/daemon_watchdog.sh"; restart_watchers_lock_is_active "$2"' _ "$PROJECT_ROOT" "$lock"
    wait "$holder"
    [ "$status" -eq 0 ]
}

@test "noncanonical inherited holder does not cause a permanent skip" {
    lock="$TEST_ROOT/lock"
    ( exec 9>"$lock"; flock -n 9; exec -a "$PROJECT_ROOT/scripts/gist_sync.sh" sleep 5 ) &
    holder=$!
    sleep 0.1
    run bash -c 'DAEMON_WATCHDOG_LIB_ONLY=1 source "$1/scripts/daemon_watchdog.sh"; restart_watchers_lock_is_active "$2"' _ "$PROJECT_ROOT" "$lock"
    wait "$holder"
    [ "$status" -eq 2 ]
}

@test "gunshi remains in the monitor watcher roster" {
    grep -Fq 'local all_agents=("shogun" "karo" "gunshi"' "$PROJECT_ROOT/scripts/ninja_monitor.sh"
}
