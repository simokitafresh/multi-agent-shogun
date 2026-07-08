#!/usr/bin/env bats
# test_detector_fp_rate.bats — detector FP rate ledger generation

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d)"
    mkdir -p "$TEST_TMPDIR/logs"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "detector_fp_rate counts cmd_save WARN followed by PASS as false_positive" {
    cat > "$TEST_TMPDIR/logs/gate_fire_log.yaml" <<'EOF'
- ts: "2026-07-08T08:49:47", file: "cmd_3757", gate: "cmd_save", result: WARN, checks: "check_ac_param_sufficiency", reasons: "ac_param_sufficiency|check=check_ac_param_sufficiency"
- ts: "2026-07-08T09:00:00", file: "cmd_3757", gate: "cmd_save", result: PASS, checks: "", reasons: ""
EOF
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries: []
EOF
    cat > "$TEST_TMPDIR/logs/gate_alerts.yaml" <<'EOF'
alerts: []
EOF

    run env DETECTOR_FP_ROOT="$TEST_TMPDIR" bash "$PROJECT_ROOT/scripts/detector_fp_rate.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cmd_save:check_ac_param_sufficiency: fp_rate=100.0% fp=1/1"* ]]
    grep -q 'detector: "cmd_save:check_ac_param_sufficiency"' "$TEST_TMPDIR/logs/detector_fp_rate.yaml"
    grep -q 'outcome: "false_positive"' "$TEST_TMPDIR/logs/detector_fp_rate.yaml"
}
