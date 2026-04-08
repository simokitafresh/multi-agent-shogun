# 設計書: l1_alm_wf_engine 6→38メトリクス拡張

**作成**: 軍師 2026-04-07（cmd_1785設計）
**目的**: ALM L1 67窓全探索で全38メトリクスを比較対象に。現行6メトリクスを38に拡張。
**絶対条件**: 速度回帰なし（prefix化で速度維持）

---

## §0. 既存実装の活用方針（車輪の再発明禁止）

**l1_alm_wf_engine.py は既に MRE を import している** (L55 `MRE = importlib.import_module("metrics_research_engine")`)

| 使うべき既存実装 | 場所 | l1_alm版への変換 |
|----------------|------|----------------|
| 全38メトリクスnumpy計算ブロック | MRE `batch_rolling_metrics` L1537-1796 | **axis=2 → axis=0** のみで転用可 |
| DD系3メトリクス完全vectorized | MRE L1768-1795 | axis変換のみ。§4の独自実装は不要 |
| best_year / worst_year | MRE L1586-1601 | year_windowsをIS期間の年配列で置換 |
| downside_deviation | MRE L1584: `np.sqrt(np.mean(np.minimum(0.0, windows)**2, axis=2))` | axis=2→axis=0 |
| MDD, Calmar, VaR, Sortino | MRE L1603-1624 | axis=2→axis=0 |
| MINIMIZE_FINAL_METRICS | **l1_alm L71-82 に既存定義済み** | 再実装禁止。MINIMIZE_SETの更新のみ |
| NEUTRAL_FINAL_METRICS | **l1_alm L83 に既存定義済み** | 再実装禁止 |

**実装方針**: `_compute_metrics_np_window_fast()` の拡張で MRE.batch_rolling_metricsの各計算ブロックを `axis=2 → axis=0` に変換して配置。コピー元行番号を必ずコメントに記載（追跡可能に）。

---

## §1. 38メトリクス全量定義一覧

出典: `scripts/analysis/standard_pf_preprocessing/metrics_research_engine.py` L84-123

| # | メトリクス名 | slug | 分類 | 実装方式 |
|---|------------|------|------|---------|
| 1 | Arithmetic Mean (monthly) | arithmetic_mean_monthly | prefix | cumsum/n |
| 2 | Arithmetic Mean (annualized) | arithmetic_mean_annualized | prefix | cumsum/n × 12 |
| 3 | Geometric Mean (monthly) | geometric_mean_monthly | prefix | exp(cumlog1p/n) - 1 |
| 4 | Geometric Mean (annualized) | geometric_mean_annualized | prefix ✅ | exp(cumlog1p×12/n) - 1 = cagr |
| 5 | Standard Deviation (monthly) | standard_deviation_monthly | prefix ✅ | sqrt(cumsq/n - mean²) |
| 6 | Standard Deviation (annualized) | standard_deviation_annualized | prefix | std × sqrt(12) |
| 7 | Downside Deviation (monthly) | downside_deviation_monthly | prefix+ | sqrt(cum_neg_sq/n) |
| 8 | Best Year | best_year | vectorized | annual groups max O(IS×P) |
| 9 | Worst Year | worst_year | vectorized | annual groups min O(IS×P) |
| 10 | Maximum Drawdown | maximum_drawdown | vectorized | (cummax-cum)/cummax O(IS×P) |
| 11 | Benchmark Correlation | benchmark_correlation | N/A | NaN固定 |
| 12 | Beta | beta | N/A | NaN固定 |
| 13 | Alpha (annualized) | alpha_annualized | N/A | NaN固定 |
| 14 | R² | r | N/A | NaN固定 |
| 15 | Sharpe Ratio | sharpe_ratio | prefix ✅ | mean/std × sqrt(12) |
| 16 | Sortino Ratio | sortino_ratio | prefix+ | mean/downside_dev × sqrt(12) |
| 17 | Treynor Ratio (%) | treynor_ratio | N/A | NaN固定 |
| 18 | Calmar Ratio | calmar_ratio | hybrid | cagr/MDD (cagr=prefix, MDD=vectorized) |
| 19 | Analytical VaR (5%) | analytical_value_at_risk_5 | prefix | mean - 1.65×std |
| 20 | Upside Capture Ratio (%) | upside_capture_ratio | N/A | NaN固定 |
| 21 | Downside Capture Ratio (%) | downside_capture_ratio | N/A | NaN固定 |
| 22 | Up/Down Spread | updown_spread | N/A | NaN固定 |
| 23 | Up/Down Ratio | updown_ratio | N/A | NaN固定 |
| 24 | Up/Down Vector | updown_vector | N/A | NaN固定 |
| 25 | Positive Periods | positive_periods | prefix+ | cumpos/n |
| 26 | Gain/Loss Ratio | gainloss_ratio | prefix+ | cumpos_sum/n / |cumneg_sum/n| |
| 27 | Skewness | skewness | prefix ✅ | cum3から算出（PrefixMomentCache実装済み・未wire） |
| 28 | Excess Kurtosis | excess_kurtosis | prefix ✅ | cum4から算出（実装済み・未wire） |
| 29 | Max Run-up | max_run_up | vectorized ✅ | suffix_max_runup共有（実装済み） |
| 30 | Tail Contribution Ratio | tail_contribution_ratio | vectorized ✅ | np.partition（実装済み・律速） |
| 31 | Left-tail Jumps | left_tail_jumps | prefix ✅ | (r < -2σ)count（実装済み） |
| 32 | New High Frequency | new_high_frequency | vectorized ✅ | cummax比較（実装済み） |
| 33 | Active Return | active_return | N/A | NaN固定 |
| 34 | Tracking Error | tracking_error | N/A | NaN固定 |
| 35 | Information Ratio | information_ratio | N/A | NaN固定 |
| 36 | Underwater Period | underwater_period | vectorized | peak-to-recovery月数 O(IS×P) |
| 37 | Drawdown Length | drawdown_length | vectorized | peak-to-trough月数 O(IS×P) |
| 38 | Recovery Time | recovery_time | vectorized | trough-to-recovery月数 O(IS×P) |

**分類サマリ**:
- prefix O(1) 既実装（wire要）: 8個（#4,5,15,27,28,29,31,32）
- prefix O(1) 新規実装: 6個（#1,2,3,6,19, + #16,25,26のCache拡張込み）
- prefix+ Cache拡張要: 4個（#7,16,25,26）
- vectorized O(IS×P) 新規: 7個（#8,9,10,18,36,37,38）
- N/A NaN固定: 13個（#11,12,13,14,17,20,21,22,23,24,33,34,35）

---

## §2. PrefixMomentCache拡張設計

**対象ファイル**: `outputs/scripts/l1_alm_wf_engine.py` L115-192

### 追加4配列

```python
# PrefixMomentCache.build() に追加（L123-132付近）
arr64 = np.asarray(arr, dtype=np.float64)
neg_sq = np.minimum(arr64, 0.0) ** 2       # min(r,0)² → Downside Dev
pos_mask = arr64 > 0.0                        # r > 0 のbool mask

new_fields = {
    "cumpos":     np.cumsum(pos_mask.astype(np.float64), axis=0),   # count(r>0)
    "cum_neg_sq": np.cumsum(neg_sq, axis=0),                         # Σmin(r,0)²
    "cumpos_sum": np.cumsum(np.where(pos_mask, arr64, 0.0), axis=0), # Σr[r>0]
    "cumneg_sum": np.cumsum(np.where(~pos_mask, arr64, 0.0), axis=0),# Σr[r≤0]
}
```

**メモリ追加**: 4配列 × (166, 119493) × 8bytes = 4 × 158MB ≈ **+632MB**

### 新規メソッド（window_stats_ext）

```python
def window_stats_ext(self, start: int, end: int) -> dict[str, np.ndarray]:
    """既存window_stats + 新規4メトリクス"""
    mean, std, skew, kurt = self.window_stats(start, end)
    n = float(end - start + 1)

    # Positive Periods
    pos_count = self._window_total(self.cumpos, start, end)
    positive_periods = pos_count / n

    # Downside Deviation (monthly)
    neg_sq_sum = self._window_total(self.cum_neg_sq, start, end)
    downside_dev = np.sqrt(np.maximum(neg_sq_sum / n, 0.0))

    # Gain/Loss Ratio
    pos_sum = self._window_total(self.cumpos_sum, start, end)
    neg_sum = self._window_total(self.cumneg_sum, start, end)  # ≤0
    with np.errstate(invalid="ignore", divide="ignore"):
        gain_loss = np.where(neg_sum < 0.0, pos_sum / (-neg_sum) * n / pos_count,
                             np.where(pos_count > 0, np.inf, np.nan))

    return {
        "mean": mean, "std": std, "skew": skew, "kurt": kurt,
        "positive_periods": positive_periods,
        "downside_dev": downside_dev,
        "gain_loss": gain_loss,
    }
```

---

## §3. _compute_metrics_np_window_fast 拡張設計

**対象**: L367-411 `_compute_metrics_np_window_fast()`

### prefix系の wire接続（追加コード）

```python
def _compute_metrics_np_window_fast(arr, start, end, prefix_cache, objective=None):
    ...
    # 既存: mean_r, std_r 計算（L379-380）
    # 新規: prefix_cacheのextended stats取得
    stats = prefix_cache.window_stats_ext(start, end)
    mean_r = stats["mean"]
    std_r = stats["std"]

    # prefix O(1) メトリクス（既存実装の活用）
    if "arithmetic_mean_monthly" in needed:
        metrics_np["arithmetic_mean_monthly"] = mean_r
    if "arithmetic_mean_annualized" in needed:
        metrics_np["arithmetic_mean_annualized"] = mean_r * 12.0
    if "standard_deviation_annualized" in needed:
        metrics_np["standard_deviation_annualized"] = std_r * np.sqrt(12.0)
    if "skewness" in needed:
        metrics_np["skewness"] = stats["skew"]
    if "excess_kurtosis" in needed:
        metrics_np["excess_kurtosis"] = stats["kurt"] - 3.0
    if "analytical_value_at_risk_5" in needed:
        metrics_np["analytical_value_at_risk_5"] = mean_r - 1.6449 * std_r
    if "positive_periods" in needed:
        metrics_np["positive_periods"] = stats["positive_periods"]
    if "downside_deviation_monthly" in needed:
        metrics_np["downside_deviation_monthly"] = stats["downside_dev"]
    if "sortino_ratio" in needed:
        dd = stats["downside_dev"]
        with np.errstate(invalid="ignore", divide="ignore"):
            metrics_np["sortino_ratio"] = np.where(dd > 0, mean_r / dd * np.sqrt(12.0), np.nan)
    if "gainloss_ratio" in needed:
        metrics_np["gainloss_ratio"] = stats["gain_loss"]
    if "geometric_mean_monthly" in needed:
        n = float(end - start + 1)
        log_total = prefix_cache._window_total(prefix_cache.cumlog1p, start, end)
        metrics_np["geometric_mean_monthly"] = np.exp(log_total / n) - 1.0
```

### vectorized系（MDD, DD系, Best/Worst Year）

```python
    # Maximum Drawdown
    if "maximum_drawdown" in needed or "calmar_ratio" in needed:
        cum = np.cumprod(1.0 + window_arr, axis=0)
        running_max = np.maximum.accumulate(cum, axis=0)
        with np.errstate(invalid="ignore", divide="ignore"):
            dd_ratio = np.where(running_max > 0, (running_max - cum) / running_max, 0.0)
        mdd = dd_ratio.max(axis=0)
        if "maximum_drawdown" in needed:
            metrics_np["maximum_drawdown"] = mdd
        if "calmar_ratio" in needed:
            cagr_val = metrics_np.get("cagr")  # prefixで計算済み
            with np.errstate(invalid="ignore", divide="ignore"):
                metrics_np["calmar_ratio"] = np.where(mdd > 0, cagr_val / mdd, np.nan)

    # DD系3メトリクス（numpy argmax）
    if any(m in needed for m in ("underwater_period", "drawdown_length", "recovery_time")):
        if "cum" not in dir():  # MDD計算で累積積が必要ならばここで計算
            cum = np.cumprod(1.0 + window_arr, axis=0)
            running_max = np.maximum.accumulate(cum, axis=0)
        n_is = window_arr.shape[0]
        trough_idx = np.argmax((running_max - cum), axis=0)  # (P,)
        # peak: trough以前でcumが最大のindex (P列ごとに異なる)
        # → ループ不可。ただしP=119493列での高速化が必要
        # 実装: _compute_dd_stats_batch(cum, running_max) で別関数化
        dd_stats = _compute_dd_stats_batch(cum, running_max)
        if "underwater_period" in needed:
            metrics_np["underwater_period"] = dd_stats["underwater"]
        if "drawdown_length" in needed:
            metrics_np["drawdown_length"] = dd_stats["dd_length"]
        if "recovery_time" in needed:
            metrics_np["recovery_time"] = dd_stats["recovery"]

    # Best Year / Worst Year
    if "best_year" in needed or "worst_year" in needed:
        metrics_np["best_year"], metrics_np["worst_year"] = _compute_annual_extremes(
            window_arr, dates[start:end+1]
        )
```

---

## §4. DD系 — MRE L1768-1795 の axis変換転用

**車輪の再発明禁止**: MRE L1768-1795に完全なvectorized実装あり。axis=2→axis=0に変換するだけ。

```python
# MRE L1768-1795 (series_count×period_count×window, axis=2) を
# l1_alm (IS月×P, axis=0) に変換。MRE元コードと1対1対応。

# cumはMDD計算ですでに必要 → 共有
cum = np.cumprod(1.0 + window_arr, axis=0)  # (IS, P)
IS, P = cum.shape

# MRE L1768-1769: running_max + dd_arr
running_max = np.maximum.accumulate(cum, axis=0)  # (IS, P)
dd_arr = np.where(running_max > 0.0, cum / running_max - 1.0, 0.0)  # (IS, P) ≤0
max_drawdown_neg = np.min(dd_arr, axis=0)  # (P,) 負値のMDD
max_drawdown = -max_drawdown_neg  # 正値

# MRE L1770: trough_pos
trough_pos = np.argmin(dd_arr, axis=0)  # (P,)

# MRE L1772-1777: peak_pos（MRE L1772-1774のインデックス変数は省略）
time_idx = np.arange(IS)[:, None]          # (IS, 1)
pre_trough_mask = time_idx <= trough_pos[None, :]  # (IS, P)
masked_cum = np.where(pre_trough_mask, cum, -np.inf)
peak_pos = np.argmax(masked_cum, axis=0)   # (P,)

# MRE L1778: drawdown_length_batch
drawdown_length = (trough_pos - peak_pos).astype(float)  # (P,)

# MRE L1780-1786: peak_val, recovery
peak_val = cum[peak_pos, np.arange(P)]     # (P,) — MRE L1780の advanced indexing
post_trough_mask = time_idx >= trough_pos[None, :]  # (IS, P)
recovered_mask = post_trough_mask & (cum >= peak_val[None, :])  # (IS, P)
has_recovery = recovered_mask.any(axis=0)  # (P,)
recovery_pos = np.argmax(recovered_mask, axis=0)  # (P,) argmax returns 0 if no True
recovery_time = np.where(has_recovery, (recovery_pos - trough_pos).astype(float), np.nan)
underwater_period = np.where(has_recovery, (recovery_pos - peak_pos).astype(float), np.nan)

# MRE L1788-1791: no_drawdown補正
no_drawdown = max_drawdown == 0.0
drawdown_length = np.where(no_drawdown, 0.0, drawdown_length)
recovery_time = np.where(no_drawdown, 0.0, recovery_time)
underwater_period = np.where(no_drawdown, 0.0, underwater_period)
```

**計算量**: O(IS × P)。MRE実装と同等。新規関数不要。

---

## §5. Best Year / Worst Year — MRE L1586-1601 の転用

**MRE L1586-1601** の処理を転用。MREは `(series_count, window_idx, window_months)` の3Dだが、l1_alm版は `(IS月, P)` の2D。構造が異なるため一部改変が必要。

```python
# MRE L1586-1601 転用。IS期間の年配列(year_arr)が必要。
# generate_folds_multi_is でfold.is_start が既知 → year配列を渡す

def _compute_best_worst_year(window_arr: np.ndarray, year_arr: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """MRE L1586-1601 の axis変換版。year_arr: IS月ごとの年(int)配列。"""
    cum = np.cumprod(1.0 + window_arr, axis=0)  # (IS, P)
    IS, P = cum.shape

    # MRE L1588-1601: year_startsを使った年次区切り
    year_starts = np.flatnonzero(np.r_[True, year_arr[1:] != year_arr[:-1]])
    if year_starts.size < 2:
        nan_arr = np.full(P, np.nan)
        return nan_arr, nan_arr

    # annual_returns: cum[year_end] / cum[year_start] - 1 (MRE L1592-1594参考)
    annual_rets = []
    for i in range(len(year_starts) - 1):
        s, e = year_starts[i], year_starts[i + 1]
        if e - s < 12:  # 不完全年スキップ (MRE L1596-1597参考)
            continue
        base = cum[s - 1] if s > 0 else np.ones(P)
        annual_rets.append(cum[e - 1] / base - 1.0)  # (P,)

    if not annual_rets:
        nan_arr = np.full(P, np.nan)
        return nan_arr, nan_arr

    stacked = np.stack(annual_rets, axis=0)  # (years, P)
    return stacked.max(axis=0), stacked.min(axis=0)
```

**注意**: IS=6Mの場合は完全年なし → NaN（MRE同様の挙動）。

---

## §6. METRIC_NAMES 更新

**対象**: L66 `METRIC_NAMES = [...]`

```python
METRIC_NAMES = [
    # prefix 既存
    "cagr", "sharpe", "max_run_up", "nhf", "tail_contribution", "left_tail_jumps_inv",
    # prefix 新規
    "arithmetic_mean_monthly", "arithmetic_mean_annualized",
    "geometric_mean_monthly",
    "standard_deviation_monthly", "standard_deviation_annualized",
    "skewness", "excess_kurtosis",
    "analytical_value_at_risk_5",
    "positive_periods", "gainloss_ratio",
    "downside_deviation_monthly", "sortino_ratio",
    # vectorized 新規
    "maximum_drawdown", "calmar_ratio",
    "best_year", "worst_year",
    "underwater_period", "drawdown_length", "recovery_time",
    # N/A (NaN固定)
    "benchmark_correlation", "beta", "alpha_annualized", "r",
    "treynor_ratio", "upside_capture_ratio", "downside_capture_ratio",
    "updown_spread", "updown_ratio", "updown_vector",
    "active_return", "tracking_error", "information_ratio",
]
# 合計38個
```

**MINIMIZE_SET 更新のみ** (L69, 再実装禁止):

`MINIMIZE_FINAL_METRICS` (L71-82) は**既存定義済み**。再実装禁止。
`MINIMIZE_SET` (L69) を `MINIMIZE_FINAL_METRICS` を参照して更新するだけ:

```python
# L69: 現行 MINIMIZE_SET: set[str] = set()（全最大化）
# 38メトリクス化後: 最小化すべきものは既存MINIMIZE_FINAL_METRICS(L71-82)から参照
MINIMIZE_SET: set[str] = MINIMIZE_FINAL_METRICS  # ← これだけ
```

**確認**: L71-82の既存定義で analytical_value_at_risk_5 が含まれているか確認が必要（設計書執筆時点ではなかった → 必要なら追加）

---

## §7. cmd分解ランブック

### cmd_1785-A: PrefixMomentCache拡張 + prefix系実装

**対象**: `outputs/scripts/l1_alm_wf_engine.py`
**変更箇所**:
- L115-192: PrefixMomentCache dataclass + build() + 新メソッド
- L66: METRIC_NAMES更新（暫定）
- L367-411: _compute_metrics_np_window_fast に prefix系14個追加

**AC**:
```
AC1: PrefixMomentCache.build()でcumpos/cum_neg_sq/cumpos_sum/cumneg_sumが生成される
     確認: assert hasattr(cache, 'cumpos') and cache.cumpos.shape == arr.shape
AC2: prefix系14メトリクスがcompute_metrics_np(full版)と atol=1e-10で一致
     確認: --validate で全prefix系PASS
AC3: 速度回帰なし。yotsume単体でPool=4、67窓、以前と同等秒以内
     確認: timeout 40 python l1_alm_wf_engine.py --csv yotsume.csv --multi-is
```

### cmd_1785-B: vectorized系実装（MDD/DD系/Best-Worst年）

**対象**: `outputs/scripts/l1_alm_wf_engine.py`
**変更箇所**:
- L367-411: _compute_metrics_np_window_fast にvectorized系追加
- **新関数なし**: MRE L1768-1795 (DD系) を axis=2→axis=0 変換転用（§4参照）
- **新関数なし**: MRE L1586-1601 (best/worst_year) を _compute_best_worst_year() として追加（§5参照）
- `_compute_best_worst_year(window_arr, year_arr)` のみ新規追加（MRE転用ラッパー）

**実装の核心（車輪の再発明禁止）**:
- MDD/Calmar: MRE L1603-1608 を axis=2→axis=0 変換。cummax+dd_ratio はインラインで十分
- DD系3個: MRE L1768-1795 の処理をそのままaxis変換（trough_pos/peak_pos/recovery_pos の argmax チェーン）
- Best/Worst Year: MRE L1586-1601 を year_arr引数版に改変。`_compute_best_worst_year()` として1関数追加

**AC**:
```
AC1: maximum_drawdown / calmar_ratio が metrics_research_engine版と atol=1e-6 一致
     確認: 既知リターン系列（V字/L字/右肩上がり）でMDD手計算と比較
     コード確認: MRE L1603 cummax→dd_ratioと実装が1対1対応すること
AC2: DD系3メトリクス（underwater/dd_length/recovery）がMRE L1768-1795と atol=1e-6
     確認: IS=24M以上のケースでargmaxチェーンの結果を突合
     コード確認: 各変数にMRE行番号コメント記載（追跡可能性）
AC3: Best Year / Worst Year が完全年のみ計算され、不完全年はNaN
     確認: IS=6M(NaN), IS=12M(1年分), IS=24M(2年分)の出力を確認
```

### cmd_1785-C: MINIMIZE_FINAL_METRICS+select_champions整合

**対象**: L71-82 + select_champions_multi_is (L688-)
**変更箇所**:
- MINIMIZE_FINAL_METRICS に VaR/underwater/drawdown/recovery 追加
- METRIC_NAMES 38個に確定

**AC**:
```
AC1: 38メトリクス全量でselect_champions_multi_isが正常動作
     確認: --multi-is --batch-csvs で7忍法PASS（全メトリクスのselectionが出力）
AC2: 速度目標維持。7忍法合計 ≤ 300秒(5分)
     確認: timeout 40 python l1_alm_wf_engine.py --multi-is --batch-csvs [全7]
```

---

## §8. 速度影響見積

追加計算量（1忍法・Pool=4あたり）:

| 追加メトリクス群 | 計算量 | 推定追加時間 |
|----------------|--------|------------|
| prefix+Cache拡張 | ビルド時O(IS月×P)×4配列 追加 | +0.5s (ビルドのみ) |
| prefix系14個 | O(1)/窓 × 2010計算 | +0.01s |
| MDD + Calmar | O(IS×P) × 2010 | +3-5s |
| DD系3個 | O(IS×P) × 2010（_compute_dd_stats_batch） | +5-10s |
| Best/Worst Year | O(IS月×P) × 2010 | +3-5s |

**合計推定追加: +10-20s/忍法**

→ yotsume: 21.46s + 15s ≈ 36s → **300秒(5分)目標を超える可能性あり**

対策: cmd_1784の速度改善（Pool配分最適化）を先に完了させてから1785を実装。
先にPool(4)でyoutsume=10sを達成してから38メトリクス化→10+15=25s。

**cmd実装順序**: `cmd_1784完了(速度) → cmd_1785-A → cmd_1785-B → cmd_1785-C`

---

## §9. テスト方針

### 数値一貫性テスト
```python
# 既知リターン系列でのground truth比較
r_test = np.array([0.01, -0.02, 0.03, -0.05, 0.10, -0.08, 0.04])  # 7ヶ月
# 手計算:
#   MDD = max((running_max - cum) / running_max)
#   DD length = peak_idx → trough_idx
#   Sortino = mean / downside_dev × sqrt(12)
# vs _compute_metrics_np_window_fast の出力比較
```

### 回帰テスト
- cmd_1782のbaseline_v2（IS=36固定）を基準
- 38メトリクス化後もIS=36部分のcagr/sharpe/max_run_up/nhf/tail/ltj がbaseline_v2と完全一致

### 速度テスト
```bash
# 各cmd後に速度確認
timeout 40 python l1_alm_wf_engine.py --csv yotsume.csv --multi-is \
  --parallel-workers 4
```
