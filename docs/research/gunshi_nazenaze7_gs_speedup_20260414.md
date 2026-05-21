# なぜなぜ7回: GS計算量爆発の根因と高速化

軍師分析。2026-04-14T02:00。殿指摘「先に道具磨きした方がいいのでは？」→「高速化できないか？なぜなぜ7回」

## 結論

L3 GS(N=84)は現行道具では328倍(9.39億パターン)で実行不可能。
根因はサブセット列挙型GS設計がN>20を想定していないこと。
高速化の本質的解法=**全体スコアからtop_n直接選出**(方法B)で69msに短縮可能(数万倍)。

## OOM問題（殿指摘 2026-04-14T02:10）

計算時間以前に、**build_grid()のgridリスト構築でOOM KILL**。計算に到達しない。

```
build_grid(): 9.39億パターン × ~500B/pattern = 437GB → 16GBシステムで即死
```

| 段階 | 現行(N=84) | 方法B |
|------|-----------|-------|
| gridリスト | 437GB → **OOM** | 不要(0B) |
| スコア計算 | 8.5MB | 8.5MB |
| シミュレーション | チャンク11MB | argsort 17MB |
| **合計** | **不可能** | **26MB** |

方法Bはgridリスト不要。全体スコアから直接argsort。メモリ26MBで完結。

## 同一性問題（殿指摘 2026-04-14T02:15）

**方法Bは現行GSと計算結果が異なる。** 同一性担保不可。

```
方法A(現行): サブセット{A,B,C,D}内でtop_1を選ぶ → サブセットごとに異なる体
方法B(提案): 全84体からtop_1を選ぶ → 常に全体最高スコア
→ 異なる戦略。結果不一致を実証済み(4体×5ヶ月で検証)
```

### 方法E: ベクトル化サブセット（同一性100% + 50分）

計算結果を完全同一に保ちつつ高速化する方法を発見・実測。

```python
# 原理: サブセットインデックスをnumpy配列化 → fancy indexing一括
indices = np.array(list(combinations(range(84), 4)))  # (1.93M, 4), 29MB
for month in range(86):
    sub_scores = scores[month][indices]      # (1.93M, 4) gather
    picks = np.argmax(sub_scores, axis=1)    # (1.93M,) argmax
    actual = indices[np.arange(c4), picks]   # (1.93M,) actual body index
    rets[:, month] = returns[month+1][actual] # (1.93M,) return lookup
```

**Pythonループは月数(86回)のみ。サブセットループ完全廃止。**

### 実測ベンチマーク

| 方式 | 時間 | メモリ | 同一性 |
|------|------|--------|--------|
| 現行(dictリスト) | OOM死 | 437GB | - |
| Generator+Streaming | 6.8日 | 少 | 同一 |
| **方法E(ベクトル化サブセット)** | **50分** | **662MB** | **同一** |
| 方法B(full-universe argsort) | 69ms | 26MB | 異なる |

方法Eの内訳(実測):
- C(84,4) index配列構築: 0.5s, 29MB
- 1 param × 86ヶ月のgather+argmax+return: 5.2s, 633MB
- CAGR計算: 1.3s
- 153 params × 3 sizes(N=2,3,4): 推定50分

## なぜなぜ7回

### Why 0: そもそも起動しない
build_grid()が9.39億パターンのdictリストを生成→437GB→OOM KILL。計算以前の問題。

### Why 1: なぜN=84で328倍か？
C(N,2)+C(N,3)+C(N,4)のサブセット×パラメータ。C(84,4)=1,929,501が支配的(N=20比398倍)。

### Why 2: なぜC(N,4)が必要か？
忍法GS=N体から2-4体サブセットを全列挙し、各サブセット内でtop_n保有。サブセット選択自体がパラメータ。

### Why 3: なぜ全サブセット列挙か？
L1(12体)の設計思想。C(12,4)=495で全列挙が安い。この前提がN=84で崩壊。

### Why 4: なぜ列挙以外の方法がないか？
simulate_batchは3D mask+broadcasting で同一サブセット内パラメータは一括化済み(cmd_1038)。
**パターンループは高速化済み。サブセットループが未対処**。

### Why 5: サブセット数を減らせないか？
3方向:
- (A) N≤3制限: 20倍速。パラメータ空間縮小(禁止に抵触)
- **(B) 全体スコアからtop_n直接選出: 2000倍速以上。正しい道具磨き**
- (C) top_n=1限定argsort: 同上(top_n>1で挙動変化)
- (D) サンプリング: 10-100倍速(網羅性喪失)

### Why 6: なぜ(B)が未実装か？
build_global_momentum_and_scores(L414)は既に全N体のスコアを1回で計算。
サブセットはtop_n picks計算のためだけにcolumn sliceしている。
L1/L2ではサブセット数が少なく問題にならなかった。

### Why 7: 根因 = L3はサブセット列挙型GSに適さない
L1/L2道具=「少数体universe+全サブセット列挙」前提。N=84でこの前提が崩壊。
道具の前提とL3の要件が不適合。

## 方法(B)の設計

### 原理
- 全84体のスコア行列(87ヶ月×84体)を1回計算(build_global_momentum_and_scores既存)
- 各月にargsort → top_n体を直接選出
- 選出体の平均リターンをnumpy一括計算
- サブセット列挙を完全廃止

### 計算量比較
```
現行: C(84,4)×153パラメータ = 2.95億通り → 数時間〜数日
方法B: 153パラメータ×87ヶ月×argsort(84) → 69ms (実測)
高速化倍率: 数万倍
```

### コード根拠
- `build_global_momentum_and_scores` (run_077_kasoku_diff.py L414): 全N体のmomentum+scoreを1回計算
- `get_kasoku_context` (L534): サブセットcomponentsのcolumn sliceでスコア取得
- `simulate_batch` (L883): 3D boolean mask + numpy broadcasting。**サブセット内は最適化済み**
- ボトルネック: `build_grid` (L958): itertools.combinations(universe, n) for n in [2,3,4] → **ここが爆発**

### 忍法設計との整合
- L1/L2: サブセット=「事前に候補を絞る」意味あり(12体→4体=候補プール制限)
- L3: 84体→4体サブセット=**実質full-universe top_n選出のサブケース**
  - サブセット内top_1は、そのサブセット内で最高スコアの1体
  - full-universe top_1は全84体で最高スコアの1体
  - L3の目的は「多様なL2体から最適な組み合わせを選出」→ full-universeが直接回答

### 実装方針
1. run_077に `--mode full-universe` フラグ追加
2. build_global_momentum_and_scoresの結果からargsort直接選出
3. 各パラメータ×top_n×月のリターンを一括計算
4. 既存のサブセット列挙モード(--mode subset)は維持(L1/L2互換)

## 数値根拠

| 忍法 | N=20パターン | N=84パターン | 倍率 |
|------|------------|------------|------|
| bunshin | 6,175 | 2,028,271 | 328x |
| kasoku_diff | 944,775 | 310,325,463 | 328x |
| kasoku_ratio | 944,775 | 310,325,463 | 328x |
| nukimi | 481,650 | 158,205,138 | 328x |
| oikaze | 222,300 | 73,017,756 | 328x |
| kawarimi | 222,300 | 73,017,756 | 328x |
| yotsume | 37,050 | 12,169,626 | 328x |
| **合計** | **2,859,025** | **939,089,473** | **328x** |

パラメータ計算式: kasoku_diff = C(18,2)=153。実測CSV行数(944,775) = 6,175×153 完全一致。

## ベンチマーク
numpy argsort (153 params × 87 months × 84 comps × top_n 1,2,3): **69ms**

## 実装結果（2026-04-14T03:00 殿指示で実装）

### 12体検証: ★ ALL MATCH

```
=== Verification ===
  New: 119,493 rows, Existing: 119,493 rows
  OK: cagr (max_diff=8.33e-17, mismatches=0)
  OK: maxdd (max_diff=8.33e-17, mismatches=0)
  OK: calmar (max_diff=4.44e-16, mismatches=0)
  OK: sharpe (max_diff=2.22e-16, mismatches=0)
  OK: worst_year_return (max_diff=1.00e-16, mismatches=0)
  OK: new_high_ratio (max_diff=8.33e-17, mismatches=0)
  ★ ALL MATCH — 計算結果同一性確認
  実行時間: 5.6s (既存run_077比較対象)
```

### なぜなぜ3層（不一致解消の過程）

| 層 | 根因 | 不一致数 | 修正 |
|----|------|---------|------|
| 1 | argmax(1体)vs nanmax boolean mask(タイ時全体平均) | 34,366 | boolean mask + ret_sum/ret_count |
| 2 | NaN→0置換 vs NaN除外後metrics計算 | 7,812 | per-pattern NaN除外 + calc_metrics_fast |
| 3 | score_key重複(10D/15D/20D/1M→mc=1) | 行数不足 | mc_to_params展開で全153 param出力 |

### スクリプト
`scripts/analysis/grid_search/gs_vectorized_subset.py`

### 方法Bは不採用
方法B(full-universe argsort)は計算結果が現行GSと異なる(タイ処理+サブセット制約の差)。
方法E(ベクトル化サブセット)が正解: 同一結果 + 高速化。

### 次ステップ
1. N=84(L2奥義GS固定)で実行テスト → メモリ・時間計測
2. 全7忍法対応(現在kasoku_diff/ratioのみ)
3. run_077への統合(--mode vectorized フラグ)
