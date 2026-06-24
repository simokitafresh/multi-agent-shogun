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
- cmd_id: test_rc_block_clear
  review_type: draft
  verdict: REQUEST_CHANGES
  gate_prediction: BLOCK
  gate_result: CLEAR
- cmd_id: test_lgtm_block_clear
  review_type: report
  verdict: LGTM
  gate_prediction: BLOCK
  gate_result: CLEAR
- cmd_id: test_lgtm_clear2
  review_type: report
  verdict: LGTM
  gate_prediction: CLEAR
  gate_result: CLEAR
YAML
}

@test "FAIL→BLOCK→CLEAR is counted as correct (公正計算)" {
    run bash "$TEST_ROOT/scripts/gates/gate_gunshi_accuracy.sh" "$TEST_TMP/review_log.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ verdict=FAIL"*"pred=BLOCK"*"result=CLEAR"*"test_fail_block_clear"* ]]
}

@test "RC→BLOCK→CLEAR is counted as correct (RC指摘→修正→CLEAR)" {
    run bash "$TEST_ROOT/scripts/gates/gate_gunshi_accuracy.sh" "$TEST_TMP/review_log.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ verdict=REQUEST_CHANGES"*"pred=BLOCK"*"result=CLEAR"*"test_rc_block_clear"* ]]
}

@test "LGTM→WARN→CLEAR is counted as correct (lesson_candidate→家老処理→CLEAR)" {
    run bash "$TEST_ROOT/scripts/gates/gate_gunshi_accuracy.sh" "$TEST_TMP/review_log.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ verdict=LGTM"*"pred=WARN"*"result=CLEAR"*"test_lgtm_warn_clear"* ]]
}

@test "LGTM→BLOCK→CLEAR is still incorrect (LGTM+BLOCK予測は判定ミス)" {
    run bash "$TEST_ROOT/scripts/gates/gate_gunshi_accuracy.sh" "$TEST_TMP/review_log.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"偽陽性"*"test_lgtm_block_clear"* ]]
}

@test "overall accuracy on fixture is 5/6 = 83%" {
    run bash "$TEST_ROOT/scripts/gates/gate_gunshi_accuracy.sh" "$TEST_TMP/review_log.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"83%"* ]]
}
