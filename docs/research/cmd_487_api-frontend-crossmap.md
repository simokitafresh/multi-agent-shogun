# DM-Signal API↔Frontend 横断マップ (cmd_487)

> 作成: kagemaru (subtask_487_recon_a)
> 入力: `docs/research/cmd_478_dm-signal-backend-catalog.md`, `docs/research/cmd_479_dm-signal-frontend-catalog.md`
> 作成日: 2026-03-02

---

## AC1: APIエンドポイント → Frontend使用箇所マップ

凡例: FE Method = api-client.tsのメソッド名 | Pages = 呼び出すページURL | Auth = 認証要件

### Viewer/Public エンドポイント

| # | Endpoint | Backend File | FE Method | Pages | Response型(FE) |
|---|----------|-------------|-----------|-------|---------------|
| 1 | `GET /api/signals` | signals.py:67 | `getSignalsLight` | `/`(Signal), `/dashboard`, `/compare`, `/compare-summary`, `/summary`, `/metrics`, `/annual-returns`, `/monthly-returns`, `/rolling-returns`, `/trades`, `/monthly-trade`, `/drawdowns` (※SignalsContext経由で全Viewerページ) | `SignalsLightResponse` |
| 2 | `GET /api/history/{id}` | history.py | `getHistory` | `/`(Signal), `/dashboard` | `HistoryResponse` |
| 3 | `GET /api/performance/{id}` | performance.py | `getPerformance` | `/`(Signal), `/dashboard`, `/compare` | `PerformanceResponse` |
| 4 | `GET /api/mtd/{id}` | performance.py | `getMtd` | `/dashboard` | `MtdResponse` |
| 5 | `GET /api/benchmark/{ticker}` | benchmark.py | `getBenchmarkPerformance` | `/`(Signal), `/dashboard`, `/compare` | `PerformanceResponse` |
| 6 | `GET /api/metrics/{id}` | metrics.py | `getMetrics` | `/summary`, `/metrics` | `MetricsResponse` |
| 7 | `GET /api/metrics/summary` | metrics.py | `getMetricsSummary` | `/compare-summary` | `MetricsSummaryResponse` |
| 8 | `GET /api/metrics/{id}/up-down-market` | metrics.py | `getUpDownMarketAnalysis` | `/metrics` | (inline) |
| 9 | `GET /api/annual-returns/{id}` | annual_returns.py | `getAnnualReturns` | `/annual-returns` | `AnnualReturnsResponse` |
| 10 | `GET /api/monthly-returns/{id}` | monthly_returns.py | `getMonthlyReturns` | `/monthly-returns` | `MonthlyReturnsResponse` |
| 11 | `GET /api/rolling-returns/{id}` | rolling_returns.py | `getRollingReturns` | `/rolling-returns` | `RollingReturnsResponse` |
| 12 | `GET /api/trades/{id}` | trades.py | `getTrades` | `/trades` | `TradesResponse` |
| 13 | `GET /api/monthly-trade/{id}` | monthly_trade.py | `getMonthlyTrade` | `/monthly-trade` | `MonthlyTradeResponse` |
| 14 | `GET /api/drawdowns/{id}` | drawdowns.py | `getDrawdowns` | `/drawdowns` | `DrawdownsResponse` |
| 15 | `GET /api/viewer-permissions` | viewer_permissions.py | `getViewerPermissions` | `/dashboard`, `/compare-summary`, `/summary` (ViewerPermissionsContext経由) | `ViewerPermissionsResponse` |

### Auth エンドポイント

| # | Endpoint | Backend File | FE Method | Pages | Response型(FE) |
|---|----------|-------------|-----------|-------|---------------|
| 16 | `POST /api/auth/verify-viewer` | auth.py | `verifyViewer` | ViewerAuthModal (layout.tsx経由で全ページ) | - |
| 17 | `POST /api/admin/login` | auth.py | `adminLogin` | `/admin`, `/admin/fof`, `/admin/folders`, `/admin/visibility` (LoginModal経由) | - |
| 18 | `POST /api/auth/logout` | auth.py | `logout` | (AuthStatus経由) | - |

### Admin PF管理エンドポイント

| # | Endpoint | Backend File | FE Method | Pages | Response型(FE) |
|---|----------|-------------|-----------|-------|---------------|
| 19 | `GET /api/portfolios/get` | portfolios.py:147 | `getPortfolios` | `/admin`, `/admin/fof`, `/admin/folders`, `/admin/visibility` (AdminAuthContext経由) | `PortfoliosPayload` |
| 20 | `POST /api/portfolios/save` | portfolios.py:215 | `savePortfolios` | `/admin`, `/admin/fof` | `SavePortfoliosResponse` |
| 21 | `DELETE /api/portfolios/{id}` | portfolios.py | `deletePortfolio` | `/admin`, `/admin/fof` | - |

### Admin 再計算・同期エンドポイント

| # | Endpoint | Backend File | FE Method | Pages | Response型(FE) |
|---|----------|-------------|-----------|-------|---------------|
| 22 | `POST /admin/recalculate-sync` | etl_trigger.py:235 | `recalculateHistory` | `/admin`, `/admin/fof` | - |
| 23 | `GET /admin/recalculate-status` | etl_trigger.py | `getRecalculateStatus` | `/admin` (RecalculateStatus) | - |
| 24 | `POST /admin/sync-prices` | etl_trigger.py | `syncPrices` | `/admin` | - |
| 25 | `POST /admin/sync-tickers` | etl_trigger.py | `syncTickers` | `/admin` | - |
| 26 | `POST /admin/sync-standard` | etl_trigger.py | `syncStandard` | `/admin` | - |
| 27 | `POST /admin/sync-fof` | etl_trigger.py | `syncFof` | `/admin` | - |
| 28 | `GET /admin/sync-status` | etl_trigger.py | `getSyncStatus` | `/admin` (RecalculateStatus) | - |
| 29 | `GET /admin/db-status` | db_admin.py | `getDbStatus` | `/admin` | - |
| 30 | `POST /admin/long-term-backfill` | backfill.py | `triggerFullBackfill` | `/admin` | - |
| 31 | `GET /admin/backfill-status` | backfill.py | `getBackfillStatus` | `/admin` | - |

### Admin フォルダ管理エンドポイント

| # | Endpoint | Backend File | FE Method | Pages | Response型(FE) |
|---|----------|-------------|-----------|-------|---------------|
| 32 | `GET /api/admin/folders` | folders.py | `getFolders` | `/admin/folders` | - |
| 33 | `POST /api/admin/folders` | folders.py | `createFolder` | `/admin/folders` | - |
| 34 | `PATCH /api/admin/folders/{id}` | folders.py | `updateFolder` | `/admin/folders` | - |
| 35 | `DELETE /api/admin/folders/{id}` | folders.py | `deleteFolder` | `/admin/folders` | - |
| 36 | `PUT /api/admin/folders/reorder` | folders.py | `reorderFolders` | `/admin/folders` | - |
| 37 | `POST /api/admin/folders/portfolios/{id}/move` | folders.py | `movePortfolioToFolder` | `/admin/folders` | - |

### Admin Tier管理エンドポイント

| # | Endpoint | Backend File | FE Method | Pages | Response型(FE) |
|---|----------|-------------|-----------|-------|---------------|
| 38 | `GET /api/admin/tiers` | viewer_tiers.py | `getTiers` | `/admin/visibility` | - |
| 39 | `POST /api/admin/tiers` | viewer_tiers.py | `createTier` | `/admin/visibility` | - |
| 40 | `PUT /api/admin/tiers/{id}` | viewer_tiers.py | `updateTier` | `/admin/visibility` | - |
| 41 | `DELETE /api/admin/tiers/{id}` | viewer_tiers.py | `deleteTier` | `/admin/visibility` | - |
| 42 | `POST /api/admin/tiers/{id}/copy` | viewer_tiers.py | `copyTier` | `/admin/visibility` | - |
| 43 | `PUT /api/admin/tiers/reorder` | viewer_tiers.py | `reorderTiers` | `/admin/visibility` | - |
| 44 | `GET /api/admin/tiers/{id}/visibility` | viewer_tiers.py | `getTierVisibility` | `/admin/visibility` | - |
| 45 | `PUT /api/admin/tiers/{id}/visibility` | viewer_tiers.py | `updateTierVisibility` | `/admin/visibility` | - |
| 46 | `GET /api/admin/tiers/visibility/global` | viewer_tiers.py | `getGlobalVisibility` | `/admin/visibility` | - |
| 47 | `PUT /api/admin/tiers/visibility/global` | viewer_tiers.py | `updateGlobalVisibility` | `/admin/visibility` | - |
| 48 | `POST /api/admin/tiers/{id}/rotate` | viewer_tiers.py | `rotateTierPassword` | `/admin/visibility` | - |
| 49 | `GET /api/admin/tiers/passwords` | viewer_tiers.py | `getAllTierPasswords` | `/admin/visibility` | - |
| 50 | `POST /api/admin/tiers/rotate-all` | viewer_tiers.py | `rotateAllTierPasswords` | `/admin/visibility` | - |
| 51 | `POST /api/admin/viewer-permissions` | viewer_permissions.py | `updateViewerPermissions` | `/admin/visibility` | - |

### Frontend未使用エンドポイント (Backend Only)

| # | Endpoint | Backend File | 用途 | 未使用理由 |
|---|----------|-------------|------|-----------|
| U1 | `POST /api/portfolios/save-legacy` | portfolios.py | PF保存(旧互換) | 新save APIに移行済み |
| U2 | `POST /admin/run-etl` | etl_trigger.py | ETL起動 | api-client.tsに`runEtl`定義あるがFEページから呼ばれない |
| U3 | `POST /admin/run-kalman-wf` | etl_trigger.py | Kalman workflow | FEから呼び出しなし |
| U4 | `GET /admin/etl-status` | etl_trigger.py | ETL状態 | FEから呼び出しなし |
| U5 | `POST /admin/cancel-recalculate` | etl_trigger.py | 再計算キャンセル | FEから呼び出しなし |
| U6 | `POST /admin/run-backfill` | etl_trigger.py | バックフィル(旧) | 新long-term-backfillに移行 |
| U7 | `POST /admin/run-maintenance` | etl_trigger.py | メンテナンス | FEから呼び出しなし |
| U8 | `POST /admin/validate-prices` | etl_trigger.py | 価格検証 | FEから呼び出しなし |
| U9 | `POST /admin/run-password-rotation` | etl_trigger.py | パスワードローテーション | 個別rotate APIに代替 |
| U10 | `POST /admin/validate-and-recalculate` | etl_trigger.py | 検証+再計算 | FEから呼び出しなし |
| U11 | `GET /admin/timing-history` | etl_trigger.py | 計測履歴 | FEから呼び出しなし |
| U12 | `GET /admin/price-tickers` | etl_trigger.py | 価格銘柄一覧 | FEから呼び出しなし |
| U13 | `DELETE /admin/cleanup-prices` | etl_trigger.py | 価格クリーンアップ | FEから呼び出しなし |
| U14 | `POST /admin/run-migration` | db_admin.py | DBマイグレーション | FEから呼び出しなし |
| U15 | `DELETE /admin/cleanup-fof-signals` | db_admin.py | FoFシグナルクリーンアップ | FEから呼び出しなし |
| U16 | `GET /api/kalman/weights` | kalman.py | Kalman weight | FEから呼び出しなし |
| U17 | `GET /api/admin/folders/tree` | folders.py | フォルダツリー | FEから呼び出しなし |
| U18 | `GET /api/debug/*` (17個) | debug.py | デバッグ系全般 | DEBUG_API_ENABLED時のみ。FE未接続 |
| U19 | `GET /healthz`, `GET /healthz/deep` | main.py | ヘルスチェック | Render.com/監視用。FE未接続 |

**集計**: Backend全エンドポイント 84-88個 → FE接続 51個 + FE未使用 19カテゴリ(debug 17個含むと35+個)

---

## AC2: Frontendページ → Backend依存 逆引きマップ

### Viewer/Public ページ (15ページ)

| # | Page URL | 呼び出すAPI | 使用コンポーネント | 認証 |
|---|----------|-----------|-----------------|------|
| 1 | `/` (Signal) | `GET /api/signals`(ctx), `GET /api/history/{id}`, `GET /api/performance/{id}`, `GET /api/benchmark/{ticker}` | PortfolioDetails, PortfolioNavSelector, MomentumChart*, TotalReturnChart*, FromYearSelector, InstallPrompt, ErrorBoundary | Viewer可(なし) |
| 2 | `/dashboard` | `GET /api/signals`(ctx), `GET /api/history/{id}`, `GET /api/performance/{id}`, `GET /api/benchmark/{ticker}`, `GET /api/mtd/{id}`, `GET /api/viewer-permissions`(ctx) | PortfolioNavSelector, TotalReturnChart*, SignalPieChart, MtdChart, MtdDailyTable, ErrorBoundary | Viewer可(なし) |
| 3 | `/summary` | `GET /api/signals`(ctx), `GET /api/metrics/{id}`, `GET /api/viewer-permissions`(ctx) | PortfolioNavSelector, SummaryTable, TimingToggle | Viewer可(権限チェック有) |
| 4 | `/compare` | `GET /api/signals`(ctx), `GET /api/performance/{id}`(×N), `GET /api/benchmark/{ticker}` | PortfolioSelector, ComparisonChart*, FromYearSelector | Viewer可(なし) |
| 5 | `/compare-summary` | `GET /api/signals`(ctx), `GET /api/metrics/summary`, `GET /api/viewer-permissions`(ctx) | CompareSummaryTable, TimingToggle, FolderFilterChip | Viewer可(権限チェック有) |
| 6 | `/metrics` | `GET /api/signals`(ctx), `GET /api/metrics/{id}`, `GET /api/metrics/{id}/up-down-market` | PortfolioNavSelector, MetricsTable, UpDownMarketChart, TimingToggle | Viewer可(なし) |
| 7 | `/annual-returns` | `GET /api/signals`(ctx), `GET /api/annual-returns/{id}` | PortfolioNavSelector, AnnualReturnsTable, AnnualReturnsChart, TimingToggle | Viewer可(なし) |
| 8 | `/monthly-returns` | `GET /api/signals`(ctx), `GET /api/monthly-returns/{id}` | PortfolioNavSelector, MonthlyReturnsTable, TimingToggle | Viewer可(なし) |
| 9 | `/rolling-returns` | `GET /api/signals`(ctx), `GET /api/rolling-returns/{id}` | PortfolioNavSelector, RollingReturnChart, RollingReturnsSummaryTable, TimingToggle | Viewer可(なし) |
| 10 | `/trades` | `GET /api/signals`(ctx), `GET /api/trades/{id}` | PortfolioNavSelector, RiskManagementTable, ModelTradesTable, TimingToggle | Viewer可(なし) |
| 11 | `/monthly-trade` | `GET /api/signals`(ctx), `GET /api/monthly-trade/{id}` | PortfolioNavSelector, MonthlyTradeTable, TimingToggle | Viewer可(なし) |
| 12 | `/drawdowns` | `GET /api/signals`(ctx), `GET /api/drawdowns/{id}` | PortfolioNavSelector, DrawdownsTable, DrawdownsChart, TimingToggle | Viewer可(なし) |
| 13 | `/docs` | なし | MethodologyContent*, TermsContent*, DisclosuresContent*, Accordion | なし |
| 14 | `/faq` | なし | LanguageToggle, Accordion | なし |
| 15 | `/offline` | なし | GlassCard | なし |

### Admin ページ (4ページ)

| # | Page URL | 呼び出すAPI | 使用コンポーネント | 認証 |
|---|----------|-----------|-----------------|------|
| 16 | `/admin` | `POST /api/admin/login`, `GET /api/portfolios/get`(ctx), `POST /api/portfolios/save`, `DELETE /api/portfolios/{id}`, `POST /admin/recalculate-sync`, `GET /admin/db-status`, `GET /admin/recalculate-status`, `POST /admin/sync-prices`, `POST /admin/sync-tickers`, `POST /admin/sync-standard`, `POST /admin/sync-fof`, `GET /admin/sync-status`, `POST /admin/long-term-backfill`, `GET /admin/backfill-status` | LoginModal, PortfolioEditor(+LookbackEditor, RelativeAssetsEditor), AdvancedOperations, RecalculateStatus, MobileMenu, ErrorBoundary | Admin必須 |
| 17 | `/admin/fof` | `POST /api/admin/login`, `GET /api/portfolios/get`(ctx), `POST /api/portfolios/save`, `DELETE /api/portfolios/{id}`, `POST /admin/recalculate-sync` | LoginModal, FoFEditor(+ComponentSelectionModal, SelectionPipelineSection, TerminalBlockSection), GlassCard | Admin必須 |
| 18 | `/admin/folders` | `POST /api/admin/login`, `GET /api/portfolios/get`(ctx), `GET /api/admin/folders`, `POST /api/admin/folders`, `PATCH /api/admin/folders/{id}`, `DELETE /api/admin/folders/{id}`, `PUT /api/admin/folders/reorder`, `POST /api/admin/folders/portfolios/{id}/move` | LoginModal, GlassCard | Admin必須 |
| 19 | `/admin/visibility` | `POST /api/admin/login`, `GET /api/portfolios/get`(ctx), `GET /api/admin/tiers`, `POST /api/admin/tiers`, `PUT /api/admin/tiers/{id}`, `DELETE /api/admin/tiers/{id}`, `POST /api/admin/tiers/{id}/copy`, `PUT /api/admin/tiers/reorder`, `GET /api/admin/tiers/{id}/visibility`, `PUT /api/admin/tiers/{id}/visibility`, `GET /api/admin/tiers/visibility/global`, `PUT /api/admin/tiers/visibility/global`, `POST /api/admin/tiers/{id}/rotate`, `GET /api/admin/tiers/passwords`, `POST /api/admin/tiers/rotate-all`, `POST /api/admin/viewer-permissions` | LoginModal, TierSelector, ManageTiersModal, ErrorBoundary | Admin必須 |

### 共通Context (layout.tsx経由で全ページに注入)

| Context | API Call | 初期化タイミング |
|---------|----------|---------------|
| SignalsProvider | `GET /api/signals` (getSignalsLight) | アプリ起動時、TTL 1h |
| ExecutionTimingProvider | (SignalsProviderのtiming抽出) | SignalsProvider依存 |
| ViewerPermissionsProvider | `GET /api/viewer-permissions` | アプリ起動時 |
| AdminAuthProvider | `GET /api/portfolios/get`, `POST /api/admin/login` | admin配下ページ遷移時 |

### API影響度ランキング (変更時の影響ページ数)

| Rank | Endpoint | 影響ページ数 | 説明 |
|------|----------|------------|------|
| 1 | `GET /api/signals` | 12+ | SignalsContext経由で全Viewerページ |
| 2 | `GET /api/portfolios/get` | 4 | AdminAuthContext経由で全Adminページ |
| 3 | `GET /api/performance/{id}` | 3 | Signal, Dashboard, Compare |
| 4 | `GET /api/benchmark/{ticker}` | 3 | Signal, Dashboard, Compare |
| 5 | `GET /api/history/{id}` | 2 | Signal, Dashboard |
| 6 | `GET /api/metrics/{id}` | 2 | Summary, Metrics |
| 7 | `POST /admin/recalculate-sync` | 2 | Admin, Admin FoF |
| 8 | `POST /api/portfolios/save` | 2 | Admin, Admin FoF |
| 9 | `DELETE /api/portfolios/{id}` | 2 | Admin, Admin FoF |
| 10 | その他Viewer系 | 1 | 各専用ページのみ |
