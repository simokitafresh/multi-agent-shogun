#!/usr/bin/env bats
# test_necessity: 家老宛の将軍発 task_assigned が閾値秒以上未読の間は inbox 読取/既読化以外の tool を BLOCK(exit 2)し、
#                 読取/既読化操作と対象外エージェントは常に通す — この不変量が崩れると指示不達(2026-08-26 push 6h停滞)が再発する。

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    GUARD="$REPO_ROOT/scripts/hooks/codex_inbox_priority_guard.sh"
    TMPD="$(mktemp -d)"
    INBOX="$TMPD/karo.yaml"
    old_ts="$(date -d '-10 minutes' '+%Y-%m-%dT%H:%M:%S')"
    new_ts="$(date '+%Y-%m-%dT%H:%M:%S')"
    cat > "$INBOX" <<EOF
messages:
- id: 'msg_old_shogun'
  from: 'shogun'
  type: 'task_assigned'
  read: false
  timestamp: '$old_ts'
  content: 'push now'
- id: 'msg_new_shogun'
  from: 'shogun'
  type: 'task_assigned'
  read: false
  timestamp: '$new_ts'
  content: 'fresh'
- id: 'msg_info'
  from: 'ninja_monitor'
  type: 'info'
  read: false
  timestamp: '$old_ts'
  content: 'noise'
EOF
}

teardown() { rm -rf "$TMPD"; }

@test "stale unread shogun task_assigned blocks non-inbox tools with exit 2" {
    run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"bash scripts/run_tests.sh push\"}}' | SHOGUN_AGENT_ID=karo SHOGUN_INBOX_FILE='$INBOX' bash '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(INBOX_PRIORITY)"* ]]
    [[ "$output" == *"msg_old_shogun"* ]]
    [[ "$output" != *"msg_new_shogun"* ]]
    [[ "$output" != *"msg_info"* ]]
}

@test "inbox read and mark_read commands pass through" {
    run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"bash scripts/inbox_mark_read.sh karo msg_old_shogun\"}}' | SHOGUN_AGENT_ID=karo SHOGUN_INBOX_FILE='$INBOX' bash '$GUARD'"
    [ "$status" -eq 0 ]
    run bash -c "echo '{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/x/queue/inbox/karo.yaml\"}}' | SHOGUN_AGENT_ID=karo SHOGUN_INBOX_FILE='$INBOX' bash '$GUARD'"
    [ "$status" -eq 0 ]
}

@test "non-target agent and fully-read inbox pass" {
    run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}' | SHOGUN_AGENT_ID=hanzo SHOGUN_INBOX_FILE='$INBOX' bash '$GUARD'"
    [ "$status" -eq 0 ]
    sed -i 's/read: false/read: true/' "$INBOX"
    run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}' | SHOGUN_AGENT_ID=karo SHOGUN_INBOX_FILE='$INBOX' bash '$GUARD'"
    [ "$status" -eq 0 ]
}
