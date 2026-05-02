#!/usr/bin/env bats
# test_daemon_watchdog.bats - PID-based daemon watchdog checks

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "daemon_watchdog documents non-flock crontab form" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
if grep -q "flock -n /tmp/daemon_watchdog.lock" "$PROJECT_ROOT/scripts/daemon_watchdog.sh"; then
    echo "FAIL: old daemon_watchdog flock crontab form remains"
    exit 1
fi
grep -q "bash /path/to/scripts/daemon_watchdog.sh" "$PROJECT_ROOT/scripts/daemon_watchdog.sh"
'
    [ "$status" -eq 0 ]
}

@test "daemon_watchdog crontab registration check warns when missing" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT

export DAEMON_WATCHDOG_LIB_ONLY=1
export RESTART_STATE_DIR="$TMP_ROOT/state"
mkdir -p "$RESTART_STATE_DIR"
source "$PROJECT_ROOT/scripts/daemon_watchdog.sh"

crontab() { return 1; }
notify() { echo "NOTIFY:$1"; }
log() { echo "LOG:$1"; }
date() {
    if [ "${1:-}" = "+%s" ]; then echo 1000; else command date "$@"; fi
}

check_crontab_registration || true
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"CRONTAB-MISSING"* ]]
    [[ "$output" == *"daemon_watchdog.shのcrontab登録が見つかりません"* ]]
}

@test "ninja_monitor singleton is PID-file based, not flock based" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
awk "/^acquire_singleton_lock\\(\\)/,/^}/ { print }" "$PROJECT_ROOT/scripts/ninja_monitor.sh" > /tmp/ninja_monitor_singleton.$$
trap "rm -f /tmp/ninja_monitor_singleton.$$" EXIT
grep -q "ninja_monitor.pid" /tmp/ninja_monitor_singleton.$$
if grep -q "flock" /tmp/ninja_monitor_singleton.$$; then
    echo "FAIL: singleton still uses flock"
    exit 1
fi
'
    [ "$status" -eq 0 ]
}
