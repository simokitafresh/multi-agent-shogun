# DM-Signal DB Schema Quick Reference (全7テーブル詳細)

> 移動元: `projects/dm-signal.yaml §(h)` (cmd_2295圧縮 2026-04-26)
> 正規ソース: `backend/app/db/models.py`
> 更新日: 2026-03-28 (GP-122実装: 軍師がmodels.pyから直接確認して追記)
> ⚠ 推測するな。ここにないテーブルはmodels.pyを直接読め。

## portfolios
- tablename: portfolios
- pk: [id]
- columns: id, name, type, config, folder_id, created_at, updated_at, hide_portfolio, hide_signal, is_active
- notes: type='standard'|'fof'。configはJSON(relative_assets,lookback,benchmark_ticker,pipeline_config等)

## signals
- tablename: signals
- pk: [portfolio_id, date]
- columns: portfolio_id, date, signal, holding_signal, momentum_data, created_at
- notes: signal=生シグナル, holding_signal=保有シグナル(リバランス考慮)

## monthly_returns
- tablename: monthly_returns
- pk: [portfolio_id, year_month]
- columns: portfolio_id, year_month, cumulative_return, cumulative_return_open, monthly_return, monthly_return_open, benchmark_cumulative, benchmark_cumulative_open, benchmark_return, benchmark_return_open, in_market, holding_signal
- notes: year_month='2024-12'形式。cumulative_return=月末累積。monthly_return=当月リターン

## recalculation_timings
- tablename: recalculation_timings
- pk: [id]
- columns: id, run_id, operation, mode, started_at, finished_at, total_elapsed_sec, bottleneck, layer_data, layer_breakdown, created_at
- notes: ⚠ completed_atではなくfinished_at。run_id='RUN-XXX'形式

## calculation_performance_log
- tablename: calculation_performance_log
- pk: [id]
- columns: id, run_id, layer, portfolio_id, substep, started_at, finished_at, elapsed_sec, memory_mb, db_queries, cache_hits, cache_misses, extra_data, created_at
- notes: RecalculationTimingの子テーブル。run_idで紐付き

## fof_pipeline_logs
- tablename: fof_pipeline_logs
- pk: [id]
- columns: id, portfolio_id, calculation_date, execution_timestamp, initial_tickers, component_types, block_results, terminal_block_type, final_signal, final_weights, nested_expansion, final_tickers, max_nesting_depth, execution_time_ms, error_message
- notes: ⚠ created_atではなくexecution_timestamp。ENABLE_FOF_DEBUG_LOGS=true時のみ記録

## fof_component_weights
- tablename: fof_component_weights
- pk: [portfolio_id, date, component_id]
- columns: portfolio_id, date, component_id, component_type, nested_depth, target_weight, actual_weight, drift, asset_value, daily_return, component_holding_signal, component_tickers, expanded_tickers, child_components
- notes: target_weight=目標, actual_weight=ドリフト後実績, drift=actual-target

## fof_rebalance_decisions
- tablename: fof_rebalance_decisions
- pk: [portfolio_id, date]
- columns: portfolio_id, date, trigger_type, should_rebalance, rebalance_reason, prev_signal, new_signal, signal_changed
- notes: ⚠ decision_dateではなくdate。ENABLE_FOF_DEBUG_LOGS=true時のみ記録
