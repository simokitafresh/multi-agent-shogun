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
