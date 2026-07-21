#!/usr/bin/env bats
# test_necessity: a successful pane send is an irreversible delivery boundary, and each target may have at most one outstanding retro prompt.

setup() {
  ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$ROOT/logs" "$ROOT/queue/retro"
  export RETRO_PANE_STATE_DIR="$BATS_TEST_TMPDIR/claims"
  export RETRO_PANE_PENDING_DIR="$BATS_TEST_TMPDIR/pending"
  export RETRO_PANE_LEDGER="$BATS_TEST_TMPDIR/ledger.tsv"
  export RETRO_PANE_TARGET='fixture:agents.7'
  export RETRO_PANE_IDLE_CHECK="$BATS_TEST_TMPDIR/idle"
  export RETRO_PANE_SEEN_CHECK="$BATS_TEST_TMPDIR/seen"
  export RETRO_PANE_TMUX_BIN="$BATS_TEST_TMPDIR/tmux"
  printf '#!/usr/bin/env bash\n[ "${FIXTURE_BUSY:-0}" = 0 ]\n' > "$RETRO_PANE_IDLE_CHECK"
  printf '#!/usr/bin/env bash\n[ "${FIXTURE_PROMPT_UNSEEN:-0}" = 0 ]\n' > "$RETRO_PANE_SEEN_CHECK"
  printf '%s\n' '#!/usr/bin/env bash' \
    'if [ "${FIXTURE_FAIL_SEND:-0}" = 1 ]; then exit 9; fi' \
    'printf "%s\\0" "$@" >> "$TMUX_CALLS"' > "$RETRO_PANE_TMUX_BIN"
  chmod +x "$RETRO_PANE_IDLE_CHECK" "$RETRO_PANE_SEEN_CHECK" "$RETRO_PANE_TMUX_BIN"
  export TMUX_CALLS="$BATS_TEST_TMPDIR/tmux.calls"
  source "$BATS_TEST_DIRNAME/../../scripts/lib/retro_pane_prompt.sh"
}

@test "same event sends once and independent event sends once" {
  retro_pane_prompt_deliver "$ROOT" tobisaru event:a fixture
  retro_pane_prompt_deliver "$ROOT" tobisaru event:a fixture
  retro_pane_prompt_deliver "$ROOT" tobisaru event:b fixture
  [ "$(grep -c $'\tdelivered_prompt_seen\t' "$RETRO_PANE_LEDGER")" -eq 2 ]
  [ "$(grep -c $'\tdeduplicated\t' "$RETRO_PANE_LEDGER")" -eq 1 ]
  [ "$(grep -aoF "$RETRO_PANE_PROMPT" "$TMUX_CALLS" | wc -l)" -eq 2 ]
  [ "$(grep -ao 'Enter' "$TMUX_CALLS" | wc -l)" -eq 2 ]
  expected=$(printf '%s' "$RETRO_PANE_PROMPT" | sha256sum | cut -d' ' -f1)
  [ "$(grep -c "$expected" "$RETRO_PANE_LEDGER")" -eq 2 ]
}

@test "busy pane and failed send release claim for retry" {
  FIXTURE_BUSY=1 run retro_pane_prompt_deliver "$ROOT" tobisaru event:retry fixture
  [ "$status" -eq 1 ]
  [ "$(find "$RETRO_PANE_STATE_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 0 ]
  FIXTURE_FAIL_SEND=1 run retro_pane_prompt_deliver "$ROOT" tobisaru event:retry fixture
  [ "$status" -eq 1 ]
  [ "$(find "$RETRO_PANE_STATE_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 0 ]
  retro_pane_prompt_deliver "$ROOT" tobisaru event:retry fixture
  [ "$(grep -c $'\tdelivered_prompt_seen\t' "$RETRO_PANE_LEDGER")" -eq 1 ]
}

@test "send without prompt-seen ack is terminal and never retries" {
  FIXTURE_PROMPT_UNSEEN=1 run retro_pane_prompt_deliver "$ROOT" tobisaru event:respawn fixture
  [ "$status" -eq 0 ]
  [ "$(find "$RETRO_PANE_STATE_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]
  [ "$(grep -c $'\tdelivered_unverified\t' "$RETRO_PANE_LEDGER")" -eq 1 ]
  retro_pane_prompt_deliver "$ROOT" tobisaru event:respawn fixture
  [ "$(grep -c $'\tdeduplicated\t' "$RETRO_PANE_LEDGER")" -eq 1 ]
  [ "$(grep -aoF "$RETRO_PANE_PROMPT" "$TMUX_CALLS" | wc -l)" -eq 1 ]
}

@test "one target can have only one outstanding event" {
  retro_pane_prompt_enqueue "$ROOT" tobisaru event:first fixture
  retro_pane_prompt_enqueue "$ROOT" tobisaru event:second fixture
  [ "$(find "$RETRO_PANE_PENDING_DIR" -type f | wc -l)" -eq 1 ]
  [ "$(grep -c $'\tsuppressed_outstanding\t' "$RETRO_PANE_LEDGER")" -eq 1 ]
}

@test "retro transport has no inbox delivery path" {
  ! grep -q 'inbox_write' "$BATS_TEST_DIRNAME/../../scripts/lib/retro_pane_prompt.sh"
}

@test "async busy attempt leaves one durable event for idle-cycle retry" {
  export FIXTURE_BUSY=1
  retro_pane_prompt_async "$ROOT" tobisaru event:async fixture
  wait
  [ "$(find "$RETRO_PANE_PENDING_DIR" -type f | wc -l)" -eq 1 ]
  [ "$(find "$RETRO_PANE_STATE_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 0 ]
  [ "$(grep -c $'\tfailed_busy\t' "$RETRO_PANE_LEDGER")" -eq 1 ]
}
