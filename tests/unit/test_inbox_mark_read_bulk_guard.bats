#!/usr/bin/env bats
# Receipt contract provenance: cmd_karo_hotfix_inbox_processing_receipt_20260901.
# test_necessity: the bulk heuristic BLOCKs by default (INBOX_MARK_READ_BULK_ENFORCE
# default flipped 0->1 2026-09-04 06:28, T3-S-54, after the 09-01 anti-pattern
# recurred and caused a 3-GATE 4.5h deadlock); INBOX_MARK_READ_BULK_ENFORCE=0
# restores the legacy observe-only WARN for explicit incident probes. Every
# normal mark requires a read receipt and --auto-info remains exempt.
# Invariant guards 2026-09-01 15:44/15:49, 2026-09-04 06:28.
# (gunshi `grep read:false | while read id; do inbox_mark_read.sh gunshi $id`
# consumed the cmd_4436 review request and the kagemaru v3 formal review, 8 resends).

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/imr_bulk.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts/lib" "$TEST_ROOT/queue/inbox" "$TEST_ROOT/logs"
    cp "$PROJECT_ROOT/scripts/inbox_mark_read.sh" "$TEST_ROOT/scripts/"
    cp "$PROJECT_ROOT/scripts/inbox_read.sh" "$TEST_ROOT/scripts/"
    cp "$PROJECT_ROOT/scripts/bulletin_confirm.sh" "$TEST_ROOT/scripts/"
    cp "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$TEST_ROOT/scripts/lib/"
    printf 'get_all_agents() { echo "karo gunshi hayate"; }\n' > "$TEST_ROOT/scripts/lib/agent_config.sh"
    cat > "$TEST_ROOT/queue/inbox/gunshi.yaml" <<'YAML'
messages:
- id: msg_a
  from: karo
  timestamp: '2026-09-01T15:40:00'
  type: report_review
  content: review a
  read: false
- id: msg_b
  from: karo
  timestamp: '2026-09-01T15:40:01'
  type: report_review
  content: review b
  read: false
- id: msg_c
  from: karo
  timestamp: '2026-09-01T15:40:02'
  type: review_draft
  content: review c
  read: false
- id: msg_d
  from: karo
  timestamp: '2026-09-01T15:40:03'
  type: review_draft
  content: review d
  read: false
YAML
    export TEST_SCRIPT="$TEST_ROOT/scripts/inbox_mark_read.sh"
    export TEST_READ_SCRIPT="$TEST_ROOT/scripts/inbox_read.sh"
    export INBOX_MARK_READ_ROOT_OVERRIDE="$TEST_ROOT"
    export INBOX_MARK_READ_RECEIPT_DIR="$TEST_ROOT/receipts"
}

teardown() { [ -n "${TEST_ROOT:-}" ] && rm -rf "$TEST_ROOT"; }

_read_status() {
    INBOX="$TEST_ROOT/queue/inbox/gunshi.yaml" MSG_ID="$1" python3 -c '
import os, yaml
for m in yaml.safe_load(open(os.environ["INBOX"]))["messages"]:
    if m["id"] == os.environ["MSG_ID"]:
        print("true" if m.get("read") else "false")'
}

_read_inbox() {
    run env SHOGUN_ROOT="$TEST_ROOT" INBOX_READ_RECEIPT_DIR="$TEST_ROOT/receipts" \
        bash "$TEST_READ_SCRIPT" gunshi
    [ "$status" -eq 0 ]
}

@test "default: third distinct message inside the window is BLOCKed (bulk-pattern enforced by default)" {
    _read_inbox
    # 2026-09-04 06:28 将軍 D0(T3-S-54): the 09-01 anti-pattern recurred and
    # caused a 3-GATE 4.5h deadlock, so the default flipped from
    # observe-only WARN to BLOCK; INBOX_MARK_READ_BULK_ENFORCE=0 remains the
    # explicit escape hatch for a legitimate fast sequence (see the
    # "opt-out mode" test below).
    run bash "$TEST_SCRIPT" gunshi msg_a; [ "$status" -eq 0 ]
    run bash "$TEST_SCRIPT" gunshi msg_b; [ "$status" -eq 0 ]
    run bash "$TEST_SCRIPT" gunshi msg_c
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK: bulk mark-read pattern"* ]]
    [ "$(_read_status msg_c)" = "false" ]
}

@test "opt-out mode (INBOX_MARK_READ_BULK_ENFORCE=0) restores observe-only WARN" {
    _read_inbox
    # karo REJECT 2026-09-01 15:49: gate notice -> LGTM ACCEPT -> accept_report check is a
    # legitimate 3-in-10s sequence; the explicit opt-out lets that sequence
    # through without weakening the BLOCK-by-default production contract.
    run bash "$TEST_SCRIPT" gunshi msg_a; [ "$status" -eq 0 ]
    run bash "$TEST_SCRIPT" gunshi msg_b; [ "$status" -eq 0 ]
    run env INBOX_MARK_READ_BULK_ENFORCE=0 bash "$TEST_SCRIPT" gunshi msg_c
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN(bulk-pattern)"* ]]
    [[ "$output" != *"BLOCK"* ]]
    [ "$(_read_status msg_c)" = "true" ]
    [ -s "$TEST_ROOT/logs/inbox_mark_read_ledger/gunshi.warn.tsv" ]
}

@test "same-id retry remains a non-bulk failure after receipt consumption" {
    _read_inbox
    run bash "$TEST_SCRIPT" gunshi msg_a
    [ "$status" -eq 0 ]
    run bash "$TEST_SCRIPT" gunshi msg_a
    [ "$status" -eq 2 ]
    [[ "$output" != *"bulk mark-read pattern"* ]]
}

@test "marks spaced beyond the window pass" {
    _read_inbox
    run env INBOX_MARK_READ_BULK_WINDOW_SEC=1 bash "$TEST_SCRIPT" gunshi msg_a; [ "$status" -eq 0 ]
    run env INBOX_MARK_READ_BULK_WINDOW_SEC=1 bash "$TEST_SCRIPT" gunshi msg_b; [ "$status" -eq 0 ]
    sleep 2
    run env INBOX_MARK_READ_BULK_WINDOW_SEC=1 bash "$TEST_SCRIPT" gunshi msg_c
    [ "$status" -eq 0 ]
    [ "$(_read_status msg_c)" = "true" ]
}

@test "one call with several explicit ids is not the loop pattern" {
    _read_inbox
    run bash "$TEST_SCRIPT" gunshi msg_a msg_b msg_c msg_d
    [ "$status" -eq 0 ]
    [ "$(_read_status msg_d)" = "true" ]
}

@test "--auto-info is exempt from the bulk guard" {
    _read_inbox
    run bash "$TEST_SCRIPT" gunshi msg_a; [ "$status" -eq 0 ]
    run bash "$TEST_SCRIPT" gunshi msg_b; [ "$status" -eq 0 ]
    run bash "$TEST_SCRIPT" gunshi --auto-info
    [[ "$output" != *"bulk mark-read pattern"* ]]
}
