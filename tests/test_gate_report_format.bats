#!/usr/bin/env bats
# test_gate_report_format.bats — gate_report_format.sh回帰テスト
# GP-073(PASSキャッシュ)、GP-128(verdict整合性)を含む主要チェックのテスト

GATE="scripts/gates/gate_report_format.sh"
TMPDIR_BATS=""

setup() {
    TMPDIR_BATS=$(mktemp -d)
    # Clear PASS cache to ensure clean state
    rm -f logs/.gate_pass_cache
}

teardown() {
    rm -rf "$TMPDIR_BATS"
    rm -f logs/.gate_pass_cache
}

# Helper: create a minimal valid report
create_valid_report() {
    local path="${1:-$TMPDIR_BATS/report.yaml}"
    cat > "$path" << 'YAML'
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
status: completed
binary_checks:
  AC1:
    - check: "テスト対象の確認項目を詳細に記載"
      result: "yes"
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
purpose_validation:
  cmd_purpose: "テスト用途の確認タスク"
  fit: true
  purpose_gap: ""
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
result:
  summary: "テスト結果のサマリ"
verdict: PASS
YAML
    echo "$path"
}

# --- T-001: Valid report → PASS ---
@test "T-001: valid report passes gate" {
    local report=$(create_valid_report)
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# --- T-002: Missing file → FAIL ---
@test "T-002: missing file returns FAIL" {
    run bash "$GATE" "$TMPDIR_BATS/nonexistent.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

# --- T-003: Empty verdict → FAIL ---
@test "T-003: empty verdict returns FAIL" {
    local report=$(create_valid_report)
    sed -i 's/^verdict: PASS/verdict: ""/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"verdict"* ]]
}

# --- T-004: GP-128 PASS+no → FAIL (verdict inconsistency) ---
@test "T-004: GP-128 verdict=PASS with bc no → FAIL" {
    local report=$(create_valid_report)
    sed -i 's/result: "yes"/result: "no"/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"binary_checks contain"* ]]
}

# --- T-005: GP-128 FAIL+all-yes → WARN ---
@test "T-005: GP-128 verdict=FAIL with all-yes → WARN" {
    local report=$(create_valid_report)
    sed -i 's/^verdict: PASS/verdict: FAIL/' "$report"
    run bash "$GATE" "$report"
    # FAIL verdict with all-yes bc → gate FAIL (because of other reason like lesson_candidate)
    # But GP-128 WARN should appear
    [[ "$output" == *"GP-128 WARN"* ]]
}

# --- T-006: GP-073 PASS cache hit ---
@test "T-006: GP-073 second call hits mtime cache" {
    local report=$(create_valid_report)
    # First call: full validation
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    # Verify cache file exists
    [ -f "logs/.gate_pass_cache" ]
    # Second call: should hit cache (no GP-062 WARN etc, just PASS)
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == "PASS" ]]
}

# --- T-007: GP-073 cache invalidation on mtime change ---
@test "T-007: GP-073 cache invalidated on file change" {
    local report=$(create_valid_report)
    # First call: cache
    bash "$GATE" "$report" > /dev/null 2>&1
    [ -f "logs/.gate_pass_cache" ]
    # Modify file (changes mtime)
    sleep 1
    echo "# mtime change" >> "$report"
    # Second call: should NOT hit cache (full validation)
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# --- T-008: Missing binary_checks → FAIL ---
@test "T-008: missing binary_checks returns FAIL" {
    local report=$(create_valid_report)
    sed -i '/^binary_checks:/,/^[a-z]/{ /^binary_checks:/d; /^  /d; }' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"binary_checks"* ]]
}

# --- T-009: YAML parse error → FAIL ---
@test "T-009: invalid YAML returns FAIL" {
    echo "invalid: yaml: : :" > "$TMPDIR_BATS/broken.yaml"
    run bash "$GATE" "$TMPDIR_BATS/broken.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

# --- T-010: FAIL report not cached ---
@test "T-010: FAIL reports are not cached" {
    local report=$(create_valid_report)
    sed -i 's/^verdict: PASS/verdict: ""/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    # Cache should not contain this file
    if [ -f "logs/.gate_pass_cache" ]; then
        run grep "$(realpath "$report")" "logs/.gate_pass_cache"
        [ "$status" -ne 0 ]
    fi
}
