#!/usr/bin/env bats
# test_necessity: enqueue/deliver must share canonical cmd identity so duplicate prompts cannot multiply durable holds while independent commands still deliver.

setup() {
  FIXTURE_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$FIXTURE_ROOT/scripts"
  cp "$BATS_TEST_DIRNAME/../../scripts/lib/retro_verbatim_prompt.sh" "$FIXTURE_ROOT/retro_verbatim_prompt.sh"
  printf '%s\n' '#!/usr/bin/env bash' \
    'if [ "${FIXTURE_FAIL_ONCE:-0}" = 1 ] && mkdir "${FIXTURE_COUNT}.fail" 2>/dev/null; then exit 9; fi' \
    'printf "%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" >> "$FIXTURE_COUNT"' \
    > "$FIXTURE_ROOT/scripts/inbox_write.sh"
  chmod +x "$FIXTURE_ROOT/scripts/inbox_write.sh"
  export FIXTURE_COUNT="$BATS_TEST_TMPDIR/deliveries"
  export RETRO_VERBATIM_STATE_DIR="$BATS_TEST_TMPDIR/claims"
  export RETRO_VERBATIM_PENDING_DIR="$BATS_TEST_TMPDIR/pending"
  export RETRO_VERBATIM_LOG="$BATS_TEST_TMPDIR/retro.log"
  source "$FIXTURE_ROOT/retro_verbatim_prompt.sh"
}

@test "same command prefixes share one enqueue and delivery identity" {
  retro_verbatim_prompt_enqueue "$FIXTURE_ROOT" karo 'cmd_complete:cmd_4100' cmd_complete
  retro_verbatim_prompt_enqueue "$FIXTURE_ROOT" karo 'gate_clear:cmd_4100' cmd_complete
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo 'cmd_complete:cmd_4100' cmd_complete
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo 'review_bundle:cmd_4100' cmd_complete
  [ "$(find "$RETRO_VERBATIM_PENDING_DIR" -type f | wc -l)" -eq 1 ]
  [ "$(wc -l < "$FIXTURE_COUNT")" -eq 1 ]
}

@test "independent commands each enqueue and deliver" {
  retro_verbatim_prompt_enqueue "$FIXTURE_ROOT" karo 'gate_clear:cmd_a' cmd_complete
  retro_verbatim_prompt_enqueue "$FIXTURE_ROOT" karo 'gate_clear:cmd_b' cmd_complete
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo 'gate_clear:cmd_a' cmd_complete
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo 'gate_clear:cmd_b' cmd_complete
  [ "$(find "$RETRO_VERBATIM_PENDING_DIR" -type f | wc -l)" -eq 2 ]
  [ "$(wc -l < "$FIXTURE_COUNT")" -eq 2 ]
}

@test "events without command context collapse by fixed content" {
  retro_verbatim_prompt_enqueue "$FIXTURE_ROOT" karo report_received:msg_a inbox_write
  retro_verbatim_prompt_enqueue "$FIXTURE_ROOT" karo task_failed:msg_b inbox_write
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo report_received:msg_a inbox_write
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo task_failed:msg_b inbox_write
  [ "$(find "$RETRO_VERBATIM_PENDING_DIR" -type f | wc -l)" -eq 1 ]
  [ "$(wc -l < "$FIXTURE_COUNT")" -eq 1 ]
}

@test "failed delivery removes claim and retry succeeds" {
  export FIXTURE_FAIL_ONCE=1
  run retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo 'gate_clear:cmd_retry' cmd_complete
  [ "$status" -eq 1 ]
  run retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo 'cmd_complete:cmd_retry' cmd_complete
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$FIXTURE_COUNT")" -eq 1 ]
  [ "$(find "$RETRO_VERBATIM_STATE_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]
}

@test "answered content is not resent while its durable claim remains" {
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo report_received:msg_a inbox_write
  printf '%s\n' 'report_received:msg_a' > "$BATS_TEST_TMPDIR/answered-event"
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo task_failed:msg_b inbox_write
  [ "$(wc -l < "$FIXTURE_COUNT")" -eq 1 ]
  [ "$(grep -c $'deduplicated' "$RETRO_VERBATIM_LOG")" -eq 1 ]
}
