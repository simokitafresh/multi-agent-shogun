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
  export TMUX_BUFFER="$BATS_TEST_TMPDIR/tmux.buffer"
  export RETRO_PANE_SLEEP_CMD="$BATS_TEST_TMPDIR/sleep"
  export ORDER_LOG="$BATS_TEST_TMPDIR/order.log"
  printf '#!/usr/bin/env bash\n[ "${FIXTURE_BUSY:-0}" = 0 ]\n' > "$RETRO_PANE_IDLE_CHECK"
  printf '#!/usr/bin/env bash\n[ "${FIXTURE_PROMPT_UNSEEN:-0}" = 0 ]\n' > "$RETRO_PANE_SEEN_CHECK"
  printf '%s\n' '#!/usr/bin/env bash' \
    'if [ "$1" = load-buffer ]; then [ "${FIXTURE_FAIL_SEND:-0}" = 0 ] || exit 9; cat > "$TMUX_BUFFER"; exit 0; fi' \
    'if [ "$1" = show-buffer ]; then [ "${FIXTURE_CAPTURE_MISMATCH:-0}" = 0 ] && cat "$TMUX_BUFFER" || printf corrupt; exit 0; fi' \
    'if [ "$1" = delete-buffer ]; then rm -f "$TMUX_BUFFER"; exit 0; fi' \
    'if [ "$1" = paste-buffer ]; then printf "paste-buffer\\n" >> "$ORDER_LOG"; printf "%s\\0" "$@" >> "$TMUX_CALLS"; cat "$TMUX_BUFFER" >> "$TMUX_CALLS"; exit 0; fi' \
    'if [ "${FIXTURE_FAIL_ENTER:-0}" = 1 ] && [ "${!#}" = Enter ]; then exit 8; fi' \
    'if [ "${!#}" = Enter ]; then printf "enter\\n" >> "$ORDER_LOG"; fi' \
    'printf "%s\\0" "$@" >> "$TMUX_CALLS"' > "$RETRO_PANE_TMUX_BIN"
  printf '#!/usr/bin/env bash\nprintf "sleep:%%s\\n" "$1" >> "$ORDER_LOG"\n' > "$RETRO_PANE_SLEEP_CMD"
  chmod +x "$RETRO_PANE_IDLE_CHECK" "$RETRO_PANE_SEEN_CHECK" "$RETRO_PANE_TMUX_BIN" "$RETRO_PANE_SLEEP_CMD"
  export TMUX_CALLS="$BATS_TEST_TMPDIR/tmux.calls"
  source "$BATS_TEST_DIRNAME/../../scripts/lib/retro_pane_prompt.sh"
  export FIXTURE_CAPTURE_TEXT="$RETRO_PANE_PROMPT"
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
  [ "$(grep -c '^sleep:0.5$' "$ORDER_LOG")" -eq 2 ]
  [ "$(sed -n '1p' "$ORDER_LOG")" = paste-buffer ]
  [ "$(sed -n '2p' "$ORDER_LOG")" = sleep:0.5 ]
  [ "$(sed -n '3p' "$ORDER_LOG")" = enter ]
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

@test "payload SHA mismatch retries safely and Enter failure resumes without repaste" {
  FIXTURE_CAPTURE_MISMATCH=1 run retro_pane_prompt_deliver "$ROOT" tobisaru event:sha fixture
  [ "$status" -eq 1 ]
  run retro_pane_prompt_deliver "$ROOT" tobisaru event:sha fixture
  [ "$status" -eq 0 ]
  [ "$(grep -aoF "$RETRO_PANE_PROMPT" "$TMUX_CALLS" | wc -l)" -eq 1 ]
  [ "$(grep -c $'\tfailed_payload_sha\t' "$RETRO_PANE_LEDGER")" -eq 1 ]

  FIXTURE_FAIL_ENTER=1 run retro_pane_prompt_deliver "$ROOT" tobisaru event:enter fixture
  [ "$status" -eq 1 ]
  run retro_pane_prompt_deliver "$ROOT" tobisaru event:enter fixture
  [ "$status" -eq 0 ]
  [ "$(grep -c $'\tfailed_enter\t' "$RETRO_PANE_LEDGER")" -eq 1 ]
  [ "$(grep -c $'\trecovered_enter\t' "$RETRO_PANE_LEDGER")" -eq 1 ]
  [ "$(grep -aoF "$RETRO_PANE_PROMPT" "$TMUX_CALLS" | wc -l)" -eq 2 ]
  [ "$(grep -c '^sleep:0.5$' "$ORDER_LOG")" -eq 3 ]
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

@test "report and reviewed failure pending events reconcile without pane delivery" {
  mkdir -p "$ROOT/queue/retro/verbatim_pending" "$ROOT/queue/inbox" "$ROOT/logs"
  report_event="$ROOT/queue/retro/verbatim_pending/report.event"
  printf 'tobisaru\nreport_received:msg-1\nfixture\nkey\n' > "$report_event"
  run retro_pane_prompt_reconcile_terminal "$ROOT" "$report_event"
  [ "$status" -eq 0 ]
  [ "$output" = report_terminal ]

  failed_event="$ROOT/queue/retro/verbatim_pending/failed.event"
  printf 'tobisaru\ntask_failed:rpt-review:2:fingerprint\nfixture\nkey\n' > "$failed_event"
  printf '%s\n' 'messages:' '- type: report_review' '  report_id: rpt-review' '  parent_cmd: cmd-reviewed' > "$ROOT/queue/inbox/gunshi.yaml"
  printf '%s\n' '- cmd_id: cmd-reviewed' '  review_type: report' '  verdict: FAIL' > "$ROOT/logs/gunshi_review_log.yaml"
  run retro_pane_prompt_reconcile_terminal "$ROOT" "$failed_event"
  [ "$status" -eq 0 ]
  [ "$output" = review_terminal:cmd-reviewed:FAIL ]
  run retro_pane_prompt_reconcile_pending "$ROOT" "$failed_event" tobisaru task_failed:rpt-review:2:fingerprint
  [ "$status" -eq 0 ]
  [ ! -e "$failed_event" ]
  [ -e "$ROOT/queue/retro/verbatim_reconciled/failed.event" ]
  [ "$(grep -c $'\treconciled_terminal\t' "$RETRO_PANE_LEDGER")" -eq 1 ]
}
