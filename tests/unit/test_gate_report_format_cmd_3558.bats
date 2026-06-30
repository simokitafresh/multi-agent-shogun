#!/usr/bin/env bats
# test_gate_report_format_cmd_3558.bats — cmd_3558 AC1/AC2検証
# AC1: commit_hash長検証(short hash FAIL, full hash PASS)
# AC2: files_modified形式検証(空文字列WARN, 数値のみFAIL, パス未含有FAIL)

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_report_format.sh"
    [ -f "$GATE_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd3558.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/queue/reports" \
             "$TEST_TMPDIR/queue/tasks" \
             "$TEST_TMPDIR/logs"
    cp "$GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_main.py" "$TEST_TMPDIR/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_combined.py" "$TEST_TMPDIR/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_autofix_main.py" "$TEST_TMPDIR/scripts/gates/"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# ベースYAMLを生成するヘルパー (commit_hashなし, files_modified=valid)
_base_yaml() {
    local rpath="$1"
    cat > "$rpath" <<'EOF'
worker_id: hayate
parent_cmd: cmd_3558
ac_version_read: abc12345
verdict: FAIL
result:
  summary: "テスト"
  details: "詳細"
files_modified:
  - path: scripts/gates/gate_report_format_main.py
    change: modified
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用のため教訓なし"
lessons_useful: []
causal_verification:
  cause_checked: "確認済み"
  design_intent_checked: "確認済み"
  evidence: "evidence"
  origin: "[[commit_missing_WA_2件]] -> [[gate_report_format未検証]] -> [[GP-287/GP-288追加]]"
binary_checks:
  AC1:
    - check: "テスト完了"
      result: "yes"
  AC2:
    - check: "テスト完了"
      result: "yes"
EOF
}

# ============================================================
# AC1: commit_hash長検証
# ============================================================

# AC1-1: 7文字短縮hash → FAIL (GP-287)
@test "AC1: short commit_hash (7 chars) causes FAIL" {
    local rpath="$TEST_TMPDIR/queue/reports/hayate_report_test_ac1_short.yaml"
    _base_yaml "$rpath"
    printf '\ncommit_hash: abc1234\n' >> "$rpath"

    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 1 ] || {
        echo "Expected exit 1 but got $status. output: $output"
        return 1
    }
    [[ "$output" == *"commit_hash"* ]] || {
        echo "Expected 'commit_hash' in output but got: $output"
        return 1
    }
    [[ "$output" == *"40文字"* ]] || {
        echo "Expected '40文字' in output but got: $output"
        return 1
    }
}

# AC1-2: 40文字フルhash → PASS (GP-287通過)
@test "AC1: full commit_hash (40 hex chars) does not cause commit_hash FAIL" {
    local rpath="$TEST_TMPDIR/queue/reports/hayate_report_test_ac1_full.yaml"
    _base_yaml "$rpath"
    printf '\ncommit_hash: 0000000000000000000000000000000000000001\n' >> "$rpath"

    run bash "$TEST_GATE" "$rpath"
    [[ "$output" != *"commit_hash: '0000000000000000000000000000000000000001' は40文字フルhashでない"* ]] || {
        echo "Unexpected commit_hash error in output: $output"
        return 1
    }
}

# ============================================================
# AC2: files_modified形式検証
# ============================================================

# AC2-1: 空文字列path → GP-288 WARN
@test "AC2: empty path in files_modified emits GP-288 WARN" {
    local rpath="$TEST_TMPDIR/queue/reports/hayate_report_test_ac2_empty.yaml"
    cat > "$rpath" <<'EOF'
worker_id: hayate
parent_cmd: cmd_3558
ac_version_read: abc12345
status: completed
verdict: PASS
result:
  summary: "テスト"
  details: "詳細"
files_modified:
  - path: ""
    change: modified
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用のため教訓なし"
lessons_useful: []
causal_verification:
  cause_checked: "確認済み"
  design_intent_checked: "確認済み"
  evidence: "evidence"
  origin: "[[origin]]"
binary_checks:
  AC1:
    - check: "テスト完了"
      result: "yes"
  AC2:
    - check: "テスト完了"
      result: "yes"
EOF
    run bash "$TEST_GATE" "$rpath"
    [[ "$output" == *"GP-288"* ]] || {
        echo "Expected 'GP-288' in output but got: $output"
        return 1
    }
}

# AC2-2: 数値のみpath ("12345") → GP-286 FAIL (パス形式でない)
@test "AC2: numbers-only path in files_modified causes FAIL (GP-286)" {
    local rpath="$TEST_TMPDIR/queue/reports/hayate_report_test_ac2_num.yaml"
    cat > "$rpath" <<'EOF'
worker_id: hayate
parent_cmd: cmd_3558
ac_version_read: abc12345
status: completed
verdict: FAIL
result:
  summary: "テスト"
  details: "詳細"
files_modified:
  - path: "12345"
    change: modified
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用のため教訓なし"
lessons_useful: []
causal_verification:
  cause_checked: "確認済み"
  design_intent_checked: "確認済み"
  evidence: "evidence"
  origin: "[[origin]]"
binary_checks:
  AC1:
    - check: "テスト完了"
      result: "yes"
  AC2:
    - check: "テスト完了"
      result: "yes"
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 1 ] || {
        echo "Expected exit 1 but got $status. output: $output"
        return 1
    }
    [[ "$output" == *"パス形式でない"* ]] || {
        echo "Expected 'パス形式でない' in output but got: $output"
        return 1
    }
}

# AC2-3: スラッシュなし説明文 ("description text") → GP-286 FAIL
@test "AC2: no-slash description text in files_modified causes FAIL (GP-286)" {
    local rpath="$TEST_TMPDIR/queue/reports/hayate_report_test_ac2_noslash.yaml"
    cat > "$rpath" <<'EOF'
worker_id: hayate
parent_cmd: cmd_3558
ac_version_read: abc12345
status: completed
verdict: FAIL
result:
  summary: "テスト"
  details: "詳細"
files_modified:
  - path: "description text without slash"
    change: modified
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用のため教訓なし"
lessons_useful: []
causal_verification:
  cause_checked: "確認済み"
  design_intent_checked: "確認済み"
  evidence: "evidence"
  origin: "[[origin]]"
binary_checks:
  AC1:
    - check: "テスト完了"
      result: "yes"
  AC2:
    - check: "テスト完了"
      result: "yes"
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 1 ] || {
        echo "Expected exit 1 but got $status. output: $output"
        return 1
    }
    [[ "$output" == *"パス形式でない"* ]] || {
        echo "Expected 'パス形式でない' in output but got: $output"
        return 1
    }
}
