#!/usr/bin/env bats
# SG-PRE31: N×M意味検算リマインド(LG048)の回帰テスト
# 本体の_sg_pre31_check関数をsourceして直接呼び出す

setup() {
    export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
    TEST_REPORT="$TMPDIR/test_pre31_report_$$.yaml"
    # 本体スクリプトから_sg_pre31_check関数だけを抽出してsource
    eval "$(sed -n '/_sg_pre31_check()/,/^}/p' scripts/gates/gate_gunshi_report_precheck.sh)"
}

teardown() {
    rm -f "$TEST_REPORT"
}

@test "SG-PRE31: N×M match (102×3=306) triggers INFO" {
    cat > "$TEST_REPORT" << 'EOF'
cmd_id: cmd_test_pre31_match
result:
  summary: "102 PF × 3日 = 306件のリバランス日を検証"
  details: "全306件が正常。102ポートフォリオ各3日"
EOF
    run _sg_pre31_check "$TEST_REPORT"
    [[ "$output" == *"INFO(LG048)"* ]]
    [[ "$output" == *"意味検算"* ]]
}

@test "SG-PRE31: no N×M match shows PASS" {
    cat > "$TEST_REPORT" << 'EOF'
cmd_id: cmd_test_pre31_clean
result:
  summary: "17件修正、23件確認済み、合計40件"
  details: "特になし"
EOF
    run _sg_pre31_check "$TEST_REPORT"
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"INFO"* ]]
}

@test "SG-PRE31: fewer than 3 numbers shows PASS" {
    cat > "$TEST_REPORT" << 'EOF'
cmd_id: cmd_test_pre31_few
result:
  summary: "200件処理完了"
  details: "正常"
EOF
    run _sg_pre31_check "$TEST_REPORT"
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"数値3個未満"* ]]
}

@test "SG-PRE31: no result block shows SKIP" {
    cat > "$TEST_REPORT" << 'EOF'
cmd_id: cmd_test_pre31_noresult
binary_checks:
  commit:
    check: "commit存在"
    result: "yes"
EOF
    run _sg_pre31_check "$TEST_REPORT"
    [[ "$output" == *"SKIP"* ]]
}

@test "SG-PRE31: large N×M match (50×20=1000) triggers INFO" {
    cat > "$TEST_REPORT" << 'EOF'
cmd_id: cmd_test_pre31_large
result:
  summary: "50銘柄 × 20期間 = 1000データポイント"
  total: 1000
  per_stock: 20
  stocks: 50
EOF
    run _sg_pre31_check "$TEST_REPORT"
    [[ "$output" == *"INFO(LG048)"* ]]
}
