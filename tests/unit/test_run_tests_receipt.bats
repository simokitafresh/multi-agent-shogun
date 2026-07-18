#!/usr/bin/env bats

setup() {
  ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$ROOT/scripts" "$ROOT/tests/unit" "$ROOT/logs"
  cp "$BATS_TEST_DIRNAME/../../scripts/run_tests.sh" "$ROOT/scripts/run_tests.sh"
  cp "$BATS_TEST_DIRNAME/../../scripts/run_with_receipt.sh" "$ROOT/scripts/run_with_receipt.sh"
  cp "$BATS_TEST_DIRNAME/../../scripts/test_timing_ledger_write.sh" "$ROOT/scripts/test_timing_ledger_write.sh"
  cp "$BATS_TEST_DIRNAME/../../scripts/test_suite_timing_ledger_write.sh" "$ROOT/scripts/test_suite_timing_ledger_write.sh"
  printf '%s\n' '#!/usr/bin/env bash' '[[ "${1:-}" != "--" ]] || shift' \
    'SHOGUN_HEAVY_JOB_LOCK_HELD=1 exec "$@"' > "$ROOT/scripts/heavy_job_admission.sh"
  git -C "$ROOT" init -q
  git -C "$ROOT" add scripts tests
  git -C "$ROOT" -c user.name=test -c user.email=test@example.com commit -qm fixture
  RECEIPT="$ROOT/logs/result.json"
}

@test "admission re-exec preserves receipt-inner and publishes exactly one receipt" {
  make_bats pass
  receipt_dir="$ROOT/logs/test_receipts"
  run env REPO_ROOT="$ROOT" RUN_TESTS_RECEIPT_DIR="$receipt_dir" \
    BATS_CACHE=0 SHOGUN_HEAVY_JOB_LOCK_FILE="$ROOT/heavy.lock" \
    bash "$ROOT/scripts/run_tests.sh" unit
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  [ "$(find "$receipt_dir" -maxdepth 1 -name '*.json' -type f | wc -l)" -eq 1 ]
  [ "$(grep -c 'TEST_RECEIPT_PASS' <<<"$output")" -eq 1 ]
}

make_bats() {
  local mode="$1"
  : > "$ROOT/tests/unit/sample.bats"
  for i in $(seq 1 45); do
    if [[ "$mode" == skip && "$i" -eq 45 ]]; then
      printf '@test "case %s" { skip fixture; }\n' "$i" >> "$ROOT/tests/unit/sample.bats"
    elif [[ "$mode" == fail && "$i" -eq 45 ]]; then
      printf '@test "case %s" { false; }\n' "$i" >> "$ROOT/tests/unit/sample.bats"
    else
      printf '@test "case %s" { true; }\n' "$i" >> "$ROOT/tests/unit/sample.bats"
    fi
  done
}

field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$RECEIPT" "$1"; }

@test "file path emits bounded summary and a verified 45-test receipt" {
  make_bats pass
  run env REPO_ROOT="$ROOT" RUN_TESTS_RECEIPT_PATH="$RECEIPT" bash "$ROOT/scripts/run_tests.sh" file "$ROOT/tests/unit/sample.bats"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_RECEIPT_PASS"* ]]
  [[ "$output" != *"ok 45"* ]]
  [ "$(field observed_test_count)" -eq 45 ]
  [ "$(field declared_test_count)" -eq 45 ]
  [ "$(field skip_count)" -eq 0 ]
}

@test "SKIP and nonzero rc are both fail-closed without rerun" {
  make_bats skip
  run env REPO_ROOT="$ROOT" RUN_TESTS_RECEIPT_PATH="$RECEIPT" bash "$ROOT/scripts/run_tests.sh" file "$ROOT/tests/unit/sample.bats"
  [ "$status" -ne 0 ]
  [ "$(field skip_count)" -eq 1 ]
  make_bats fail
  run env REPO_ROOT="$ROOT" RUN_TESTS_RECEIPT_PATH="$RECEIPT" bash "$ROOT/scripts/run_tests.sh" file "$ROOT/tests/unit/sample.bats"
  [ "$status" -ne 0 ]
  [ "$(field rc)" -ne 0 ]
}

@test "partial TAP and corrupt receipt are rejected" {
  mkdir -p "$ROOT/bin"
  printf '#!/usr/bin/env bash\nprintf "1..45\\nok 1 only\\n"\n' > "$ROOT/bin/bats"
  chmod +x "$ROOT/bin/bats"
  run env PATH="$ROOT/bin:$PATH" REPO_ROOT="$ROOT" RUN_TESTS_RECEIPT_PATH="$RECEIPT" bash "$ROOT/scripts/run_tests.sh" file fixture
  [ "$status" -ne 0 ]
  [ "$(field complete)" = False ]
  printf '{broken\n' > "$RECEIPT"
  run bash "$ROOT/scripts/run_with_receipt.sh" --verify-receipt "$RECEIPT"
  [ "$status" -ne 0 ]
}
