#!/usr/bin/env bats
# test_ninja_monitor_inbox_cache.bats - inbox unread count cycle cache

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "count_unread_messages_cached: same cycle reuses count and next cycle refreshes" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
CALLS_FILE="$TMP_ROOT/calls"
printf "0\n" > "$CALLS_FILE"
export CALLS_FILE

count_unread_messages() {
    local calls
    calls=$(cat "$CALLS_FILE")
    calls=$((calls + 1))
    printf "%s\n" "$calls" > "$CALLS_FILE"
    echo "$calls"
}

cycle=41
count_unread_messages_cached "$PROJECT_ROOT/queue/inbox/hayate.yaml" first
count_unread_messages_cached "$PROJECT_ROOT/queue/inbox/hayate.yaml" second
cycle=42
count_unread_messages_cached "$PROJECT_ROOT/queue/inbox/hayate.yaml" third
calls=$(cat "$CALLS_FILE")

printf "%s,%s,%s,calls=%s\n" "$first" "$second" "$third" "$calls"
'
    [ "$status" -eq 0 ]
    [ "$output" = "1,1,2,calls=2" ]
}
