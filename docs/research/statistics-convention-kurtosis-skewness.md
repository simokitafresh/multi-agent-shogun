# 統計指標の慣例整合性 — Kurtosis・Skewness
<!-- link_id: statistics_convention_kurtosis_skewness -->
<!-- origin: [[cmd_3524]] -> [[kurtosis_raw_vs_excess不整合発見]] -> [[本番pandas互換方針確定]] -->
<!-- created: 2026-06-25 -->

## 結論

**DM-Signal全体で excess kurtosis + Fisher-adjusted skewness を使う。** 本番metrics_impl.py(pandas)に合わせる。

## Kurtosis: Raw vs Excess

| 方式 | 正規分布の値 | 使用箇所 | 数式 |
|------|------------|---------|------|
| Raw Kurtosis | **3.0** | robustness_common.py cmd_3524実装(修正前) | `E[(X-μ)^4] / σ^4` |
| Excess Kurtosis | **0.0** | 本番 metrics_impl.py L1174 `pandas .kurt()` | `Raw - 3.0` |

- pandas `.kurt()` = excess kurtosis(Fisher定義。bias=True/False切替可、デフォルトbias=True)
- scipy `kurtosis()` = デフォルトexcess(fisher=True)
- numpy には kurtosis関数なし

**金融慣例**: excess kurtosis を使う。テールリスクを0基準で評価(正>0=ファットテール、負<0=薄テール)。

**修正**: `np.mean(standardized**4) - 3.0`

## Skewness: 母集団式 vs Fisher補正

| 方式 | 数式 | 使用箇所 |
|------|------|---------|
| 母集団式(biased) | `(1/n) Σ((x-μ)/σ)^3` | robustness_common.py cmd_3524実装(修正前) |
| Fisher補正(unbiased) | `n/((n-1)(n-2)) Σ((x-μ)/σ)^3` | 本番 metrics_impl.py L1170 `pandas .skew()` |

- pandas `.skew()` = Fisher補正(デフォルト)
- n=60ヶ月で約5%差、n=24ヶ月で約10%差
- 差はサンプル数に反比例

**修正**: `scipy.stats.skew(clean, bias=False)` または pandas互換の手動補正

## 実測への影響(cmd_3524結果)

cmd_3524の378行のKurtosis値は全てraw。読み替えは一律`-3.0`:
- 出力4.92 → excess **1.92**(ファットテール)
- 出力3.00 → excess **0.00**(正規分布相当)
- 出力2.38 → excess **-0.62**(薄テール)

再計算は不要。robustness_common.pyのコード修正後に再実行すれば正しい値が出る。

## 因果リンク

- ← [[cmd_3524]] 5指標追加cmd。実装時にraw kurtosisで出力
- → [[metrics_impl]] 本番指標計算。pandas .kurt()/.skew() = excess/Fisher
- → [[robustness_common]] α6+5指標計算基盤。修正対象
