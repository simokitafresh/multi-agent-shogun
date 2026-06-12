# Gate Prediction Accuracy分析 — WARN→CLEARの構造的パターン
<!-- generated: 2026-06-12T17:35:00+09:00 by gunshi idle analysis -->

## 発見

gate_prediction accuracy = 44% (11/25)。不一致14件は**全てWARN→CLEAR**。

## 根因

SG-PRE12がlesson_candidate有→gate_prediction: WARN/BLOCK必須と判定。
しかし家老がcmd_complete_gate前にlesson処理を完了するため、実際はCLEAR。

因果: lesson_candidate有 → WARN予測 → 家老先行処理 → CLEAR → accuracy低下

## 数値

| 指標 | 値 |
|------|-----|
| Total predictions | 25 |
| Match (accuracy) | 11 (44%) |
| Mismatch | 14 (56%) |
| WARN→CLEAR | 14 (100% of mismatch) |
| Recent 10 accuracy | 50% |

## 分析

- WARN→CLEARは**保守的偽陽性**（安全側の誤り）。BLOCKを見逃す偽陰性(CLEAR→BLOCK)は0件
- 保守的WARNは安全だが、accuracy指標としてはノイズ
- lesson_candidateがBLOCKになるケース（家老処理遅延）は理論上存在するが、直近25件で0回

## 提案

1. **accuracy計算の二分化**:
   - strict accuracy = 44% (現行)
   - safety-adjusted accuracy = 100% (偽陰性0件。CLEAR予測→BLOCK実結果は0件)
2. **SG-PRE12判定の維持**: 保守的WARNは安全側。家老処理遅延時のリスクを考慮して維持
3. **review_logへの理由明記**: `gate_prediction: WARN(lesson_candidate有、家老先行でCLEAR見込み)` を記載し、分析者が保守的WARNと判断可能に
4. **gunshi_stats.yamlへの指標追加提案**: safety-adjusted accuracy指標を追加し、偽陰性0件を可視化

## 因果リンク

- [[SG-PRE12]] -> [[lesson_candidate有]] -> [[WARN予測]] -> [[家老先行CLEAR]] -> [[accuracy 44%]]
- 対策: 計測指標の分離。保守的WARNの維持は正しい設計判断
