#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TEST_ROOT="$(mktemp -d)"
    export DAEMON_MAINTENANCE_MARKER="$TEST_ROOT/marker"
    export DAEMON_MAINTENANCE_NOW=10000
    export AGENT_ID=kagemaru
}

teardown() { rm -rf "$TEST_ROOT"; }

@test "set records timestamp and operator; unset removes marker" {
    run bash "$PROJECT_ROOT/scripts/daemon_maintenance.sh" set
    [ "$status" -eq 0 ]
    grep -qx 'started_at=10000' "$DAEMON_MAINTENANCE_MARKER"
    grep -qx 'operator=kagemaru' "$DAEMON_MAINTENANCE_MARKER"
    run bash "$PROJECT_ROOT/scripts/daemon_maintenance.sh" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"operator=kagemaru"* ]]
    run bash "$PROJECT_ROOT/scripts/daemon_maintenance.sh" unset
    [ "$status" -eq 0 ]
    [ ! -e "$DAEMON_MAINTENANCE_MARKER" ]
}

@test "marker expires at 60 minute TTL and is removed" {
    printf 'started_at=6399\noperator=tester\n' > "$DAEMON_MAINTENANCE_MARKER"
    run bash "$PROJECT_ROOT/scripts/daemon_maintenance.sh" status
    [ "$status" -eq 1 ]
    [[ "$output" == *"maintenance inactive"* ]]
    [ ! -e "$DAEMON_MAINTENANCE_MARKER" ]
}

@test "three restart entry points use common marker and skip restart operations" {
    printf 'started_at=10000\noperator=tester\n' > "$DAEMON_MAINTENANCE_MARKER"

    export RESTART_WATCHERS_WARMUP_ONLY=1
    run bash "$PROJECT_ROOT/scripts/restart_watchers.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP: daemon maintenance active"* ]]

    export DAEMON_WATCHDOG_LIB_ONLY=1
    run bash -c 'source "$1/scripts/daemon_watchdog.sh"; pid_file_has_live_daemon(){ return 1; }; find_live_daemon_pid(){ return 1; }; log(){ echo "$*"; }; check_ninja_monitor' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"restart deferred"* ]]

    export DAEMON_SUPERVISOR_LIB_ONLY=1
    run bash -c 'source "$1/scripts/daemon_supervisor.sh"; ds_log(){ echo "$*"; }; ds_inbox_watcher_pids(){ return 0; }; ds_start_inbox_watcher(){ echo RESTARTED; }; ds_supervise_inbox_watcher test' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" != *"RESTARTED"* ]]
    [[ "$output" == *"restart deferred"* ]]

    export DAEMON_WATCHDOG_HEARTBEAT_FILE="$TEST_ROOT/heartbeat"
    unset DAEMON_WATCHDOG_LIB_ONLY DAEMON_SUPERVISOR_LIB_ONLY
    run bash "$PROJECT_ROOT/scripts/daemon_watchdog.sh"
    [ "$status" -eq 0 ]
    [ -s "$DAEMON_WATCHDOG_HEARTBEAT_FILE" ]
}

@test "marker absent preserves normal decision path for all three entry points" {
    [ ! -e "$DAEMON_MAINTENANCE_MARKER" ]
    run bash -c 'source "$1/scripts/lib/daemon_maintenance_lock.sh"; is_maintenance_active' _ "$PROJECT_ROOT"
    [ "$status" -eq 1 ]
    run env RESTART_WATCHERS_WARMUP_ONLY=1 bash "$PROJECT_ROOT/scripts/restart_watchers.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"SKIP: daemon maintenance"* ]]
    run bash -c 'source "$1/scripts/daemon_watchdog.sh"; is_maintenance_active' _ "$PROJECT_ROOT"
    [ "$status" -eq 1 ]
    run bash -c 'source "$1/scripts/daemon_supervisor.sh"; is_maintenance_active' _ "$PROJECT_ROOT"
    [ "$status" -eq 1 ]
}

@test "corrupt marker fails closed" {
    printf 'operator=tester\n' > "$DAEMON_MAINTENANCE_MARKER"
    run bash "$PROJECT_ROOT/scripts/restart_watchers.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"corrupt"* ]]
}
