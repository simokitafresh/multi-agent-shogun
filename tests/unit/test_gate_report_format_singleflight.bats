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

# cmd_karo_hotfix_singleflight_fail_misattribution_20260725 (provenance: 118dc5ff8)
# test_necessity: a single-flight lock timeout is infrastructure contention, not a report
# quality problem, and must be distinguishable by callers via exit code alone (not string
# prefix matching, which collides with the ordinary quality-FAIL "FAIL:" prefix).
@test "single-flight lock timeout reports a dedicated exit code and marker, not FAIL:" {
    flock "${REPORT}.gate.lock" sleep 3 &
    lock_pid=$!
    sleep 0.1

    run env GATE_SINGLEFLIGHT_TIMEOUT=1 bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$REPORT"

    wait "$lock_pid"
    [ "$status" -eq 2 ]
    [[ "$output" == "INFRA_TIMEOUT: report gate single-flight timeout: $REPORT" ]]
    [[ "$output" != FAIL:* ]]
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

# cmd_karo_hotfix_control_plane_contracts_ga321_20260723
# test_necessity: SKILL_LOG_SYNCの同期loggerが起動するtransitive background子へreport lock FDを継承させず、親gate直後の後続gateが取得できる不変量。
@test "sync skill logger closes report lock FD before transitive background spawn" {
    run python3 - "$REPO_ROOT/scripts/gates/gate_report_format.sh" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index('if [ "${SKILL_LOG_SYNC:-0}" = "1" ]; then')
end = text.index("else", start)
branch = text[start:end]
assert "exec 199>&-" in branch
assert branch.index("exec 199>&-") < branch.index('bash "$_SKILL_LOG"')
PY
    [ "$status" -eq 0 ]

    lock="$TEST_DIR/transitive.gate.lock"
    (
        exec 199>"$lock"
        flock 199
        (
            exec 199>&-
            sleep 2 &
        )
    )
    run flock -w 1 "$lock" true
    [ "$status" -eq 0 ]
}
