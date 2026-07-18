#!/usr/bin/env bats

setup() {
  export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export RETRO_ROOT_OVERRIDE="$BATS_TEST_TMPDIR/root"
  mkdir -p "$RETRO_ROOT_OVERRIDE/scripts" "$RETRO_ROOT_OVERRIDE/queue/inbox"
  cp "$PROJECT_ROOT/scripts/retro_write.sh" "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh"
  cat > "$RETRO_ROOT_OVERRIDE/scripts/inbox_write.sh" <<'SH'
#!/bin/bash
printf '%s|%s|%s|%s\n' "$1" "$3" "$4" "$2" >> "${RETRO_ROOT_OVERRIDE}/notifications"
SH
}

submit() {
  bash "$RETRO_ROOT_OVERRIDE/scripts/retro_write.sh" submit "$1" "$2" \
    2026-07-18T15:00:00+09:00 "$3" "$4" "$5" "${6:-normal}" result
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
