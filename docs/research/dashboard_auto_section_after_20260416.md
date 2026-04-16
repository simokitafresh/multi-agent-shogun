# dashboard_auto_section.sh CoDD Spec + After Report (cmd_1954)

- cmd: cmd_1954
- 実施者: saizo
- CoDD Phase到達: Phase 5(before/after計測+実装+検証)。specは事後作成(2026-04-16)

## 対象

- `scripts/dashboard_auto_section.sh`

## before 計測

- 条件:
  - `bash scripts/dashboard_auto_section.sh --dry-run`
  - CI cache は既存値あり・TTL切れ状態
  - `knowledge_metrics` cache あり
- 実測:
  - `0.89s`
  - `0.89s`
  - `0.90s`
- 平均: `0.89s`

## ボトルネック

1. `model_analysis.sh --summary` が空キャッシュでも毎回再実行され、約 `0.28s` を消費。
2. 日本語名/スナップショット状態/lesson threshold の取得で小さい subprocess を多発。
3. CI status は cache があっても stale 判定後の更新制御が弱く、呼出しコストが載りやすい。

## 実装

1. `KM_MODEL_CACHE` は「空でも有効 cache」とみなし、無限再実行を停止。
2. 日本語名を `_JP_CACHE`、snapshot status を `SNAP_STATUS` に事前展開して O(1) lookup 化。
3. `lesson_effectiveness_status.txt` の `status/rate/window/referenced/injected` を 1 回の `awk` で取得。
4. CI status は cache があれば即利用し、TTL切れ時の refresh は lock 付き非同期更新へ変更。

## after 計測

- 条件:
  - `bash scripts/dashboard_auto_section.sh --dry-run`
  - CI cache は既存値あり・TTL切れ状態
  - 同一 workspace で連続実行
- 実測:
  - `0.37s`
  - `0.33s`
  - `0.33s`
- 平均: `0.34s`

## 結果

- `0.89s → 0.34s`
- 改善率: `-61.8%`
- 目標 `500ms` を達成

## 検証

- `bats tests/unit/test_dashboard_auto_context_freshness.bats`
- `bash scripts/dashboard_auto_section.sh --dry-run`
