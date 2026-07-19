#!/usr/bin/env bats
# test_necessity: Retro transport preserves exactly-once batching, idle-only delivery identity, answer/timeout holds, and proposal-to-hotfix closure; violation is BLOCK.

setup() {
  export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export RETRO_ROOT_OVERRIDE="$BATS_TEST_TMPDIR/root"
  mkdir -p "$RETRO_ROOT_OVERRIDE/scripts" "$RETRO_ROOT_OVERRIDE/queue/inbox"
  mkdir -p "$RETRO_ROOT_OVERRIDE/scripts/lib"
  cp "$PROJECT_ROOT/scripts/retro_write.sh" "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh"
  cat > "$RETRO_ROOT_OVERRIDE/scripts/lib/defense_overhead_writer.sh" <<'SH'
self_retro_write_async() { :; }
SH
  cat > "$RETRO_ROOT_OVERRIDE/scripts/inbox_write.sh" <<'SH'
#!/bin/bash
printf '%s|%s|%s|%s\n' "$1" "$3" "$4" "$2" >> "${RETRO_ROOT_OVERRIDE}/notifications"
SH
}

submit() {
  bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" submit "$1" "$2" \
    2026-07-18T15:00:00+09:00 "$3" "$4" "$5" "${6:-normal}" "${7:-result}"
}

@test "normal 1-5 interrupt zero; sixth emits one batch" {
  for i in $(seq 1 5); do submit n$i r$i 2026-07-18T15:08:31+09:00 - -; done
  [ ! -e "$RETRO_ROOT_OVERRIDE/notifications" ]
  submit n6 r6 2026-07-18T15:08:31+09:00 - -
  [ "$(wc -l < "$RETRO_ROOT_OVERRIDE/notifications")" -eq 1 ]
  grep -q 'karo|retro_batch_ready|retro_batcher|.*count=6' "$RETRO_ROOT_OVERRIDE/notifications"
  [ "$(wc -l < "$RETRO_ROOT_OVERRIDE/queue/retro/events.jsonl")" -eq 6 ]
}

@test "duplicate and processed batch retry are exactly once" {
  for i in $(seq 1 6); do submit n$i r$i 2026-07-18T15:08:31+09:00 - -; done
  submit n1 r1 2026-07-18T15:08:31+09:00 - -
  [ "$(wc -l < "$RETRO_ROOT_OVERRIDE/queue/retro/events.jsonl")" -eq 6 ]
  [ "$(wc -l < "$RETRO_ROOT_OVERRIDE/notifications")" -eq 1 ]
}

@test "duration uses earliest terminal and excludes 33m34s idle" {
  submit saizo rpt1 2026-07-18T15:33:34+09:00 2026-07-18T15:08:31+09:00 2026-07-18T15:09:00+09:00
  grep -q '"duration_seconds": 511' "$RETRO_ROOT_OVERRIDE/queue/retro/events.jsonl"
}

@test "malformed fails closed without append" {
  run bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" submit n r bad - - - normal result
  [ "$status" -ne 0 ]
  [ ! -e "$RETRO_ROOT_OVERRIDE/queue/retro/events.jsonl" ]
}

@test "urgent notifies immediately and final checkpoint flushes partial" {
  submit n1 r1 2026-07-18T15:08:31+09:00 - - security
  grep -q 'retro_urgent' "$RETRO_ROOT_OVERRIDE/notifications"
  submit n2 r2 2026-07-18T15:08:31+09:00 - - normal
  bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" final-checkpoint
  [ "$(wc -l < "$RETRO_ROOT_OVERRIDE/notifications")" -eq 2 ]
}

@test "parallel six lose zero and notify once" {
  for i in $(seq 1 6); do submit n$i r$i 2026-07-18T15:08:31+09:00 - - & done
  wait
  [ "$(wc -l < "$RETRO_ROOT_OVERRIDE/queue/retro/events.jsonl")" -eq 6 ]
  [ "$(wc -l < "$RETRO_ROOT_OVERRIDE/notifications")" -eq 1 ]
}

@test "legacy prompts tombstone while current delivery remains answer-tracked" {
  mkdir -p "$RETRO_ROOT_OVERRIDE/queue/retro"
  for i in $(seq 1 63); do
    printf '%s\n' "- ninja: n$i" "  triggered_at: 2026-07-18T15:00:00+09:00" "  parent_msg: msg-$i" "  status: pending" >> "$RETRO_ROOT_OVERRIDE/queue/retro/pending.yaml"
  done
  bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" enqueue-trigger n64 msg-64 2026-07-18T15:00:00+09:00
  [ ! -s "$RETRO_ROOT_OVERRIDE/queue/retro/pending.yaml" ]
  [ "$(wc -l < "$RETRO_ROOT_OVERRIDE/queue/retro/events.jsonl")" -eq 1 ]
  grep -q '"migrated_count": 63' "$RETRO_ROOT_OVERRIDE/queue/retro/events.jsonl"
  [ ! -e "$RETRO_ROOT_OVERRIDE/notifications" ]
  bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" final-checkpoint
  [ ! -e "$RETRO_ROOT_OVERRIDE/notifications" ]
  [ "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["legacy_tombstones"]))' "$RETRO_ROOT_OVERRIDE/queue/retro/state.json")" -eq 64 ]
}

@test "empty trigger duplicate and parallel submissions become tombstones without notifications" {
  for i in $(seq 1 6); do
    bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" enqueue-trigger n$i msg-$i 2026-07-18T15:00:00+09:00 &
  done
  wait
  bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" enqueue-trigger n1 msg-1 2026-07-18T15:00:00+09:00
  bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" mark-delivered n1 report_received:msg-1 2026-07-18T15:01:00+09:00
  [ ! -e "$RETRO_ROOT_OVERRIDE/queue/retro/events.jsonl" ]
  [ ! -e "$RETRO_ROOT_OVERRIDE/notifications" ]
  [ "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["legacy_tombstones"]))' "$RETRO_ROOT_OVERRIDE/queue/retro/state.json")" -eq 6 ]
}

@test "delivery and retro_answer reconcile by event_id with zero duplicate reminder" {
  mkdir -p "$RETRO_ROOT_OVERRIDE/queue/inbox"
  bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" enqueue-trigger n1 msg-1 2026-07-18T15:00:00+09:00
  bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" mark-delivered n1 report_received:msg-1 2026-07-18T15:01:00+09:00
  cat > "$RETRO_ROOT_OVERRIDE/queue/inbox/karo.yaml" <<'YAML'
messages:
- type: retro_answer
  content: 'analysis complete event_id=report_received:msg-1'
YAML
  RETRO_ANSWER_TIMEOUT_SECONDS=0 run bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" final-checkpoint
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELIVERED=1 ANSWERED=1 UNANSWERED=0 PANE_IDLE_DELIVERED=1"* ]]
  [ ! -e "$RETRO_ROOT_OVERRIDE/notifications" ]
  RETRO_ANSWER_TIMEOUT_SECONDS=0 bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" final-checkpoint
  [ ! -e "$RETRO_ROOT_OVERRIDE/notifications" ]
}

@test "expired unanswered delivery blocks next task and reprompts exactly once" {
  bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" enqueue-trigger n1 msg-1 2026-07-18T15:00:00+09:00
  bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" mark-delivered n1 report_received:msg-1 2026-07-18T15:01:00+09:00
  RETRO_ANSWER_TIMEOUT_SECONDS=0 run bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" final-checkpoint
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELIVERED=1 ANSWERED=0 UNANSWERED=1 PANE_IDLE_DELIVERED=1"* ]]
  grep -q 'karo|retro_unanswered|retro_batcher|BLOCK_NEXT_TASK ninja=n1 count=1 event_ids=report_received:msg-1 action=reprompt' "$RETRO_ROOT_OVERRIDE/notifications"
  RETRO_ANSWER_TIMEOUT_SECONDS=0 bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" final-checkpoint
  [ "$(wc -l < "$RETRO_ROOT_OVERRIDE/notifications")" -eq 1 ]
}

@test "E4 answer ledger reconciles delivery without inbox answer" {
  bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" enqueue-trigger n1 msg-1 2026-07-18T15:00:00+09:00
  bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" mark-delivered n1 report_received:msg-1 2026-07-18T15:01:00+09:00
  printf '%s\n' '{"event_id":"report_received:msg-1","answer":"investigated"}' > "$RETRO_ROOT_OVERRIDE/queue/retro/answers.jsonl"
  RETRO_ANSWER_TIMEOUT_SECONDS=0 run bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" final-checkpoint
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELIVERED=1 ANSWERED=1 UNANSWERED=0 PANE_IDLE_DELIVERED=1"* ]]
  [ ! -e "$RETRO_ROOT_OVERRIDE/notifications" ]
}

@test "improvement proposal without hotfix deployment blocks checkpoint once" {
  submit n1 r1 2026-07-18T15:08:31+09:00 - - normal "improvement_proposals=2 hotfix_deployed=1"
  run bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" final-checkpoint
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROPOSALS=2 HOTFIX_DEPLOYED=1"* ]]
  grep -q 'retro_proposal_unactioned.*proposal_count=2 hotfix_deployed=1 unassigned=1' "$RETRO_ROOT_OVERRIDE/notifications"
  bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" final-checkpoint
  [ "$(grep -c retro_proposal_unactioned "$RETRO_ROOT_OVERRIDE/notifications")" -eq 1 ]
}
