#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_autofix_proposal.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_autofix_proposal.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/logs"
    cp "$SRC_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_autofix_proposal.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_autofix_proposal.sh"

    cat > "$TEST_TMPDIR/scripts/insight_write.sh" <<'EOF'
#!/usr/bin/env bash
printf 'INSIGHT:%s\n' "$1"
EOF
    chmod +x "$TEST_TMPDIR/scripts/insight_write.sh"

    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_autofix_proposal.sh"
    export SHOGUN_STARTUP_ROOT="$TEST_TMPDIR"
}

teardown() {
    unset SHOGUN_STARTUP_ROOT
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "gate_autofix_proposal normalizes recent BLOCK patterns and emits proposals at threshold" {
    cat > "$TEST_TMPDIR/logs/gate_metrics.log" <<'EOF'
2026-04-25T10:00:00	cmd_1	BLOCK	report_format:saizo_report_cmd_1.yaml|saizo:binary_checks_fail	impl	model	routine	none	title
2026-04-25T10:01:00	cmd_2	BLOCK	saizo:binary_checks_fail	impl	model	routine	none	title
2026-04-25T10:02:00	cmd_3	BLOCK	hayate:binary_checks_fail|draft_lessons:1	impl	model	routine	none	title
2026-04-25T10:03:00	cmd_4	BLOCK	report_format:hayate_report_cmd_4.yaml	impl	model	routine	none	title
2026-04-25T10:04:00	cmd_5	CLEAR	all_gates_passed	impl	model	routine	none	title
EOF

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Recent BLOCK window: 50"* ]]
    [[ "$output" == *"[3] binary_checks_fail :: report_yaml"* ]]
    [[ "$output" == *"[2] report_format :: report_yaml"* ]]
    [[ "$output" == *"[1] draft_lessons :: lesson_flow"* ]]
    [[ "$output" == *"binary_checks_fail: INSIGHT:AUTOFIX-PROPOSAL: binary_checks_fail -> instructions/ashigaru.md"* ]]
    [[ "$output" != *"report_format: INSIGHT:"* ]]
}

@test "gate_autofix_proposal uses only the most recent 50 BLOCK rows" {
    : > "$TEST_TMPDIR/logs/gate_metrics.log"
    printf '2026-04-24T00:00:00\tcmd_old\tBLOCK\tdraft_lessons:1\timpl\tmodel\troutine\tnone\ttitle\n' >> "$TEST_TMPDIR/logs/gate_metrics.log"
    for i in $(seq 1 50); do
        printf '2026-04-25T00:%02d:00\tcmd_%02d\tBLOCK\tsaizo:binary_checks_fail\timpl\tmodel\troutine\tnone\ttitle\n' "$i" "$i" >> "$TEST_TMPDIR/logs/gate_metrics.log"
    done

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[50] binary_checks_fail :: report_yaml"* ]]
    [[ "$output" != *"draft_lessons :: lesson_flow"* ]]
}
