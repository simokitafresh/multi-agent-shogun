# 冷え観点遡及分析: ambiguity zero_streak=10

## 分析日時
2026-06-03T00:45+09:00

## 背景
gate_gunshi_startup.shのAdaptive Gating: ambiguity=0/10件(zero_streak=10)、adversarial=0/10件(zero_streak=10)。
直近10件のレビューでambiguity/adversarial観点を一度も使っていない。

## 遡及検証(cmd_3138-3142 draft review)

| cmd | ambiguity遡及結果 | 見落とし |
|-----|-------------------|---------|
| cmd_3138 | q12テキスト追加。ACは明確 | なし |
| cmd_3139 | 洗脳フレーズのパターン定義が暗黙 | あり — パターンリスト明示要求すべき |
| cmd_3140 | target_path未設定時fallback動作がACに未定義 | あり — FM1で指摘したがambiguity_pointsに未記録 |
| cmd_3141 | command欄からのファイル参照抽出基準が暗黙 | あり — パス文字列判定の定義なし |
| cmd_3142 | cooldown 30秒の根拠未記載 | 軽微 |

## 自己検出率
- 遡及検出: 3/5件にambiguity finding候補あり
- 本番検出: 0/5件 → **偽陰性率60%** (3件見落とし)

## 根因
- ambiguity findingsがpremortem/assumptionsに吸収され、独立観点として機能していない
- ambiguity専用の「これは曖昧か？」問いを発していない
- finding_categoriesにambiguityを記載するインセンティブがない(verdictに影響しないため)

## adversarial遡及
- 直近5件draftは全てchanged_lines<200 → required=false。zero_streakは正当
- ただしcmd_3139(stop hook中枢変更)は破壊シナリオ検討の余地あり

## 対策案
1. **既存Step 1(Challenge Assumptions)にambiguity専用サブ問いを追加**: 「ACの用語定義に曖昧さはないか？」を明示的に問う
2. **finding_categoriesへのambiguity記載を義務化**: ambiguity_points:noneでもfinding_categoriesにambiguityを含め、「確認した」を記録
3. **adversarial発火条件緩和**: changed_lines>=200だけでなく「中枢スクリプト変更」も対象に含める

## 効果予測
- ambiguity偽陰性率60%→20%以下を目標
- 既存プロセスの1行追加(LG023 原理1行>各論パッチ)で対応可能
