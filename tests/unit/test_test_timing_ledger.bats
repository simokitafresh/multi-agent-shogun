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

@test "direct timed bats wrapper publishes one ledger row" {
  cat >"$TMPROOT/direct.bats" <<'EOF'
@test "direct pass" { true; }
EOF
  before=0
  [ ! -f "$TEST_TIMING_LEDGER" ] || before="$(wc -l <"$TEST_TIMING_LEDGER")"
  run env SHOGUN_REPO_ROOT="$ROOT" TEST_TIMING_LEDGER="$TEST_TIMING_LEDGER" \
    bash "$ROOT/scripts/run_timed_bats.sh" "$TMPROOT/direct.bats"
  [ "$status" -eq 0 ]
  after="$(wc -l <"$TEST_TIMING_LEDGER")"
  [ "$after" -eq "$((before + 2))" ]
  awk -F'\t' -v f="$TMPROOT/direct.bats" 'NR==2{exit !($4=="direct" && $6==f && $9=="pass" && $10==0)}' "$TEST_TIMING_LEDGER"
}

@test "ledger health warns when completed speed report has no timing row" {
  make_row fresh unit tests/recorded.bats 1.0 0 "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$TMPROOT/fresh"
  bash "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/fresh"
  mkdir -p "$TMPROOT/reports"
  cat >"$TMPROOT/reports/ninja_report_cmd_training_test_speed_missing.yaml" <<'EOF'
status: completed
parent_cmd: cmd_training_test_speed_missing
files_modified:
  - path: tests/missing.bats
EOF
  run env TESTS_DIR="$TMPROOT/empty" TEST_TIMING_LEDGER="$TEST_TIMING_LEDGER" \
    TEST_SPEED_REPORT_DIR="$TMPROOT/reports" bash "$ROOT/scripts/gates/gate_test_health.sh" --ledger-health
  [ "$status" -eq 1 ]
  [[ "$output" == *"timing path coverage: 0/1"* ]]
  [[ "$output" == *"has no timing ledger row"* ]]
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

run_asset_gate() {
  env TESTS_DIR="$TMPROOT/assets" TEST_TIMING_LEDGER="$TMPROOT/missing-ledger.tsv" \
    TEST_ASSET_CATALOG="$TMPROOT/catalog.tsv" TEST_PRODUCTION_ROOT="$TMPROOT" \
    bash "$ROOT/scripts/gates/gate_test_health.sh"
}

@test "stale fixture emits four-column static catalog and WARN" {
  mkdir -p "$TMPROOT/assets"
  cat >"$TMPROOT/assets/stale.bats" <<'EOF'
# test-health: production-symbol removed_contract
# test-health: spec-status removed
@test "stale" { run scripts/missing.sh; }
EOF
  run run_asset_gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale candidates: 1"* ]]
  [ "$(head -1 "$TMPROOT/catalog.tsv")" = $'test_file\treferenced_path_exists\tproduction_symbol_exists\tlast_target_change_sha\tspec_status' ]
  awk -F'\t' 'NR==2{exit !($2=="false" && $3=="false" && $5=="removed")}' "$TMPROOT/catalog.tsv"
}

@test "all four allowed mock categories avoid divergence WARN" {
  mkdir -p "$TMPROOT/assets"
  cat >"$TMPROOT/assets/allowed.bats" <<'EOF'
# test-health: mock-category external-service
@test "external" { run mock_http; }
# test-health: mock-category destructive-operation
@test "destructive" { run fake_delete; }
# test-health: mock-category real-time
@test "clock" { run patch_clock; }
# test-health: mock-category failure-injection
@test "failure" { run monkeypatch_failure; }
EOF
  run run_asset_gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"outside mock categories: 0"* ]]
  [[ "$output" != *"mock outside allowed categories"* ]]
}

@test "mock without one of four categories emits divergence WARN" {
  mkdir -p "$TMPROOT/assets"
  cat >"$TMPROOT/assets/outside.bats" <<'EOF'
@test "unclassified" { run mock_internal_helper; }
EOF
  run run_asset_gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside mock categories: 1"* ]]
  [[ "$output" == *"WARN: mock outside allowed categories"* ]]
}
