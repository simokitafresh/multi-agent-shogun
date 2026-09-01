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

@test "review messages require a post-message review log entry while normal messages stay unchanged" {
    mkdir -p "$TEST_ROOT/queue/reports"
    touch "$TEST_ROOT/queue/reports/good_report.yaml" "$TEST_ROOT/queue/reports/stale_report.yaml"
    cat > "$TEST_ROOT/queue/inbox/hayate.yaml" <<'YAML'
messages:
- id: review_good
  from: karo
  timestamp: '2026-09-01T16:00:00+00:00'
  type: review_draft
  content: "review request report=good_report.yaml"
  read: false
- id: review_stale
  from: karo
  timestamp: '2026-09-01T16:05:00+00:00'
  type: report_review
  content: "review request report=stale_report.yaml"
  read: false
- id: normal
  from: karo
  timestamp: '2026-09-01T16:06:00+00:00'
  type: task_supplement
  content: ordinary message
  read: false
YAML
    mkdir -p "$TEST_ROOT/logs"
    cat > "$TEST_ROOT/logs/gunshi_review_log.yaml" <<'YAML'
- report: good_report.yaml
  review_type: report
  reviewed_at: '2026-09-01T16:01:00+00:00'
- report: stale_report.yaml
  review_type: report
  reviewed_at: '2026-09-01T16:04:00+00:00'
YAML
    _read_inbox
    _mark review_good
    [ "$status" -eq 0 ]
    [ "$(_status review_good)" = true ]
    _mark normal
    [ "$status" -eq 0 ]
    [ "$(_status normal)" = true ]
    _mark review_stale
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK: review not recorded"* ]]
    [ "$(_status review_stale)" = false ]
}

@test "report-less review_draft uses the canonical inbox receipt only" {
    cat > "$TEST_ROOT/queue/inbox/hayate.yaml" <<'YAML'
messages:
- id: draft_without_report
  from: karo
  timestamp: '2026-09-01T19:41:22+00:00'
  type: review_draft
  content: "draft review request with no report"
  read: false
YAML
    _read_inbox
    _mark draft_without_report
    [ "$status" -eq 0 ]
    [ "$(_status draft_without_report)" = true ]
}

@test "structured report_path is used when an existing report requires review log" {
    mkdir -p "$TEST_ROOT/queue/reports"
    touch "$TEST_ROOT/queue/reports/structured_report.yaml"
    cat > "$TEST_ROOT/queue/inbox/hayate.yaml" <<'YAML'
messages:
- id: structured_review
  from: karo
  timestamp: '2026-09-01T19:00:00+00:00'
  type: report_review
  report_path: queue/reports/structured_report.yaml
  read: false
YAML
    cat > "$TEST_ROOT/logs/gunshi_review_log.yaml" <<'YAML'
- report: structured_report.yaml
  reviewed_at: '2026-09-01T19:01:00+00:00'
YAML
    _read_inbox
    _mark structured_review
    [ "$status" -eq 0 ]
    [ "$(_status structured_review)" = true ]
}

@test "review_draft with an existing report still uses only the canonical receipt" {
    mkdir -p "$TEST_ROOT/queue/reports"
    touch "$TEST_ROOT/queue/reports/draft_report.yaml"
    cat > "$TEST_ROOT/queue/inbox/hayate.yaml" <<'YAML'
messages:
- id: draft_with_report
  from: karo
  timestamp: '2026-09-01T19:00:00+00:00'
  type: review_draft
  report_path: queue/reports/draft_report.yaml
  read: false
YAML
    _read_inbox
    _mark draft_with_report
    [ "$status" -eq 0 ]
    [ "$(_status draft_with_report)" = true ]
}

@test "report_review treats a timezone-naive message timestamp as JST" {
    mkdir -p "$TEST_ROOT/queue/reports"
    touch "$TEST_ROOT/queue/reports/jst_report.yaml"
    cat > "$TEST_ROOT/queue/inbox/hayate.yaml" <<'YAML'
messages:
- id: jst_review
  from: karo
  timestamp: '2026-09-01T19:00:00'
  type: report_review
  report_path: queue/reports/jst_report.yaml
  read: false
YAML
    cat > "$TEST_ROOT/logs/gunshi_review_log.yaml" <<'YAML'
- report: jst_report.yaml
  reviewed_at: '2026-09-01T10:00:00+00:00'
YAML
    _read_inbox
    _mark jst_review
    [ "$status" -eq 0 ]
    [ "$(_status jst_review)" = true ]
}

@test "report_review with an existing report and no review log is blocked" {
    mkdir -p "$TEST_ROOT/queue/reports"
    touch "$TEST_ROOT/queue/reports/unreviewed_report.yaml"
    cat > "$TEST_ROOT/queue/inbox/hayate.yaml" <<'YAML'
messages:
- id: unreviewed_report
  from: karo
  timestamp: '2026-09-01T19:00:00+00:00'
  type: report_review
  report_path: queue/reports/unreviewed_report.yaml
  read: false
YAML
    _read_inbox
    _mark unreviewed_report
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK: review not recorded"* ]]
    [ "$(_status unreviewed_report)" = false ]
}

@test "review log entry may match standard report filename through cmd_id" {
    cat > "$TEST_ROOT/queue/inbox/hayate.yaml" <<'YAML'
messages:
- id: review_cmd
  from: karo
  timestamp: '2026-09-01T16:00:00+00:00'
  type: report_review
  content: "review request report=hayate_report_cmd_fixture.yaml"
  read: false
YAML
    cat > "$TEST_ROOT/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_fixture
  review:
    reviewed_at: '2026-09-01T16:01:00+00:00'
YAML
    _read_inbox
    _mark review_cmd
    [ "$status" -eq 0 ]
    [ "$(_status review_cmd)" = true ]
}
