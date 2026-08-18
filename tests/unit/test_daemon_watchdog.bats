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

@test "watchdog uses owner identity and generation instead of generic legacy process" {
    run bash -c '
        set -u
        root="$1"; state="$root/state"; count="$root/starts"; args="$root/args"
        mkdir -p "$state"; : >"$count"; : >"$args"
        export DAEMON_WATCHDOG_LIB_ONLY=1 SHOGUN_STATE_DIR="$state"
        export NINJA_MONITOR_OWNER_FILE="$state/ninja_monitor.owner"
        export DAEMON_WATCHDOG_LOG="$root/watchdog.log" RESTART_STATE_DIR="$root/restarts"
        source "$root/scripts/daemon_watchdog.sh"
        pid_is_live() { return 0; }
        pid_cmdline_matches() { return 0; }
        is_maintenance_active() { return 1; }
        check_restart_throttle() { return 0; }
        record_restart() { :; }
        notify() { :; }
        log() { :; }
        nohup() { printf "%s\n" "$*" >>"$count"; printf "%s\n" "$*" >>"$args"; :; }

        check_ninja_monitor
        test "$(wc -l <"$count")" -eq 1

        fp=$(sha256sum "$root/scripts/ninja_monitor.sh" | awk "{print \$1}")
        printf "%s current-generation 1\n" "$$" >"$NINJA_MONITOR_OWNER_FILE"
        printf "1 %s\n" "$fp" >"$NINJA_MONITOR_OWNER_FILE.identity"
        check_ninja_monitor
        test "$(wc -l <"$count")" -eq 1
        test ! -e "$state/ninja_monitor.watchdog.starting"

        printf "1 stale-fingerprint\n" >"$NINJA_MONITOR_OWNER_FILE.identity"
        check_ninja_monitor
        test "$(wc -l <"$count")" -eq 2
        grep -Fq "NINJA_MONITOR_REPLACE_GENERATION=current-generation" "$args"

        state="$root/parallel"; export STATE_DIR="$state" SHOGUN_STATE_DIR="$state"
        NINJA_MONITOR_OWNER_FILE="$state/ninja_monitor.owner"; export NINJA_MONITOR_OWNER_FILE
        mkdir -p "$state"; : >"$count"
        (check_ninja_monitor) & first=$!
        (check_ninja_monitor) & second=$!
        wait "$first"; wait "$second"
        test "$(wc -l <"$count")" -eq 1
        test "$(awk "{print \\$1}" "$state/ninja_monitor.watchdog.starting")" != "$$"
        printf "legacy_start=1 healthy_start=0 stale_start=1 replace_generation=1 parallel_winner=1\n"
    ' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"legacy_start=1 healthy_start=0 stale_start=1 replace_generation=1 parallel_winner=1"* ]]
}
