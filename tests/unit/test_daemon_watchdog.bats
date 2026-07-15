#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "unread count remains a single integer when awk cannot read input" {
    run bash -lc '
set -uo pipefail
export DAEMON_WATCHDOG_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/daemon_watchdog.sh"
tmp=$(mktemp)
printf -- "- id: one\n  read: false\n" > "$tmp"
inbox_unread_count_file "$tmp"
rm -f "$tmp"
'
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "pid cmdline race is silent for a vanished process" {
    run bash -lc '
set -uo pipefail
export DAEMON_WATCHDOG_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/daemon_watchdog.sh"
pid_cmdline_matches 999999999 daemon 2>&1 || true
'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "daemon inventory warns for every missing daemon class" {
    run bash -lc '
set -uo pipefail
export DAEMON_WATCHDOG_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/daemon_watchdog.sh"
daemon_inventory_snapshot() { printf "%s\n" "bash inbox_watcher.sh one"; }
log() { printf "%s\n" "$*"; }
check_daemon_inventory
'
    [ "$status" -eq 0 ]
    [ "$(printf "%s\n" "$output" | grep -c "DAEMON-INVENTORY-WARN")" -eq 5 ]
    [[ "$output" == *"inbox_watcher.sh expected>=9 actual=1"* ]]
    [[ "$output" == *"gist_sync.sh expected>=1 actual=0"* ]]
}

@test "daemon inventory emits no warning when all expected daemons exist" {
    run bash -lc '
set -uo pipefail
export DAEMON_WATCHDOG_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/daemon_watchdog.sh"
daemon_inventory_snapshot() {
    for i in {1..9}; do echo "bash inbox_watcher.sh agent$i"; done
    echo "bash ninja_monitor.sh"
    echo "bash ntfy_listener.sh"
    echo "bash usage_statusbar_loop.sh"
    echo "bash gist_sync.sh"
}
log() { printf "%s\n" "$*"; }
check_daemon_inventory
'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "tmux health is silent when list-sessions succeeds" {
    run bash -lc '
export DAEMON_WATCHDOG_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/daemon_watchdog.sh"
tmux() { return 0; }
log() { printf "unexpected-log"; }
notify() { printf "unexpected-notify"; }
check_tmux_health
'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "tmux health logs notifies and emits ALERT when list-sessions fails" {
    run bash -lc '
export DAEMON_WATCHDOG_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/daemon_watchdog.sh"
tmux() { return 1; }
log() { printf "LOG:%s\n" "$*"; }
notify() { printf "NOTIFY:%s\n" "$*"; }
check_tmux_health
'
    [ "$status" -eq 1 ]
    [[ "$output" == *"LOG:TMUX-HEALTH-ALERT"* ]]
    [[ "$output" == *"NOTIFY:【watchdog/CRITICAL】"* ]]
    [[ "$output" == *"TMUX-HEALTH-ALERT:"* ]]
}
