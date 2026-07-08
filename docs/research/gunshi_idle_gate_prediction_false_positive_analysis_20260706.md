# Gate Prediction False Positive Analysis
<!-- generated: 2026-07-06T01:36:00+09:00 by gunshi idle analysis -->

## 問題

gate_prediction accuracy直近10件が60%(6/10)に低下。全体92%(58/63)。
MISS 4件全てpred=BLOCK→actual=CLEAR（偽陽性方向）。見落とし(CLEAR→BLOCK)は0件。

## 偽陽性4件の詳細

| cmd_id | verdict | gate_prediction | gate_result | summary |
|--------|---------|-----------------|-------------|---------|
| cmd_3687 | LGTM | BLOCK | CLEAR | database repo commit 4ファイル一致。EODHD/Tiingo差分0.00 |
| cmd_3689 | FAIL | BLOCK | CLEAR | AC1本旨未達(SQL生成のみ)→家老waive? |
| cmd_3690 | LGTM | BLOCK | CLEAR | 本番デプロイ完了。102/102/78 PASS |
| cmd_3691 | LGTM | BLOCK | CLEAR | 58734行照合+配当分母修正+19テストPASS |

## 根因分析

### GATE_PREDICTIONがBLOCKになる条件(gate_gunshi_report_precheck.sh)

1. **vercel_phase broken_refs** (L678): context変更の参照先が実在しない
2. **generated_not_penetrated** (L741): instructions正本変更がgenerated/に未反映
3. **draft_lessons存在** (L803): tasks/lessons.mdにdraft教訓がある→WARNへ降格

### 推定原因

報告YAMLがarchive済みで再実行不可のため、直接原因の特定は推定に留まる。

- cmd_3687/3690/3691はLGTM(4観点OK)だが、precheckのlesson_candidate有→engine側のdraft_lessons検出でWARN→BLOCKに昇格した可能性
- cmd_3689はFAIL verdict→GATE CLEARは家老waiveまたはcmd_complete_gate --forceの可能性。pred=BLOCKは正しい予測だが、家老介入でCLEARになった

### 偽陽性パターンの分類

| パターン | 件数 | 方向 | 安全性 |
|----------|------|------|--------|
| BLOCK予測→実際CLEAR | 4 | 偽陽性(安全側) | 低リスク(過剰検出) |
| CLEAR予測→実際BLOCK | 0 | 偽陰性(危険側) | 0件(最重要指標) |

## 改善提案

1. **GATE_PREDICTION reason記録**: review_logにgate_prediction_reasonフィールドを追加し、BLOCK予測時の理由を記録する。事後分析を可能にする
2. **draft_lessons偽陽性抑制**: tasks/lessons.mdのdraft教訓が当該cmdと無関係な場合はBLOCK予測を抑制する
3. **報告YAMLアーカイブ前のprecheck結果保存**: archive前にprecheck出力をreview_logに1行記録する

## 結論

偽陽性は安全側のMISSであり、見落とし(CLEAR→BLOCK)が0件のため実害は限定的。
ただし精度60%は信頼性低下の兆候。提案1(reason記録)がD0実装可能で最も効果的。
