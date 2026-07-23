#!/usr/bin/env bats
# test_necessity: A report generation already validated by the active leader must bypass the same report lock without a false timeout.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_DIR="$(mktemp -d "$REPO_ROOT/.cache/gate-singleflight.XXXXXX")"
    REPORT="$TEST_DIR/report.yaml"
    printf 'worker_id: test\n' >"$REPORT"
    FP="$(sha256sum "$REPORT" | awk '{print $1}')"
    printf '%s\n' "$FP" >"${REPORT}.validated_fingerprints"
}

teardown() {
    find "$TEST_DIR" -type f -delete
    rmdir "$TEST_DIR"
}

@test "validated fingerprint reuse happens before the report singleflight lock" {
    flock "${REPORT}.gate.lock" sleep 3 &
    lock_pid=$!
    sleep 0.1

    run env \
        GATE_SINGLEFLIGHT_TIMEOUT=1 \
        GATE_VALIDATED_FINGERPRINT="$FP" \
        bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$REPORT"

    wait "$lock_pid"
    [ "$status" -eq 0 ]
    [ "$output" = "PASS (fingerprint reuse)" ]
}

@test "one byte report mutation cannot reuse a stale validated fingerprint" {
    printf 'x' >>"$REPORT"

    run env \
        GATE_VALIDATED_FINGERPRINT="$FP" \
        GATE_FAST_EXIT=1 \
        GATE_NO_LOG=1 \
        bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$REPORT"

    [ "$status" -ne 0 ]
    [[ "$output" != *"fingerprint reuse"* ]]
}
