#!/usr/bin/env bats
# test_restart_watchers.bats - inbox_watcher restart singleton enforcement

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "restart_watchers kills old watchers and verifies exact normal count" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
grep -q "stop_existing_watchers" "$PROJECT_ROOT/scripts/restart_watchers.sh"
grep -q "pkill -TERM -f \"\\[i\\]nbox_watcher\\\\.sh\"" "$PROJECT_ROOT/scripts/restart_watchers.sh"
grep -q "pkill -KILL -f \"\\[i\\]nbox_watcher\\\\.sh\"" "$PROJECT_ROOT/scripts/restart_watchers.sh"
grep -q "verify_watcher_count \"\$EXPECTED_WATCHER_COUNT\"" "$PROJECT_ROOT/scripts/restart_watchers.sh"
grep -q "EXPECTED_WATCHER_COUNT=\"\${EXPECTED_WATCHER_COUNT:-9}\"" "$PROJECT_ROOT/scripts/restart_watchers.sh"
'
    [ "$status" -eq 0 ]
}

@test "shutsujin departure watcher path kills old watchers and verifies exact normal count" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
grep -q "stop_existing_inbox_watchers" "$PROJECT_ROOT/shutsujin_departure.sh"
grep -q "pkill -TERM -f \"\\[i\\]nbox_watcher\\\\.sh\"" "$PROJECT_ROOT/shutsujin_departure.sh"
grep -q "pkill -KILL -f \"\\[i\\]nbox_watcher\\\\.sh\"" "$PROJECT_ROOT/shutsujin_departure.sh"
grep -q "verify_inbox_watcher_count \"\$EXPECTED_WATCHER_COUNT\"" "$PROJECT_ROOT/shutsujin_departure.sh"
grep -q "EXPECTED_WATCHER_COUNT=\"\${EXPECTED_WATCHER_COUNT:-9}\"" "$PROJECT_ROOT/shutsujin_departure.sh"
'
    [ "$status" -eq 0 ]
}
