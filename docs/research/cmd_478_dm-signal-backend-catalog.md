# DM-Signal Backend Catalog (cmd_478)

- 作成者: hayate (`subtask_478_recon_a`)
- 対象: `/mnt/c/Python_app/DM-signal/backend/app/`
- 作成時刻: 2026-03-02 JST
- 参照: `backend/app/main.py`, `backend/app/api/*.py`, `backend/app/jobs/**/*.py`, `backend/requirements.txt`
- 統合状況: `queue/reports/kagemaru_report_cmd_478.yaml`（kagemaru, `subtask_478_recon_b`）を反映し、AC6統合済み。

---

## §1 APIルーターカタログ（AC1）

### 1.1 `main.py` ルーター登録順

1. portfolios
2. etl_trigger
3. backfill
4. db_admin
5. signals
6. history
7. performance
8. benchmark
9. metrics
10. kalman
11. annual_returns
12. monthly_returns
13. rolling_returns
14. trades
15. monthly_trade
16. drawdowns
17. auth
18. viewer_permissions
19. viewer_tiers
20. folders
21. debug（`DEBUG_API_ENABLED=true` の場合のみ）

### 1.2 ファイル別カタログ

#### `api/__init__.py` (1行)
- 登録順: なし（定義のみ）
- エンドポイント: なし

#### `api/annual_returns.py` (98行)
- 登録順: 11
- 認証: viewer
- `GET /api/annual-returns/{portfolio_id}`: 年次リターン一覧を返す

#### `api/auth.py` (97行)
- 登録順: 17
- 認証: mixed (public/admin)
- `POST /api/auth/verify-viewer`: viewerパスワード検証とviewerセッション発行
- `POST /api/admin/login`: 管理者ログイン（admin認証）
- `POST /api/auth/logout`: セッションCookieを削除

#### `api/backfill.py` (342行)
- 登録順: 3
- 認証: admin
- `POST /admin/long-term-backfill`: 長期バックフィル実行
- `GET /admin/backfill-status`: バックフィル進捗/状態を返す

#### `api/benchmark.py` (121行)
- 登録順: 8
- 認証: viewer
- `GET /api/benchmark/{ticker}`: ベンチマークの時系列パフォーマンスを返す

#### `api/db_admin.py` (343行)
- 登録順: 4
- 認証: admin
- `POST /admin/run-migration`: DBマイグレーション実行
- `GET /admin/db-status`: DB整合/状態確認
- `DELETE /admin/cleanup-fof-signals`: FoFシグナル関連クリーンアップ

#### `api/debug.py` (886行)
- 登録順: 21（条件付き）
- 認証: mostly admin（`test-strip`, `code-version` はpublic）
- `GET /api/debug/signal-raw/{portfolio_id}`: 生シグナル取得
- `GET /api/debug/fof-components/{fof_id}`: FoF構成要素シグナル確認
- `GET /api/debug/fof-trades-debug/{fof_id}`: FoFトレード計算デバッグ
- `GET /api/debug/test-strip`: 文字列整形テスト
- `GET /api/debug/code-version`: コードバージョン表示
- `GET /api/debug/prices/{symbol}`: 単一銘柄価格データ確認
- `GET /api/debug/prices-range/{symbol}`: 価格レンジ取得
- `GET /api/debug/daily-return/{symbol}`: 日次リターン確認
- `GET /api/debug/fof-profiling`: FoFプロファイリング確認
- `GET /api/debug/monthly-returns-raw/{portfolio_id}`: 月次リターン生データ確認
- `GET /api/debug/portfolio-config/{portfolio_id}`: PF設定確認
- `GET /api/debug/fof-list`: FoF一覧取得
- `GET /api/debug/trade-performance/{portfolio_id}`: trade performance内部値確認
- `GET /api/debug/ticker-daily-returns`: 銘柄日次リターン確認
- `GET /api/debug/fof-pipeline-log/{portfolio_id}`: FoFパイプラインログ取得
- `GET /api/debug/fof-weights/{portfolio_id}`: FoFウェイト履歴取得
- `GET /api/debug/fof-rebalance/{portfolio_id}`: FoFリバランス履歴取得

#### `api/drawdowns.py` (60行)
- 登録順: 16
- 認証: viewer
- `GET /api/drawdowns/{portfolio_id}`: ドローダウン期間を返す

#### `api/etl_trigger.py` (1111行)
- 登録順: 2
- 認証: admin
- `POST /admin/run-etl`: ETL起動
- `POST /admin/run-kalman-wf`: Kalman workflow起動
- `GET /admin/etl-status`: ETL状態確認
- `GET /admin/recalculate-status`: 再計算状態確認
- `POST /admin/cancel-recalculate`: 再計算キャンセル
- `POST /admin/run-backfill`: バックフィル起動
- `POST /admin/run-maintenance`: メンテナンス起動
- `POST /admin/recalculate-sync`: 同期再計算実行
- `POST /admin/validate-prices`: 価格検証実行
- `POST /admin/run-password-rotation`: viewerパスワードローテーション
- `POST /admin/validate-and-recalculate`: 価格検証+再計算連結実行
- `GET /admin/timing-history`: レイヤー計測履歴取得
- `POST /admin/sync-prices`: L1価格同期
- `POST /admin/sync-tickers`: L1 ticker return同期
- `POST /admin/sync-standard`: L2標準PF同期
- `POST /admin/sync-fof`: L3 FoF同期
- `GET /admin/sync-status`: 同期ジョブ状態確認
- `GET /admin/price-tickers`: 価格テーブル銘柄一覧
- `DELETE /admin/cleanup-prices`: 未使用価格データ削除

#### `api/folders.py` (309行)
- 登録順: 20
- 認証: admin
- `GET /api/admin/folders`: フォルダ一覧
- `GET /api/admin/folders/tree`: フォルダツリー取得
- `POST /api/admin/folders`: フォルダ作成
- `PATCH /api/admin/folders/{folder_id}`: フォルダ更新
- `DELETE /api/admin/folders/{folder_id}`: フォルダ削除
- `PUT /api/admin/folders/reorder`: フォルダ並び替え
- `POST /api/admin/folders/portfolios/{portfolio_id}/move`: PFのフォルダ移動

#### `api/history.py` (244行)
- 登録順: 6
- 認証: viewer
- `GET /api/history/{portfolio_id}`: ポートフォリオ履歴系列を返す

#### `api/kalman.py` (61行)
- 登録順: 10
- 認証: admin
- `GET /api/kalman/weights`: Kalman weight取得

#### `api/metrics.py` (367行)
- 登録順: 9
- 認証: viewer
- `GET /api/metrics/summary`: 全PFメトリクス要約
- `GET /api/metrics/{portfolio_id}`: PFメトリクス詳細
- `GET /api/metrics/{portfolio_id}/up-down-market`: 上昇/下落局面分析

#### `api/monthly_returns.py` (112行)
- 登録順: 12
- 認証: viewer
- `GET /api/monthly-returns/{portfolio_id}`: 月次リターンヒートマップデータ

#### `api/monthly_trade.py` (168行)
- 登録順: 15
- 認証: viewer
- `GET /api/monthly-trade/{portfolio_id}`: 月次トレード明細

#### `api/performance.py` (276行)
- 登録順: 7
- 認証: viewer
- `GET /api/performance/{portfolio_id}`: 累積パフォーマンス系列
- `GET /api/mtd/{portfolio_id}`: 当月MTDパフォーマンス

#### `api/portfolios.py` (624行)
- 登録順: 1
- 認証: admin（`main.py` コメント上は`/get`公開意図だが実装は`require_admin`）
- `GET /api/portfolios/get`: PF設定一覧取得
- `DELETE /api/portfolios/{portfolio_id}`: PF削除
- `POST /api/portfolios/save`: PF保存（現行）
- `POST /api/portfolios/save-legacy`: PF保存（旧互換）

#### `api/rolling_returns.py` (67行)
- 登録順: 13
- 認証: viewer
- `GET /api/rolling-returns/{portfolio_id}`: ローリングリターン系列/集計

#### `api/signals.py` (252行)
- 登録順: 5
- 認証: viewer
- `GET /api/signals`: シグナル軽量一覧（トップ画面用）

#### `api/trades.py` (169行)
- 登録順: 14
- 認証: viewer
- `GET /api/trades/{portfolio_id}`: トレード/リスク管理データ

#### `api/viewer_permissions.py` (65行)
- 登録順: 18
- 認証: mixed
- `GET /api/viewer-permissions`: viewer権限設定取得（viewer）
- `POST /api/admin/viewer-permissions`: viewer権限設定更新（admin）

#### `api/viewer_tiers.py` (480行)
- 登録順: 19
- 認証: admin
- `GET /api/admin/tiers`: tier一覧
- `POST /api/admin/tiers`: tier作成
- `PUT /api/admin/tiers/reorder`: tier順序更新
- `PUT /api/admin/tiers/{tier_id}`: tier更新
- `DELETE /api/admin/tiers/{tier_id}`: tier削除
- `POST /api/admin/tiers/{tier_id}/copy`: tier複製
- `GET /api/admin/tiers/{tier_id}/visibility`: tier可視性取得
- `PUT /api/admin/tiers/{tier_id}/visibility`: tier可視性更新
- `POST /api/admin/tiers/{tier_id}/rotate`: tierパスワードローテーション
- `GET /api/admin/tiers/passwords`: tierパスワード一覧
- `POST /api/admin/tiers/rotate-all`: 全tierパスワードローテーション
- `GET /api/admin/tiers/visibility/global`: 全体可視性取得
- `PUT /api/admin/tiers/visibility/global`: 全体可視性更新

---

## §2 Jobsカタログ（AC3）

### 2.1 全ジョブファイル一覧（行数・エントリポイント・フェーズ・OPT）

| ファイル | 行数 | エントリポイント（公開/実行起点） | 処理フェーズ概要 | OPT-* |
|---|---:|---|---|---|
| `app/jobs/__init__.py` | 1 | なし | パッケージ定義 | - |
| `app/jobs/constants.py` | 34 | `get_fof_batch_size` | 定数/環境値解決 | - |
| `app/jobs/daily_etl.py` | 80 | `run_etl` | ETL orchestrate → maintenance/recalc連携 | - |
| `app/jobs/data_fetcher.py` | 143 | `DataFetcherJob`, `run_fetch_job` | 価格/経済データ取得ジョブ | - |
| `app/jobs/etl/__init__.py` | 4 | `DataFetcher`,`EtlCalculator`,`EtlLoader`,`EtlOrchestrator` | ETL部品公開 | - |
| `app/jobs/etl/calculator.py` | 151 | `EtlCalculator` | モメンタム/シグナル計算 | - |
| `app/jobs/etl/fetcher.py` | 126 | `DataFetcher` | 外部APIフェッチ/再試行 | - |
| `app/jobs/etl/loader.py` | 100 | `EtlLoader` | Price/Economic/Signal書込み | - |
| `app/jobs/etl/orchestrator.py` | 302 | `EtlOrchestrator` | fetch→calc→load→optional recalc | - |
| `app/jobs/flush/__init__.py` | 17 | `_flush_batch`,`_flush_fof_*` | flush helper公開 | - |
| `app/jobs/flush/fof_flush.py` | 221 | `_flush_fof_pipeline_logs`, `_flush_fof_component_weights`, `_flush_fof_rebalance_decisions` | FoF補助テーブル一括flush | - |
| `app/jobs/flush/signal_flush.py` | 60 | `_flush_batch` | `Signal` UPSERTバッチflush | - |
| `app/jobs/generators/__init__.py` | 28 | `_generate_*`群 | 派生テーブル生成器公開 | - |
| `app/jobs/generators/drawdowns.py` | 159 | `_generate_drawdown_periods` | 月次リターンからDD期間算出 | OPT-H |
| `app/jobs/generators/monthly_returns.py` | 371 | `_generate_monthly_returns` | Signal→MonthlyReturn生成 | OPT-J |
| `app/jobs/generators/portfolio_metrics.py` | 118 | `_generate_portfolio_metrics` | メトリクス算出/UPSERT | OPT-H |
| `app/jobs/generators/risk_metrics.py` | 251 | `_generate_risk_management_metrics` | リスク指標算出 | - |
| `app/jobs/generators/rolling_returns.py` | 236 | `_generate_rolling_returns_summary`, `_generate_rolling_returns_chart` | rolling集計/チャート生成 | OPT-H |
| `app/jobs/generators/trade_performance.py` | 583 | `_generate_trade_performance` | trade期間収益/統計生成 | OPT-G, OPT-J |
| `app/jobs/kalman_wf.py` | 267 | `run_kalman_wf`, `main` | Kalman weight生成/保存 | - |
| `app/jobs/maintenance.py` | 407 | `run_backfill`, `run_maintenance_check`, `run_price_validation` | 保守系検証/補完 | - |
| `app/jobs/password_rotation.py` | 44 | `monthly_password_rotation` | viewer tier password更新 | - |
| `app/jobs/recalculate_fast.py` | 2079 | `recalculate_history_fast` | 全レイヤー再計算統括 | OPT-A, OPT-E, OPT-G, OPT-H, OPT-J |
| `app/jobs/recalculate_fof.py` | 931 | `_recalculate_fof_history` | FoF再計算コア | - |
| `app/jobs/recalculator.py` | 66 | `RecalculatorJob`, `run_recalculate_job` | 再計算起動ラッパ | - |
| `app/jobs/shared.py` | 271 | `get_batch_size`, `build_signal_cache_value`, `preload_fof_signals_recursive`, `get_pipeline_block_registry` | 共通キャッシュ/ヘルパ | OPT-J |
| `app/jobs/sync_layers.py` | 400 | `sync_prices`, `sync_tickers`, `sync_standard`, `sync_fof` | L1/L2/L3層別同期 | - |
| `app/jobs/ticker_returns.py` | 231 | `generate_ticker_monthly_returns`, `generate_ticker_daily_returns` | ticker return生成 | - |

### 2.2 `recalculate_fast.py`（2,079行）詳細フェーズ

- 主要エントリ: `recalculate_history_fast`
- フェーズ構成（コードコメント準拠）
  - Phase 0: 事前クリーンアップ（再構築前提）
  - Phase 1: 標準PF向け価格/経済データロード
  - Phase 1.5: シンボル最古日バッチ取得→PF有効開始日決定
  - Phase 2: 前処理（symbol分割、日次リターン、PriceCache、ベンチ累積Series）
  - Phase 3.5: pipeline block事前解決（OPT-A）
  - Phase 3.7: vectorized signal事前計算（OPT-E）
  - Phase 3: 状態初期化
  - Phase 4: 標準PF日次ループ（signal/holding生成、flush）
  - Phase 4.5: 標準PF MonthlyReturn生成
  - Phase 5: FoF再計算呼出し（`_recalculate_fof_history`）
  - 後段: Layer1/L2派生テーブル生成（ticker/monthly/trade/risk/rolling等）
- 最適化マーカー
  - OPT-A: block pre-resolve
  - OPT-E: vectorized pipeline signal
  - OPT-G: DTB3をPriceCache同梱（trade_perf再ロード削減）
  - OPT-H: MonthlyReturn cache再利用
  - OPT-J: benchmark cumulative seriesキャッシュ

### 2.3 `recalculate_fof.py`（931行）詳細フェーズ

- 主要エントリ: `_recalculate_fof_history`
- フェーズ構成（コードコメント準拠）
  - 準備: benchmark price preload、PipelineEngine生成
  - 087最適化: global `ComponentPriceCache` 一括ロード
  - 116最適化: component signal cache preload
  - 116最適化: shared `PriceCache`（MonthlyReturn生成共通化）
  - PFループ:
    - 有効開始日算出（全component signal共通期間）
    - pipeline config正規化/検証
    - Phase 4A最適化: 月初中心実行（非リバランス日は継続シグナル）
    - 日次signal/momentum_data/pipeline_log/rebalance_decision蓄積
    - flush（Signal/FoF logs/rebalance decisions）
    - 087 Phase 2: 旧drift calcループを削除（コメント上「SKIPPED」）
    - `_generate_monthly_returns` 呼出しとFoF-of-FoF向けcache再読込
  - 終了: profiling集計返却（daily_loop内訳、db_write内訳含む）
- 補足
  - `ENABLE_FOF_DEBUG_LOGS` 有効時のみFoFデバッグテーブルflush
  - `jobs/recalculate_fof.py` 自体に `OPT-*` 文字列は未付与（最適化は087/116/154番号で管理）

---

## §3 依存関係マップ（AC5）

### 3.1 主要依存フロー（api → services → jobs → db）

```text
API Layer
  main.py
   └─ include_router(api/*)

api/etl_trigger.py (admin orchestration)
  ├─ jobs.daily_etl.run_etl
  ├─ jobs.maintenance.{run_backfill, run_maintenance_check, run_price_validation}
  ├─ jobs.recalculate_fast.recalculate_history_fast
  ├─ jobs.sync_layers.{sync_prices,sync_tickers,sync_standard,sync_fof}
  └─ db.models.* / db.session.get_db_session

jobs.recalculate_fast.recalculate_history_fast
  ├─ services.pipeline.engine.PipelineEngine
  ├─ jobs.recalculate_fof._recalculate_fof_history
  ├─ jobs.generators.* (_generate_monthly_returns, trade_performance, rolling, risk, drawdown)
  ├─ jobs.flush.signal_flush._flush_batch
  └─ db.models (Price, Signal, MonthlyReturn, etc.)

jobs.recalculate_fof._recalculate_fof_history
  ├─ services.pipeline.engine.PipelineEngine
  ├─ services.component_price_cache.ComponentPriceCache
  ├─ services.price_ratio_calculator.PriceCache
  ├─ jobs.flush.{signal_flush,fof_flush}
  ├─ jobs.generators.monthly_returns._generate_monthly_returns
  └─ db.models (Signal, Portfolio, Price, MonthlyReturn)
```

### 3.2 循環依存検出

ASTベース静的解析結果（`backend/app` 全py）:

1. 循環群A（6モジュール）
   - `app.api.etl_trigger`
   - `app.jobs.daily_etl`
   - `app.jobs.recalculate_fast`
   - `app.jobs.recalculate_fof`
   - `app.jobs.recalculator`
   - `app.jobs.sync_layers`

   代表エッジ:
   - `api.etl_trigger -> jobs.recalculate_fast`
   - `recalculate_fast -> jobs.recalculate_fof`
   - `recalculate_fof -> api.etl_trigger`（`update_progress`の遅延import）
   - `sync_layers -> api.etl_trigger`（`update_progress/clear_progress`）

   判定: import cycleは存在。多くが関数内遅延importで実行時破綻を回避しているが、結合は強い。

2. 循環群B（2モジュール）
   - `app.schemas.models <-> app.schemas.pipeline`

   判定: スキーマ相互参照の構造サイクル。

### 3.3 外部ライブラリ主要依存（`backend/requirements.txt` + import実績）

- `fastapi`, `uvicorn`, `pydantic`: API/スキーマ基盤
- `sqlalchemy`, `psycopg2-binary`: DB ORM/接続
- `pandas`, `numpy`: リターン計算/集計/統計
- `httpx`, `tenacity`: 外部API通信/リトライ
- `slowapi`: レート制限
- `python-dateutil`: 日付処理補助
- `psutil`: メモリ計測（`recalculate_fast.log_memory_usage`）

---

## §4 AC6統合（kagemaru: AC2/AC4反映）

### 4.1 Services（AC2）統合サマリー

- 対象: `backend/app/services/` 全51ファイル、約13,031行
- 内訳:
  - top-level services: 23ファイル
  - `services/fof/`: 4ファイル（441行）
  - `services/kalman/`: 7ファイル（472行）
  - `services/pipeline/`: 2ファイル（529行）
  - `services/pipeline/blocks/`: 15ファイル（2,399行）
- コア大型ファイル:
  - `services/price_ratio_calculator.py` (1,767行): 価格比率計算・FoF展開・累積リターン基盤
  - `services/trades_calculator.py` (1,247行): トレード履歴/リスク管理計算
  - `services/metrics_calculator.py` (1,069行): 指標計算コア
  - `services/monthly_trade_calculator.py` (797行), `services/monthly_returns_calculator.py` (650行)
- パイプライン実装:
  - `pipeline/engine.py` が Selection chain + Terminal block 実行を統括
  - blocks配下は Selection 11種 + Terminal 3種（EqualWeight/Cash/KalmanMeta）
- FoF依存解決:
  - `services/fof/dependency.py` がトポロジカルソート・親子依存解決を提供

### 4.2 DB / Schemas / Core / Utils / Storage（AC4）統合サマリー

- `backend/app/db/`（6ファイル）
  - `db/models.py` は29テーブルを定義（signals/monthly_returns/trade_performance/rolling/risk/tier系等）
  - `db/migrations.py` は冪等マイグレーション（650行）
- `backend/app/schemas/`（4ファイル）
  - Pydanticモデル総数34（`models.py` + `pipeline.py` + `auth.py` + `response.py`）
- `backend/app/core/`
  - `core/rate_limiter.py`（slowapi Limiter定義）
- `backend/app/utils/`（17ファイル）
  - `utils/timing.py` (391行): LayerTimer/SubstepProfiler
  - `utils/cache.py` (233行): TTL cache + invalidation
  - `utils/fof_validation.py` (231行): FoF循環参照検出
  - `utils/recalc_status.py` (155行): 再計算排他状態管理
- `backend/app/storage/`（3ファイル）
  - `storage/repository.py` (333行): PortfolioRepository（load/save/delete）

### 4.3 統合判定

- AC6要件「影丸報告YAML参照の統合」は達成。
- 参照ソース: `queue/reports/kagemaru_report_cmd_478.yaml`（timestamp: 2026-03-01T23:58:00, status: done）。
