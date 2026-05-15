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
INBOX_FILE="$TMP_ROOT/hayate.yaml"
cat > "$INBOX_FILE" <<EOF
messages:
- id: msg_1
  read: false
EOF

cycle=41
count_unread_messages_cached "$INBOX_FILE" first
cat >> "$INBOX_FILE" <<EOF
- id: msg_2
  read: false
EOF
count_unread_messages_cached "$INBOX_FILE" second
cycle=42
count_unread_messages_cached "$INBOX_FILE" third

printf "%s,%s,%s\n" "$first" "$second" "$third"
'
    [ "$status" -eq 0 ]
    [ "$output" = "1,1,2" ]
}
