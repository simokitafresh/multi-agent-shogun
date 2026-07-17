#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TEST_ROOT="$BATS_TEST_TMPDIR/root"
  LOG_DIR="$BATS_TEST_TMPDIR/logs"
  mkdir -p "$TEST_ROOT/queue/inbox"
}

@test "inbox_read emits the inbox and records a compatible read receipt" {
  printf 'messages: []\n' > "$TEST_ROOT/queue/inbox/karo.yaml"

  run env SHOGUN_ROOT="$TEST_ROOT" INBOX_READ_LOG_DIR="$LOG_DIR" \
    bash "$REPO_ROOT/scripts/inbox_read.sh" karo

  [ "$status" -eq 0 ]
  [ "$output" = "messages: []" ]
  [ "$(cat "$LOG_DIR/claude_read_log_karo.txt")" = "queue/inbox/karo.yaml" ]
}

@test "inbox_read does not record a receipt when the inbox is missing" {
  run env SHOGUN_ROOT="$TEST_ROOT" INBOX_READ_LOG_DIR="$LOG_DIR" \
    bash "$REPO_ROOT/scripts/inbox_read.sh" karo

  [ "$status" -eq 1 ]
  [[ "$output" == *"inbox not found"* ]]
  [ ! -e "$LOG_DIR/claude_read_log_karo.txt" ]
}

@test "inbox_read rejects unsafe agent ids" {
  run env SHOGUN_ROOT="$TEST_ROOT" INBOX_READ_LOG_DIR="$LOG_DIR" \
    bash "$REPO_ROOT/scripts/inbox_read.sh" '../karo'

  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid agent_id"* ]]
  [ ! -e "$LOG_DIR/claude_read_log_../karo.txt" ]
}

@test "triage orders P0 P1 P2, preserves all messages, and records one receipt" {
  cat > "$TEST_ROOT/queue/inbox/karo.yaml" <<'YAML'
messages:
  - {id: same-b, type: unknown_kind, timestamp: '2026-07-17T10:00:00', content: "line1\nline2", read: false}
  - {id: p1, type: task_assigned, timestamp: '2026-07-17T11:00:00', content: task, read: false}
  - {id: p0, type: notice, timestamp: '2026-07-17T12:00:00', content: urgent, action_required: true, read: false}
  - {id: same-a, type: unknown_kind, timestamp: '2026-07-17T10:00:00', content: ordinary, read: false}
YAML

  run env SHOGUN_ROOT="$TEST_ROOT" INBOX_READ_LOG_DIR="$LOG_DIR" \
    INBOX_TRIAGE_NOW='2026-07-17T12:30:00' bash "$REPO_ROOT/scripts/inbox_read.sh" karo --triage

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c '^  priority: P')" -eq 4 ]
  [ "$(printf '%s' "$output" | grep -c 'id: p0$')" -eq 2 ]
  [[ "$output" == *$'id: same-a\n  priority: P2'* ]]
  [[ "$output" == *$'id: same-b\n  priority: P2'* ]]
  [[ "$output" == *"line1"* ]]
  [[ "$output" == *"line2"* ]]
  [ "$(wc -l < "$LOG_DIR/claude_read_log_karo.txt")" -eq 1 ]
}

@test "triage promotes unread aged messages deterministically" {
  cat > "$TEST_ROOT/queue/inbox/karo.yaml" <<'YAML'
messages:
  - {id: aged-p1, type: task_assigned, timestamp: '2026-07-17T07:59:59', content: old task, read: false}
  - {id: aged-p2, type: unknown_kind, timestamp: '2026-07-16T11:59:59', content: old note, read: false}
YAML

  run env SHOGUN_ROOT="$TEST_ROOT" INBOX_READ_LOG_DIR="$LOG_DIR" \
    INBOX_TRIAGE_NOW='2026-07-17T12:00:00' bash "$REPO_ROOT/scripts/inbox_read.sh" karo --triage

  [ "$status" -eq 0 ]
  [[ "$output" == *$'id: aged-p1\n  priority: P0'* ]]
  [[ "$output" == *$'id: aged-p2\n  priority: P1'* ]]
}

@test "triage fails closed on malformed YAML without a receipt" {
  printf 'messages: [\n' > "$TEST_ROOT/queue/inbox/karo.yaml"

  run env SHOGUN_ROOT="$TEST_ROOT" INBOX_READ_LOG_DIR="$LOG_DIR" \
    bash "$REPO_ROOT/scripts/inbox_read.sh" karo --triage

  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed inbox YAML"* ]]
  [ ! -e "$LOG_DIR/claude_read_log_karo.txt" ]
}

@test "15-message fixture has lossless IDs and no missed action-required header" {
  cat > "$TEST_ROOT/queue/inbox/karo.yaml" <<'YAML'
messages:
  - {id: msg-p2-a, type: notice, timestamp: '2026-07-17T12:00:00', content: ordinary notice, read: false}
  - {id: msg-p1-a, type: task_assigned, timestamp: '2026-07-17T12:01:00', content: assigned task, read: false}
  - {id: msg-p0-a, type: escalation, timestamp: '2026-07-17T12:02:00', content: escalation, read: false}
  - {id: msg-p2-b, type: unknown_kind, timestamp: '2026-07-17T12:03:00', content: "unknown\nmultiline", read: false}
  - {id: msg-p0-b, type: notice, timestamp: '2026-07-17T12:04:00', content: explicit action, action_required: true, read: false}
  - {id: msg-p1-b, type: review_request, timestamp: '2026-07-17T12:05:00', content: review, read: false}
  - {id: msg-p2-c, type: notice, timestamp: '2026-07-17T12:06:00', content: read item, read: true}
  - {id: msg-p1-aged, type: unknown_kind, timestamp: '2026-07-16T12:00:00', content: aged ordinary, read: false}
  - {id: msg-p0-aged, type: task_supplement, timestamp: '2026-07-17T07:00:00', content: aged task, read: false}
  - {id: msg-p2-d, type: recovery, timestamp: '2026-07-17T12:09:00', content: recovery, read: false}
  - {id: msg-p1-c, type: verify_request, timestamp: '2026-07-17T12:10:00', content: verify, read: false}
  - {id: msg-p0-c, type: blocker, timestamp: '2026-07-17T12:11:00', content: blocker, read: false}
  - {id: msg-tie-b, type: notice, timestamp: '2026-07-17T12:12:00', content: tie b, read: false}
  - {id: msg-tie-a, type: notice, timestamp: '2026-07-17T12:12:00', content: tie a, read: false}
  - {id: msg-p2-e, type: notice, timestamp: '2026-07-17T12:14:00', content: final notice, read: false}
YAML

  run env SHOGUN_ROOT="$TEST_ROOT" INBOX_READ_LOG_DIR="$LOG_DIR" \
    INBOX_TRIAGE_NOW='2026-07-17T13:00:00' bash "$REPO_ROOT/scripts/inbox_read.sh" karo --triage

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c '^  priority: P')" -eq 15 ]
  [ "$(printf '%s' "$output" | grep -c 'id: msg-')" -eq 30 ]
  [[ "$output" == *$'id: msg-p0-b\n  priority: P0'* ]]
  [[ "$output" == *$'id: msg-tie-a\n  priority: P2'* ]]
  [[ "$output" == *$'id: msg-tie-b\n  priority: P2'* ]]
}
