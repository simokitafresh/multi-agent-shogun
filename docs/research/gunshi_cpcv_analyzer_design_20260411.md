# CPCV全方位分析ツール設計書
<!-- gunshi 2026-04-11 将軍指示: 道具磨き -->

## 結論

`outputs/scripts/cpcv_analyzer.py` — GS CSV/.npyにCPCV(N=8, 28fold)を適用し6メトリクスを一括算出。
champion_selector.pyの知見(NaN-safe/float64/チャンク)を継承。
**30倍高速化(愚直224秒→7.4秒)。kasoku_diff 944K列: 7.4秒/758MB。7忍法全量: 推定30秒。**

### 高速化3段階
| 手法 | kasoku_diff | 倍率 |
|------|-------------|------|
| 愚直(28fold×全量CAGR) | 224秒(推定) | 1x |
| v1: パーティション事前計算 | 10.2秒 | 22x |
| **v2: + ループ乗算 + rankdata除去** | **7.4秒** | **30x** |

v2の内訳: 事前計算5.7秒(I/Oバウンド=本質的下限) + 28fold 1.7秒。
matmul(log→exp変換)よりループ直接乗算の方が高速(log/exp不要)。
PBO判定にrankdataは不要(median比較のみ: 4.0秒→0.01秒)。

## CPCV概要

Bailey et al. (2017) "The Probability of Backtest Overfitting" に基づく。

- N=8等分割（時系列順）→ C(8,2)=28組み合わせ
- 各組み合わせ: 6パーティション=IS(in-sample), 2パーティション=OOS(out-of-sample)
- purge=1ヶ月: IS/OOS境界の前後1ヶ月を除外（情報漏洩防止）
- ISで全パターンのCAGRを計算 → ISベストを特定
- OOSでISベストのCAGRを計算
- 28組の(IS rank, OOS rank, IS CAGR, OOS CAGR)を収集

## 6メトリクス

| # | メトリクス | 定義 | 解釈 |
|---|-----------|------|------|
| 1 | **PBO** | ISベストがOOS中央値以下になる確率(28組中) | 0=過適合なし, 1=完全過適合 |
| 2 | **Spearman ρ** | ISランクとOOSランクの順位相関(28組平均) | 1=ISとOOS完全一致, 0=無相関 |
| 3 | **OOS CAGR σ** | 28組のOOS CAGRの標準偏差 | 低い=regime非依存, 高い=不安定 |
| 4 | **OOS CAGR mean** | 28組のOOS CAGR平均 | 正=実力あり, 負=過適合 |
| 5 | **Stacked OOS CAGR** | 全OOS区間を時系列連結した疑似全期間CAGR | ISと大差なければ汎化OK |
| 6 | **MinBTL** | 過適合回避の最小バックテスト期間推定(月) | 現データが足りているか |

## データフロー

```
入力: GS CSV/.npy (year_month × pattern_id のmonthly_returns)
  ↓
1. 月次リターンを8等分割
2. C(8,2)=28組み合わせ生成
3. 各組み合わせ:
   a. IS/OOS月インデックス分離 + purge適用
   b. IS区間の全パターンCAGR計算 (NaN-safe, float64, チャンク)
   c. ISベスト特定 + ISランク算出
   d. OOS区間のISベストCAGR計算
   e. OOSランク算出
4. 28組の結果集約 → 6メトリクス算出
  ↓
出力: JSON + Markdown比較表
```

## champion_selector.pyからの継承

| 要素 | 理由 |
|------|------|
| NaN-safe CAGR | cumprod NaN伝播で真のチャンピオンが消失(kasoku_diff実証) |
| float64 | MaxDD/CAGR近接パターンの順位安定 |
| チャンク処理 | L2 kasoku_diff 944K列でもpeak RSS ~1GB |
| NHF NaN月除外 | NaN→0でequity横ばい=偽new high防止 |

## 高速化: パーティション事前計算 (31倍)

### 愚直方式の問題
28fold×全パターンCAGRを毎回計算 → kasoku_diff: 28 × 8秒 = 224秒

### 高速方式
prod(IS区間) = prod(partition[0]) × prod(partition[1]) × ... × prod(partition[5])
→ 8パーティションのprodを**1回だけ事前計算**し、28foldは6個の積を掛けるだけ

```python
# Step 1: 8パーティションのprod/n_valid事前計算 (1回だけ、チャンク対応)
for p_months in partitions:
    for chunk in chunks(arr[p_months, :], CHUNK):
        part_prod[p] = (1 + safe).prod(axis=0)
        part_nvalid[p] = valid.sum(axis=0)

# Step 2: 28foldは積を掛けるだけ (O(1)×28)
for oos_pair in C(8,2):
    is_prod = prod(part_prods[p] for p in is_parts)  # 6回の乗算
    is_cagr = is_prod ** (12/is_nvalid) - 1
```

### 実測ベンチマーク (kasoku_diff 944K列)

| 方式 | 事前計算 | 28fold | 合計 | 倍率 |
|------|---------|--------|------|------|
| 愚直 | — | 224秒(推定) | **224秒** | 1x |
| **高速** | 4.8秒 | 5.4秒 | **10.2秒** | **22x** |

100K列ベンチマークでは31倍。全量では22倍（メモリアクセスパターンの差）。

### 計算量見積もり（高速方式）

| 層 | パターン数 | 推定時間 | peak RSS |
|----|-----------|---------|----------|
| L0 | 12 | <1秒 | <50MB |
| L2 bunshin | 6,175 | ~0.5秒 | ~50MB |
| L2 kasoku_diff | 944,775 | **10秒** | **870MB** |
| L2 全7本 | 2,859,025 | **~40秒** | ~870MB(peak) |

### CPCV実測結果 (kasoku_diff)

| メトリクス | 値 |
|-----------|-----|
| PBO | 0.250 (28fold中7回ISベストがOOS中央値以下) |
| OOS CAGR mean | 66.6% |
| OOS CAGR σ | 24.7% |

## メモリ見積もり

8パーティションprod配列(各944K×float64=7.2MB) × 8 = 57MB + チャンク処理peak = **~870MB**。

## CLI設計

```bash
python cpcv_analyzer.py \
  --csv-dir outputs/grid_search/okugi_shin_ninpo_20body \
  --cmd-id cmd_1822 \
  --n-splits 8 \
  --purge 1 \
  --json            # JSON出力(デフォルトはMarkdown表)

# 単体CSV入力(L0用)
python cpcv_analyzer.py \
  --csv outputs/grid_search/shin_shijin_l1/shin_v2_12_monthly_returns.csv \
  --n-splits 8 \
  --purge 1
```

## PBO計算の詳細

```python
# 各fold(28組)で:
is_cagr = calc_cagr_nan_safe(arr[is_months, :])  # 全パターンのIS CAGR
is_best_idx = np.nanargmax(is_cagr)               # ISベストパターン
is_best_rank = rankdata(-is_cagr)[is_best_idx]     # ISベストのランク(1=最高)

oos_cagr = calc_cagr_nan_safe(arr[oos_months, :])  # 全パターンのOOS CAGR
oos_rank_of_is_best = rankdata(-oos_cagr)[is_best_idx]  # ISベストのOOSランク
oos_median_rank = len(oos_cagr) / 2

# PBO = ISベストがOOS中央値以下の割合
pbo = sum(oos_rank_of_is_best > oos_median_rank for fold) / 28
```

## MinBTL推定

Bailey et al. (2017) の式:
```
MinBTL ≈ N_patterns^(1/8) × max_IS_sharpe_ratio / target_sharpe_ratio
```
簡易推定として、IS/OOS Sharpeの劣化率から逆算。

## purge実装

```python
# パーティション境界の前後purge_months月を除外
for i, (is_parts, oos_parts) in enumerate(combinations):
    is_months = flatten(partitions[p] for p in is_parts)
    oos_months = flatten(partitions[p] for p in oos_parts)

    # IS末尾とOOS先頭の境界にpurge適用
    boundary_months = set()
    for is_p in is_parts:
        for oos_p in oos_parts:
            if abs(is_p - oos_p) == 1:  # 隣接パーティション
                boundary = max(partitions[min(is_p, oos_p)])
                for m in range(1, purge_months + 1):
                    boundary_months.add(boundary + m)  # IS側末尾除外
    is_months = [m for m in is_months if m not in boundary_months]
```

## 3層比較の使い方

| PBO | 解釈 |
|-----|------|
| L0 < L1 < L2 | 層を重ねるごとに過適合が進行。警告 |
| L0 ≈ L1 ≈ L2 | 各層で過適合度が同等。構造的に安定 |
| L2 < 0.5 | 奥義の過適合リスクは許容範囲 |
| L2 > 0.8 | 奥義のISベストはOOSで通用しない。過適合 |
