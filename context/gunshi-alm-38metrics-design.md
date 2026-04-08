<!-- last_updated: 2026-04-09 -->
# 設計索引: l1_alm_wf_engine 6→38メトリクス拡張

<!-- cmd: cmd_1785 | author: gunshi | created: 2026-04-07 -->

## 結論

l1_alm_wf_engineのcompute_metrics_npを6→38メトリクスに拡張する設計。**実装済み**（ALL_METRIC_NAMES=38、DD3メトリクス計算、PrefixMomentCache拡張完了）。
PrefixMomentCacheに4配列追加で14個がO(1)化。残りは vectorized O(IS×P) or N/A。

## 38メトリクス分類

| 分類 | 件数 | 内容 |
|------|------|------|
| prefix O(1) — 既存 | 6 | cagr/sharpe/max_run_up/nhf/tail_contribution/ltj_inv |
| prefix O(1) — 追加実装 | 8 | mean monthly/ann, geo monthly, std ann, skew, kurt, VaR, (実装済みだが未wire) |
| prefix+ O(1) — Cache拡張要 | 4 | downside_dev, positive_periods, gain_loss_ratio, sortino |
| vectorized O(IS×P) | 9 | MDD, calmar, DD系3, best/worst_year, MDD系 |
| N/A — NaN固定 | 13 | ベンチマーク依存7+benchmark系6 |

**N/Aメトリクス**: Benchmark Correlation, Beta, Alpha, R², Treynor, Upside Capture, Downside Capture, Up/Down Spread/Ratio/Vector, Active Return, Tracking Error, Information Ratio

## PrefixMomentCache拡張（4配列追加）

```python
@dataclass
class PrefixMomentCache:
    # 既存
    cumsum: np.ndarray      # Σr
    cumsq: np.ndarray       # Σr²
    cum3: np.ndarray        # Σr³
    cum4: np.ndarray        # Σr⁴
    cumlog1p: np.ndarray    # Σlog(1+r)
    # 新規追加
    cumpos: np.ndarray      # Σ[r>0] (count) → Positive Periods
    cum_neg_sq: np.ndarray  # Σmin(r,0)² → Downside Deviation
    cumpos_sum: np.ndarray  # Σr×[r>0] → Gain/Loss分子
    cumneg_sum: np.ndarray  # Σr×[r<0] → Gain/Loss分母、Sortino
```

ビルド追加コード（`PrefixMomentCache.build()` に追加）:
```python
arr64 = np.asarray(arr, dtype=np.float64)
neg_sq = np.minimum(arr64, 0.0) ** 2
pos_mask = arr64 > 0.0
return cls(
    ...  # 既存5配列
    cumpos=np.cumsum(pos_mask.astype(np.float64), axis=0),
    cum_neg_sq=np.cumsum(neg_sq, axis=0),
    cumpos_sum=np.cumsum(np.where(pos_mask, arr64, 0.0), axis=0),
    cumneg_sum=np.cumsum(np.where(~pos_mask, arr64, 0.0), axis=0),
)
```

## 実装設計

→ 詳細: `docs/research/gunshi-alm-38metrics-design.md`

## cmd分解案

| cmd | 内容 | AC数 | 対象ファイル |
|-----|------|------|------------|
| cmd_1785-A | PrefixMomentCache拡張+prefix系14個実装 | 3 | l1_alm_wf_engine.py |
| cmd_1785-B | vectorized系9個実装（MDD/DD系/best-worst年） | 3 | l1_alm_wf_engine.py |
| cmd_1785-C | MINIMIZE_FINAL_METRICS更新+select_champions整合 | 2 | l1_alm_wf_engine.py |

**配備順序**: A→B→C（依存あり）。A完了後にBのMDD実装が可能。
