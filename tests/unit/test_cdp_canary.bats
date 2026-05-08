#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TMP_DIR="$(mktemp -d)"
    FAKE_BENCHMARK="${TMP_DIR}/fake_benchmark.sh"
}

teardown() {
    rm -rf "$TMP_DIR"
}

write_fake_benchmark() {
    cat > "$FAKE_BENCHMARK" <<EOF
#!/usr/bin/env bash
$1
EOF
    chmod +x "$FAKE_BENCHMARK"
}

@test "cdp_canary: explicit PASS output resets alert streak" {
    write_fake_benchmark "echo '- Dashboard [warm-reload] status=PASS regression=PASS health=100'"

    run env CDP_BENCHMARK_SCRIPT="$FAKE_BENCHMARK" \
        bash "$PROJECT_ROOT/scripts/cdp_canary.sh" \
        --target dashboard --runs 1 --interval 1 --consecutive-alerts 1

    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT target=dashboard run=1 status=PASS"* ]]
    [[ "$output" == *"OK target=dashboard"* ]]
}

@test "cdp_canary: unknown successful output counts toward alert streak" {
    write_fake_benchmark "echo 'benchmark completed without regression summary'"

    run env CDP_BENCHMARK_SCRIPT="$FAKE_BENCHMARK" \
        bash "$PROJECT_ROOT/scripts/cdp_canary.sh" \
        --target dashboard --runs 1 --interval 1 --consecutive-alerts 1

    [ "$status" -eq 1 ]
    [[ "$output" == *"RESULT target=dashboard run=1 status=UNKNOWN"* ]]
    [[ "$output" == *"ALERT target=dashboard consecutive_alerts=1 threshold=1"* ]]
}
