#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMP_ROOT="$(mktemp -d)"
  export CMD_SKELETON_QUEUE_FILE="$TMP_ROOT/queue.yaml"
  export CMD_SKELETON_ARCHIVE_CMD_DIR="$TMP_ROOT/archive"
  export CMD_SKELETON_LAST_CMD_FILE="$TMP_ROOT/last_cmd.txt"
  export CMD_SKELETON_RESERVATION_FILE="$TMP_ROOT/reservations.txt"
  export CMD_SKELETON_RESERVATION_LOCK="$TMP_ROOT/reservations.lock"
  printf 'commands:\n' > "$CMD_SKELETON_QUEUE_FILE"
}

teardown() {
  rm -rf "$TMP_ROOT"
}

@test "skeleton emits estimated_minutes and the complete deployment time contract" {
  run bash "$REPO_ROOT/scripts/cmd_skeleton.sh" "契約テスト" infra
  [ "$status" -eq 0 ]
  [[ "$output" == *"estimated_minutes: 10"* ]]
  [[ "$output" == *"10分超はsplit_decision"* ]]
  [[ "$output" == *"15分超はexecution_env.long_runtime_reason+measured_runtime_sec"* ]]
  [[ "$output" == *"execution_env:"* ]]
  [[ "$output" == *"long_runtime_reason:"* ]]
  [[ "$output" == *"measured_runtime_sec: 0"* ]]
}
