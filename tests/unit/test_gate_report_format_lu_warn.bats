#!/usr/bin/env bats
# test_gate_report_format_lu_warn.bats — cmd_3561: LU-COMBO WARN tests
# AC1: gate_report_format配下に教訓注入あり+lessons_useful空リストの組合せWARNを追加

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_report_format.sh"
    [ -f "$GATE_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/lu_warn.XXXXXX")"
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

# === Test 1: lesson_candidate.found=true + lessons_useful=[] → WARN (LU-COMBO) ===
@test "LU-COMBO WARN: lesson_candidate.found=true and lessons_useful=[] emits WARN" {
    local rpath="$TEST_TMPDIR/queue/reports/hayate_report_cmd_test.yaml"
    cat > "$rpath" <<'EOF'
worker_id: hayate
parent_cmd: cmd_test
verdict: PASS
result:
  summary: "テスト"
  details: "詳細"
files_modified:
  - path: scripts/foo.sh
    change: modified
lesson_candidate:
  found: true
  title: "テスト教訓"
  detail: "テスト詳細"
lessons_useful: []
binary_checks:
  AC1:
    - check: "テスト完了"
      result: "yes"
causal_verification:
  cause_checked: "確認済み"
  design_intent_checked: "確認済み"
  evidence: "evidence"
  origin: "[[origin]]"
EOF
    run bash "$TEST_GATE" "$rpath"
    [[ "$output" == *"WARN (LU-COMBO)"* ]] || {
        echo "Expected WARN (LU-COMBO) in output but got: $output"
        return 1
    }
}

# === Test 2: lesson_candidate.found=false + lessons_useful=[] → WARNなし ===
@test "LU-COMBO: lesson_candidate.found=false + lessons_useful=[] does NOT emit WARN" {
    local rpath="$TEST_TMPDIR/queue/reports/hayate_report_cmd_test.yaml"
    cat > "$rpath" <<'EOF'
worker_id: hayate
parent_cmd: cmd_test
verdict: PASS
result:
  summary: "テスト"
  details: "詳細"
files_modified:
  - path: scripts/foo.sh
    change: modified
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
binary_checks:
  AC1:
    - check: "テスト完了"
      result: "yes"
EOF
    run bash "$TEST_GATE" "$rpath"
    [[ "$output" != *"WARN (LU-COMBO)"* ]] || {
        echo "Unexpected WARN (LU-COMBO) in output: $output"
        return 1
    }
}

# === Test 3: lesson_candidate.found=true + lessons_useful記入あり → WARNなし ===
@test "LU-COMBO: lesson_candidate.found=true + lessons_useful filled does NOT emit WARN" {
    local rpath="$TEST_TMPDIR/queue/reports/hayate_report_cmd_test.yaml"
    cat > "$rpath" <<'EOF'
worker_id: hayate
parent_cmd: cmd_test
verdict: PASS
result:
  summary: "テスト"
  details: "詳細"
files_modified:
  - path: scripts/foo.sh
    change: modified
lesson_candidate:
  found: true
  title: "テスト教訓"
  detail: "テスト詳細"
lessons_useful:
  - id: L001
    useful: true
    reason: "このタスクで直接役立った"
binary_checks:
  AC1:
    - check: "テスト完了"
      result: "yes"
causal_verification:
  cause_checked: "確認済み"
  design_intent_checked: "確認済み"
  evidence: "evidence"
  origin: "[[origin]]"
EOF
    run bash "$TEST_GATE" "$rpath"
    [[ "$output" != *"WARN (LU-COMBO)"* ]] || {
        echo "Unexpected WARN (LU-COMBO) in output: $output"
        return 1
    }
}

# === Test 4: GATE_LU_COMBO_WARN_DISABLE=1 → WARNが抑制される ===
@test "LU-COMBO: GATE_LU_COMBO_WARN_DISABLE=1 suppresses WARN" {
    local rpath="$TEST_TMPDIR/queue/reports/hayate_report_cmd_test.yaml"
    cat > "$rpath" <<'EOF'
worker_id: hayate
parent_cmd: cmd_test
verdict: PASS
result:
  summary: "テスト"
  details: "詳細"
files_modified:
  - path: scripts/foo.sh
    change: modified
lesson_candidate:
  found: true
  title: "テスト教訓"
  detail: "テスト詳細"
lessons_useful: []
binary_checks:
  AC1:
    - check: "テスト完了"
      result: "yes"
EOF
    GATE_LU_COMBO_WARN_DISABLE=1 run bash "$TEST_GATE" "$rpath"
    [[ "$output" != *"WARN (LU-COMBO)"* ]] || {
        echo "WARN (LU-COMBO) should be suppressed when GATE_LU_COMBO_WARN_DISABLE=1 but got: $output"
        return 1
    }
}
