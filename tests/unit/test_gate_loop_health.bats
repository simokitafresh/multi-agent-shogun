#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_loop_health.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_loop_health.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/logs" "$TEST_TMPDIR/queue"
    cp "$SRC_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_loop_health.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_loop_health.sh"

    cat > "$TEST_TMPDIR/scripts/insight_write.sh" <<'EOF'
#!/usr/bin/env bash
echo "INSIGHT_TEST"
exit 0
EOF
    chmod +x "$TEST_TMPDIR/scripts/insight_write.sh"

    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_loop_health.sh"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "gate_loop_health warns when recent CLEAR duration is a strong outlier vs median" {
    cat > "$TEST_TMPDIR/logs/gate_fire_log.yaml" <<'EOF'
- ts: "2026-04-19T14:00:00" file: "queue/reports/sasuke_report_cmd_1.yaml" result: FAIL reasons: "binary_checks.ACx missing" fixes: ""
EOF

    cat > "$TEST_TMPDIR/logs/gate_metrics.log" <<'EOF'
2026-04-19T14:00:00	cmd_1	CLEAR	all_gates_passed	impl	gpt-5.4_high_fast	routine	none	title 1	duration_sec=120
2026-04-19T14:01:00	cmd_2	CLEAR	all_gates_passed	impl	gpt-5.4_high_fast	routine	none	title 2	duration_sec=150
2026-04-19T14:02:00	cmd_3	CLEAR	all_gates_passed	impl	gpt-5.4_high_fast	routine	none	title 3	duration_sec=180
2026-04-19T14:03:00	cmd_4	CLEAR	all_gates_passed	impl	gpt-5.4_high_fast	routine	none	title 4	duration_sec=210
2026-04-19T14:04:00	cmd_5	CLEAR	all_gates_passed	impl	gpt-5.4_high_fast	routine	none	title 5	duration_sec=3600
EOF

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"=== Task Duration Outlier Check ==="* ]]
    [[ "$output" == *"WARNING: task duration異常値 cmd_5 (duration=3600s, median=180.0s, ratio=20.00x, delta=+3420.0s)"* ]]
}
