#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SOURCE_SCRIPT="$PROJECT_ROOT/.claude/hooks/post-bulletin-notify-read-check.sh"
    [ -f "$SOURCE_SCRIPT" ] || return 1
    python3 -c "import yaml" >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1
}

setup() {
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/post_bulletin_notify.XXXXXX")"
    mkdir -p "$TEST_ROOT/.claude/hooks" "$TEST_ROOT/queue/inbox" "$TEST_ROOT/queue"
    cp "$SOURCE_SCRIPT" "$TEST_ROOT/.claude/hooks/post-bulletin-notify-read-check.sh"
    chmod +x "$TEST_ROOT/.claude/hooks/post-bulletin-notify-read-check.sh"
    export TEST_SCRIPT="$TEST_ROOT/.claude/hooks/post-bulletin-notify-read-check.sh"
    rm -f /tmp/claude_read_log_hayate.txt
}

teardown() {
    rm -f /tmp/claude_read_log_hayate.txt
    rm -rf "$TEST_ROOT"
}

write_inbox() {
    local type="$1"
    cat > "$TEST_ROOT/queue/inbox/hayate.yaml" <<YAML
messages:
- id: msg_001
  from: karo
  type: ${type}
  content: notice
  read: true
YAML
}

write_pending_bulletin() {
    cat > "$TEST_ROOT/queue/bulletin_board.yaml" <<'YAML'
entries:
- id: blt_001
  content: |-
    確認が必要
  posted_by: karo
  posted_at: '2026-05-02T10:00:00'
  requires_confirmation: true
  confirmed_by: []
  status: 'open'
YAML
}

run_hook() {
    local command="$1"
    local payload
    payload="$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$command" | jq -Rs .)")"
    run bash -c "cd '$TEST_ROOT' && printf '%s' '$payload' | '$TEST_SCRIPT'"
}

@test "warns when bulletin_notify is marked read while bulletin entry is unconfirmed" {
    write_inbox bulletin_notify
    write_pending_bulletin

    run_hook "bash scripts/inbox_mark_read.sh hayate msg_001"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: bulletin_notify"* ]]
    [[ "$output" == *"blt_001"* ]]
}

@test "stays silent after bulletin_board.yaml was read first" {
    write_inbox bulletin_notify
    write_pending_bulletin
    echo "$TEST_ROOT/queue/bulletin_board.yaml" > /tmp/claude_read_log_hayate.txt

    run_hook "bash scripts/inbox_mark_read.sh hayate msg_001"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "stays silent for non-bulletin inbox messages" {
    write_inbox task_assigned
    write_pending_bulletin

    run_hook "bash scripts/inbox_mark_read.sh hayate msg_001"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
