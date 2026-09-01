#!/usr/bin/env bats
# test_necessity: Bulk override cannot consume later messages, and block scalar body indentation never creates a message record boundary; violation is BLOCK.
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
    cp "$PROJECT_ROOT/scripts/inbox_read.sh" "$TEST_ROOT/scripts/inbox_read.sh"
    cp "$SOURCE_CONFIRM_SCRIPT" "$TEST_ROOT/scripts/bulletin_confirm.sh"
    cp "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$TEST_ROOT/scripts/lib/yaml_field_set.sh"
    chmod +x "$TEST_ROOT/scripts/inbox_mark_read.sh"
    chmod +x "$TEST_ROOT/scripts/bulletin_confirm.sh"
    chmod +x "$TEST_ROOT/scripts/lib/yaml_field_set.sh"
    cat > "$TEST_ROOT/scripts/lib/agent_config.sh" <<'SH'
get_all_agents() {
    echo "karo gunshi hayate kagemaru hanzo saizo kotaro tobisaru"
}
SH

    export TEST_SCRIPT="$TEST_ROOT/scripts/inbox_mark_read.sh"
    export TEST_READ_SCRIPT="$TEST_ROOT/scripts/inbox_read.sh"
    export INBOX_MARK_READ_ROOT_OVERRIDE="$TEST_ROOT"
    export INBOX_MARK_READ_RECEIPT_DIR="$TEST_ROOT/receipts"
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

_read_inbox() {
    local agent="$1"
    run env SHOGUN_ROOT="$TEST_ROOT" INBOX_READ_RECEIPT_DIR="$TEST_ROOT/receipts" \
        bash "$TEST_READ_SCRIPT" "$agent"
    [ "$status" -eq 0 ]
}

@test "mark specific msg_id as read" {
    _create_inbox testagent
    _read_inbox testagent

    run bash "$TEST_SCRIPT" testagent msg_001
    [ "$status" -eq 0 ]
    [[ "$output" == *"Marked 1 message"* ]]

    # msg_001 should be read, msg_002 still unread
    [ "$(_get_read_status testagent msg_001)" = "true" ]
    [ "$(_get_read_status testagent msg_002)" = "false" ]
    # msg_003 was already read, unchanged
    [ "$(_get_read_status testagent msg_003)" = "true" ]
}

# test_necessity: an unprocessed shogun task_assigned must stay unread in the
# commander inbox; otherwise the command can be lost without a durable trace.
@test "karo self task_assigned without processing evidence is blocked" {
    mkdir -p "$TEST_ROOT/queue/tasks"
    printf 'task:\n  status: idle\n' > "$TEST_ROOT/queue/tasks/karo.yaml"
    cat > "$TEST_ROOT/queue/inbox/karo.yaml" <<'YAML'
messages:
- id: msg_shogun_001
  from: shogun
  timestamp: '2026-08-28T14:00:00'
  type: task_assigned
  content: 'cmd_t122_guard_001 process this task'
  read: false
YAML
    _read_inbox karo
    run env INBOX_MARK_READ_ROOT_OVERRIDE="$TEST_ROOT" bash "$TEST_SCRIPT" karo msg_shogun_001
    [ "$status" -eq 2 ]
    [[ "$output" == *"without task YAML, bulletin, or reply-inbox processing evidence"* ]]
    grep -q 'read: false' "$TEST_ROOT/queue/inbox/karo.yaml"
}

# test_necessity: an updated matching Karo task YAML is an accepted processing
# trace, while the normal explicit-ID/flock path remains the same.
@test "karo self task_assigned with matching task YAML evidence is allowed" {
    mkdir -p "$TEST_ROOT/queue/tasks"
    cat > "$TEST_ROOT/queue/tasks/karo.yaml" <<'YAML'
task:
  task_id: cmd_t122_guard_002_normal
  status: in_progress
YAML
    cat > "$TEST_ROOT/queue/inbox/karo.yaml" <<'YAML'
messages:
- id: msg_shogun_002
  from: shogun
  timestamp: '2026-08-28T14:00:00'
  type: task_assigned
  content: 'cmd_t122_guard_002_normal process this task'
  read: false
YAML
    _read_inbox karo
    run env INBOX_MARK_READ_ROOT_OVERRIDE="$TEST_ROOT" bash "$TEST_SCRIPT" karo msg_shogun_002
    [ "$status" -eq 0 ]
    [ "$(_get_read_status karo msg_shogun_002)" = "true" ]
}

# test_necessity: bulletin processing is an alternate durable trace accepted
# by the commander guard without changing ninja/normal acknowledgement.
@test "karo self task_assigned with bulletin evidence is allowed" {
    mkdir -p "$TEST_ROOT/queue/tasks"
    printf 'task:\n  status: idle\n' > "$TEST_ROOT/queue/tasks/karo.yaml"
    cat > "$TEST_ROOT/queue/inbox/karo.yaml" <<'YAML'
messages:
- id: msg_shogun_003
  from: shogun
  timestamp: '2026-08-28T14:00:00'
  type: task_assigned
  content: 'cmd_t122_guard_003 process this task'
  read: false
YAML
    printf 'entries:\n- id: bulletin_t122_003\n  content: cmd_t122_guard_003\n' > "$TEST_ROOT/queue/bulletin_board.yaml"
    _read_inbox karo
    run env INBOX_MARK_READ_ROOT_OVERRIDE="$TEST_ROOT" bash "$TEST_SCRIPT" karo msg_shogun_003
    [ "$status" -eq 0 ]
    [ "$(_get_read_status karo msg_shogun_003)" = "true" ]
}

@test "msg_id omission blocks when unread messages exist" {
    _create_inbox testagent
    _read_inbox testagent

    run bash "$TEST_SCRIPT" testagent
    [ "$status" -eq 2 ]
    [[ "$output" == *"msg_id is required"* ]]

    [ "$(_get_read_status testagent msg_001)" = "false" ]
    [ "$(_get_read_status testagent msg_002)" = "false" ]
    [ "$(_get_read_status testagent msg_003)" = "true" ]
}

@test "bulk override cannot consume messages that arrived after inbox read" {
    _create_inbox testagent
    _read_inbox testagent

    run env INBOX_MARK_READ_ALLOW_ALL=1 bash "$TEST_SCRIPT" testagent
    [ "$status" -eq 2 ]
    [[ "$output" == *"Bulk acknowledgement is forbidden"* ]]

    [ "$(_get_read_status testagent msg_001)" = "false" ]
    [ "$(_get_read_status testagent msg_002)" = "false" ]
    [ "$(_get_read_status testagent msg_003)" = "true" ]
}

@test "queue/inbox symlink marks real target without symlink lock file" {
    local real_inbox="$TEST_ROOT/real_inbox"
    rm -rf "$TEST_ROOT/queue/inbox"
    mkdir -p "$real_inbox"
    ln -s "$real_inbox" "$TEST_ROOT/queue/inbox"
    _create_inbox testagent
    _read_inbox testagent

    run bash "$TEST_SCRIPT" testagent msg_001
    [ "$status" -eq 0 ]
    [[ "$output" == *"Marked 1 message"* ]]

    [ "$(_get_read_status testagent msg_001)" = "true" ]
    [ -f "$real_inbox/testagent.yaml" ]
    # The canonical real-file lock may be reachable through the symlink; the
    # invariant is that no lock is created for the symlink directory itself.
    [ ! -e "$TEST_ROOT/queue/inbox.lock" ]
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
    _read_inbox testagent

    run bash "$TEST_SCRIPT" testagent msg_001
    [ "$status" -eq 0 ]
    [[ "$output" == *"Marked 1 message"* ]]
    [ "$(_get_read_status testagent msg_001)" = "true" ]
    [ "$(_get_read_status testagent msg_002)" = "false" ]
    [ "$(grep -c '^    read: false$' "$TEST_ROOT/queue/inbox/testagent.yaml")" -eq 2 ]

    run bash "$TEST_SCRIPT" testagent msg_002
    [ "$status" -eq 0 ]
    [[ "$output" == *"Marked 1 message"* ]]
    [ "$(_get_read_status testagent msg_002)" = "true" ]
    [ "$(grep -c '^    read: false$' "$TEST_ROOT/queue/inbox/testagent.yaml")" -eq 2 ]
}

@test "nested bullets and field order mark only the selected record" {
    cat > "$TEST_ROOT/queue/inbox/testagent.yaml" <<'YAML'
messages:
- content: |-
    - id: nested_fake
    - bullet
      read: false
  type: task_assigned
  read: false
  id: msg_id_after_content
- id: msg_id_before_content
  content: |-
    - id: another_fake
    - bullet two
  type: wake_up
  read: false
YAML
    _read_inbox testagent

    run bash "$TEST_SCRIPT" testagent msg_id_after_content
    [ "$status" -eq 0 ]
    [[ "$output" == *"Marked 1 message"* ]]
    [ "$(_get_read_status testagent msg_id_after_content)" = "true" ]
    [ "$(_get_read_status testagent msg_id_before_content)" = "false" ]
    [ "$(grep -c '^    - ' "$TEST_ROOT/queue/inbox/testagent.yaml")" -eq 4 ]
    python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); assert len(d["messages"]) == 2' "$TEST_ROOT/queue/inbox/testagent.yaml"
}

@test "nonexistent msg_id returns nonzero so callers can detect the mismatch" {
    _create_inbox testagent
    _read_inbox testagent

    run bash "$TEST_SCRIPT" testagent msg_nonexistent
    [ "$status" -eq 2 ]
    [[ "$output" == *"does not cover msg_id=msg_nonexistent"* ]]

    # Original messages unchanged
    [ "$(_get_read_status testagent msg_001)" = "false" ]
    [ "$(_get_read_status testagent msg_002)" = "false" ]
}

@test "re-marking already read message returns nonzero so callers can detect stale state" {
    _create_inbox testagent
    _read_inbox testagent

    # Mark msg_003 which is already read:true
    run bash "$TEST_SCRIPT" testagent msg_003
    [ "$status" -eq 2 ]
    [[ "$output" == *"does not cover msg_id=msg_003"* ]]

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
    _read_inbox saizo

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
    _read_inbox saizo

    run bash "$TEST_SCRIPT" saizo msg_blt
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: bulletin_confirm failed for blt_missing"* ]]
    [[ "$output" == *"Marked 1 message"* ]]
    [ "$(_get_read_status saizo msg_blt)" = "true" ]
}

@test "複数msg_id同時指定で全件がmarkされる (2026-07-07 軍師発見バグ再発防止)" {
    _create_inbox hayate
    _read_inbox hayate

    run bash "$TEST_SCRIPT" hayate msg_001 msg_002
    [ "$status" -eq 0 ]
    [ "$(_get_read_status hayate msg_001)" = "true" ]
    [ "$(_get_read_status hayate msg_002)" = "true" ]
}

@test "batch ACK marks only snapshot IDs and preserves later unread message" {
    _create_inbox hayate
    _read_inbox hayate

    run bash "$TEST_SCRIPT" hayate msg_001 msg_001
    [ "$status" -eq 0 ]
    [[ "$output" == *"Marked 1 message"* ]]
    [ "$(_get_read_status hayate msg_001)" = "true" ]
    [ "$(_get_read_status hayate msg_002)" = "false" ]
    [ "$(_get_read_status hayate msg_003)" = "true" ]
}

@test "batch ACK confirms every selected bulletin notification" {
    cat > "$TEST_ROOT/queue/inbox/saizo.yaml" <<'YAML'
messages:
- id: msg_blt_1
  type: bulletin_notify
  content: '掲示板新規投稿(blt_test_001): 確認せよ'
  read: false
- id: msg_blt_2
  type: bulletin_notify
  content: '掲示板新規投稿(blt_test_002): 確認せよ'
  read: false
YAML
    cat > "$TEST_ROOT/queue/bulletin_board.yaml" <<'YAML'
entries:
- id: 'blt_test_001'
  confirmed_by: []
- id: 'blt_test_002'
  confirmed_by: []
YAML
    _read_inbox saizo

    run bash "$TEST_SCRIPT" saizo msg_blt_1 msg_blt_2
    [ "$status" -eq 0 ]
    [[ "$(_get_confirmed_by blt_test_001)" == *"saizo"* ]]
    [[ "$(_get_confirmed_by blt_test_002)" == *"saizo"* ]]
}

@test "mark-read records acknowledged_at on active task when empty" {
    _create_inbox hanzo
    mkdir -p "$TEST_ROOT/queue/tasks"
    cat > "$TEST_ROOT/queue/tasks/hanzo.yaml" <<'YAML'
task:
  parent_cmd: cmd_999
  status: assigned
  acknowledged_at: ''
YAML
    _read_inbox hanzo

    run bash "$TEST_SCRIPT" hanzo msg_001
    [ "$status" -eq 0 ]

    run python3 - <<PY
import re
import yaml
data = yaml.safe_load(open("$TEST_ROOT/queue/tasks/hanzo.yaml"))
ack = str(data["task"].get("acknowledged_at", ""))
assert re.match(r"^202[0-9]-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$", ack), ack
print("ACK_TS_OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACK_TS_OK"* ]]
}

@test "mark-read does not overwrite existing acknowledged_at" {
    _create_inbox hanzo
    mkdir -p "$TEST_ROOT/queue/tasks"
    cat > "$TEST_ROOT/queue/tasks/hanzo.yaml" <<'YAML'
task:
  parent_cmd: cmd_999
  status: in_progress
  acknowledged_at: '2026-07-08T09:00:00'
YAML
    _read_inbox hanzo

    run bash "$TEST_SCRIPT" hanzo msg_001
    [ "$status" -eq 0 ]

    run python3 - <<PY
import yaml
data = yaml.safe_load(open("$TEST_ROOT/queue/tasks/hanzo.yaml"))
assert data["task"]["acknowledged_at"] == "2026-07-08T09:00:00"
print("ACK_TS_PRESERVED")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACK_TS_PRESERVED"* ]]
}

# test_necessity: Every YAML null scalar spelling must be timestamped exactly
# once, while an existing timestamp and inactive task remain unchanged.
@test "mark-read treats YAML null scalars as missing and skips inactive tasks" {
    mkdir -p "$TEST_ROOT/queue/tasks"

    for null_value in null Null NULL '~' ''; do
        _create_inbox hanzo
        if [ -n "$null_value" ]; then
            printf "task:\n  parent_cmd: cmd_999\n  status: assigned\n  acknowledged_at: %s\n" "$null_value" > "$TEST_ROOT/queue/tasks/hanzo.yaml"
        else
            cat > "$TEST_ROOT/queue/tasks/hanzo.yaml" <<'YAML'
task:
  parent_cmd: cmd_999
  status: assigned
  acknowledged_at:
YAML
        fi

        _read_inbox hanzo
        run bash "$TEST_SCRIPT" hanzo msg_001
        [ "$status" -eq 0 ] || {
            echo "null_value=${null_value:-<empty>} validation_output=$output"
            return 1
        }
        run python3 - <<PY
import re
import yaml
data = yaml.safe_load(open("$TEST_ROOT/queue/tasks/hanzo.yaml"))
ack_value = data["task"].get("acknowledged_at", "")
ack = ack_value.isoformat() if hasattr(ack_value, "isoformat") else str(ack_value)
assert re.match(r"^202[0-9]-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$", ack), ack
PY
        [ "$status" -eq 0 ] || {
            echo "null_value=${null_value:-<empty>} validation_output=$output"
            return 1
        }
    done

    _create_inbox hanzo
    cat > "$TEST_ROOT/queue/tasks/hanzo.yaml" <<'YAML'
task:
  parent_cmd: cmd_999
  status: done
  acknowledged_at: null
YAML
    _read_inbox hanzo
    run bash "$TEST_SCRIPT" hanzo msg_001
    [ "$status" -eq 0 ]
    run python3 - <<PY
import yaml
data = yaml.safe_load(open("$TEST_ROOT/queue/tasks/hanzo.yaml"))
assert data["task"]["acknowledged_at"] is None
PY
    [ "$status" -eq 0 ]
}

# test_necessity: gate_clear is an actionable completion event and must remain
# unread for the recipient's self-drive, while the four informational types
# continue to be auto-acknowledged and digested.
@test "auto-info preserves gate_clear and acknowledges informational types" {
    cat > "$TEST_ROOT/queue/inbox/alpha.yaml" <<'YAML'
messages:
- id: gate
  from: karo
  type: gate_clear
  timestamp: '2026-08-09T00:00:00'
  content: done
  read: false
- id: info
  from: karo
  type: info
  timestamp: '2026-08-09T00:00:00'
  content: info
  read: false
- id: heartbeat
  from: karo
  type: heartbeat
  timestamp: '2026-08-09T00:00:00'
  content: heartbeat
  read: false
- id: status
  from: karo
  type: status_update
  timestamp: '2026-08-09T00:00:00'
  content: status
  read: false
- id: retro
  from: karo
  type: retro_answer
  timestamp: '2026-08-09T00:00:00'
  content: retro
  read: false
YAML

    run env INBOX_MARK_READ_ROOT_OVERRIDE="$TEST_ROOT" bash "$TEST_SCRIPT" alpha --auto-info
    [ "$status" -eq 0 ]
    [ "$(_get_read_status alpha gate)" = "false" ]
    [ "$(_get_read_status alpha info)" = "true" ]
    [ "$(_get_read_status alpha heartbeat)" = "true" ]
    [ "$(_get_read_status alpha status)" = "true" ]
    [ "$(_get_read_status alpha retro)" = "true" ]
    run python3 - "$TEST_ROOT/logs/inbox_info_digest.jsonl" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1])]
assert {row['msg_id'] for row in rows} == {'info', 'heartbeat', 'status', 'retro'}
assert all(row['type'] != 'gate_clear' for row in rows)
print('gate_clear_auto_ack=0 info_auto_ack=4')
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"gate_clear_auto_ack=0 info_auto_ack=4"* ]]
}
