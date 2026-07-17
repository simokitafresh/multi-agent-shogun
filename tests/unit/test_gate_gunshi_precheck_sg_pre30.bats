#!/usr/bin/env bats
# SG-PRE30: daemon lib-only再利用時の機械列挙BLOCK(LG046)回帰テスト
# 本体の_sg_pre30_check関数をsourceして直接呼び出す(ロジック複製排除)

setup() {
    export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
    TEST_REPORT="$TMPDIR/test_pre30_report_$$.yaml"
    # 本体スクリプトから_sg_pre30_check関数だけを抽出してsource
    # (スクリプト全体のset -euo pipefail + main実行を回避)
    eval "$(sed -n '/_sg_pre30_check()/,/^}/p' scripts/gates/gate_gunshi_report_precheck.sh)"
}

teardown() {
    rm -f "$TEST_REPORT"
}

@test "SG-PRE30: daemon script without enumeration evidence is blocked" {
    cat > "$TEST_REPORT" << 'EOF'
cmd_id: cmd_test_pre30_daemon
files_modified:
  - scripts/ninja_monitor.sh
  - scripts/lib/dashboard_helpers.sh
result:
  summary: "ninja_monitor修正"
EOF
    run _sg_pre30_check "$TEST_REPORT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(LG046)"* ]]
}

@test "SG-PRE30: ntfy_listener without evidence is blocked" {
    cat > "$TEST_REPORT" << 'EOF'
cmd_id: cmd_test_pre30_ntfy
files_modified:
  - scripts/ntfy_listener.sh
result:
  summary: "ntfy修正"
EOF
    run _sg_pre30_check "$TEST_REPORT"
    [ "$status" -eq 2 ]
}

@test "SG-PRE30: inbox_watcher without evidence is blocked" {
    cat > "$TEST_REPORT" << 'EOF'
cmd_id: cmd_test_pre30_watcher
files_modified:
  - scripts/inbox_watcher.sh
result:
  summary: "watcher修正"
EOF
    run _sg_pre30_check "$TEST_REPORT"
    [ "$status" -eq 2 ]
}

@test "SG-PRE30: LIB_ONLY mention without evidence is blocked" {
    cat > "$TEST_REPORT" << 'EOF'
cmd_id: cmd_test_pre30_libonly
files_modified:
  - scripts/lib/dashboard_helpers.sh
result:
  summary: "NINJA_MONITOR_LIB_ONLY=1でsource再利用"
EOF
    run _sg_pre30_check "$TEST_REPORT"
    [ "$status" -eq 2 ]
}

@test "SG-PRE30: no daemon/lib-only shows PASS" {
    cat > "$TEST_REPORT" << 'EOF'
cmd_id: cmd_test_pre30_clean
files_modified:
  - scripts/gates/gate_report_format.sh
  - docs/research/analysis.md
result:
  summary: "gate修正のみ"
EOF
    run _sg_pre30_check "$TEST_REPORT"
    [[ "$output" == *"PASS"* ]]
    [ "$status" -eq 0 ]
}

@test "SG-PRE30: complete enumeration evidence passes" {
    cat > "$TEST_REPORT" << 'EOF'
cmd_id: cmd_test_pre30_chars
files_modified:
  - scripts/ninja_monitor.sh
result:
  summary: "daemon関数修正"
operational_simulation:
  command: "sed -n '/target_fn()/,/^}/p' scripts/ninja_monitor.sh | grep -oE '\$[A-Z_][A-Z0-9_]*|\$\{[A-Z_][A-Z0-9_]*' | sort -u"
  expected: "全参照グローバルを列挙し、lib-only時の初期化を突合"
  actual: "$KARO_PANE $PANE_TARGETS $GUNSHI_PANE"
  result: PASS
EOF
    run _sg_pre30_check "$TEST_REPORT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS(LG046)"* ]]
    [[ "$output" != *"��"* ]]
}

@test "SG-PRE30: ninja_monitor in result.summary only does NOT false-positive" {
    # files_modifiedにdaemonスクリプトなし、result.summaryにのみninja_monitor言及
    cat > "$TEST_REPORT" << 'EOF'
cmd_id: cmd_test_pre30_fp
files_modified:
  - docs/research/analysis.md
result:
  summary: "ninja_monitorのログ分析のみ。変更対象ではない"
EOF
    run _sg_pre30_check "$TEST_REPORT"
    [[ "$output" == *"PASS"* ]]
    [ "$status" -eq 0 ]
}

@test "SG-PRE30: daemon keyword in unrelated field after files_modified does NOT trigger" {
    # daemon keyword appears in lesson_candidate (after files_modified block ends)
    cat > "$TEST_REPORT" << 'EOF'
cmd_id: cmd_test_pre30_field
files_modified:
  - scripts/gates/gate_report_format.sh
lesson_candidate:
  found: true
  summary: "ninja_monitorのstall検知改善の教訓"
result:
  summary: "gate修正"
EOF
    run _sg_pre30_check "$TEST_REPORT"
    [[ "$output" == *"PASS"* ]]
    [ "$status" -eq 0 ]
}

@test "SG-PRE30: enumeration command without actual result is blocked" {
    cat > "$TEST_REPORT" << 'EOF'
files_modified:
  - scripts/ninja_monitor.sh
operational_simulation:
  command: "grep -oE '\$[A-Z_][A-Z0-9_]*' scripts/ninja_monitor.sh"
  expected: "globals listed"
  actual: ""
  result: PASS
EOF
    run _sg_pre30_check "$TEST_REPORT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"actual"* ]]
}

@test "SG-PRE30: enumeration with failed initialization comparison is blocked" {
    cat > "$TEST_REPORT" << 'EOF'
files_modified:
  - scripts/inbox_watcher.sh
operational_simulation:
  command: "grep -oE '\$[A-Z_][A-Z0-9_]*' scripts/inbox_watcher.sh"
  expected: "globals initialized"
  actual: "$SCRIPT_DIR"
  result: FAIL
EOF
    run _sg_pre30_check "$TEST_REPORT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"PASS証拠"* ]]
}
