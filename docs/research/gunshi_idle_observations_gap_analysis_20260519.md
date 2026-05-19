# Observations Gap Analysis — review_logエントリ22件で必須フィールド欠落
<!-- generated: 2026-05-19T15:00:00+09:00 by gunshi idle analysis -->

## 発見

review_log直近54件中22件(41%)でobservations/finding_categories/origin/causal_chainが欠落。
cmd_2861以降の全エントリが該当。前セッション後半の高速レビュー時に省略が構造化。

## 対象エントリ

| cmd_id | review_type | observations | finding_categories | origin | causal_chain |
|--------|------------|-------------|-------------------|--------|-------------|
| cmd_2861 | draft | 欠落 | 欠落 | 欠落 | 欠落 |
| cmd_2865 (draft+report) | both | 欠落 | 欠落 | 欠落 | 欠落 |
| cmd_2866 (draft+report) | both | 欠落 | 欠落 | 欠落 | 欠落 |
| cmd_2867 (draft+report) | both | 欠落 | 欠落 | 欠落 | 欠落 |
| cmd_2868 (draft+report) | both | 欠落 | 欠落 | 欠落 | 欠落 |
| cmd_2869 (draft+report) | both | 欠落 | 欠落 | 欠落 | 欠落 |
| cmd_2870 (draft+report) | both | 欠落 | 欠落 | 欠落 | 欠落 |
| cmd_2871 (draft+report) | both | 欠落 | 欠落 | 欠落 | 欠落 |
| cmd_2872 (report) | report | ★修正済み(本セッション) | ★修正済み | ★修正済み | ★修正済み |
| cmd_training×2 | report | 欠落 | 欠落 | 欠落 | 欠落 |
| cmd_karo_selfgate×1 | report | 欠落 | 欠落 | 欠落 | 欠落 |
| cmd_karo_wa×1 | report | 欠落 | 欠落 | 欠落 | 欠落 |

## 根因分析(なぜなぜ)

1. なぜobservationsが欠落？→ review_log追記がEdit tool手動操作で省略可能
2. なぜ省略した？→ 高速レビュー時にフィールド数が多く最小限の記入で進んだ
3. なぜ最小限で通った？→ gate_gunshi_cs_checklistはWARN止まり(BLOCK化されていない)
4. なぜWARN止まり？→ observations必須チェックがstartup gate起動時のみ。レビュー追記時のリアルタイム検証がない
5. なぜリアルタイム検証がない？→ review_log追記がスキル(review-bundle)経由でもEdit tool直接でも可能で、どちらもobservations必須を強制していない
6. 根因: **review_log追記の構造がobservationsを省略可能にしている**(Phase 4: 意志依存)
7. 自動化ターゲット: review-bundleスキル内でobservations空チェック→BLOCK、またはpre-write-edit hookでreview_log追記時にobservations必須チェック

## 因果チェーン

```
高速レビュー(10+件/セッション) → 手動追記で省略発生 → WARN無視(意志依存) → 22件欠落蓄積
→ 計測データ(observations)欠落 → Adaptive Gating冷え(finding_categoriesなし) → 全7観点0件
→ 盲点の自己検知不能
```

## 提案(GP候補)

1. **review-bundleスキル内observations必須チェック**: スキルフロー上でobservations空→中断
2. **遡及追記**: 22件中高価値エントリ(draft review)にobservationsを遡及追記
3. **Adaptive Gating回復**: finding_categoriesの遡及追記で冷え観点データを復元

## 影響

- observations欠落→レビュー深度の唯一の計測データが消失
- finding_categories欠落→Adaptive Gating(冷え検知)が機能不全(全7観点0件の真因)
- origin/causal_chain欠落→因果ネットワーク接続断絶
