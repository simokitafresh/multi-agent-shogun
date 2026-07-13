#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPROOT="$(mktemp -d)"
  export TEST_TIMING_LEDGER="$TMPROOT/ledger.tsv"
  mkdir -p "$TMPROOT/empty"
}

teardown() { rm -rf "$TMPROOT"; }

make_row() {
  printf '%s\trepo\tsha\t%s\tbats\t%s\t1\t%s\tpass\t0\t%s\tfp\t%s\tmode=%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$2"
}

@test "writer creates exact 14-column schema in tmp ledger" {
  make_row r1 unit tests/a.bats 1.0 0 2026-07-14T00:00:00Z >"$TMPROOT/batch"
  run bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/batch"
  [ "$status" -eq 0 ]
  [ "$(awk -F'\t' 'NR==1{print NF}' "$TEST_TIMING_LEDGER")" -eq 14 ]
  [ "$(awk -F'\t' 'NR==2{print NF}' "$TEST_TIMING_LEDGER")" -eq 14 ]
}

@test "concurrent writers preserve both batches without lost update" {
  make_row r1 unit tests/a.bats 1.0 0 2026-07-14T00:00:00Z >"$TMPROOT/a"
  make_row r2 unit tests/b.bats 2.0 0 2026-07-14T00:01:00Z >"$TMPROOT/b"
  bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/a" & p1=$!
  bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/b" & p2=$!
  wait "$p1"; wait "$p2"
  [ "$(wc -l <"$TEST_TIMING_LEDGER")" -eq 3 ]
  grep -q '^r1' "$TEST_TIMING_LEDGER"
  grep -q '^r2' "$TEST_TIMING_LEDGER"
}

@test "gate warns stale and reports OK after fresh completed non-cache run" {
  make_row old unit tests/a.bats 1.0 0 2020-01-01T00:00:00Z >"$TMPROOT/old"
  bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/old"
  run env TESTS_DIR="$TMPROOT/empty" TEST_TIMING_LEDGER="$TEST_TIMING_LEDGER" bash "$ROOT/scripts/gates/gate_test_health.sh" --ledger-health
  [ "$status" -ne 0 ]
  [[ "$output" == *"ledger stale"* ]]
  make_row fresh unit tests/a.bats 1.0 0 "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$TMPROOT/fresh"
  bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/fresh"
  run env TESTS_DIR="$TMPROOT/empty" TEST_TIMING_LEDGER="$TEST_TIMING_LEDGER" bash "$ROOT/scripts/gates/gate_test_health.sh" --ledger-health
  [ "$status" -eq 0 ]
  [[ "$output" == *"ledger fresh"* ]]
}

@test "cache-only recent row does not refresh suite freshness" {
  make_row cached unit tests/a.bats 0 1 "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$TMPROOT/cache"
  bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/cache"
  run env TESTS_DIR="$TMPROOT/empty" TEST_TIMING_LEDGER="$TEST_TIMING_LEDGER" bash "$ROOT/scripts/gates/gate_test_health.sh" --ledger-health
  [ "$status" -ne 0 ]
  [[ "$output" == *"ledger stale"* ]]
}
