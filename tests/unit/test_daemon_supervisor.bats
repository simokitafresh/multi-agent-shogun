#!/usr/bin/env bats
# test_necessity: long-lived daemon descendants must not retain the short-lived
# restart coordinator lock, otherwise watchdog supervision can be skipped forever.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "supervisor closes inherited restart lock and detached watcher fd" {
    grep -Fq 'close_inherited_restart_watchers_lock' "$PROJECT_ROOT/scripts/daemon_supervisor.sh"
    grep -Fq 'inbox_watcher_${agent}.log" 200>&-' "$PROJECT_ROOT/scripts/daemon_supervisor.sh"
    run bash -c '
        set -u
        lock="$1/fixture.lock"
        exec 9>"$lock"
        export RESTART_WATCHERS_LOCK_FILE="$lock" DAEMON_SUPERVISOR_LIB_ONLY=1
        source "$1/scripts/daemon_supervisor.sh"
        exec 9>"$lock"
        close_inherited_restart_watchers_lock
        [ ! -e /proc/$$/fd/9 ]
    ' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
}

@test "all daemon entrypoints contain the inherited-lock boundary" {
    for script in daemon_watchdog.sh ninja_monitor.sh gist_sync.sh usage_statusbar_loop.sh; do
        grep -Fq 'close_inherited_restart_watchers_lock' "$PROJECT_ROOT/scripts/$script"
    done
}

# test_necessity: legacy pgrep matches are not serving evidence; only the
# owner PID, monitor cmdline, and current script fingerprint authorize health.
@test "ninja monitor supervision follows owner identity instead of legacy pgrep" {
    run bash -c '
        set -u
        root="$1"; state="$root/state"; count="$root/starts"; mkdir -p "$state"
        export DAEMON_SUPERVISOR_LIB_ONLY=1 SHOGUN_STATE_DIR="$state" \
            NINJA_MONITOR_OWNER_FILE="$state/ninja_monitor.owner" \
            DAEMON_SUPERVISOR_LOG="$root/supervisor.log"
        source "$root/scripts/daemon_supervisor.sh"
        ds_pattern_pids() { printf "999\n"; }
        ds_pid_live() { return 0; }
        ds_cmdline() { printf "/scripts/ninja_monitor.sh\n"; }
        ds_start_ninja_monitor() { printf "start\n" >>"$count"; }

        ds_supervise_ninja_monitor
        test "$(wc -l <"$count")" -eq 1

        fp=$(sha256sum "$root/scripts/ninja_monitor.sh" | awk "{print \$1}")
        printf "%s current-generation 1\n" "$$" >"$NINJA_MONITOR_OWNER_FILE"
        printf "1 %s\n" "$fp" >"$NINJA_MONITOR_OWNER_FILE.identity"
        ds_supervise_ninja_monitor
        test "$(wc -l <"$count")" -eq 1

        printf "1 stale-fingerprint\n" >"$NINJA_MONITOR_OWNER_FILE.identity"
        ds_supervise_ninja_monitor
        test "$(wc -l <"$count")" -eq 2

        state="$root/state-parallel"; export STATE_DIR="$state" SHOGUN_STATE_DIR="$state"
        NINJA_MONITOR_OWNER_FILE="$state/ninja_monitor.owner"; export NINJA_MONITOR_OWNER_FILE
        count="$root/parallel-starts"; export count
        mkdir -p "$state"; : >"$count"
        (ds_supervise_ninja_monitor) & first=$!
        (ds_supervise_ninja_monitor) & second=$!
        wait "$first"; wait "$second"
        test "$(wc -l <"$count")" -eq 1
        printf "legacy_start=1 healthy_start=0 stale_start=1 parallel_winner=1\n"
    ' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"legacy_start=1 healthy_start=0 stale_start=1 parallel_winner=1"* ]]
}
