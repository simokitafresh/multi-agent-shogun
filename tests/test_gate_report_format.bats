#!/usr/bin/env bats
# test_gate_report_format.bats — gate_report_format.sh回帰テスト
# GP-073(PASSキャッシュ)、GP-128(verdict整合性)を含む主要チェックのテスト

GATE="scripts/gates/gate_report_format.sh"
AUTOFIX="scripts/gates/gate_report_autofix.sh"
TMPDIR_BATS=""
REPO_TMPDIR_BATS=""

setup() {
    TMPDIR_BATS=$(mktemp -d)
    REPO_TMPDIR_BATS=$(mktemp -d "tests/.tmp_gate_report_format.XXXXXX")
    # --jobs 8並列実行時の競合を回避するためキャッシュ/ログをテストごとに一意化
    export GATE_PASS_CACHE_FILE="$TMPDIR_BATS/.gate_pass_cache"
    export GATE_FIRE_LOG_FILE="$TMPDIR_BATS/gate_fire_log.yaml"
}

teardown() {
    rm -rf "$TMPDIR_BATS"
    rm -rf "$REPO_TMPDIR_BATS"
    unset GATE_PASS_CACHE_FILE GATE_FIRE_LOG_FILE
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

# --- T-003: Empty verdict with unfilled binary_checks → FAIL (autofix cannot derive) ---
@test "T-003: empty verdict with unfilled binary_checks returns FAIL" {
    local report=$(create_valid_report)
    # Set verdict="" AND binary_checks result="" → autofix can't derive verdict
    sed -i 's/^verdict: PASS/verdict: ""/' "$report"
    sed -i 's/result: "yes"/result: ""/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"verdict"* ]]
}

# --- T-004: GP-128 PASS+no → auto-corrected to FAIL verdict → PASS ---
@test "T-004: GP-128 verdict=PASS with bc no → gate FAIL (消火撤去: autofix verdict訂正廃止)" {
    local report=$(create_valid_report)
    sed -i 's/result: "yes"/result: "no"/' "$report"
    # 消火撤去: autofixはverdict訂正しない。GP-128がgate側でFAILする
    run bash "$GATE" "$report"
    [ "$status" -ne 0 ]
    [[ "$output" == *"verdict"* ]]
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
    local report="$REPO_TMPDIR_BATS/cache_report.yaml"
    create_valid_report "$report" >/dev/null
    # First call: full validation
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    # Verify cache file exists
    [ -f "$GATE_PASS_CACHE_FILE" ]
    # Second call: should hit cache (no GP-062 WARN etc, just PASS)
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == "PASS" ]]
}

# --- T-007: GP-073 cache invalidation on mtime change ---
@test "T-007: GP-073 cache invalidated on file change" {
    local report="$REPO_TMPDIR_BATS/cache_invalidate_report.yaml"
    create_valid_report "$report" >/dev/null
    # First call: cache
    bash "$GATE" "$report" > /dev/null 2>&1
    [ -f "$GATE_PASS_CACHE_FILE" ]
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

# --- T-010: FAIL report not cached (use unfixable FAIL: empty result string) ---
@test "T-010: FAIL reports are not cached" {
    local report=$(create_valid_report)
    # Set both verdict="" and binary_checks result="" → autofix can't derive → still FAIL
    sed -i 's/^verdict: PASS/verdict: ""/' "$report"
    sed -i 's/result: "yes"/result: ""/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    # Cache should not contain this file
    if [ -f "$GATE_PASS_CACHE_FILE" ]; then
        run grep "$(realpath "$report")" "$GATE_PASS_CACHE_FILE"
        [ "$status" -ne 0 ]
    fi
}

# --- T-NOLOG-1: GATE_NO_LOG=1 PASS時にgate_fire_logに書込みなし ---
@test "T-NOLOG-1: GATE_NO_LOG=1 skips fire_log on PASS" {
    local report=$(create_valid_report)
    GATE_NO_LOG=1 run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    # fire_log should not exist or not contain this report
    if [ -f "$GATE_FIRE_LOG_FILE" ]; then
        run grep "gate_report_format" "$GATE_FIRE_LOG_FILE"
        [ "$status" -ne 0 ]
    fi
}

# --- T-NOLOG-2: GATE_NO_LOG未設定で通常書込み確認 ---
@test "T-NOLOG-2: without GATE_NO_LOG fire_log is written" {
    local report="$REPO_TMPDIR_BATS/report.yaml"
    create_valid_report "$report" >/dev/null
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    # fire_log should contain an entry
    [ -f "$GATE_FIRE_LOG_FILE" ]
    run grep "gate_report_format" "$GATE_FIRE_LOG_FILE"
    [ "$status" -eq 0 ]
}

# --- T-NOLOG-3: /tmp/テストレポートはfire_logに書き込まない ---
@test "T-NOLOG-3: /tmp reports are excluded from fire_log" {
    local report=$(create_valid_report)
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    if [ -f "$GATE_FIRE_LOG_FILE" ]; then
        run grep "$report" "$GATE_FIRE_LOG_FILE"
        [ "$status" -ne 0 ]
    fi
}

# --- T-011: Autofix binary_checks str→list conversion ---
@test "T-011: autofix converts binary_checks string to list" {
    local report="$TMPDIR_BATS/report.yaml"
    cat > "$report" << 'YAML'
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
status: completed
binary_checks:
  AC1: "テスト対象の確認項目を詳細に記載"
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
    # Run autofix — should convert string to [{check: str, result: yes}]
    run bash "$AUTOFIX" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"binary_checks"* ]]
    # Verify format gate passes after autofix
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
}

# --- T-012: lessons_useful MISSING → BLOCK (消火撤去: スケルトン生成廃止) ---
@test "T-012: lessons_useful MISSING triggers BLOCK not autofix" {
    # Setup directory structure matching report→task path resolution
    mkdir -p "$TMPDIR_BATS/tasks" "$TMPDIR_BATS/reports"
    cat > "$TMPDIR_BATS/tasks/testninja.yaml" << 'YAML'
task:
  related_lessons:
    - id: L001
      summary: "テスト教訓1"
    - id: L002
      summary: "テスト教訓2"
YAML
    local report="$TMPDIR_BATS/reports/testninja_report_cmd_test.yaml"
    # Report WITHOUT lessons_useful key
    cat > "$report" << 'YAML'
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
    # Run gate format check — should FAIL (lessons_useful MISSING → BLOCK)
    # 消火撤去(GP-107): autofixでスケルトン生成=消火。忍者が自力記入すべき
    run bash "$GATE" "$report"
    [ "$status" -ne 0 ]
    [[ "$output" == *"lessons_useful"* ]]
}
