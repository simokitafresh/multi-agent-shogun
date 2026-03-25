#!/usr/bin/env bats
# test_report_field_set_bc_validation.bats
# Purpose: binary_checks型バリデーション — string形式/boolean result/PASS-FAIL resultをBLOCK
# Origin: cmd_cycle_001 (report_field_set.sh GP-072 binary_checks型バリデーション)

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export RFS="$PROJECT_ROOT/scripts/report_field_set.sh"
    [ -f "$RFS" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/rfs_bc.XXXXXX")"
    # Minimal report template
    cat > "$TEST_TMPDIR/report.yaml" <<'EOF'
worker_id: test_ninja
parent_cmd: cmd_test
ac_version_read: abc12345
binary_checks:
  AC1:
    - check: "テスト確認"
      result: ""
verdict: ""
EOF
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# --- AC1: string形式入力 → exit 1 ---

@test "full-field: string形式binary_checksでexit 1" {
    run bash -c 'bash "$RFS" "$TEST_TMPDIR/report.yaml" binary_checks "AC1: YES, AC2: NO" 2>&1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: binary_checks must be YAML list of dicts with result: yes/no."* ]]
}

@test "full-field: bare string入力でexit 1" {
    run bash -c 'bash "$RFS" "$TEST_TMPDIR/report.yaml" binary_checks "all checks passed" 2>&1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: binary_checks must be YAML list of dicts"* ]]
}

@test "per-AC: string形式でexit 1" {
    run bash -c 'bash "$RFS" "$TEST_TMPDIR/report.yaml" binary_checks.AC1 "YES" 2>&1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: binary_checks must be YAML list of dicts"* ]]
}

# --- AC1: result boolean(true/false) → exit 1 ---

@test "full-field: result true でexit 1" {
    run bash -c 'echo "{AC1: [{check: test, result: true}]}" | bash "$RFS" "$TEST_TMPDIR/report.yaml" binary_checks - 2>&1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: binary_checks must be YAML list of dicts"* ]]
}

@test "full-field: result false でexit 1" {
    run bash -c 'echo "{AC1: [{check: test, result: false}]}" | bash "$RFS" "$TEST_TMPDIR/report.yaml" binary_checks - 2>&1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: binary_checks must be YAML list of dicts"* ]]
}

@test "per-AC: result true でexit 1" {
    run bash -c 'echo "[{check: test, result: true}]" | bash "$RFS" "$TEST_TMPDIR/report.yaml" binary_checks.AC1 - 2>&1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: binary_checks must be YAML list of dicts"* ]]
}

# --- AC1: result PASS/FAIL文字列 → exit 1 ---

@test "full-field: result PASS でexit 1" {
    run bash -c 'echo "{AC1: [{check: test, result: PASS}]}" | bash "$RFS" "$TEST_TMPDIR/report.yaml" binary_checks - 2>&1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: binary_checks must be YAML list of dicts"* ]]
}

@test "full-field: result FAIL でexit 1" {
    run bash -c 'echo "{AC1: [{check: test, result: FAIL}]}" | bash "$RFS" "$TEST_TMPDIR/report.yaml" binary_checks - 2>&1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: binary_checks must be YAML list of dicts"* ]]
}

@test "per-AC: result PASS でexit 1" {
    run bash -c 'echo "[{check: test, result: PASS}]" | bash "$RFS" "$TEST_TMPDIR/report.yaml" binary_checks.AC1 - 2>&1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: binary_checks must be YAML list of dicts"* ]]
}

# --- AC1: 正しい形式(result yes/no list) → exit 0 ---

@test "full-field: 正しい形式(result yes)でexit 0" {
    run bash -c 'echo "{AC1: [{check: test, result: yes}]}" | bash "$RFS" "$TEST_TMPDIR/report.yaml" binary_checks - 2>&1'
    [ "$status" -eq 0 ]
}

@test "full-field: 正しい形式(result no)でexit 0" {
    run bash -c 'echo "{AC1: [{check: test, result: no}]}" | bash "$RFS" "$TEST_TMPDIR/report.yaml" binary_checks - 2>&1'
    [ "$status" -eq 0 ]
}

@test "per-AC: 正しい形式(result yes)でexit 0" {
    run bash -c 'echo "[{check: test, result: yes}]" | bash "$RFS" "$TEST_TMPDIR/report.yaml" binary_checks.AC1 - 2>&1'
    [ "$status" -eq 0 ]
}

@test "full-field: result空文字はexit 0(テンプレート状態許容)" {
    run bash -c 'echo "{AC1: [{check: test, result: \"\"}]}" | bash "$RFS" "$TEST_TMPDIR/report.yaml" binary_checks - 2>&1'
    [ "$status" -eq 0 ]
}
