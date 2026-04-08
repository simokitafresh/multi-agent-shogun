# DM-Signal 基盤調査カタログ — tests/CI/config/.claude/その他

> cmd_481 | recon by tobisaru | 2026-03-01

---

## §1 テスト基盤カタログ

### Backend Tests (`backend/tests/`)

| 指標 | 値 |
|------|-----|
| テストファイル数 | 113 (うちintegration/ 3) |
| テストクラス数 | 312 |
| テスト関数数 (`def test_*`) | 128 (クラスメソッド除くトップレベル) |
| テスト定義合計 (class + def test_) | 440 |
| conftest.py | 2 (root + integration/) |

#### ファイル一覧 (113ファイル)

**integration/ (3ファイル)**

| ファイル | 対象モジュール |
|---------|--------------|
| test_cleanup_regression.py | レガシーimport/calculator/cumulative_ratio除去検証 |
| test_kalman_recalculate_fast.py | kalman_meta weights保存・月次リターン |
| test_return_calculations.py | Annual/PriceRatio/Benchmark/OpenClose/FoFリターン整合 |

**root tests/ (110ファイル)**

| ファイル | 対象モジュール |
|---------|--------------|
| test_055_pending_entry.py | pending entry作成・対称性・統合 |
| test_067_nested_fof_signal_decomposition.py | ネストFoFシグナル分解・重み合計 |
| test_090_fof_trade_component_signal_date.py | FoF trade component signal date |
| test_107_dtb3_cache.py | DTB3キャッシュ基本・計算・統合・SSOT |
| test_109_monthly_returns_component_signal_date.py | 月次リターン component signal date |
| test_127_fof_upward_recalculation.py | FoF上方再計算・逆依存マップ |
| test_137_fof_helpers.py | FoFヘルパー(参照FoF取得・コンポーネントID・ソフト削除) |
| test_138_pending_before_month_change.py | 月変わり前pending entry |
| test_176_dtb3_economic_indicator.py | DTB3経済指標モメンタム |
| test_admin_tiers.py | Admin tier・可視性 |
| test_annual_returns_058.py | 058: as_of/YTD/月次複利/precompute |
| test_annual_returns_calculator.py | 年次リターン計算(Open/EdgeCase) |
| test_api_estimation.py | API行数推定・バルクリクエスト検証 |
| test_api_masking.py | APIマスキング(viewer/admin/hidden PF) |
| test_api_response.py | ApiResponseラッパー |
| test_auth_cleanup.py | 認証クリーンアップ・トークン制限 |
| test_benchmark_pricecache_parity.py | ベンチマークPriceCache整合・キャッシュDTB3除外 |
| test_benchmark_repro.py | ベンチマークティッカー整合再現 |
| test_benchmark_unification_057.py | ベンチマーク統一・API検証・禁止シンボル |
| test_business_day_utils.py | 営業日ユーティリティ |
| test_cache.py | TTLキャッシュ・グローバルキャッシュ |
| test_check_mtd_script.py | MTDチェックスクリプト |
| test_client_mock.py | StockAPIクライアントモック |
| test_component_price_cache.py | コンポーネント価格キャッシュ(構築・参照・統合・性能・ネストFoF) |
| test_consistency_checks.py | 月次/年次/TradeSignal/FoF整合チェック |
| test_cumulative_price_ratio.py | 累積価格比率 |
| test_data_loader.py | データローダー(最早日付・共通開始日) |
| test_debug_segmented.py | デバッグセグメントリターン |
| test_determinism.py | 決定論的(ソート/FoF/DBクエリ/E2E) |
| test_drawdowns_nan.py | ドローダウンNaN処理・APIレスポンス |
| test_drift_calc_removal.py | ドリフト計算ループ除去 |
| test_drift_calculation.py | ドリフト計算(日次/月次/リバランス月) |
| test_error_handling.py | エラーハンドリング |
| test_etl_integration.py | ETL統合 |
| test_etl_trade_dates.py | ETL取引日 |
| test_expanded_tickers_inline.py | 展開ティッカーインライン(ラッパー除去後) |
| test_flush.py | Flush(JSON/バッチ/FoFパイプラインログ/コンポーネント重み/リバランス決定) |
| test_fof.py | FoF検証 |
| test_fof_circular_reference.py | FoF循環参照検出・深度制限 |
| test_fof_complete_unification.py | FoF完全統一・ティッカー展開・価格比率計算 |
| test_fof_component_weights.py | FoFコンポーネント重みモデル |
| test_fof_data_persistence.py | FoFデータ永続化・ResultEmptyバグ修正 |
| test_fof_individual_recalculate.py | FoF個別再計算(依存解決/エンドポイント/キャッシュ統合) |
| test_fof_kalman_meta.py | FoFカルマンメタ終端ブロック |
| test_fof_pipeline_logs.py | FoFパイプラインログモデル・ブロック結果 |
| test_fof_rebalance_decisions.py | FoFリバランス決定 |
| test_fof_rebalance_theory.py | リバランス月判定理論 |
| test_fof_requires_pipeline_config.py | FoF pipeline_config必須・レガシーパス除去 |
| test_fof_signal_unification.py | FoFシグナル統一(holding_signal更新判定) |
| test_fof_trades.py | FoFトレード |
| test_future_warning_fix.py | FutureWarning修正 |
| test_get_portfolio_all_tickers.py | PF全ティッカー取得 |
| test_global_visibility.py | グローバル可視性設定(モデル/API/スキーマ/マスキング) |
| test_grid_search_consistency.py | GS整合(取引日/加重リターン/リバランス月) |
| test_holding_signal.py | holdingシグナルロジック・シナリオ・エッジケース |
| test_jobs_constants.py | ジョブ定数(FoFバッチサイズ) |
| test_kalman_meta_block.py | カルマンメタブロック |
| test_layer_timing_integration.py | レイヤータイミング統合 |
| test_masking_service.py | マスキングサービス(config/should_mask/mask_value/trades/PF return/完全/統合) |
| test_meta_fof_blocks.py | メタFoFブロック(MultiView/TrendReversal/統合) |
| test_momentum_acceleration_filter.py | モメンタム加速フィルタ(ratio/diff/ゼロ分母) |
| test_momentum_cache.py | モメンタムキャッシュ(ヘルパー/構築/参照/精度/DTB3/性能/系列取得) |
| test_monthly_benchmark_single_source.py | 月次ベンチマーク単一ソース |
| test_monthly_common.py | 月次共通(年月/MTD/partial/取引日/pending) |
| test_monthly_price_consistency.py | 月次価格整合 |
| test_monthly_returns_056_fields.py | 056: 月次リターンフィールド・pending entry |
| test_monthly_returns_exception.py | 月次リターン例外 |
| test_monthly_returns_mtd.py | 月次リターンMTD |
| test_monthly_returns_open_fallback.py | 月次リターンOpenフォールバック |
| test_monthly_returns_start_partial.py | 月次リターン開始partial |
| test_monthly_trade_calculator.py | 月次トレード計算 |
| test_multi_view_momentum_filter.py | 複数視点モメンタムフィルタ |
| test_nested_fof_signal.py | ネストFoFシグナル |
| test_optj_benchmark_ticker.py | OPT-Jベンチマークティッカー |
| test_password_expiry.py | パスワード有効期限 |
| test_performance_all_period.py | パフォーマンス全期間 |
| test_performance_cumulative.py | パフォーマンス累積 |
| test_performance_minimization_calc.py | パフォーマンス最小化計算 |
| test_performance_minimization_loader.py | パフォーマンス最小化ローダー |
| test_performance_price_ratio.py | パフォーマンス価格比率 |
| test_pipeline_cache_optimization.py | パイプラインキャッシュ最適化 |
| test_pipeline_engine.py | パイプラインエンジン |
| test_pipeline_precomputed_cache.py | パイプライン事前計算キャッシュ |
| test_portfolio_sort_order.py | PFソート順 |
| test_price_cache.py | 価格キャッシュ |
| test_price_ratio_calculator.py | 価格比率計算 |
| test_price_ratio_theory.py | 価格比率理論 |
| test_rebalance.py | リバランス |
| test_recalculate_modes.py | 再計算モード |
| test_recalculate_status.py | 再計算ステータス |
| test_resolve_holding_nested_fof.py | holding解決ネストFoF |
| test_return_calculator.py | リターン計算 |
| test_reversal_filter.py | リバーサルフィルタ |
| test_right_tail_metrics.py | 右テールメトリクス |
| test_security_headers.py | セキュリティヘッダー |
| test_security_static_files.py | セキュリティ静的ファイル |
| test_services.py | サービス |
| test_signal_fix_date.py | シグナル日付修正 |
| test_symbol_masking.py | シンボルマスキング |
| test_sync_layers.py | 同期レイヤー |
| test_sync_layers_timing.py | 同期レイヤータイミング |
| test_ticker_daily_returns.py | ティッカー日次リターン |
| test_tier_auth.py | Tier認証 |
| test_tier_masking.py | Tierマスキング |
| test_timezone_expiry.py | タイムゾーン有効期限 |
| test_timing.py | タイミング |
| test_timing_db.py | タイミングDB |
| test_trade_perf_vectorized.py | トレードパフォーマンスベクトル化 |
| test_trade_performance_open.py | トレードパフォーマンスOpen |
| test_trade_period_return.py | トレード期間リターン |
| test_trade_risk_unification.py | トレードリスク統一 |
| test_trade_start_date_fix.py | トレード開始日修正 |
| test_trades_ticker_masking.py | トレードティッカーマスキング |
| test_trend_reversal_filter.py | トレンドリバーサルフィルタ |
| test_true_cagr_metrics.py | 真CAGRメトリクス |
| test_utc_datetime_type.py | UTC日時型 |
| test_vectorized_momentum.py | ベクトル化モメンタム |
| test_vectorized_momentum_use_calendar.py | ベクトル化モメンタムカレンダー使用 |
| test_verification_tables.py | 検証テーブル |
| test_viewer_auth.py | Viewer認証 |
| test_visibility_masking.py | 可視性マスキング |

#### カバレッジ概算

| バックエンドモジュール | テストあり | テストなし |
|----------------------|-----------|-----------|
| **services/ (29モジュール)** | | |
| return_calculator.py | ✅ test_return_calculator | |
| momentum_cache.py | ✅ test_momentum_cache | |
| vectorized_momentum.py | ✅ test_vectorized_momentum + _use_calendar | |
| price_ratio_calculator.py | ✅ test_price_ratio_calculator + _theory | |
| masking_service.py | ✅ test_masking_service | |
| pipeline/engine.py | ✅ test_pipeline_engine + _cache + _precomputed | |
| pipeline/blocks/* (14ブロック) | ✅ 主要ブロックはテスト済 | |
| component_price_cache.py | ✅ test_component_price_cache | |
| monthly_common.py | ✅ test_monthly_common | |
| monthly_returns_calculator.py | ✅ test_monthly_returns_* (6ファイル) | |
| monthly_trade_calculator.py | ✅ test_monthly_trade_calculator | |
| annual_returns_calculator.py | ✅ test_annual_returns_calculator + _058 | |
| consistency_checks.py | ✅ test_consistency_checks | |
| rebalance.py | ✅ test_rebalance | |
| signal.py | ✅ test_signal_fix_date + holding_signal | |
| symbol_masking.py | ✅ test_symbol_masking | |
| page_visibility.py | ✅ test_global_visibility | |
| drawdowns_calculator.py | ✅ test_drawdowns_nan | |
| fof/ (サブパッケージ) | ✅ test_fof_* (14ファイル) | |
| verification_service.py | ✅ test_verification_tables | |
| metrics_calculator.py | | ❌ 直接テストなし |
| rolling_returns_calculator.py | | ❌ 直接テストなし |
| trades_calculator.py | | ❌ 直接テストなし |
| render_env.py | | ❌ 直接テストなし |
| up_down_market_analyzer.py | | ❌ 直接テストなし |
| visibility_helpers.py | | ❌ 直接テストなし |
| monthly_product_momentum.py | | ❌ 直接テストなし |
| scm/ (サブパッケージ) | | ❌ テストなし |
| kalman/ (サブパッケージ) | ✅ test_kalman_meta_block + integration | |
| **api/ (22ルーター)** | | |
| signals.py | ✅ test_api_masking | |
| portfolios.py | ✅ test_portfolio_sort_order | |
| etl_trigger.py | ✅ test_etl_integration + _trade_dates + sync_layers | |
| auth.py | ✅ test_auth_cleanup + tier_auth + viewer_auth | |
| monthly_returns.py | ✅ 間接テスト(monthly_returns_*) | |
| annual_returns.py | ✅ test_annual_returns_058 | |
| その他(15ルーター) | | ❌ 直接テストが薄い |
| **jobs/ (12モジュール)** | | |
| recalculate_fast.py | ✅ test_recalculate_modes + _status | |
| recalculate_fof.py | ✅ test_fof_individual_recalculate + determinism | |
| flush/ | ✅ test_flush | |
| sync_layers.py | ✅ test_sync_layers + _timing | |
| shared.py | ✅ test_jobs_constants | |
| data_fetcher.py | ✅ test_data_loader | |
| password_rotation.py | ✅ test_password_expiry | |
| その他(5モジュール) | | ❌ 直接テストなし |
| **db/ (6モジュール)** | | |
| models.py | ✅ 間接テスト(多数) | |
| その他 | | ❌ 直接テストなし |

**概算カバレッジ**: テストありモジュール約70%、テストなし約30%。servicesとpipelineの主要計算ロジックはほぼカバー。API・jobsの一部とユーティリティ系が手薄。

### Frontend Tests (`frontend/`)

| 指標 | 値 |
|------|-----|
| テストファイル数 | 29 (node_modules除外) |
| テスト定義行数 (describe/it/test) | 約331 |
| テストフレームワーク | Jest 30 + @testing-library/react 16 + ts-jest |

#### ファイル一覧 (29ファイル)

| パス | 対象 |
|------|------|
| **app/__tests__/ (2)** | |
| page-masking.test.tsx | ページレベルマスキング |
| page_masking.test.tsx | ページマスキング(命名重複注意) |
| **app/admin/components/__tests__/ (3)** | |
| AdvancedOperations.test.tsx | 管理者高度操作 |
| LoginModal.test.tsx | ログインモーダル |
| LookbackEditor.test.tsx | ルックバック編集 |
| **app/admin/fof/__tests__/ (1)** | |
| fof_copy_reorder.test.tsx | FoFコピー・並替 |
| **app/admin/fof/components/__tests__/ (3)** | |
| FoFEditor.test.tsx | FoFエディター |
| SelectionPipelineSection.test.tsx | 選択パイプラインセクション |
| TerminalBlockSection.test.tsx | ターミナルブロックセクション |
| **app/admin/visibility/__tests__/ (1)** | |
| visibility-page.test.tsx | 可視性ページ |
| **app/admin/visibility/components/__tests__/ (1)** | |
| ManageTiersModal.test.tsx | Tier管理モーダル |
| **components/__tests__/ (10)** | |
| annual_returns_masking.test.tsx | 年次リターンマスキング |
| annual_returns_open_toggle.test.tsx | 年次リターンOpen切替 |
| auth-status.test.tsx | 認証ステータス |
| chart-props.test.ts | チャートプロパティ |
| monthly_returns_056.test.tsx | 月次リターン056 |
| monthly_returns_masking.test.tsx | 月次リターンマスキング |
| monthly_returns_open_toggle.test.tsx | 月次リターンOpen切替 |
| period-notes.test.tsx | 期間ノート |
| summary-table-true-cagr.test.tsx | サマリーテーブル真CAGR |
| viewer-auth-modal.test.tsx | Viewer認証モーダル |
| **hooks/__tests__/ (1)** | |
| movePortfolio.test.ts | PF移動フック |
| **lib/__tests__/ (7)** | |
| admin-auth.test.ts | 管理者認証 |
| api-client-auth.test.ts | APIクライアント認証 |
| api-client-password.test.ts | APIクライアントパスワード |
| chart-utils.test.ts | チャートユーティリティ |
| constants.test.ts | 定数 |
| lookbackFormatter.test.ts | ルックバックフォーマッター |
| viewer-auth.test.ts | Viewer認証 |

---

## §2 設定ファイルカタログ

### トップレベル全件

| ファイル | サイズ | 説明 |
|---------|-------|------|
| `render.yaml` | 4.5KB | Render.comサービス構成(backend web/frontend static/cron 5本/password rotation/DB) |
| `.gitignore` | 2.1KB | Python/Node/IDE/OS/data/debug/GS出力の除外パターン |
| `.env` | 142B | DATABASE_URL(本番PostgreSQL接続文字列) |
| `docker-compose.local.yml` | 695B | ローカルPostgreSQL(port:5433, postgres:18) |
| `CLAUDE.md` | 116行 | Claude Codeセッションガイド |

### Backend

| ファイル | 説明 |
|---------|------|
| `backend/requirements.txt` | Python依存(12パッケージ): fastapi 0.110, uvicorn 0.29, pydantic 2.6.4, httpx 0.27, tenacity 8.2.3, python-dateutil 2.9, sqlalchemy 2.0.28, pandas 2.2.1, numpy 1.26.4, slowapi 0.1.9, psycopg2-binary 2.9.9, psutil≥5.9 |

### Frontend

| ファイル | 説明 |
|---------|------|
| `frontend/package.json` | Next.js 14.2.3 + React 18.3 + recharts 3.5 + tailwind-merge + katex + lucide-react。テスト: Jest 30 + testing-library/react 16 + ts-jest |
| `frontend/tsconfig.json` | strict:true, module:esnext, bundler解決, @/パスエイリアス |
| `frontend/next.config.mjs` | output:'export'(SSG), trailingSlash:true, images:unoptimized |

### render.yaml構成詳細

| サービス | タイプ | 実行内容 |
|---------|--------|---------|
| dm-signal-backend | web (python/pro) | FastAPI + uvicorn, singapore, healthCheck:/healthz |
| dm-signal-frontend | static | Next.js SSG, 12ルートrewrite(compare/admin/metrics等) |
| dm-signal-sync-prices | cron 01:00UTC | POST /admin/sync-prices |
| dm-signal-sync-tickers | cron 01:05UTC | POST /admin/sync-tickers |
| dm-signal-sync-standard | cron 01:10UTC | POST /admin/sync-standard |
| dm-signal-sync-fof | cron 01:40UTC | POST /admin/sync-fof |
| dm-signal-password-rotation | cron 月1日16:00UTC | password_rotation.py |
| dm-signal-db | PostgreSQL basic-1gb | singapore, dm_signal_user |

---

## §3 .claude/ カタログ

### 設定ファイル

| ファイル | 内容 |
|---------|------|
| `settings.json` | 0バイト(空) |
| `settings.local.json` | パーミッション設定: allow 60+パターン(python/git/npm/docker/psql等), deny 5パターン(sudo/git push/rm -rf), additionalDirectories 3パス |
| `_INDEX.md` | 設定・スキル一覧の目次 |

### Skills一覧 (24スキル)

各スキルフォルダにSKILL.md + skill.md(小文字複製)の2ファイルが存在。

| カテゴリ | スキル名 | 1行要約 |
|---------|---------|---------|
| **忍者システム系 (7)** | | |
| | ninja-council | 下忍合議+仙人助言で設計判断 |
| | ninja-task-force | 下忍3名並列コード調査 |
| | ninja-build-force | 下忍並列実装オーケストレーション |
| | ninja-daily-report | 忍者スタイル日報作成 |
| | ninja-monthly-report | 忍者スタイル月報作成 |
| | ninja-doc-review | 忍者合議ドキュメントレビュー |
| | jounin-advisor | 上忍視点の優先任務提言 |
| **ドキュメント・管理系 (5)** | | |
| | create-yaml-toc | VercelスタイルYAML目次追加 |
| | manage-index-md | _INDEX.md作成・更新 |
| | document-naming-convention | ドキュメント命名規則 |
| | documentation-guide | ドキュメント作成ガイド |
| | skills-creation-guide | 新スキル作成ガイド |
| **戦略・FoF系 (6)** | | |
| | create-ninpou-fof | 忍法FoF作成→本番登録→検証ランブック |
| | fof-calculation | FoF計算不一致調査 |
| | fof-pipeline-troubleshooting | FoFパイプラインデバッグ |
| | building-block-pattern | パイプライン設計パターン参照 |
| | building-block-addition | Building Block追加手順 |
| | download-prod-pf | 本番PF設定CSVダウンロード |
| **インフラ・品質系 (6)** | | |
| | api-testing | APIエンドポイント動作確認 |
| | code-review | コードレビュー(品質/セキュリティ/一貫性) |
| | data-validation | DBとAPIの整合性チェック |
| | performance-analysis | HAR分析・パフォーマンス計測 |
| | password-expiry-management | パスワード有効期限管理 |
| | tier-visibility-control | Tier別可視性制御 |

### docs/skills/ との整合性チェック

| .claude/skills/ にあり → docs/skills/ | 状態 |
|---------------------------------------|------|
| building-block-addition → building-block-addition-guide.md | ✅ 名称微差(末尾-guide)だが対応あり |
| building-block-pattern → building-block-pattern.md | ✅ |
| document-naming-convention → document-naming-convention.md | ✅ |
| fof-pipeline-troubleshooting → fof-pipeline-troubleshooting.md | ✅ |
| password-expiry-management → password-expiry-management.md | ✅ |
| skills-creation-guide → skills-creation-guide.md | ✅ |
| tier-visibility-control → tier-visibility-control.md | ✅ |
| api-testing | ❌ docs/skills/にapi-testing.mdなし(api-reference.mdは別物) |
| code-review | ❌ docs/skills/に対応なし |
| create-ninpou-fof | ❌ docs/skills/に対応なし |
| create-yaml-toc | ❌ docs/skills/に対応なし |
| data-validation | ❌ docs/skills/に対応なし |
| documentation-guide | ❌ docs/skills/に対応なし |
| download-prod-pf | ❌ docs/skills/に対応なし |
| fof-calculation | ❌ docs/skills/に対応なし |
| jounin-advisor | ❌ docs/skills/に対応なし |
| manage-index-md | ❌ docs/skills/に対応なし |
| ninja-build-force | ❌ docs/skills/に対応なし |
| ninja-council | ❌ docs/skills/に対応なし |
| ninja-daily-report | ❌ docs/skills/に対応なし |
| ninja-doc-review | ❌ docs/skills/に対応なし |
| ninja-monthly-report | ❌ docs/skills/に対応なし |
| ninja-task-force | ❌ docs/skills/に対応なし |
| performance-analysis | ❌ docs/skills/にperformance-audit/measurementはあるが直接対応なし |

| docs/skills/ にあり → .claude/skills/ なし |
|--------------------------------------------|
| Agent Skills.md (エージェントスキル全般) |
| api-reference.md (本番API+認証) |
| best-practices.md (ベストプラクティス) |
| database-schema.md (DBスキーマ) |
| environment-switching.md (環境切替) |
| knowledge-01〜06.md (知識ベース) |
| passive-context-index-standard.md (パッシブコンテキスト) |
| performance-audit.md (パフォーマンス監査) |
| performance-measurement.md (パフォーマンス計測) |
| portfolio-analysis-idea-loop.md (PF分析アイデアループ) |
| portfolio-analysis-verification.md (PF分析検証) |
| structural-suspect-ban.md (構造的容疑禁止) |

**まとめ**: .claude/skills/24スキル中7スキルがdocs/skills/に対応あり、17スキルは.claude/skills/のSKILL.mdのみ。docs/skills/側は知識ベース・参照ドキュメント系が中心で.claude/skills/とは役割が異なる（実行可能スキル vs 参照文書）。

---

## §4 その他ディレクトリカタログ

### analysis_runs/

| 内容 | 説明 |
|------|------|
| `experiments.db` | 13.6MB SQLiteデータベース。daily_prices(86銘柄OHLCV)+monthly_returns(バックテスト月次リターン)。価格データのground truth(ローカル分析用) |
| `prod_pg.dump` | 24MB PostgreSQL本番ダンプ |
| `_INDEX.md` | 8.7KB 目次 |
| `_uuid_comparison.txt` | 2KB UUID比較 |
| `docs/` | 10ファイル(CPCV検証/FoF報告/パイプライン/GS分析ルール等) |
| `idea-loop/` | 9ファイル(機能提案/PF構造マップ/理論結果/バックアップJSON) |
| `results/` | 複数(DM2/DM6等の拡張分析結果md/ベンチマーク/FoF/パイプラインタイミング/archive) |
| `snapshots/` | parquet 6ファイル(before/after月次リターン・PFメトリクス・トレードパフォーマンス) + CSV 3ファイル(本番月次リターン) + PFリスト |

**experiments.dbテーブル**: sqlite3未インストールのため.tablesコマンド実行不可。projects/dm-signal.yamlの定義では `daily_prices` と `monthly_returns` の2テーブル。

### outputs/

| サブディレクトリ | 内容 |
|----------------|------|
| `grid_search/` | GS結果CSV 12ファイル(4忍法×results+monthly+meta.yaml) + DATA_CATALOG.md + yotsume/(四つ目GS meta) |
| `scripts/` | cmd_284/ (コマンド関連スクリプト出力) |
| `trend_scan/` | トレンドスキャンCSV 4ファイル + dynamic_sizing結果 |
| `charts/` | 存在(PNG/CSV出力先、.gitignore対象) |
| `data/` | 存在(cmd別データ、.gitignore対象) |

**GS CSVサイズ**: kasoku_monthly 541MB / nukimi_monthly 403MB / oikaze_monthly 109MB / kawarimi_monthly 76MB (合計約1.2GB、.gitignore対象)

### marketing-director/

| 内容 | 説明 |
|------|------|
| 目的 | マーケティング・コンテンツ管理。note.com記事生成、メンバー管理、タイムライン記録 |
| `SKILL.md` | 21.6KB マーケティングディレクタースキル定義 |
| `marketing-agent.md` | 14.2KB マーケティングエージェント定義 |
| `marketing-info.md` | 31.2KB マーケティング情報 |
| `x_article_rules.md` | 8.7KB X(Twitter)記事ルール |
| `20251231_メンバー一覧.csv` | 26.8KB メンバー一覧CSV |
| `2026-timeline-diary.md` | 35.5KB 2026年タイムライン日記 |
| `_INDEX.md` | 3.6KB 目次 |
| `index.md` | 2.7KB メインインデックス |
| `content/` | 記事コンテンツ |
| `launch/` | ローンチ関連 |
| `legal/` | 法的文書 |
| `logs/` | ログ(日報・月報出力先) |
| `product/` | プロダクト情報 |
| `research/` | マーケティングリサーチ |
| `strategy/` | 戦略文書 |
| `templates/` | テンプレート |

### performance/

| 内容 | 説明 |
|------|------|
| 目的 | パフォーマンス計測・履歴管理 |
| `_INDEX.md` | 1.2KB 目次 |
| `report_template.md` | 1.3KB レポートテンプレート |
| `history/` | metrics_history.json (メトリクス履歴) |
| `reports/` | 空(レポート出力先) |

### tasks/

| ファイル | サイズ | 説明 |
|---------|-------|------|
| `_INDEX.md` | 907B | 目次 |
| `decisions.md` | 531B | ADR(Architecture Decision Records)。D001: MomentumCache廃止・per-ticker統一(cmd_083) |
| `lessons.md` | 1,330行 | 教訓集。ロックファイル付き(lessons.md.lock) |
| `todo.md` | 1.8KB | ToDoリスト。ドキュメント更新+FoFパリティ検証Phase1-5 |
| `decisions.md.lock` | 0B | ロックファイル |
| `lessons.md.lock` | 0B | ロックファイル |

---

## §5 補足

### CI/CD

- **CI**: 専用CI設定ファイル(`.github/workflows/`等)は確認されず。テストはローカル実行(`pytest` / `npm test`)
- **CD**: Render.com自動デプロイ(git push → render.yaml定義に基づくビルド・デプロイ)
- **Cron**: Render.com Cron Jobs 5本(価格/ティッカー/Standard/FoF同期 + パスワードローテーション)

### テストランナー設定

- Backend: pytest(conftest.py 2ファイルでフィクスチャ定義)
- Frontend: Jest 30 + ts-jest + @testing-library/react + jest-environment-jsdom

### プロジェクト構成サマリー

```
DM-signal/
├── backend/           # FastAPI + SQLAlchemy + pandas
│   ├── app/
│   │   ├── api/       # 22ルーター, 84-88エンドポイント
│   │   ├── services/  # 29モジュール + pipeline/ + fof/ + kalman/
│   │   ├── jobs/      # 12モジュール + flush/ + etl/ + generators/
│   │   ├── db/        # 6モジュール (SQLAlchemy models)
│   │   └── schemas/   # Pydanticスキーマ
│   └── tests/         # 113ファイル, 440テスト定義
├── frontend/          # Next.js 14 SSG + React 18 + Tailwind
│   ├── app/           # ページ(12ルート)
│   ├── components/    # UIコンポーネント
│   ├── lib/           # api-client, utils, types
│   ├── hooks/         # Reactフック
│   └── __tests__/     # 29ファイル, 約331テスト定義
├── .claude/           # AIエージェント設定(24スキル)
├── analysis_runs/     # experiments.db + ダンプ + 分析結果
├── outputs/           # GS結果CSV(1.2GB) + チャート + スクリプト出力
├── marketing-director/# マーケティング・コンテンツ管理
├── performance/       # パフォーマンス計測・履歴
├── tasks/             # ADR + 教訓集 + ToDo
├── render.yaml        # Render.comサービス構成(7サービス + DB)
├── docker-compose.local.yml  # ローカルPostgreSQL
└── .env               # 本番DATABASE_URL
```
