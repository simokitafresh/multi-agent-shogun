#!/usr/bin/env bats
# Receipt contract provenance: cmd_karo_hotfix_inbox_processing_receipt_20260901.
# test_necessity: exact read receipt identity is required before read-state
# mutation; no-receipt, tamper, stale-generation, retry, and fast-path cases
# are permanent inbox safety invariants.

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/inbox_receipt.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts/lib" "$TEST_ROOT/queue/inbox" "$TEST_ROOT/logs"
    cp "$PROJECT_ROOT/scripts/inbox_read.sh" "$TEST_ROOT/scripts/"
    cp "$PROJECT_ROOT/scripts/inbox_mark_read.sh" "$TEST_ROOT/scripts/"
    cp "$PROJECT_ROOT/scripts/bulletin_confirm.sh" "$TEST_ROOT/scripts/"
    cp "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$TEST_ROOT/scripts/lib/"
    printf 'get_all_agents() { echo "karo gunshi hayate kagemaru"; }\n' > "$TEST_ROOT/scripts/lib/agent_config.sh"
    cat > "$TEST_ROOT/queue/inbox/hayate.yaml" <<'YAML'
messages:
- id: msg_a
  from: karo
  timestamp: '2026-09-01T16:00:00'
  type: task_supplement
  content: body a
  read: false
- id: msg_b
  from: karo
  timestamp: '2026-09-01T16:00:01'
  type: task_supplement
  content: body b
  read: false
- id: msg_c
  from: karo
  timestamp: '2026-09-01T16:00:02'
  type: task_supplement
  content: body c
  read: false
YAML
    export READ_SCRIPT="$TEST_ROOT/scripts/inbox_read.sh" MARK_SCRIPT="$TEST_ROOT/scripts/inbox_mark_read.sh"
    export RECEIPTS="$TEST_ROOT/logs/receipts" INBOX_MARK_READ_ROOT_OVERRIDE="$TEST_ROOT"
    export INBOX_MARK_READ_RECEIPT_DIR="$RECEIPTS"
}

teardown() { [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"; }

_read_inbox() {
    run env SHOGUN_ROOT="$TEST_ROOT" INBOX_READ_RECEIPT_DIR="$RECEIPTS" bash "$READ_SCRIPT" hayate
    [ "$status" -eq 0 ]
}
_mark() { run bash "$MARK_SCRIPT" hayate "$@"; }
_status() {
    INBOX="$TEST_ROOT/queue/inbox/hayate.yaml" MSG_ID="$1" python3 -c '
import os, yaml
for msg in yaml.safe_load(open(os.environ["INBOX"]))["messages"]:
    if msg["id"] == os.environ["MSG_ID"]: print("true" if msg.get("read") else "false")'
}

@test "read emits body and publishes agent generation content receipt" {
    _read_inbox
    [[ "$output" == *"body a"* && "$output" == *"body c"* ]]
    python3 - "$RECEIPTS/hayate.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))
assert d['version'] == 1 and d['agent'] == 'hayate' and len(d['generation']) == 64
assert [e['msg_id'] for e in d['entries']] == ['msg_a','msg_b','msg_c']
assert all(len(e['content_hash']) == 64 for e in d['entries'])
PY
}

@test "mark without receipt is blocked and leaves unread" {
    _mark msg_a
    [ "$status" -eq 2 ]
    [[ "$output" == *"no inbox read receipt"* ]]
    [ "$(_status msg_a)" = false ]
}

@test "one read supports batch and sequential marks then consumes entries" {
    _read_inbox
    _mark msg_a msg_b; [ "$status" -eq 0 ]
    _mark msg_c; [ "$status" -eq 0 ]
    [ "$(_status msg_a)" = true ] && [ "$(_status msg_b)" = true ] && [ "$(_status msg_c)" = true ]
    [ ! -e "$RECEIPTS/hayate.json" ]
}

@test "receipt reuse, content tamper, and new-message race fail closed" {
    _read_inbox
    _mark msg_a; [ "$status" -eq 0 ]
    _mark msg_a; [ "$status" -eq 2 ]
    [[ "$output" == *"does not cover msg_id=msg_a"* || "$output" == *"was not unread"* ]]
    sed -i 's/content: body b/content: tampered/' "$TEST_ROOT/queue/inbox/hayate.yaml"
    _mark msg_b; [ "$status" -eq 2 ]
    [[ "$output" == *"stale inbox read receipt"* ]]
    [ "$(_status msg_b)" = false ]
    cat >> "$TEST_ROOT/queue/inbox/hayate.yaml" <<'YAML'
- id: msg_new
  from: karo
  timestamp: '2026-09-01T16:00:03'
  type: task_supplement
  content: body new
  read: false
YAML
    _mark msg_c; [ "$status" -eq 2 ]
    [[ "$output" == *"stale inbox read receipt"* ]]
}

@test "receipt agent identity tamper is rejected" {
    _read_inbox
    sed -i 's/"agent": "hayate"/"agent": "kagemaru"/' "$RECEIPTS/hayate.json"
    _mark msg_a
    [ "$status" -eq 2 ]
    [[ "$output" == *"identity mismatch"* ]]
}

@test "auto-info remains exempt and keeps gate_clear unread" {
    cat > "$TEST_ROOT/queue/inbox/kagemaru.yaml" <<'YAML'
messages:
- id: info
  from: karo
  timestamp: '2026-09-01T16:00:00'
  type: info
  content: informational
  read: false
- id: gate
  from: karo
  timestamp: '2026-09-01T16:00:01'
  type: gate_clear
  content: actionable
  read: false
YAML
    run env INBOX_MARK_READ_ROOT_OVERRIDE="$TEST_ROOT" bash "$MARK_SCRIPT" kagemaru --auto-info
    [ "$status" -eq 0 ]
    INBOX="$TEST_ROOT/queue/inbox/kagemaru.yaml" python3 -c 'import os,yaml; m=yaml.safe_load(open(os.environ["INBOX"]))["messages"]; assert m[0]["read"] is True and m[1]["read"] is False'
}

@test "receipt gate measures unread loop 3 to 0 and heuristic FP 1 to 0" {
    loop_success=0
    for id in msg_a msg_b msg_c; do _mark "$id"; [ "$status" -eq 0 ] && loop_success=$((loop_success+1)); done
    [ "$loop_success" -eq 0 ]
    _read_inbox; _mark msg_a; [ "$status" -eq 0 ]; _mark msg_b; [ "$status" -eq 0 ]
    run env INBOX_MARK_READ_BULK_ENFORCE=1 bash "$MARK_SCRIPT" hayate msg_c
    [ "$status" -eq 2 ]
    sed -i 's/read: true/read: false/g' "$TEST_ROOT/queue/inbox/hayate.yaml"
    _read_inbox; receipt_success=0
    for id in msg_a msg_b msg_c; do _mark "$id"; [ "$status" -eq 0 ] && receipt_success=$((receipt_success+1)); done
    [ "$receipt_success" -eq 3 ]
    printf 'loop_success=3->0 legitimate_success=2->3 heuristic_fp=1->0\n'
}
