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
