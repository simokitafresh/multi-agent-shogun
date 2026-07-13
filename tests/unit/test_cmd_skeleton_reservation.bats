#!/usr/bin/env bats

setup() {
  FIXTURE="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$FIXTURE/archive"
  printf 'commands:\n  cmd_3877: {}\n' > "$FIXTURE/queue.yaml"
  printf 'cmd_3876\n' > "$FIXTURE/last_cmd.txt"
  printf 'cmd_3878-cmd_3886 design reservation\n' > "$FIXTURE/reservations.txt"
  touch "$FIXTURE/archive/cmd_9999.yaml"
}

run_skeleton() {
  CMD_SKELETON_QUEUE_FILE="$FIXTURE/queue.yaml" \
  CMD_SKELETON_ARCHIVE_CMD_DIR="$FIXTURE/archive" \
  CMD_SKELETON_LAST_CMD_FILE="$FIXTURE/last_cmd.txt" \
  CMD_SKELETON_RESERVATION_FILE="$FIXTURE/reservations.txt" \
  CMD_SKELETON_RESERVATION_LOCK="$FIXTURE/reservations.lock" \
    bash scripts/cmd_skeleton.sh test infra 2>/dev/null
}

@test "reservation upper bound wins and out-of-band archive is ignored" {
  run run_skeleton
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd_3887:"* ]]
  grep -qx 'cmd_3887 skeleton .*' "$FIXTURE/reservations.txt"
}

@test "queue and last_cmd maxima remain candidates" {
  printf 'commands:\n  cmd_3900: {}\n' > "$FIXTURE/queue.yaml"
  printf 'cmd_3901\n' > "$FIXTURE/last_cmd.txt"
  run run_skeleton
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd_3902:"* ]]
}

@test "two concurrent calls reserve distinct IDs" {
  run_skeleton > "$FIXTURE/a.yaml" &
  pid_a=$!
  run_skeleton > "$FIXTURE/b.yaml" &
  pid_b=$!
  wait "$pid_a"
  wait "$pid_b"
  ids="$(grep -hoE 'cmd_[0-9]+:' "$FIXTURE/a.yaml" "$FIXTURE/b.yaml" | sort -u)"
  [ "$(printf '%s\n' "$ids" | grep -c '^cmd_')" -eq 2 ]
  [[ "$ids" == *"cmd_3887:"* ]]
  [[ "$ids" == *"cmd_3888:"* ]]
}
