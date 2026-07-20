#!/usr/bin/env bats
# test_necessity: enqueue/deliver must share exact event identity so retries cannot multiply durable holds while independent events still deliver.

setup() {
  FIXTURE_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$FIXTURE_ROOT/scripts"
  cp "$BATS_TEST_DIRNAME/../../scripts/lib/retro_verbatim_prompt.sh" "$FIXTURE_ROOT/retro_verbatim_prompt.sh"
  cp "$BATS_TEST_DIRNAME/../../scripts/lib/retro_pane_prompt.sh" "$FIXTURE_ROOT/retro_pane_prompt.sh"
  printf '%s\n' '#!/usr/bin/env bash' \
    'if [ "${FIXTURE_FAIL_ONCE:-0}" = 1 ] && mkdir "${FIXTURE_COUNT}.fail" 2>/dev/null; then exit 9; fi' \
    'printf "%s\\0" "$@" >> "$FIXTURE_COUNT"' > "$FIXTURE_ROOT/tmux"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FIXTURE_ROOT/idle"
  chmod +x "$FIXTURE_ROOT/tmux" "$FIXTURE_ROOT/idle"
  export FIXTURE_COUNT="$BATS_TEST_TMPDIR/deliveries"
  export RETRO_VERBATIM_STATE_DIR="$BATS_TEST_TMPDIR/claims"
  export RETRO_VERBATIM_PENDING_DIR="$BATS_TEST_TMPDIR/pending"
  export RETRO_VERBATIM_LOG="$BATS_TEST_TMPDIR/retro.log"
  export RETRO_PANE_TARGET='fixture:agents.1'
  export RETRO_PANE_TMUX_BIN="$FIXTURE_ROOT/tmux"
  export RETRO_PANE_IDLE_CHECK="$FIXTURE_ROOT/idle"
  source "$FIXTURE_ROOT/retro_verbatim_prompt.sh"
}

@test "same exact event shares one enqueue and delivery identity" {
  retro_verbatim_prompt_enqueue "$FIXTURE_ROOT" karo 'cmd_complete:cmd_4100' cmd_complete
  retro_verbatim_prompt_enqueue "$FIXTURE_ROOT" karo 'cmd_complete:cmd_4100' cmd_complete
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo 'cmd_complete:cmd_4100' cmd_complete
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo 'cmd_complete:cmd_4100' cmd_complete
  [ "$(find "$RETRO_VERBATIM_PENDING_DIR" -type f | wc -l)" -eq 1 ]
  [ "$(grep -ao 'send-keys' "$FIXTURE_COUNT" | wc -l)" -eq 2 ]
}

@test "independent commands each enqueue and deliver" {
  retro_verbatim_prompt_enqueue "$FIXTURE_ROOT" karo 'gate_clear:cmd_a' cmd_complete
  retro_verbatim_prompt_enqueue "$FIXTURE_ROOT" karo 'gate_clear:cmd_b' cmd_complete
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo 'gate_clear:cmd_a' cmd_complete
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo 'gate_clear:cmd_b' cmd_complete
  [ "$(find "$RETRO_VERBATIM_PENDING_DIR" -type f | wc -l)" -eq 2 ]
  [ "$(grep -ao 'send-keys' "$FIXTURE_COUNT" | wc -l)" -eq 4 ]
}

@test "events without command context remain independent" {
  retro_verbatim_prompt_enqueue "$FIXTURE_ROOT" karo report_received:msg_a inbox_write
  retro_verbatim_prompt_enqueue "$FIXTURE_ROOT" karo task_failed:msg_b inbox_write
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo report_received:msg_a inbox_write
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo task_failed:msg_b inbox_write
  [ "$(find "$RETRO_VERBATIM_PENDING_DIR" -type f | wc -l)" -eq 2 ]
  [ "$(grep -ao 'send-keys' "$FIXTURE_COUNT" | wc -l)" -eq 4 ]
}

@test "failed delivery removes claim and retry succeeds" {
  export FIXTURE_FAIL_ONCE=1
  run retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo 'gate_clear:cmd_retry' cmd_complete
  [ "$status" -eq 1 ]
  run retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo 'cmd_complete:cmd_retry' cmd_complete
  [ "$status" -eq 0 ]
  [ "$(grep -ao 'send-keys' "$FIXTURE_COUNT" | wc -l)" -eq 2 ]
  [ "$(find "$RETRO_VERBATIM_STATE_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]
}

@test "answered content is not resent while its durable claim remains" {
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo report_received:msg_a inbox_write
  printf '%s\n' 'report_received:msg_a' > "$BATS_TEST_TMPDIR/answered-event"
  retro_verbatim_prompt_deliver "$FIXTURE_ROOT" karo report_received:msg_a inbox_write
  [ "$(grep -ao 'send-keys' "$FIXTURE_COUNT" | wc -l)" -eq 2 ]
  [ "$(grep -c $'deduplicated' "$RETRO_VERBATIM_LOG")" -eq 1 ]
}
