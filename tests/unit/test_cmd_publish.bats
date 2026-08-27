#!/usr/bin/env bats

# test_necessity: Keep the cmd_publish outer timing contract executable: every
# success and failure must retain the four monotonic checkpoints and the three
# derived intervals in an append-only raw log.

setup() {
  ROOT="$BATS_TEST_DIRNAME/../.."
  PUBLISH="$ROOT/scripts/cmd_publish.sh"
  TEST_ROOT="$BATS_TEST_TMPDIR/cmd-publish"
  mkdir -p "$TEST_ROOT"
}

write_fixture() {
  local queue="$1" save="$2" delegate="$3"
  printf '%s\n' 'commands:' '  cmd_publish_phase_probe:' '    status: draft' '    title: phase probe' >"$queue"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$save"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$delegate"
  chmod +x "$save" "$delegate"
}

@test "success records three runs with four checkpoints and three intervals" {
  local queue="$TEST_ROOT/queue.yaml" save="$TEST_ROOT/save.sh" delegate="$TEST_ROOT/delegate.sh"
  local timing="$TEST_ROOT/cmd_publish_timing.log" ledger="$TEST_ROOT/defense_overhead.jsonl"
  write_fixture "$queue" "$save" "$delegate"

  for _ in 1 2 3; do
    run env \
      CMD_PUBLISH_QUEUE_FILE="$queue" \
      CMD_PUBLISH_LAST_CMD_FILE="$TEST_ROOT/absent_last.txt" \
      CMD_PUBLISH_CMD_SAVE_SCRIPT="$save" \
      CMD_PUBLISH_CMD_DELEGATE_SCRIPT="$delegate" \
      CMD_PUBLISH_TIMING_LOG_FILE="$timing" \
      DEFENSE_OVERHEAD_LEDGER="$ledger" \
      DEFENSE_OVERHEAD_INDEX="$TEST_ROOT/defense_overhead.sqlite3" \
      bash "$PUBLISH" cmd_publish_phase_probe probe
    [ "$status" -eq 0 ]
  done

  run awk '
    NR == 1 { next }
    {
      if ($2 != "PASS" || $3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ ||
          $5 !~ /^[0-9]+$/ || $6 !~ /^[0-9]+$/) exit 1
      for (i = 7; i <= 10; i++) if ($i !~ /^[0-9]+$/) exit 1
      if ($11 == "none" || $12 !~ /^[0-9]+$/) exit 1
      count++
    }
    END { exit (count == 3 ? 0 : 1) }
  ' "$timing"
  [ "$status" -eq 0 ]
}

@test "failure records FAIL with a monotonic process-to-preflight interval" {
  local queue="$TEST_ROOT/queue.yaml" save="$TEST_ROOT/save.sh" delegate="$TEST_ROOT/delegate.sh"
  local timing="$TEST_ROOT/cmd_publish_timing.log" ledger="$TEST_ROOT/defense_overhead.jsonl"
  write_fixture "$queue" "$save" "$delegate"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 7' >"$save"
  chmod +x "$save"

  run env \
    CMD_PUBLISH_QUEUE_FILE="$queue" \
    CMD_PUBLISH_LAST_CMD_FILE="$TEST_ROOT/absent_last.txt" \
    CMD_PUBLISH_CMD_SAVE_SCRIPT="$save" \
    CMD_PUBLISH_CMD_DELEGATE_SCRIPT="$delegate" \
    CMD_PUBLISH_TIMING_LOG_FILE="$timing" \
    DEFENSE_OVERHEAD_LEDGER="$ledger" \
    DEFENSE_OVERHEAD_INDEX="$TEST_ROOT/defense_overhead.sqlite3" \
    bash "$PUBLISH" cmd_publish_phase_probe probe
  [ "$status" -ne 0 ]

  run awk 'NR == 2 { exit !($2 == "FAIL" && $3 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/ && $5 == "NA" && $6 ~ /^[0-9]+$/ && $7 ~ /^[0-9]+$/ && $8 == "NA" && $9 == "NA" && $10 ~ /^[0-9]+$/); }' "$timing"
  [ "$status" -eq 0 ]
}

