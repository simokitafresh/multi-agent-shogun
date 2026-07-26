#!/usr/bin/env bats
# test_gate_gunshi_accuracy.bats — 対照fixture (cmd_karo_impl_control_fixture_gunshi_accuracy_20260726)
#
# 検出対象(この検知器が何を検出するか、1行):
#   軍師が事前に出した gate_prediction が、公正計算ルール(FAIL/REQUEST_CHANGES→BLOCK→CLEAR、
#   LGTM→WARN→CLEAR を正解とみなす)を適用してもなお実際の gate_result と一致しない件
#   = 軍師の予測ミス(偽陽性)を列挙する。
#
# test_necessity:
#   守る不変量は1つ — 「verdict=LGTM かつ gate_prediction=BLOCK かつ gate_result=CLEAR の行を
#   必ず偽陽性として列挙し、公正計算ルールに合致する行だけの入力では偽陽性を1件も列挙しない」。
#   この不変量が壊れると、軍師の予測精度が実態と乖離したまま報告され続ける(検知器自身の誤りは
#   誰にも検知されない)。陽性/陰性の両方向を固定するため、対照fixtureとして永続させる。
#
# 対照は検知器本体(gate_gunshi_accuracy.sh <fixture>)を実行して出力を検証する。
# 判定を緩めた形跡がないことを担保するため、fixtureは検知器へ一切手を入れずに通ること。

setup() {
    TEST_ROOT="${BATS_TEST_DIRNAME}/../.."
    GATE="$TEST_ROOT/scripts/gates/gate_gunshi_accuracy.sh"

    # 陽性対照: 本体コメント(gate_gunshi_accuracy.sh:10)が「誤答」と明記する唯一の型。
    # LGTM(問題なしと判定)を出しながらBLOCKを予測し、実際はCLEARした = 予測ミス。
    cat > "$BATS_TEST_TMPDIR/positive.yaml" <<'YAML'
- cmd_id: control_positive_lgtm_block_clear
  review_type: report
  verdict: LGTM
  gate_prediction: BLOCK
  gate_result: CLEAR
YAML

    # 陰性対照: 公正計算ルールに合致する正常系のみ。
    #   LGTM→CLEAR→CLEAR = 素直な的中
    #   FAIL→BLOCK→CLEAR = 軍師がFAILを検出し家老修正でCLEAR(ルール上の正解)
    cat > "$BATS_TEST_TMPDIR/negative.yaml" <<'YAML'
- cmd_id: control_negative_lgtm_clear_clear
  review_type: report
  verdict: LGTM
  gate_prediction: CLEAR
  gate_result: CLEAR
- cmd_id: control_negative_fail_block_clear
  review_type: report
  verdict: FAIL
  gate_prediction: BLOCK
  gate_result: CLEAR
YAML
}

@test "positive control: a genuine misprediction (LGTM+BLOCK->CLEAR) is listed as 偽陽性" {
    run bash "$GATE" "$BATS_TEST_TMPDIR/positive.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"偽陽性1件"* ]]
    [[ "$output" == *"control_positive_lgtm_block_clear"* ]]
    [[ "$output" == *"全体: 0/1"* ]]
}

@test "negative control: fair-calculation-conformant rows produce no 偽陽性" {
    run bash "$GATE" "$BATS_TEST_TMPDIR/negative.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *"偽陽性"* ]]
    [[ "$output" == *"全体: 2/2 (100%)"* ]]
}
