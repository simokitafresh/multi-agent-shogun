#!/usr/bin/env bats
# test_necessity: Maintenance marker TTL expiry prevents permanent lockout and all three restart entry points respect the marker; violation is BLOCK.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TEST_ROOT="$(mktemp -d)"
    export DAEMON_MAINTENANCE_MARKER="$TEST_ROOT/marker"
    export DAEMON_MAINTENANCE_NOW=10000
    export AGENT_ID=kagemaru
    export SHOGUN_STATE_DIR="$TEST_ROOT/state"
    # restart_watchers warm-up is not the subject of this suite.  Point it at
    # an absent fixture DB so the test cannot start a detached copy of the
    # production memory DB and leak work beyond the bats root in clean CI.
    export SHOGUN_MEMORY_DB_SOURCE_PATH="$TEST_ROOT/missing-memory.db"
    # Never contend with or inherit the production restart lock.  A clean CI
    # run printed all 5 passing tests, then kept the bats root open until the
    # outer 900s timeout while daemon fixtures shared the global /tmp lock.
    export RESTART_WATCHERS_LOCK_FILE="$TEST_ROOT/restart-watchers.lock"
}

teardown() { rm -rf "$TEST_ROOT"; }

# Daemon entry points may detach descendants.  They must never inherit bats'
# formatter/control descriptors: even after TAP prints all five passing cases,
# one inherited descriptor keeps the bats root alive until the outer timeout.
# Close the reserved descriptor range at the child boundary so every descendant
# inherits the safe state while stdout/stderr remain available to `run`.
run_daemon_isolated() {
    run bash -c '
        exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-
        exec "$@"
    ' _ "$@"
}

@test "daemon child boundary closes bats formatter descriptors" {
    run_daemon_isolated bash -c '
        for fd in 3 4 5 6 7 8 9; do
            [ ! -e "/proc/$$/fd/$fd" ] || exit 1
        done
    '
    [ "$status" -eq 0 ]
}

@test "set records timestamp and operator; unset removes marker" {
    run_daemon_isolated bash -c '
        set -e
        bash "$1/scripts/daemon_maintenance.sh" set
        cat "$DAEMON_MAINTENANCE_MARKER"
        bash "$1/scripts/daemon_maintenance.sh" status
        bash "$1/scripts/daemon_maintenance.sh" unset
        [ ! -e "$DAEMON_MAINTENANCE_MARKER" ]
        echo marker_absent
    ' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"started_at=10000"* ]]
    [[ "$output" == *"operator=kagemaru"* ]]
    [[ "$output" == *"maintenance active: operator=kagemaru"* ]]
    [[ "$output" == *"marker_absent"* ]]
}

@test "marker expires at 60 minute TTL and is removed" {
    printf 'started_at=6399\noperator=tester\n' > "$DAEMON_MAINTENANCE_MARKER"
    run_daemon_isolated bash "$PROJECT_ROOT/scripts/daemon_maintenance.sh" status
    [ "$status" -eq 1 ]
    [[ "$output" == *"maintenance inactive"* ]]
    [ ! -e "$DAEMON_MAINTENANCE_MARKER" ]
}

@test "three restart entry points use common marker and skip restart operations" {
    printf 'started_at=10000\noperator=tester\n' > "$DAEMON_MAINTENANCE_MARKER"

    export RESTART_WATCHERS_WARMUP_ONLY=1
    run_daemon_isolated bash "$PROJECT_ROOT/scripts/restart_watchers.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP: daemon maintenance active"* ]]

    export DAEMON_WATCHDOG_LIB_ONLY=1
    run_daemon_isolated bash -c 'DAEMON_WATCHDOG_LIB_ONLY=1 source "$1/scripts/daemon_watchdog.sh"; pid_file_has_live_daemon(){ return 1; }; find_live_daemon_pid(){ return 1; }; log(){ echo "$*"; }; check_ninja_monitor' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"restart deferred"* ]]

    export DAEMON_SUPERVISOR_LIB_ONLY=1
    run_daemon_isolated bash -c 'DAEMON_SUPERVISOR_LIB_ONLY=1 source "$1/scripts/daemon_supervisor.sh"; ds_log(){ echo "$*"; }; ds_inbox_watcher_pids(){ return 0; }; ds_start_inbox_watcher(){ echo RESTARTED; }; ds_supervise_inbox_watcher test' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" != *"RESTARTED"* ]]
    [[ "$output" == *"restart deferred"* ]]

    export DAEMON_WATCHDOG_HEARTBEAT_FILE="$TEST_ROOT/heartbeat"
    # Never execute the production entrypoint in a unit fixture.  Its normal
    # path may nohup durable daemons; stubbing only their inputs still lets a
    # newly-added supervision branch escape the bats process tree.  Source the
    # library and exercise the maintenance decisions explicitly, then publish
    # the heartbeat which is the only entrypoint-side contract asserted here.
    export DAEMON_WATCHDOG_LIB_ONLY=1
    run_daemon_isolated bash -c '
        DAEMON_WATCHDOG_LIB_ONLY=1 source "$1/scripts/daemon_watchdog.sh"
        check_ninja_monitor
        check_ntfy_listener
        check_inbox_watchers
        date +%s > "$DAEMON_WATCHDOG_HEARTBEAT_FILE"
    ' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [ -s "$DAEMON_WATCHDOG_HEARTBEAT_FILE" ]
}

@test "fixtureはproduction daemon entrypointを実行せず全sourceをlib-onlyにする" {
    run bash -c '
        if grep -Eq '\''bash "\$PROJECT_ROOT/scripts/daemon_(watchdog|supervisor)\.sh"'\'' "$1"; then
            exit 1
        fi
        awk '\''
            /source "\$1\/scripts\/daemon_watchdog\.sh"/ && $0 !~ /DAEMON_WATCHDOG_LIB_ONLY=1 source/ { bad=1 }
            /source "\$1\/scripts\/daemon_supervisor\.sh"/ && $0 !~ /DAEMON_SUPERVISOR_LIB_ONLY=1 source/ { bad=1 }
            END { exit bad }
        '\'' "$1"
    ' _ "$BATS_TEST_FILENAME"
    [ "$status" -eq 0 ]
}

@test "marker absent preserves normal decision path for all three entry points" {
    [ ! -e "$DAEMON_MAINTENANCE_MARKER" ]
    run_daemon_isolated bash -c 'source "$1/scripts/lib/daemon_maintenance_lock.sh"; is_maintenance_active' _ "$PROJECT_ROOT"
    [ "$status" -eq 1 ]
    run_daemon_isolated env RESTART_WATCHERS_WARMUP_ONLY=1 bash "$PROJECT_ROOT/scripts/restart_watchers.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"SKIP: daemon maintenance"* ]]
    run_daemon_isolated bash -c 'DAEMON_WATCHDOG_LIB_ONLY=1 source "$1/scripts/daemon_watchdog.sh"; is_maintenance_active' _ "$PROJECT_ROOT"
    [ "$status" -eq 1 ]
    run_daemon_isolated bash -c 'DAEMON_SUPERVISOR_LIB_ONLY=1 source "$1/scripts/daemon_supervisor.sh"; is_maintenance_active' _ "$PROJECT_ROOT"
    [ "$status" -eq 1 ]
}

@test "corrupt marker fails closed" {
    printf 'operator=tester\n' > "$DAEMON_MAINTENANCE_MARKER"
    run_daemon_isolated bash -c '
        set +e
        bash "$1/scripts/daemon_maintenance.sh" status
        status_rc=$?
        bash "$1/scripts/restart_watchers.sh"
        restart_rc=$?
        printf "status_rc=%s restart_rc=%s\n" "$status_rc" "$restart_rc"
        [ "$status_rc" -eq 2 ] && [ "$restart_rc" -eq 1 ]
    ' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"maintenance invalid: corrupt marker"* ]]
    [[ "$output" == *"corrupt"* ]]
}
