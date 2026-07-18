#!/usr/bin/env bats
# test_necessity: Atomic PASS receipt with SHA256 hash and verify-receipt detects corruption/tampering fail-closed; violation is BLOCK.

setup() {
    RUNNER="$BATS_TEST_DIRNAME/../../scripts/run_with_receipt.sh"
    RECEIPT="$BATS_TEST_TMPDIR/receipt.json"
}

field() {
    python3 - "$RECEIPT" "$1" <<'PY'
import json, sys
with open(sys.argv[1]) as fh: value=json.load(fh)[sys.argv[2]]
print(str(value).lower() if isinstance(value, bool) else value)
PY
}

@test "rc0 TAP writes complete atomic PASS receipt with counts and hash" {
    run bash "$RUNNER" --receipt "$RECEIPT" --declared-test-count 2 -- bash -c "printf '1..2\nok 1 alpha\nok 2 beta\n'"
    [ "$status" -eq 0 ]
    [ "$(field complete)" = true ]
    [ "$(field result)" = PASS ]
    [ "$(field observed_test_count)" -eq 2 ]
    [ "$(field skip_count)" -eq 0 ]
    [ "$(field output_sha256)" = "$(sha256sum "${RECEIPT%.json}.output" | awk '{print $1}')" ]
}

@test "nonzero command writes durable FAIL receipt" {
    run bash "$RUNNER" --receipt "$RECEIPT" -- bash -c "echo broken; exit 7"
    [ "$status" -ne 0 ]
    [ "$(field complete)" = true ]
    [ "$(field result)" = FAIL ]
    [ "$(field rc)" -eq 7 ]
}

@test "TAP skip is counted and classified FAIL without false positive" {
    run bash "$RUNNER" --receipt "$RECEIPT" --declared-test-count 2 -- bash -c "printf '1..2\nok 1 cannot skip words\nok 2 real # SKIP reason\n'"
    [ "$(field observed_test_count)" -eq 2 ]
    [ "$(field skip_count)" -eq 1 ]
    [ "$(field result)" = FAIL ]
}

@test "partial TAP plan is incomplete even when command rc is zero" {
    run bash "$RUNNER" --receipt "$RECEIPT" -- bash -c "printf '1..3\nok 1 only\nok 2 partial\n'"
    [ "$status" -ne 0 ]
    [ "$(field declared_test_count)" -eq 3 ]
    [ "$(field observed_test_count)" -eq 2 ]
    [ "$(field complete)" = false ]
    [ "$(field result)" = FAIL ]
}

@test "bounded artifact truncates output and receipt remains parseable" {
    run bash "$RUNNER" --receipt "$RECEIPT" --max-bytes 16 -- bash -c "printf '12345678901234567890'"
    [ "$status" -eq 0 ]
    [ "$(wc -c < "${RECEIPT%.json}.output")" -eq 16 ]
    [ "$(field complete)" = true ]
}

@test "TERM during command atomically publishes incomplete receipt" {
    bash "$RUNNER" --receipt "$RECEIPT" -- bash -c 'echo started; sleep 10' > "$BATS_TEST_TMPDIR/term.out" 2>&1 &
    pid=$!
    for _ in {1..50}; do [[ -s "$BATS_TEST_TMPDIR/term.out" ]] && break; sleep 0.02; done
    kill -TERM "$pid"
    wait "$pid" || true
    [ -f "$RECEIPT" ]
    [ "$(field complete)" = false ]
    [ "$(field result)" = FAIL ]
    [ "$(field signal)" = TERM ]
}

@test "help embeds receipt usage and required fields" {
    run bash "$RUNNER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--receipt PATH"* ]]
    [[ "$output" == *"output_sha256"* ]]
    [[ "$output" == *"observed_test_count"* ]]
}

@test "verify-receipt detects JSON corruption and artifact tampering fail-closed" {
    bash "$RUNNER" --receipt "$RECEIPT" -- bash -c 'echo durable'
    run bash "$RUNNER" --verify-receipt "$RECEIPT"
    [ "$status" -eq 0 ]
    printf '{broken\n' > "$RECEIPT"
    run bash "$RUNNER" --verify-receipt "$RECEIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"RECEIPT_FAIL"* ]]

    bash "$RUNNER" --receipt "$RECEIPT" -- bash -c 'echo durable'
    printf 'tamper\n' >> "${RECEIPT%.json}.output"
    run bash "$RUNNER" --verify-receipt "$RECEIPT"
    [ "$status" -ne 0 ]
}

@test "long TAP complete and truncated-terminal fixtures are decided once from receipts" {
    good="$BATS_TEST_TMPDIR/long-good.json"
    bad="$BATS_TEST_TMPDIR/long-bad.json"
    run bash "$RUNNER" --receipt "$good" --declared-test-count 200 -- bash -c \
        'echo 1..200; for i in $(seq 1 200); do echo "ok $i case"; done'
    [ "$status" -eq 0 ]
    [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["observed_test_count"])' "$good")" -eq 200 ]
    run bash "$RUNNER" --verify-receipt "$good"
    [ "$status" -eq 0 ]

    run bash "$RUNNER" --receipt "$bad" --declared-test-count 200 -- bash -c \
        'echo 1..200; for i in $(seq 1 199); do echo "ok $i case"; done'
    [ "$status" -ne 0 ]
    [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["observed_test_count"])' "$bad")" -eq 199 ]
    run bash "$RUNNER" --verify-receipt "$bad"
    [ "$status" -ne 0 ]
}
