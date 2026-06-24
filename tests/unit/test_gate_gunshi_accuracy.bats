#!/usr/bin/env bats
# test_gate_gunshi_accuracy.bats — gate_gunshi_accuracy.sh 公正計算テスト
# 全テストがスクリプト本体(gate_gunshi_accuracy.sh <fixture>)の出力を検証する

setup() {
    TEST_ROOT="${BATS_TEST_DIRNAME}/../.."
    TEST_TMP="$BATS_TEST_TMPDIR"
    cat > "$TEST_TMP/review_log.yaml" <<'YAML'
- cmd_id: test_lgtm_clear
  review_type: report
  verdict: LGTM
  gate_prediction: CLEAR
  gate_result: CLEAR
- cmd_id: test_fail_block_clear
  review_type: report
  verdict: FAIL
  gate_prediction: BLOCK
  gate_result: CLEAR
- cmd_id: test_lgtm_warn_clear
  review_type: report
  verdict: LGTM
  gate_prediction: WARN
  gate_result: CLEAR
- cmd_id: test_lgtm_clear2
  review_type: report
  verdict: LGTM
  gate_prediction: CLEAR
  gate_result: CLEAR
YAML
}

@test "FAIL→BLOCK→CLEAR is counted as correct (✓ in output)" {
    run bash "$TEST_ROOT/scripts/gates/gate_gunshi_accuracy.sh" "$TEST_TMP/review_log.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ verdict=FAIL"*"pred=BLOCK"*"result=CLEAR"*"test_fail_block_clear"* ]]
}

@test "LGTM→WARN→CLEAR is counted as incorrect (偽陽性 in output)" {
    run bash "$TEST_ROOT/scripts/gates/gate_gunshi_accuracy.sh" "$TEST_TMP/review_log.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"偽陽性"*"test_lgtm_warn_clear"* ]]
}

@test "overall accuracy on fixture is 3/4 = 75%" {
    run bash "$TEST_ROOT/scripts/gates/gate_gunshi_accuracy.sh" "$TEST_TMP/review_log.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"75%"* ]]
}
