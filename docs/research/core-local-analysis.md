# DM-Signal ローカル分析関数詳細
<!-- cmd_286 | 2026-02-23 | core.md §5から移動。simulate_strategy_vectorized()の全パラメータと注意事項 -->

## simulate_strategy_vectorized()

パス: `scripts/analysis/grid_search/grid_search_metrics_v2.py`

```python
simulate_strategy_vectorized(
    monthly_returns_df,   # 月次リターンDF
    rebalance_schedule,   # 'monthly', 'quarterly_jan', etc.
    base_portfolio_name,  # 'DM2', 'DM3', 'DM6', 'DM7+'
    candidate_params      # オーバーライドパラメータ
) → {total_return, cagr, max_drawdown, sharpe_ratio, sortino_ratio, monthly_returns, ...}
```

注意:
- **MomentumCache必須**: `momentum_cache`を渡さないと黙って空リストを返す（例外なし）
- `date_from`/`date_to`で期間制限可（WF検証用）
- リバランススケジュール: monthly|bimonthly_odd|quarterly_jan|semiannual_jan|annual_jan

## 月次リターン計算ルール

```
シグナル実行: 月末シグナル → 翌月リターン適用
月次リターン = (月末価格 / 月初価格) - 1
マルチアセット: 保有銘柄リターンの単純平均
```
