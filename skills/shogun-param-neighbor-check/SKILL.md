---
name: shogun-param-neighbor-check
argument-hint: "[gs_result_path|cmd_id]"
quality_metric: "将軍系: 近傍分析cmdのcmd_save.shチェック通過率(q1-q4 BLOCKなしで保存できた割合)"
description: |
  【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
  グリッドサーチのチャンピオンに対して隣接パラメータ性能を比較し、
  過適合リスクを定量評価するスキル。
  TRIGGER: /shogun-param-neighbor-check、チャンピオン近傍分析、隣接パラメータ比較、過適合判定
  DO NOT TRIGGER: グリッドサーチ実行そのもの、知識棚卸し（→shogun-teire）、
  統計分析全般（本スキルはGSチャンピオンの近傍特化）
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# param-neighbor-check

> **【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。**

グリッドサーチのチャンピオンパターンに対し、隣接パラメータの性能を自動抽出・比較して過適合リスクを定量評価するスキル。

チャンピオンが「孤立した最適解」なのか「安定した高原の一部」なのかを判定し、パラメータ選択の堅牢性を可視化する。

## 使い方

```bash
# 基本: パターン名を指定して近傍分析
python ~/.claude/skills/shogun-param-neighbor-check/scripts/param_neighbor_check.py \
  --pattern "MACDSignal_GS_M_GLD_20D_w50_50_T1"

# CSV指定 + メトリクス限定
python ~/.claude/skills/shogun-param-neighbor-check/scripts/param_neighbor_check.py \
  --pattern "MACDSignal_GS_Qj_XLU_3M_w50_40_10_T2" \
  --csv /path/to/custom_grid_search.csv \
  --metrics "sharpe_ratio,total_return,max_drawdown"
```

## パラメータ

| 引数 | 必須 | デフォルト | 説明 |
|------|------|-----------|------|
| `--pattern` | Yes | - | 分析対象のチャンピオンパターン名 |
| `--csv` | Yes | (なし — 実行時に指定必須) | グリッドサーチ結果CSVファイルパス。`outputs/grid_search/` 配下の該当CSVを指定 |
| `--metrics` | No | `sharpe_ratio,total_return,max_drawdown,win_rate,calmar_ratio,sortino_ratio` | 分析対象メトリクス（カンマ区切り） |

## 近傍の定義

「近傍」= チャンピオンから**1パラメータだけ異なる**パターン。

パターン名 `{family}_GS_{rebalance}_{asset}_{lookback}_{weights}_{threshold}` のうち、1要素だけを変動させた全パターンを収集する。

例: チャンピオン `MACDSignal_GS_M_GLD_20D_w50_50_T1` の近傍:
- **rebalance方向**: `..._Qj_GLD_20D_w50_50_T1`, `..._Qf_GLD_20D_w50_50_T1`, ...
- **asset方向**: `..._M_XLU_20D_w50_50_T1`, `..._M_TMV_20D_w50_50_T1`
- **lookback方向**: `..._M_GLD_15D_w50_50_T1`, `..._M_GLD_1M_w50_50_T1`, ...
- **weights方向**: `..._M_GLD_20D_w50_40_10_T1`, ...

4次元（rebalance / asset / lookback / weights）× 各次元の候補数 が近傍サイズとなる。thresholdはT1/T2の2値のため、threshold方向も含めると5次元。

## 出力フォーマット

### 1. テキストヒートマップ

各次元ごとに、チャンピオンと近傍のメトリクス値をパーセンタイルで可視化:

```
=== rebalance dimension ===
          sharpe  return  drawdown  win_rate  calmar  sortino
M    [=== ████████ 85%ile ========]  ← champion
Qj   [=== ██████   72%ile ========]
Qf   [=== ███      45%ile ========]
...
```

### 2. 安定性スコア

近傍パターン全体の平均パーセンタイルから算出:

```
Overall Stability: 72.3%ile → ROBUST
```

### 3. 次元別安定性

```
Dimension Stability:
  rebalance : 78%ile (robust)
  asset     : 65%ile (moderate)
  lookback  : 71%ile (robust)
  weights   : 52%ile (moderate)
  threshold : 80%ile (robust)
```

## 安定性判定基準

| 判定 | 条件 | 意味 |
|------|------|------|
| **robust** | 平均パーセンタイル ≥ 70%ile | 近傍も高性能。過適合リスク低い |
| **moderate** | 50%ile ≤ 平均 < 70%ile | 一部方向に性能低下あり。注意が必要 |
| **suspect** | 平均 < 50%ile | 孤立した最適解の可能性。過適合リスク高い |

## パターン名の構造

```
{family}_GS_{rebalance}_{asset}_{lookback}_{weights}_{threshold}
```

### パラメータ要素一覧

| 要素 | 候補値 |
|------|--------|
| **rebalance** | `M`, `Qj`, `Qf`, `Qm`, `Sa`, `Bo` |
| **asset** | `GLD`, `XLU`, `TMV` |
| **lookback** | `10D`, `15D`, `20D`, `1M`, `2M`, `3M`, `4M`, `5M`, `6M`, `12M`, `24M` |
| **weights** | `w50_50`, `w50_40_10` 等 |
| **threshold** | `T1`, `T2` |

## 前提条件

- Python 3.x
- pandas

## データソース

`--csv` で対象のグリッドサーチ結果CSVを指定する（必須）。
CSVは `outputs/grid_search/` 配下にある忍法別の結果ファイル（例: `246_oikaze_grid_results_fast.csv`）。

## 関連

- 提案元: 小太郎(kotaro)
- プロジェクト: DM-signal
- スクリプト: `~/.claude/skills/shogun-param-neighbor-check/scripts/param_neighbor_check.py`（半蔵が開発）
