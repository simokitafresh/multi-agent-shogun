#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "get_unread_info parses unread ids and multiline special payload without PyYAML fallback" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/queue/inbox"

cat > "$TMP_ROOT/bin/inotifywait" <<'"'"'SH'"'"'
#!/bin/bash
exit 0
SH
chmod +x "$TMP_ROOT/bin/inotifywait"

cat > "$TMP_ROOT/queue/inbox/hayate.yaml" <<'"'"'YAML'"'"'
messages:
- content: '"'"'通常メッセージ'"'"'
  from: '"'"'karo'"'"'
  id: '"'"'msg_002'"'"'
  read: false
  timestamp: '"'"'2026-04-02T14:17:35'"'"'
  type: '"'"'task_assigned'"'"'
- content: |-
    /clear
    続けて復帰せよ
  from: '"'"'karo'"'"'
  id: '"'"'msg_001'"'"'
  read: false
  timestamp: '"'"'2026-04-02T14:17:34'"'"'
  type: '"'"'clear_command'"'"'
- content: '"'"'既読メッセージ'"'"'
  from: '"'"'karo'"'"'
  id: '"'"'msg_003'"'"'
  read: true
  timestamp: '"'"'2026-04-02T14:17:36'"'"'
  type: '"'"'task_assigned'"'"'
YAML

PATH="$TMP_ROOT/bin:$PATH"
export INBOX_WATCHER_LIB_ONLY=1
set -- hayate shogun:agents.3
source "$PROJECT_ROOT/scripts/inbox_watcher.sh"
INBOX="$TMP_ROOT/queue/inbox/hayate.yaml"

raw="$(get_unread_info)"
IFS=$'\''\t'\'' read -r normal_count has_specials fingerprint specials_b64 has_task_assigned <<< "$raw"

[ "$normal_count" = "1" ]
[ "$has_specials" = "true" ]
[ "$fingerprint" = "msg_002" ]
[ "$has_task_assigned" = "true" ]

decoded="$(printf %s "$specials_b64" | base64 -d)"
printf "%s\n" "$decoded" | grep -q "^msg_001"
special_content_b64="$(printf "%s\n" "$decoded" | cut -f3)"
[ "$(printf %s "$special_content_b64" | base64 -d)" = $'\''/clear\n続けて復帰せよ'\'' ]
echo "PARSED_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PARSED_OK"* ]]
}
