#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/scripts/restart_watchers.sh"
}

watcher_pids() {
    ps -eo pid=,ppid=,args= | awk '
        /(^| )bash .*\/inbox_watcher\.sh [a-z]/ {
            pid=$1; ppid=$2; watcher[pid]=1; parent[pid]=ppid
        }
        END {
            for (pid in watcher) if (!(parent[pid] in watcher)) print pid
        }
    ' | sort -n
}

@test "--status reports watcher processes without changing their PIDs" {
    before="$(watcher_pids)"

    run bash "$SCRIPT" --status

    after="$(watcher_pids)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"inbox_watcher: 9/9 running"* ]]
    [ "$after" = "$before" ]
}

@test "unknown option fails closed with usage and leaves watcher PIDs unchanged" {
    before="$(watcher_pids)"

    run bash "$SCRIPT" --unknown

    after="$(watcher_pids)"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: bash scripts/restart_watchers.sh [--status]"* ]]
    [ "$after" = "$before" ]
}

@test "extra argument after --status fails closed" {
    run bash "$SCRIPT" --status unexpected

    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: bash scripts/restart_watchers.sh [--status]"* ]]
}
