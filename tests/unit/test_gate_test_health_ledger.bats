#!/usr/bin/env bats

# test_necessity: protects the startup-critical ledger freshness contract across
# ISO-8601 timezone forms and prevents reintroduction of per-row external date forks.
# regression_justification: this is the boundary contract for the cmd_karo_hotfix_test_health_date_fork_202607211922 bug.

setup() {
  TMP_DIR="$(mktemp -d)"
  LEDGER="$TMP_DIR/ledger.tsv"
  TESTS="$TMP_DIR/tests"
  REPORTS="$TMP_DIR/reports"
  BIN="$TMP_DIR/bin"
  mkdir -p "$TESTS" "$REPORTS" "$BIN"
  cp /usr/bin/date "$BIN/date"
  cat > "$LEDGER" <<'EOF'
run_id	repo	commit_sha	suite_root	worker_id	test_file	test_count	wall_sec	status	failure_count	skip_count	cache_hit	measured_at	resource_tags	source_fingerprint
EOF
}

teardown() {
  rm -rf "$TMP_DIR"
}

append_row() {
  local run_id="$1" suite="$2" status="$3" cache_hit="$4" measured_at="$5"
  printf '%s\trepo\tsha\t%s\tworker\ttests/unit/example.bats\t1\t0.1\t%s\t0\t0\t%s\t%s\tnone\tfingerprint\n' \
    "$run_id" "$suite" "$status" "$cache_hit" "$measured_at" >> "$LEDGER"
}

run_gate() {
  run env \
    PATH="$BIN:/usr/bin:/bin" \
    TEST_TIMING_LEDGER="$LEDGER" \
    TESTS_DIR="$TESTS" \
    TEST_SPEED_REPORT_DIR="$REPORTS" \
    LEDGER_STALE_HOURS=1000000 \
    bash scripts/gates/gate_test_health.sh --ledger-health
}

@test "ledger freshness accepts Z and offset timestamps while ignoring empty and invalid values" {
  append_row z all pass 0 '2026-07-21T09:00:00Z'
  append_row offset unit pass 0 '2026-07-21T19:00:00+09:00'
  append_row empty all pass 0 ''
  append_row invalid unit pass 0 'not-a-timestamp'

  run_gate

  # The pre-existing ratchet reports ALERT for invalid/mixed runs; freshness
  # itself must still select the two valid equivalent instants.
  [ "$status" -eq 1 ]
  [[ "$output" == *"OK: timing ledger fresh"* ]]
}

@test "ledger freshness retains status cache and suite filters" {
  append_row good all pass 0 '2026-07-21T10:00:00Z'
  append_row failed all fail 0 '2099-01-01T00:00:00Z'
  append_row cached all pass 1 '2099-01-01T00:00:00Z'
  append_row other integration pass 0 '2099-01-01T00:00:00Z'

  run_gate

  # One comparable run retains the pre-existing ratchet warm-up ALERT.
  [ "$status" -eq 1 ]
  [[ "$output" == *"OK: timing ledger fresh"* ]]
}

@test "8195 matching rows finish within one second without invoking external date" {
  for ((i = 1; i <= 8195; i++)); do
    append_row "run-$i" all pass 0 '2026-07-21T10:00:00Z'
  done
  cat > "$BIN/date" <<'EOF'
#!/usr/bin/env bash
echo invoked >> "${DATE_FORK_LOG:?}"
exec /usr/bin/date "$@"
EOF
  chmod +x "$BIN/date"
  DATE_FORK_LOG="$TMP_DIR/date-forks"
  : > "$DATE_FORK_LOG"

  start_ns="$(/usr/bin/date +%s%N)"
  run env DATE_FORK_LOG="$DATE_FORK_LOG" \
    PATH="$BIN:/usr/bin:/bin" \
    TEST_TIMING_LEDGER="$LEDGER" \
    TESTS_DIR="$TESTS" \
    TEST_SPEED_REPORT_DIR="$REPORTS" \
    LEDGER_STALE_HOURS=1000000 \
    bash scripts/gates/gate_test_health.sh --ledger-health
  end_ns="$(/usr/bin/date +%s%N)"
  elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))

  [ "$status" -eq 0 ]
  [ "$elapsed_ms" -lt 1000 ]
  [ ! -s "$DATE_FORK_LOG" ]
}

# test_necessity: A changed test's budget must use its own median plus robust
# dispersion, so one contention spike cannot cause a false regression while a
# shifted representative runtime still blocks.
@test "ratchet uses per-file median and MAD instead of cohort p95" {
  export TEST_TIMING_RATCHET_SUITE_ABS_SEC=1000
  # config/test_timing_budget_exceptions.tsv is a live operational file: any
  # unexpired entry turns the expected BLOCK into "WARN: ... active measured
  # exception suppresses BLOCK" (exit 1).  Measured 2026-07-26: an entry
  # expiring 2026-07-31 made this case fail while the median+MAD logic itself
  # was intact.  Isolate it here only -- the other cases must keep the exact
  # conditions they had, so the shared helper is left untouched.  A path that
  # does not exist means no active exception; an empty file would instead trip
  # the schema BLOCK.
  export TEST_TIMING_RATCHET_EXCEPTIONS="$TMP_DIR/absent_exceptions.tsv"
  local i value
  for i in 1 2 3 4 5 6 7 8 9; do
    value=10
    [ "$i" = 4 ] && value=100
    printf 'r%s\trepo\told%s\tunit\tworker\ttests/unit/noisy.bats\t1\t%s\tpass\t0\t0\t0\t2026-07-%02dT00:00:00Z\tmode=unit;jobs=8\told\n' \
      "$i" "$i" "$value" "$((20 + i))" >> "$LEDGER"
  done
  printf 'r10\trepo\tnew\tunit\tworker\ttests/unit/noisy.bats\t1\t12\tpass\t0\t0\t0\t2026-07-30T00:00:00Z\tmode=unit;jobs=8\tnew\n' >> "$LEDGER"

  run_gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: timing budget ratchet"* ]]

  sed -i -e '/^r7\t/s/\t10\tpass/\t20\tpass/' \
    -e '/^r8\t/s/\t10\tpass/\t20\tpass/' \
    -e '/^r9\t/s/\t10\tpass/\t20\tpass/' \
    -e '/^r10\t/s/\t12\tpass/\t20\tpass/' "$LEDGER"
  run_gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK: new/changed test budget exceeded: tests/unit/noisy.bats"* ]]
}
