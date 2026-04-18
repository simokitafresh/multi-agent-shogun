#!/usr/bin/env bats
# test_gate_report_format_pass_no_improvement.bats
# cmd_2072: PASS_NO_IMPROVEMENT判定のテスト

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_report_format.sh"
    export GATE_MAIN_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_report_format_main.py"
    [ -f "$GATE_SCRIPT" ] || return 1
    [ -f "$GATE_MAIN_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/pni_test.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/queue/reports" \
             "$TEST_TMPDIR/queue/tasks" \
             "$TEST_TMPDIR/logs"
    cp "$GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
    cp "$GATE_MAIN_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_report_format_main.py"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_combined.py" "$TEST_TMPDIR/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_autofix_main.py" "$TEST_TMPDIR/scripts/gates/"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# 共通ベース報告YAMLを書く(_write_base_pni_report <path> <binary_checks_yaml>)
_write_base_pni_report() {
    local rpath="$1"
    local bc_yaml="$2"
    cat > "$rpath" <<EOF
worker_id: tobisaru
parent_cmd: cmd_2072
ac_version_read: test_hash_abc
status: completed
result:
  summary: "テスト用報告"
  details: "詳細"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified:
  - scripts/gates/gate_report_format_cmd_2072.sh
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用の報告であるため新規教訓なし"
  title: ""
  detail: ""
lessons_useful:
  - id: L001
    useful: true
    reason: helpful
${bc_yaml}
verdict: PASS
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
EOF
}

# === Test 1: 全AC revert → PASS_NO_IMPROVEMENT ===
@test "全ACがrevertを含む場合はPASS_NO_IMPROVEMENTを出力する" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_2072.yaml"
    _write_base_pni_report "$rpath" "binary_checks:
  AC1:
    - check: After>=Beforeなら即revert
      result: yes
  AC2:
    - check: revert済み確認
      result: yes"

    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS_NO_IMPROVEMENT"* ]]
    [[ "$output" == *"WARN"* ]]
}

# === Test 2: 部分 revert (1/3 AC = 33%) → PASS ===
@test "revertが全ACの33%の場合はPASSを出力する" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_2072.yaml"
    _write_base_pni_report "$rpath" "binary_checks:
  AC1:
    - check: After>=Beforeなら即revert
      result: yes
  AC2:
    - check: 改善実装完了
      result: yes
  AC3:
    - check: テスト全PASS
      result: yes"

    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"PASS_NO_IMPROVEMENT"* ]]
}

# === Test 3: revert なし → PASS ===
@test "revertなしの場合はPASSを出力する" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_2072.yaml"
    _write_base_pni_report "$rpath" "binary_checks:
  AC1:
    - check: 改善実装完了
      result: yes
  AC2:
    - check: テスト全PASS
      result: yes"

    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"PASS_NO_IMPROVEMENT"* ]]
}

# === Test 4: PASS_NO_IMPROVEMENT はゲートとしてexit 0 (PASSと同等) ===
@test "PASS_NO_IMPROVEMENTのときゲートはexit 0を返す" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_2072.yaml"
    _write_base_pni_report "$rpath" "binary_checks:
  AC1:
    - check: revert済みで改善なし
      result: yes
  AC2:
    - check: revert適用確認
      result: yes"

    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
}

# === Test 5: verdict=PASS_NO_IMPROVEMENT も有効なverdict として受け付ける ===
@test "verdict=PASS_NO_IMPROVEMENTをninja報告でも受け付ける" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_2072.yaml"
    cat > "$rpath" <<EOF
worker_id: tobisaru
parent_cmd: cmd_2072
ac_version_read: test_hash_abc
status: completed
result:
  summary: "テスト用報告"
  details: "詳細"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified:
  - scripts/gates/gate_report_format_cmd_2072.sh
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用の報告であるため新規教訓なし"
  title: ""
  detail: ""
lessons_useful:
  - id: L001
    useful: true
    reason: helpful
binary_checks:
  AC1:
    - check: 改善実装完了
      result: yes
verdict: PASS_NO_IMPROVEMENT
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
EOF

    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" != *"verdict:"*"is not valid"* ]]
}
