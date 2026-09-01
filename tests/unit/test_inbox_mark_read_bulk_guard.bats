#!/usr/bin/env bats
# test_necessity: inbox_mark_read.sh must BLOCK (exit 2, message stays unread)
# when an agent marks a third DISTINCT message read within the bulk window,
# must still allow retries of the same id and marks spaced beyond the window,
# and must leave --auto-info untouched. Invariant guards 2026-09-01 15:44
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
}

teardown() { [ -n "${TEST_ROOT:-}" ] && rm -rf "$TEST_ROOT"; }

_read_status() {
    INBOX="$TEST_ROOT/queue/inbox/gunshi.yaml" MSG_ID="$1" python3 -c '
import os, yaml
for m in yaml.safe_load(open(os.environ["INBOX"]))["messages"]:
    if m["id"] == os.environ["MSG_ID"]:
        print("true" if m.get("read") else "false")'
}

@test "third distinct message inside the window is BLOCKed and stays unread" {
    run bash "$TEST_SCRIPT" gunshi msg_a; [ "$status" -eq 0 ]
    run bash "$TEST_SCRIPT" gunshi msg_b; [ "$status" -eq 0 ]
    run bash "$TEST_SCRIPT" gunshi msg_c
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK: bulk mark-read pattern"* ]]
    [ "$(_read_status msg_a)" = "true" ]
    [ "$(_read_status msg_b)" = "true" ]
    [ "$(_read_status msg_c)" = "false" ]
}

@test "retrying the same id does not count as bulk" {
    run bash "$TEST_SCRIPT" gunshi msg_a; [ "$status" -eq 0 ]
    run bash "$TEST_SCRIPT" gunshi msg_a
    # already read -> not-found path, but not the bulk BLOCK
    [[ "$output" != *"bulk mark-read pattern"* ]]
    run bash "$TEST_SCRIPT" gunshi msg_a
    [[ "$output" != *"bulk mark-read pattern"* ]]
    run bash "$TEST_SCRIPT" gunshi msg_b
    [ "$status" -eq 0 ]
    [ "$(_read_status msg_b)" = "true" ]
}

@test "marks spaced beyond the window pass" {
    run env INBOX_MARK_READ_BULK_WINDOW_SEC=1 bash "$TEST_SCRIPT" gunshi msg_a; [ "$status" -eq 0 ]
    run env INBOX_MARK_READ_BULK_WINDOW_SEC=1 bash "$TEST_SCRIPT" gunshi msg_b; [ "$status" -eq 0 ]
    sleep 2
    run env INBOX_MARK_READ_BULK_WINDOW_SEC=1 bash "$TEST_SCRIPT" gunshi msg_c
    [ "$status" -eq 0 ]
    [ "$(_read_status msg_c)" = "true" ]
}

@test "one call with several explicit ids is not the loop pattern" {
    run bash "$TEST_SCRIPT" gunshi msg_a msg_b msg_c msg_d
    [ "$status" -eq 0 ]
    [ "$(_read_status msg_d)" = "true" ]
}

@test "--auto-info is exempt from the bulk guard" {
    run bash "$TEST_SCRIPT" gunshi msg_a; [ "$status" -eq 0 ]
    run bash "$TEST_SCRIPT" gunshi msg_b; [ "$status" -eq 0 ]
    run bash "$TEST_SCRIPT" gunshi --auto-info
    [[ "$output" != *"bulk mark-read pattern"* ]]
}
