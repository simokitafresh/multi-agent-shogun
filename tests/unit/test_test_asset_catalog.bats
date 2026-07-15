#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPROOT="$(mktemp -d)"
  mkdir -p "$TMPROOT/tests" "$TMPROOT/scripts"
  export TEST_ASSET_CATALOG="$TMPROOT/catalog.tsv"
  export TEST_PRODUCTION_ROOT="$TMPROOT"
  printf '#!/bin/sh\nreal_contract() { :; }\n' >"$TMPROOT/scripts/real.sh"
}

teardown() { rm -rf "$TMPROOT"; }

run_gate() {
  env TESTS_DIR="$TMPROOT/tests" TEST_TIMING_LEDGER="$TMPROOT/missing-ledger.tsv" \
    TEST_ASSET_CATALOG="$TEST_ASSET_CATALOG" TEST_PRODUCTION_ROOT="$TEST_PRODUCTION_ROOT" \
    bash "$ROOT/scripts/gates/gate_test_health.sh"
}

@test "stale fixture emits four-column static catalog and WARN" {
  cat >"$TMPROOT/tests/stale.bats" <<'EOF'
# test-health: production-symbol removed_contract
# test-health: spec-status removed
@test "stale" { run scripts/missing.sh; }
EOF
  run run_gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale candidates: 1"* ]]
  [ "$(head -1 "$TEST_ASSET_CATALOG")" = $'test_file\treferenced_path_exists\tproduction_symbol_exists\tlast_target_change_sha\tspec_status' ]
  awk -F'\t' 'NR==2{exit !($2=="false" && $3=="false" && $5=="removed")}' "$TEST_ASSET_CATALOG"
}

@test "all four allowed mock categories avoid divergence WARN" {
  cat >"$TMPROOT/tests/allowed.bats" <<'EOF'
# test-health: mock-category external-service
@test "external" { run mock_http; }
# test-health: mock-category destructive-operation
@test "destructive" { run fake_delete; }
# test-health: mock-category real-time
@test "clock" { run patch_clock; }
# test-health: mock-category failure-injection
@test "failure" { run monkeypatch_failure; }
EOF
  run run_gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"outside mock categories: 0"* ]]
  [[ "$output" != *"mock outside allowed categories"* ]]
}

@test "mock without one of four categories emits divergence WARN" {
  cat >"$TMPROOT/tests/outside.bats" <<'EOF'
@test "unclassified" { run mock_internal_helper; }
EOF
  run run_gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside mock categories: 1"* ]]
  [[ "$output" == *"WARN: mock outside allowed categories"* ]]
}
