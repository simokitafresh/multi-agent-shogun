#!/usr/bin/env bats
# test_count_gate_metrics.bats — count_gate_metrics.sh の集計挙動を検証

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/count_gate_metrics.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/count_gate_metrics.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/logs"
    cp "$SRC_SCRIPT" "$TEST_TMPDIR/scripts/count_gate_metrics.sh"
    chmod +x "$TEST_TMPDIR/scripts/count_gate_metrics.sh"
    export TEST_SCRIPT="$TEST_TMPDIR/scripts/count_gate_metrics.sh"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "missing log returns 0 with message" {
    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gate metrics log not found"* ]]
}

@test "latest status per cmd is deduped and compound block reasons are split" {
    cat > "$TEST_TMPDIR/logs/gate_metrics.log" <<'EOF'
2026-04-02T01:00:00	cmd_1	BLOCK	report_format:foo|ci_failure:run_1	impl	unknown	unknown	none
2026-04-02T01:01:00	cmd_1	CLEAR	all_gates_passed	impl	unknown	unknown	none
2026-04-02T01:02:00	cmd_2	BLOCK	report_format:foo|ci_failure:run_1	impl	unknown	unknown	none
2026-04-02T01:03:00	cmd_3	BLOCK	ci_failure:run_1	impl	unknown	unknown	none
EOF

    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"対象(cmd最新状態): 3件"* ]]
    [[ "$output" == *"CLEAR: 1件"* ]]
    [[ "$output" == *"BLOCK: 2件"* ]]
    [[ "$output" == *"BLOCK率: 66.67%"* ]]
    [[ "$output" == *"  ci_failure:run_1: 2件"* ]]
    [[ "$output" == *"  report_format:foo: 1件"* ]]
}

@test "no latest block entries prints none" {
    cat > "$TEST_TMPDIR/logs/gate_metrics.log" <<'EOF'
2026-04-02T01:00:00	cmd_1	BLOCK	report_format:foo	impl	unknown	unknown	none
2026-04-02T01:01:00	cmd_1	CLEAR	all_gates_passed	impl	unknown	unknown	none
2026-04-02T01:02:00	cmd_2	CLEAR	all_gates_passed	impl	unknown	unknown	none
EOF

    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK: 0件"* ]]
    [[ "$output" == *"  (none)"* ]]
}
