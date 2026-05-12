# BLOCK原因パターン分析 — accuracy Goodhart是正後の全量調査
<!-- generated: 2026-05-12T12:22:00+09:00 by gunshi idle analysis -->

## 要約

gate_metrics.log 216件BLOCKの原因分類。軍師レビュー改善可能領域=48件(22%)。残り168件(78%)はシステム構造問題(draft_lessons/missing_gate)。

## BLOCK原因全体構成

| 原因カテゴリ | 件数 | 構成比 | 軍師対応 |
|------------|------|--------|---------|
| draft_lessons | 154 | 71% | 範囲外(家老プロセス) |
| missing_gate | 48 | 22% | 範囲外(gate設計) |
| report_format | 20 | 9% | precheck対応済み |
| 忍者固有(bc_fail等) | 28 | 13% | precheck対応済み |

※比率合計>100%は複合原因による重複

## 月別推移(軍師対応可能BLOCK)

| 月 | 件数 | 主因 |
|----|------|------|
| 2026-04 | 8 | 分散 |
| 2026-05 | 30 | kagemaru report_format 4件集中 + hayate bc_fail 8件 |

5月急増の主因: hayate binary_checks_fail(cmd_2461が4連続再試行)+kagemaru report_format(4連続)

## 忍者別BLOCK集中度(軍師対応可能)

| 忍者 | 固有BLOCK | 総配備数 | BLOCK率 | 主パターン |
|------|----------|---------|---------|-----------|
| hayate | 35 | 316 | 11.1% | bc_fail(10)+empty_lu(10)+lesson_done(12) |
| saizo | 11 | 269 | 4.1% | empty_lu(4)+lesson_done(3) |
| kagemaru | 8 | 199 | 4.0% | lesson_done(4)+report_format(直近4連続) |
| hanzo | 8 | 91 | 8.8% | empty_lu(4)+lesson_done(2) |
| tobisaru | 2 | 49 | 4.1% | - |
| kotaro | 1 | 69 | 1.4% | - |

hayateの固有BLOCK率(11.1%)が最も高い。他忍者の2-3倍。

## 因果推論

1. **draft_lessons 154件(最大因)**: 家老のlesson登録タイミング問題。軍師提案済み(lesson_done_missing時系列→家老受領, 閾値3件で配備予定)
2. **hayate集中(35件)**: 配備頻度最高(316件)に比例する面もあるが、BLOCK率(11.1%)が他忍者(4%)の2.8倍。bc_failとempty_luが各10件で均等に分散 → 特定弱点ではなく全般的な品質不安定
3. **kagemaru report_format 4連続**: GPTモデルでの報告フォーマート問題。修行L4で対処中(cmd_training_L4_r16_kotaro同様)
4. **empty_lessons_useful 22件**: 教訓注入のtopic_mismatch問題。cmd_2685(useful率改善)で対処予定

## 利他行動変換

| 発見 | 行動 | 状態 |
|------|------|------|
| lesson_done_missing 20件 | 家老にlesson_candidate送信 | 家老受領済み(閾値3件で配備) |
| useful率23%(topic_mismatch 61%) | 掲示板投稿→将軍cmd_2685起票 | 配備待ち |
| hayate BLOCK率11.1% | 配備時のweak_points注入で対応済み(deploy_task.sh) | 自動化済み |
| kagemaru report_format 4連続 | 修行L4配備中(r15/r16) | 進行中 |
