# cmd_484 DM-signal supplemental catalog (2nd pass)

- cmd: `cmd_542`
- created_at: `2026-03-04`
- source_repo: `/mnt/c/Python_app/DM-signal`
- source_scope:
  - `backend/app/jobs/`
  - `scripts/`
  - `backend/app/api/etl_trigger.py`
  - `render.yaml`

## §1. recalculate-sync関連スクリプト一覧（backend/app/jobs）

`/admin/recalculate-sync` の実行本体は `backend/app/jobs/recalculate_fast.py`（`recalculate_history_fast`）で、FoF計算・flush・派生テーブル生成まで `jobs/` 配下のモジュールを連鎖利用する。

### §1.1 API入口（参照）

| Endpoint | 役割 | 実装 |
|---|---|---|
| `/admin/recalculate-sync` | 履歴再計算（full/ticker/portfolio）をバックグラウンド起動 | `backend/app/api/etl_trigger.py:284` |
| `/admin/recalculate-status` | 再計算進捗確認 | `backend/app/api/etl_trigger.py:197` |

### §1.2 jobsカタログ

| Script | 1行説明 | 主エントリ | Path |
|---|---|---|---|
| `recalculate_fast.py` | 再計算の主処理（L0-L3統合・高速化版） | `recalculate_history_fast` | `backend/app/jobs/recalculate_fast.py` |
| `recalculate_fof.py` | FoF履歴再計算（パイプライン実行+月次生成） | `_recalculate_fof_history` | `backend/app/jobs/recalculate_fof.py` |
| `recalculator.py` | 再計算ジョブラッパー（env引数対応） | `RecalculatorJob.run` | `backend/app/jobs/recalculator.py` |
| `sync_layers.py` | L0-L3分離同期（`sync-*` API本体） | `sync_prices/sync_tickers/sync_standard/sync_fof` | `backend/app/jobs/sync_layers.py` |
| `shared.py` | 再計算共有ユーティリティ（キャッシュ・block registry） | `get_pipeline_block_registry` ほか | `backend/app/jobs/shared.py` |
| `ticker_returns.py` | Ticker日次/月次リターン生成（L1） | `generate_ticker_monthly_returns` / `generate_ticker_daily_returns` | `backend/app/jobs/ticker_returns.py` |
| `flush/signal_flush.py` | SignalバッチUPSERT | `_flush_batch` | `backend/app/jobs/flush/signal_flush.py` |
| `flush/fof_flush.py` | FoF系ログ/判定/構成比フラッシュ | `_flush_fof_pipeline_logs` ほか | `backend/app/jobs/flush/fof_flush.py` |
| `generators/monthly_returns.py` | MonthlyReturn生成 | `_generate_monthly_returns` | `backend/app/jobs/generators/monthly_returns.py` |
| `generators/trade_performance.py` | TradePerformance生成 | `_generate_trade_performance` | `backend/app/jobs/generators/trade_performance.py` |
| `generators/drawdowns.py` | Drawdown期間生成 | `_generate_drawdown_periods` | `backend/app/jobs/generators/drawdowns.py` |
| `generators/rolling_returns.py` | Rolling returns要約/チャート生成 | `_generate_rolling_returns_summary` / `_generate_rolling_returns_chart` | `backend/app/jobs/generators/rolling_returns.py` |
| `generators/portfolio_metrics.py` | PortfolioMetrics生成（35指標） | `_generate_portfolio_metrics` | `backend/app/jobs/generators/portfolio_metrics.py` |
| `generators/risk_metrics.py` | リスク管理指標生成 | `_generate_risk_management_metrics` | `backend/app/jobs/generators/risk_metrics.py` |

## §2. register-shijin関連スクリプト（scripts/配下）

現行treeで `register-shijin` 直系は `register_285_yotsume_fof.py` が主軸。補助として本番PF取得/保存/検証スクリプト群がある。

| Script | 1行説明 | Path |
|---|---|---|
| `register_285_yotsume_fof.py` | 四つ目FoF（3モード）の本番登録（dry-run/execute） | `scripts/analysis/register_285_yotsume_fof.py` |
| `upload_portfolios.py` | PF JSONを本番保存し `recalculate-sync` まで実行 | `scripts/core/upload_portfolios.py` |
| `fetch_portfolios.py` | 本番PF一覧取得（登録前後比較に使用） | `scripts/core/fetch_portfolios.py` |
| `collect_all_pf_data.py` | 本番PF/metricsを一括収集して `analysis_runs/idea-loop` へ保存 | `scripts/core/collect_all_pf_data.py` |
| `verify_all_portfolios.py` | 全Standard PFの月次リターンを本番とパリティ検証 | `scripts/analysis/grid_search/verify_all_portfolios.py` |

## §3. デプロイ関連スクリプト群（scripts/deploy*, scripts/analysis/等）

`scripts/deploy*` は現行treeに存在しない。代替として `scripts/core` + `scripts/analysis` がデプロイ実務（登録・再計算・検証）を担う。

### §3.1 `scripts/deploy*` 実在チェック

| パターン | 件数 | 判定 |
|---|---:|---|
| `scripts/deploy*` | 0 | 不在 |

### §3.2 実運用で使うデプロイ補助スクリプト

| Script | 1行説明 | Path |
|---|---|---|
| `trigger_etl.py` | ETLジョブを直接起動 | `scripts/core/trigger_etl.py` |
| `run_recalculate.py` | ローカルから再計算実行（jobs直呼び） | `scripts/core/run_recalculate.py` |
| `upload_portfolios.py` | 本番PF保存+再計算トリガー | `scripts/core/upload_portfolios.py` |
| `backfill_data.py` | 過去データバックフィル（Price/EconomicIndicator） | `scripts/core/backfill_data.py` |
| `check_fof_freshness.py` | FoF `gs_metadata.data_period_end` 鮮度チェック | `scripts/analysis/check_fof_freshness.py` |
| `verify_all_portfolios.py` | デプロイ後の整合性確認（月次パリティ） | `scripts/analysis/grid_search/verify_all_portfolios.py` |

## §4. 運用系スクリプト（sync-prices, sync-tickers等のcron関連）

cronは Render から `/admin/sync-*` を叩き、実処理は `etl_trigger.py` → `jobs/sync_layers.py` へ委譲される。

### §4.1 cron → endpoint → jobs 実行マップ

| Cron name (UTC) | Endpoint | Job function | 主Path |
|---|---|---|---|
| `dm-signal-sync-prices` (`0 1 * * *`) | `POST /admin/sync-prices` | `sync_layers.sync_prices` | `render.yaml`, `backend/app/api/etl_trigger.py`, `backend/app/jobs/sync_layers.py` |
| `dm-signal-sync-tickers` (`5 1 * * *`) | `POST /admin/sync-tickers` | `sync_layers.sync_tickers` | 同上 |
| `dm-signal-sync-standard` (`10 1 * * *`) | `POST /admin/sync-standard` | `sync_layers.sync_standard` | 同上 |
| `dm-signal-sync-fof` (`40 1 * * *`) | `POST /admin/sync-fof` | `sync_layers.sync_fof` | 同上 |

### §4.2 cron運用を支える関連スクリプト

| Script | 1行説明 | Path |
|---|---|---|
| `download_all_prices.py` | StockData APIから全価格をローカル取得 | `scripts/analysis/data_sync/download_all_prices.py` |
| `download_prod_data.py` | 本番月次/価格/シグナル等をローカルへ同期 | `scripts/analysis/data_sync/download_prod_data.py` |
| `refresh_sqlite_from_api.py` | API再取得でSQLite再同期（パリティ用途） | `scripts/analysis/data_sync/refresh_sqlite_from_api.py` |
| `sync_dm_monthly_returns.py` | 対象DMの月次リターンを本番APIから取得 | `scripts/analysis/data_sync/sync_dm_monthly_returns.py` |
| `sync_prices_from_prod.py` | 本番PostgreSQLからSQLiteへ価格同期 | `scripts/analysis/data_sync/sync_prices_from_prod.py` |
| `local_metrics.py` | ローカルDBから指標算出（運用検証） | `scripts/analysis/data_sync/local_metrics.py` |

## §5. 調査メモ（最小）

- `context/dm-signal-ops.md` の参照先として必要だった `docs/research/cmd_484_dm-signal-supplemental-catalog-2.md` を再作成した。
- 参照元実装は `backend/app/api/etl_trigger.py`（`/recalculate-sync`, `/sync-*`）と `render.yaml` cron 定義で確認済み。
