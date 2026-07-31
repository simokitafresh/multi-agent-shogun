#!/usr/bin/env bats
# test_gate_gunshi_accuracy.bats — 対照fixture (cmd_karo_impl_control_fixture_gunshi_accuracy_20260726)
#
# 検出対象(この検知器が何を検出するか、1行):
#   cmd_idごとの最終entryで gate_prediction と gate_result が一致しない件を
#   軍師の最終予測ミスとして列挙する。
#
# test_necessity:
#   守る不変量は1つ — 「同cmd_idのRC/FAIL途中entryを母数に混ぜず、最終entryのみを1件として計測する」。
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

    # 陰性対照: 同cmdの途中FAILは後続LGTMによって置き換わり、1cmdとして的中。
    cat > "$BATS_TEST_TMPDIR/negative.yaml" <<'YAML'
- cmd_id: control_negative_roundtrip
  review_type: report
  verdict: FAIL
  gate_prediction: BLOCK
  gate_result: CLEAR
- cmd_id: control_negative_roundtrip
  review_type: report
  verdict: LGTM
  gate_prediction: CLEAR
  gate_result: CLEAR
YAML
}

@test "positive control: a final-command misprediction is listed" {
    run bash "$GATE" "$BATS_TEST_TMPDIR/positive.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"最終cmd不一致1件"* ]]
    [[ "$output" == *"control_positive_lgtm_block_clear"* ]]
    [[ "$output" == *"全体: 0/1"* ]]
}

@test "negative control: an RC round trip counts only the final command entry" {
    run bash "$GATE" "$BATS_TEST_TMPDIR/negative.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *"最終cmd不一致"* ]]
    [[ "$output" == *"全体: 1/1 (100%)"* ]]
    [[ "$output" == *"RECENT_FINAL_CMD_ACCURACY=100 SAMPLE=1"* ]]
}
