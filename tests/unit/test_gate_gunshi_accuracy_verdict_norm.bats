#!/usr/bin/env bats
# test_gate_gunshi_accuracy_verdict_norm.bats — 対照fixture
# (cmd_karo_impl_gunshi_accuracy_verdict_norm_20260726)
#
# 検出対象(この検知器が何を検出するか、1行):
#   gate_gunshi_accuracy.sh が verdict の表記ゆれ(REQ_CHANGES)を正典(REQUEST_CHANGES)へ
#   正規化して公正計算ルールへ乗せること、かつ LGTM/APPROVE という段階(report/draft)に
#   束縛された別概念を同一視して寄せないこと、かつ cmd_idのみの空エントリを
#   silentに落とさず skipped=N として明示カウントすることを検証する。
#
# test_necessity(3件、各1不変量):
#   1. path=scripts/gates/gate_gunshi_accuracy.sh
#      defense_target: "verdict=REQ_CHANGES(表記ゆれ)はREQUEST_CHANGESへ正規化されRC正解分岐
#        (BLOCK→CLEAR)に乗る。同時にAPPROVEはLGTM+WARN→CLEARの特例分岐へは決して乗らない
#        (report×LGTM/draft×APPROVEは交差0件の別概念のため)。"
#      overlap_evidence: "test_gate_gunshi_accuracy.bats は検知器本体(LGTM+BLOCK→CLEARの
#        偽陽性列挙)の陽性/陰性対照であり、本ファイルが検証するverdict語彙正規化・
#        段階非混同・skipped明示カウントの3不変量とは重複しない"
#      overlaps_existing: false
#   2. path=tests/unit/test_gate_gunshi_accuracy_verdict_norm.bats (this file)
#      (bats自体は自己参照しないため対象外。上記1件のみを本弾の永続契約とする)
#
# 対照は検知器本体(gate_gunshi_accuracy.sh <fixture>)を実行して出力を検証する。

setup() {
    TEST_ROOT="${BATS_TEST_DIRNAME}/../.."
    GATE="$TEST_ROOT/scripts/gates/gate_gunshi_accuracy.sh"

    # AC1/AC3(i): REQ_CHANGES(表記ゆれ) + BLOCK + CLEAR は正規化後、
    # REQUEST_CHANGESの「RC指摘→忍者修正→CLEAR」正解分岐に乗る
    # (修正前は誤答計上されていた表記ゆれ)。
    cat > "$BATS_TEST_TMPDIR/reqchanges_typo.yaml" <<'YAML'
- cmd_id: control_reqchanges_typo_block_clear
  review_type: report
  verdict: REQ_CHANGES
  gate_prediction: BLOCK
  gate_result: CLEAR
YAML

    # AC3(ii): 既存の正式表記 REQUEST_CHANGES 3パターンが不変であることの陰性対照。
    cat > "$BATS_TEST_TMPDIR/requestchanges_unchanged.yaml" <<'YAML'
- cmd_id: control_rc_block_clear
  review_type: report
  verdict: REQUEST_CHANGES
  gate_prediction: BLOCK
  gate_result: CLEAR
- cmd_id: control_rc_block_block
  review_type: report
  verdict: REQUEST_CHANGES
  gate_prediction: BLOCK
  gate_result: BLOCK
- cmd_id: control_rc_clear_block
  review_type: report
  verdict: REQUEST_CHANGES
  gate_prediction: CLEAR
  gate_result: BLOCK
YAML

    # AC3(iii): LGTM(report段階)とAPPROVE(draft段階)は同義語ではない
    # (軍師実測: report×LGTM=28/28, draft×APPROVE=23/23, 交差0件)。
    # APPROVE+WARN+CLEARはLGTM+WARN+CLEARの特例分岐に乗ってはならない。
    cat > "$BATS_TEST_TMPDIR/approve_not_merged.yaml" <<'YAML'
- cmd_id: control_approve_warn_clear
  review_type: draft
  verdict: APPROVE
  gate_prediction: WARN
  gate_result: CLEAR
YAML

    # AC2: cmd_idしか持たない空エントリ(2026-07-19の実例と同型)は
    # 正規表現に掛からず分母から除外されるが、skipped=Nとして明示カウントする。
    cat > "$BATS_TEST_TMPDIR/skipped_entry.yaml" <<'YAML'
- cmd_id: control_skipped_cmd_id_only
- cmd_id: control_skipped_companion_ok
  review_type: report
  verdict: LGTM
  gate_prediction: CLEAR
  gate_result: CLEAR
YAML
}

@test "AC1/AC3(i): REQ_CHANGES (typo) + BLOCK + CLEAR normalizes to REQUEST_CHANGES and is counted correct" {
    run bash "$GATE" "$BATS_TEST_TMPDIR/reqchanges_typo.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *"偽陽性"* ]]
    [[ "$output" == *"全体: 1/1 (100%)"* ]]
    [[ "$output" == *"verdict=REQUEST_CHANGES"* ]]
}

@test "AC3(ii) negative: the 3 existing REQUEST_CHANGES (correct spelling) patterns are unchanged" {
    run bash "$GATE" "$BATS_TEST_TMPDIR/requestchanges_unchanged.yaml"
    [ "$status" -eq 0 ]
    # control_rc_block_clear: RC正解分岐 -> correct
    # control_rc_block_block: else pred==result (BLOCK==BLOCK) -> correct
    # control_rc_clear_block: else pred==result (CLEAR==BLOCK) -> incorrect
    [[ "$output" == *"全体: 2/3"* ]]
    [[ "$output" == *"偽陽性1件"* ]]
    [[ "$output" == *"control_rc_clear_block"* ]]
}

@test "AC3(iii) negative: APPROVE is not merged into the LGTM+WARN->CLEAR special-case branch" {
    run bash "$GATE" "$BATS_TEST_TMPDIR/approve_not_merged.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"偽陽性1件"* ]]
    [[ "$output" == *"control_approve_warn_clear"* ]]
    [[ "$output" == *"全体: 0/1"* ]]
}

@test "AC2: a cmd_id-only entry is excluded from the denominator but explicitly counted as skipped=1" {
    run bash "$GATE" "$BATS_TEST_TMPDIR/skipped_entry.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"全体: 1/1 (100%) skipped=1"* ]]
    [[ "$output" != *"control_skipped_cmd_id_only"* ]]
}
