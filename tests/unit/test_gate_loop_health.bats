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

@test "gate_loop_health fail rate warning uses recent 20 entries not lifetime totals" {
    {
        for i in $(seq 1 30); do
            printf -- '- ts: "2026-04-19T13:%02d:00" file: "queue/reports/old_report_%02d.yaml" result: FAIL reasons: "old_pattern MISSING" fixes: ""\n' "$i" "$i"
        done
        for i in $(seq 1 20); do
            printf -- '- ts: "2026-04-19T14:%02d:00" file: "queue/reports/recent_report_%02d.yaml" result: PASS reasons: "" fixes: ""\n' "$i" "$i"
        done
    } > "$TEST_TMPDIR/logs/gate_fire_log.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING: FAIL率20%超"* ]]
    [[ "$output" == *"OK: 直近のFAILパターンなし"* ]]
}

@test "gate_loop_health INVESTIGATE recommendations use recent 20 reason counts" {
    {
        for i in $(seq 1 12); do
            printf -- '- ts: "2026-04-19T13:%02d:00" file: "queue/reports/old_report_%02d.yaml" result: FAIL reasons: "legacy_field MISSING" fixes: ""\n' "$i" "$i"
        done
        for i in $(seq 1 20); do
            printf -- '- ts: "2026-04-19T14:%02d:00" file: "queue/reports/recent_report_%02d.yaml" result: PASS reasons: "" fixes: ""\n' "$i" "$i"
        done
    } > "$TEST_TMPDIR/logs/gate_fire_log.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *'INVESTIGATE: "legacy_field MISSING"'* ]]
    [[ "$output" == *"現時点で成熟提案なし"* ]]
}

@test "gate_loop_health fail rate warning threshold is above 30 percent" {
    {
        for i in $(seq 1 5); do
            printf -- '- ts: "2026-04-19T13:%02d:00" file: "queue/reports/old_report_%02d.yaml" result: FAIL reasons: "old_pattern MISSING" fixes: ""\n' "$i" "$i"
        done
        printf -- '- ts: "2026-04-19T13:30:00" file: "queue/reports/autofixed_report.yaml" result: AUTO-FIXED reasons: "" fixes: "fixed"\n'
        for i in $(seq 1 7); do
            printf -- '- ts: "2026-04-19T14:%02d:00" file: "queue/reports/recent_fail_%02d.yaml" result: FAIL reasons: "recent_quality_issue" fixes: ""\n' "$i" "$i"
        done
        for i in $(seq 1 13); do
            printf -- '- ts: "2026-04-19T15:%02d:00" file: "queue/reports/recent_pass_%02d.yaml" result: PASS reasons: "" fixes: ""\n' "$i" "$i"
        done
    } > "$TEST_TMPDIR/logs/gate_fire_log.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"WARNING: FAIL率30%超"* ]]
    [[ "$output" != *"WARNING: FAIL率20%超"* ]]
}
