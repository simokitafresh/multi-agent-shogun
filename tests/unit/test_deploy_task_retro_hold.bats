#!/usr/bin/env bats
# test_necessity: retro hold must use exact persisted answer identities under the ninja lock; nearby event text must never release an unanswered hold.

setup() {
  PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
  ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$ROOT/queue/retro/verbatim_awaiting_answer" "$ROOT/queue/inbox" "$ROOT/logs" "$ROOT/scripts/lib"
  cp "$PROJECT_ROOT/scripts/lib/defense_overhead_writer.sh" "$ROOT/scripts/lib/defense_overhead_writer.sh"
  export DEPLOY_TASK_LIB_ONLY=1
  source "$PROJECT_ROOT/scripts/deploy_task.sh"
  SCRIPT_DIR="$ROOT"
  LOG="$ROOT/logs/deploy_task.log"
  export DEPLOY_TASK_NINJA_LOCK_FD=9
  exec 9>"$ROOT/ninja.lock"
  printf 'ninja-a\nreport_received:msg-1\n' > "$ROOT/queue/retro/verbatim_awaiting_answer/hold.event"
}

teardown() { exec 9>&-; }

@test "exact E4 answer releases hold and records PASS metric" {
  printf '%s\n' '{"event_id":"report_received:msg-1","answer":"done"}' > "$ROOT/queue/retro/answers.jsonl"
  deploy_task_guard_retro_answer_hold ninja-a
  [ ! -e "$ROOT/queue/retro/verbatim_awaiting_answer/hold.event" ]
  grep -q $'ninja-a\treport_received:msg-1\tanswered=1 decision=PASS' "$ROOT/logs/retro_hold_gate_fire.log"
}

@test "unanswered hold blocks and nearby event cannot false-release" {
  printf '%s\n' '{"event_id":"report_received:msg-10","answer":"wrong event"}' > "$ROOT/queue/retro/answers.jsonl"
  printf 'messages:\n- type: retro_answer\n  content: "analysis event_id=report_received:msg-10"\n' > "$ROOT/queue/inbox/karo.yaml"
  run deploy_task_guard_retro_answer_hold ninja-a
  [ "$status" -eq 2 ]
  [ -e "$ROOT/queue/retro/verbatim_awaiting_answer/hold.event" ]
  grep -q $'ninja-a\treport_received:msg-1\tanswered=0 decision=BLOCK' "$ROOT/logs/retro_hold_gate_fire.log"
}

@test "structured retro answer in karo mailbox releases exactly one hold" {
  printf 'messages:\n- type: retro_answer\n  event_id: report_received:msg-1\n  content: "answer recorded"\n' > "$ROOT/queue/inbox/karo.yaml"
  deploy_task_guard_retro_answer_hold ninja-a
  [ ! -e "$ROOT/queue/retro/verbatim_awaiting_answer/hold.event" ]
  [ "$(grep -c 'decision=PASS' "$ROOT/logs/retro_hold_gate_fire.log")" -eq 1 ]
}

# test_necessity: inbox_archive後もexact retro_answer identityが回答済みとしてholdを解除し続ける不変量。
@test "archived structured retro answer releases hold after live inbox removal" {
  mkdir -p "$ROOT/archive/inbox"
  printf 'messages:\n- type: retro_answer\n  event_id: report_received:msg-1\n  content: "answer archived"\n  read: true\n' > "$ROOT/archive/inbox/karo_20260722.yaml"
  printf 'messages: []\n' > "$ROOT/queue/inbox/karo.yaml"
  deploy_task_guard_retro_answer_hold ninja-a
  [ ! -e "$ROOT/queue/retro/verbatim_awaiting_answer/hold.event" ]
  [ "$(grep -c 'decision=PASS' "$ROOT/logs/retro_hold_gate_fire.log")" -eq 1 ]
}
