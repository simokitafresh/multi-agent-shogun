#!/usr/bin/env bats
# inbox_mark_read.sh unit tests (cmd_cycle_002)

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SOURCE_SCRIPT="$PROJECT_ROOT/scripts/inbox_mark_read.sh"
    export SOURCE_CONFIRM_SCRIPT="$PROJECT_ROOT/scripts/bulletin_confirm.sh"
    [ -f "$SOURCE_SCRIPT" ] || return 1
    [ -f "$SOURCE_CONFIRM_SCRIPT" ] || return 1
    python3 -c "import yaml" >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/inbox_mark_read.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts/lib" "$TEST_ROOT/queue/inbox" "$TEST_ROOT/queue"

    cp "$SOURCE_SCRIPT" "$TEST_ROOT/scripts/inbox_mark_read.sh"
    cp "$SOURCE_CONFIRM_SCRIPT" "$TEST_ROOT/scripts/bulletin_confirm.sh"
    chmod +x "$TEST_ROOT/scripts/inbox_mark_read.sh"
    chmod +x "$TEST_ROOT/scripts/bulletin_confirm.sh"
    cat > "$TEST_ROOT/scripts/lib/agent_config.sh" <<'SH'
get_all_agents() {
    echo "karo gunshi hayate kagemaru hanzo saizo kotaro tobisaru"
}
SH

    export TEST_SCRIPT="$TEST_ROOT/scripts/inbox_mark_read.sh"
}

teardown() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

# Helper: create inbox with test messages
_create_inbox() {
    local agent="$1"
    cat > "$TEST_ROOT/queue/inbox/${agent}.yaml" << 'YAML'
messages:
- id: msg_001
  from: karo
  timestamp: '2026-03-25T10:00:00'
  type: task_assigned
  content: first message
  read: false
- id: msg_002
  from: karo
  timestamp: '2026-03-25T10:01:00'
  type: wake_up
  content: second message
  read: false
- id: msg_003
  from: shogun
  timestamp: '2026-03-25T10:02:00'
  type: cmd_new
  content: third message
  read: true
YAML
}

# Helper: read message field from inbox YAML
_get_read_status() {
    local agent="$1" msg_id="$2"
    INBOX="$TEST_ROOT/queue/inbox/${agent}.yaml" MSG_ID="$msg_id" python3 -c "
import yaml, os
with open(os.environ['INBOX']) as f:
    data = yaml.safe_load(f)
for m in data.get('messages', []):
    if m.get('id') == os.environ['MSG_ID']:
        print('true' if m.get('read') else 'false')
        break
"
}

_get_confirmed_by() {
    local entry_id="$1"
    BULLETIN="$TEST_ROOT/queue/bulletin_board.yaml" ENTRY_ID="$entry_id" python3 -c "
import os, yaml
with open(os.environ['BULLETIN']) as f:
    data = yaml.safe_load(f)
for entry in data.get('entries', []):
    if entry.get('id') == os.environ['ENTRY_ID']:
        print(','.join(entry.get('confirmed_by') or []))
        break
"
}

@test "mark specific msg_id as read" {
    _create_inbox testagent

    run bash "$TEST_SCRIPT" testagent msg_001
    [ "$status" -eq 0 ]
    [[ "$output" == *"Marked 1 message"* ]]

    # msg_001 should be read, msg_002 still unread
    [ "$(_get_read_status testagent msg_001)" = "true" ]
    [ "$(_get_read_status testagent msg_002)" = "false" ]
    # msg_003 was already read, unchanged
    [ "$(_get_read_status testagent msg_003)" = "true" ]
}

@test "mark all unread messages when msg_id omitted" {
    _create_inbox testagent

    run bash "$TEST_SCRIPT" testagent
    [ "$status" -eq 0 ]
    [[ "$output" == *"Marked 2 message"* ]]

    # All should be read now
    [ "$(_get_read_status testagent msg_001)" = "true" ]
    [ "$(_get_read_status testagent msg_002)" = "true" ]
    [ "$(_get_read_status testagent msg_003)" = "true" ]
}

@test "does not alter read:false text inside message content" {
    cat > "$TEST_ROOT/queue/inbox/testagent.yaml" << 'YAML'
messages:
- id: msg_001
  from: karo
  timestamp: '2026-03-25T10:00:00'
  type: task_assigned
  content: |
    literal payload:
    read: false
  read: false
- id: msg_002
  from: karo
  timestamp: '2026-03-25T10:01:00'
  type: wake_up
  content: |
    another literal:
    read: false
  read: false
YAML

    run bash "$TEST_SCRIPT" testagent msg_001
    [ "$status" -eq 0 ]
    [[ "$output" == *"Marked 1 message"* ]]
    [ "$(_get_read_status testagent msg_001)" = "true" ]
    [ "$(_get_read_status testagent msg_002)" = "false" ]
    [ "$(grep -c '^    read: false$' "$TEST_ROOT/queue/inbox/testagent.yaml")" -eq 2 ]

    run bash "$TEST_SCRIPT" testagent
    [ "$status" -eq 0 ]
    [[ "$output" == *"Marked 1 message"* ]]
    [ "$(_get_read_status testagent msg_002)" = "true" ]
    [ "$(grep -c '^    read: false$' "$TEST_ROOT/queue/inbox/testagent.yaml")" -eq 2 ]
}

@test "nonexistent msg_id returns success with informational message" {
    _create_inbox testagent

    run bash "$TEST_SCRIPT" testagent msg_nonexistent
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found or already read"* ]]

    # Original messages unchanged
    [ "$(_get_read_status testagent msg_001)" = "false" ]
    [ "$(_get_read_status testagent msg_002)" = "false" ]
}

@test "idempotent: re-marking already read message succeeds" {
    _create_inbox testagent

    # Mark msg_003 which is already read:true
    run bash "$TEST_SCRIPT" testagent msg_003
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found or already read"* ]]

    # State unchanged
    [ "$(_get_read_status testagent msg_003)" = "true" ]
    [ "$(_get_read_status testagent msg_001)" = "false" ]
}

@test "missing inbox file returns exit 0 with message" {
    # No inbox file created for this agent
    run bash "$TEST_SCRIPT" nonexistentagent
    [ "$status" -eq 0 ]
    [[ "$output" == *"No inbox file"* ]]
}

@test "empty agent_id argument shows usage and exits 1" {
    run bash "$TEST_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "inbox with no messages returns success" {
    # Create empty inbox
    echo "messages: []" > "$TEST_ROOT/queue/inbox/testagent.yaml"

    run bash "$TEST_SCRIPT" testagent
    [ "$status" -eq 0 ]
    [[ "$output" == *"No messages"* ]] || [[ "$output" == *"No unread"* ]]
}

@test "bulletin_notify mark-read auto-confirms referenced bulletin entry" {
    cat > "$TEST_ROOT/queue/inbox/saizo.yaml" <<'YAML'
messages:
- id: msg_blt
  from: karo
  timestamp: '2026-05-12T12:00:00'
  type: bulletin_notify
  content: '掲示板新規投稿(blt_test_001): 確認せよ'
  read: false
YAML
    cat > "$TEST_ROOT/queue/bulletin_board.yaml" <<'YAML'
entries:
- id: 'blt_test_001'
  content: |-
    確認せよ
  posted_by: 'karo'
  posted_at: '2026-05-12T12:00:00'
  requires_confirmation: false
  confirmed_by: []
  status: 'open'
YAML

    run bash "$TEST_SCRIPT" saizo msg_blt
    [ "$status" -eq 0 ]
    [[ "$output" == *"bulletin_confirmed blt_test_001"* ]]
    [[ "$output" == *"Marked 1 message"* ]]
    [ "$(_get_read_status saizo msg_blt)" = "true" ]
    [[ "$(_get_confirmed_by blt_test_001)" == *"saizo"* ]]
}

@test "bulletin_confirm failure warns but mark-read still succeeds" {
    cat > "$TEST_ROOT/queue/inbox/saizo.yaml" <<'YAML'
messages:
- id: msg_blt
  from: karo
  timestamp: '2026-05-12T12:00:00'
  type: bulletin_notify
  content: '掲示板新規投稿(blt_missing): 確認せよ'
  read: false
YAML
    cat > "$TEST_ROOT/queue/bulletin_board.yaml" <<'YAML'
entries:
- id: 'blt_other'
  content: |-
    別エントリ
  posted_by: 'karo'
  posted_at: '2026-05-12T12:00:00'
  requires_confirmation: false
  confirmed_by: []
  status: 'open'
YAML

    run bash "$TEST_SCRIPT" saizo msg_blt
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: bulletin_confirm failed for blt_missing"* ]]
    [[ "$output" == *"Marked 1 message"* ]]
    [ "$(_get_read_status saizo msg_blt)" = "true" ]
}
