#!/usr/bin/env bats
# test_daemon_supervisor.bats - unified daemon supervisor checks

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "daemon_supervisor enumerates shogun plus active agent watchers (9 total)" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export DAEMON_SUPERVISOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/daemon_supervisor.sh"
ds_agent_list
'
    [ "$status" -eq 0 ]
    [ "$(printf "%s\n" "$output" | sed "/^$/d" | wc -l)" -eq 9 ]
    [[ "$output" == *"shogun"* ]]
    [[ "$output" == *"karo"* ]]
    [[ "$output" == *"gunshi"* ]]
    [[ "$output" == *"hayate"* ]]
}

@test "daemon_supervisor restarts missing inbox_watcher and notifies" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export DAEMON_SUPERVISOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/daemon_supervisor.sh"
ds_inbox_watcher_pids() { return 0; }
ds_start_inbox_watcher() { echo "START:$1"; }
ds_notify() { echo "NOTIFY:$1"; }
ds_log() { echo "LOG:$1"; }

ds_supervise_inbox_watcher hayate || true
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MISSING: inbox_watcher(hayate)"* ]]
    [[ "$output" == *"NOTIFY:"*"inbox_watcher(hayate)"* ]]
    [[ "$output" == *"START:hayate"* ]]
}

@test "daemon_supervisor stops older duplicate inbox_watcher processes" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export DAEMON_SUPERVISOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/daemon_supervisor.sh"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
printf "0\n" > "$TMP_ROOT/calls"
ds_inbox_watcher_pids() {
    local calls
    calls="$(cat "$TMP_ROOT/calls")"
    calls=$((calls + 1))
    printf "%s\n" "$calls" > "$TMP_ROOT/calls"
    if [ "$calls" -eq 1 ]; then
        printf "%s\n" 101 202 303
    else
        printf "%s\n" 303
    fi
}
ds_stop_pid() { echo "STOP:$1:$2"; }
ds_notify() { echo "NOTIFY:$1"; }
ds_log() { echo "LOG:$1"; }

ds_supervise_inbox_watcher karo
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"DUPLICATE: inbox_watcher(karo) count=3"* ]]
    [[ "$output" == *"STOP:101:inbox_watcher(karo)"* ]]
    [[ "$output" == *"STOP:202:inbox_watcher(karo)"* ]]
    [[ "$output" != *"STOP:303:inbox_watcher(karo)"* ]]
}

@test "daemon_supervisor supervises ninja_monitor and ntfy_listener singleton names" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
grep -q "ds_supervise_singleton \"ninja_monitor.sh\"" "$PROJECT_ROOT/scripts/daemon_supervisor.sh"
grep -q "ds_supervise_singleton \"ntfy_listener.sh\"" "$PROJECT_ROOT/scripts/daemon_supervisor.sh"
grep -q "ds_start_ninja_monitor" "$PROJECT_ROOT/scripts/daemon_supervisor.sh"
grep -q "ds_start_ntfy_listener" "$PROJECT_ROOT/scripts/daemon_supervisor.sh"
'
    [ "$status" -eq 0 ]
}
