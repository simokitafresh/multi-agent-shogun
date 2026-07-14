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

make_budget_run() {
  local run_id="$1" wall="$2" revision="${3:-sha}" fingerprint="${4:-fp-stable}"
  printf '%s\trepo\t%s\tunit\tbats\ttests/a.bats\t1\t%s\tpass\t0\t0\t%s\t%s\tmode=unit;jobs=1\n' \
    "$run_id" "$revision" "$wall" "$fingerprint" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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

@test "gate clears stale warning but keeps ratchet warm-up WARN after one fresh run" {
  make_row old unit tests/a.bats 1.0 0 2020-01-01T00:00:00Z >"$TMPROOT/old"
  bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/old"
  run env TESTS_DIR="$TMPROOT/empty" TEST_TIMING_LEDGER="$TEST_TIMING_LEDGER" bash "$ROOT/scripts/gates/gate_test_health.sh" --ledger-health
  [ "$status" -ne 0 ]
  [[ "$output" == *"ledger stale"* ]]
  make_row fresh unit tests/a.bats 1.0 0 "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$TMPROOT/fresh"
  bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/fresh"
  run env TESTS_DIR="$TMPROOT/empty" TEST_TIMING_LEDGER="$TEST_TIMING_LEDGER" bash "$ROOT/scripts/gates/gate_test_health.sh" --ledger-health
  [ "$status" -eq 1 ]
  [[ "$output" == *"ledger fresh"* ]]
  [[ "$output" == *"warm-up 2/5"* ]]
}

@test "cache-only recent row does not refresh suite freshness" {
  make_row cached unit tests/a.bats 0 1 "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$TMPROOT/cache"
  bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/cache"
  run env TESTS_DIR="$TMPROOT/empty" TEST_TIMING_LEDGER="$TEST_TIMING_LEDGER" bash "$ROOT/scripts/gates/gate_test_health.sh" --ledger-health
  [ "$status" -ne 0 ]
  [[ "$output" == *"ledger stale"* ]]
}

@test "ratchet keeps BLOCK disabled while comparable run count is below five" {
  for n in 1 2 3 4; do make_budget_run "r$n" 1 >>"$TMPROOT/batch"; done
  bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/batch"
  run env TESTS_DIR="$TMPROOT/empty" TEST_TIMING_LEDGER="$TEST_TIMING_LEDGER" bash "$ROOT/scripts/gates/gate_test_health.sh" --ledger-health
  [ "$status" -eq 1 ]
  [[ "$output" == *"warm-up 4/5"* ]]
  [[ "$output" != *"総合判定: BLOCK"* ]]
}

@test "ratchet blocks a fifth comparable run exceeding absolute and relative limits" {
  for n in 1 2 3 4; do make_budget_run "r$n" 1 >>"$TMPROOT/batch"; done
  make_budget_run r5 40 sha fp-changed >>"$TMPROOT/batch"
  bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/batch"
  run env TESTS_DIR="$TMPROOT/empty" TEST_TIMING_LEDGER="$TEST_TIMING_LEDGER" bash "$ROOT/scripts/gates/gate_test_health.sh" --ledger-health
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK: new/changed test budget exceeded"* ]]
  [[ "$output" == *"BLOCK: suite wall exceeded"* ]]
}

@test "ratchet does not file-BLOCK an unchanged existing slow test" {
  for n in 1 2 3 4; do make_budget_run "r$n" 1 >>"$TMPROOT/batch"; done
  make_budget_run r5 40 >>"$TMPROOT/batch"
  bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/batch"
  run env TESTS_DIR="$TMPROOT/empty" TEST_TIMING_LEDGER="$TEST_TIMING_LEDGER" \
    TEST_TIMING_RATCHET_SUITE_ABS_SEC=1000 bash "$ROOT/scripts/gates/gate_test_health.sh" --ledger-health
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN: suite wall regression"* ]]
  [[ "$output" == *"OK: timing budget ratchet"* ]]
  [[ "$output" != *"new/changed test budget exceeded"* ]]
}

@test "ratchet file-BLOCKs the same test when its source fingerprint changes" {
  for n in 1 2 3 4; do make_budget_run "r$n" 1 >>"$TMPROOT/batch"; done
  make_budget_run r5 40 sha fp-changed >>"$TMPROOT/batch"
  bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/batch"
  run env TESTS_DIR="$TMPROOT/empty" TEST_TIMING_LEDGER="$TEST_TIMING_LEDGER" \
    TEST_TIMING_RATCHET_SUITE_ABS_SEC=1000 bash "$ROOT/scripts/gates/gate_test_health.sh" --ledger-health
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK: new/changed test budget exceeded: tests/a.bats"* ]]
  [[ "$output" != *"BLOCK: suite wall exceeded"* ]]
}

@test "ratchet exception requires exact owner expiry reason schema" {
  for n in 1 2 3 4; do make_budget_run "r$n" 1 >>"$TMPROOT/batch"; done
  make_budget_run r5 40 sha fp-changed >>"$TMPROOT/batch"
  bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/batch"
  printf 'owner\texpires\nteam\t2099-01-01\n' >"$TMPROOT/exceptions.tsv"
  run env TESTS_DIR="$TMPROOT/empty" TEST_TIMING_LEDGER="$TEST_TIMING_LEDGER" \
    TEST_TIMING_RATCHET_EXCEPTIONS="$TMPROOT/exceptions.tsv" bash "$ROOT/scripts/gates/gate_test_health.sh" --ledger-health
  [ "$status" -eq 2 ]
  [[ "$output" == *"exception schema must be owner<TAB>expires<TAB>reason"* ]]

  printf 'owner\texpires\treason\nteam\t2099-01-01\tmeasured fixture overhead\n' >"$TMPROOT/exceptions.tsv"
  run env TESTS_DIR="$TMPROOT/empty" TEST_TIMING_LEDGER="$TEST_TIMING_LEDGER" \
    TEST_TIMING_RATCHET_EXCEPTIONS="$TMPROOT/exceptions.tsv" bash "$ROOT/scripts/gates/gate_test_health.sh" --ledger-health
  [ "$status" -eq 1 ]
  [[ "$output" == *"active measured exception suppresses BLOCK"* ]]
}

@test "mixed revision run disables ratchet BLOCK fail-closed" {
  for n in 1 2 3 4; do make_budget_run "r$n" 1 >>"$TMPROOT/batch"; done
  make_budget_run r5 40 >>"$TMPROOT/batch"
  make_budget_run mixed 1 sha-a >>"$TMPROOT/batch"
  make_budget_run mixed 1 sha-b >>"$TMPROOT/batch"
  bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/batch"
  run env TESTS_DIR="$TMPROOT/empty" TEST_TIMING_LEDGER="$TEST_TIMING_LEDGER" bash "$ROOT/scripts/gates/gate_test_health.sh" --ledger-health
  [ "$status" -eq 1 ]
  [[ "$output" == *"mixed revision; BLOCK disabled"* ]]
  [[ "$output" != *"総合判定: BLOCK"* ]]
}
