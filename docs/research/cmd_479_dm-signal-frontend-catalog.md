# DM-Signal Frontend カタログ (cmd_479)

> 生成: subtask_479_recon_a (hanzo) + subtask_479_recon_b (saizo)
> 対象: `/mnt/c/Python_app/DM-signal/frontend/`

---

## §1 ページカタログ (frontend/app/)

全18ページ + 2 layout。合計6,080行。

| # | URL Path | page.tsx行数 | 主要コンポーネント | 使用API (api-client.ts) | 認証 | 説明 |
|---|----------|-------------|-------------------|------------------------|------|------|
| 1 | `/` (Signal) | 391 | PortfolioDetails, PortfolioNavSelector, MomentumChart*, TotalReturnChart*, FromYearSelector, InstallPrompt, ErrorBoundary | `getSignalsLight`, `getHistory`, `getPerformance`, `getBenchmarkPerformance` | なし(Viewer可) | シグナル一覧+チャート。メインページ |
| 2 | `/dashboard` | 412 | PortfolioNavSelector, TotalReturnChart*, SignalPieChart, MtdChart, MtdDailyTable, ErrorBoundary | `getSignalsLight`, `getHistory`, `getPerformance`, `getBenchmarkPerformance`, `getMtd` | なし(Viewer可) | ダッシュボード。パフォーマンスチャート+MTDデイリー |
| 3 | `/summary` | 157 | PortfolioNavSelector, SummaryTable, TimingToggle | `getMetrics` | なし(Viewer可, 権限チェック有) | メトリクスサマリー表 |
| 4 | `/compare` | 325 | PortfolioSelector(複数選択), ComparisonChart*, FromYearSelector | `getPerformance`, `getBenchmarkPerformance` | なし(Viewer可) | 複数PF累積リターン比較チャート |
| 5 | `/compare-summary` | 322 | CompareSummaryTable, TimingToggle, FolderFilterChip | `getMetricsSummary` | なし(Viewer可, 権限チェック有) | 全PFメトリクス横断比較テーブル |
| 6 | `/metrics` | 182 | PortfolioNavSelector, MetricsTable, UpDownMarketChart, TimingToggle | `getMetrics`, `getUpDownMarketAnalysis` | なし(Viewer可) | 個別PFメトリクス詳細+Up/Downマーケット分析 |
| 7 | `/annual-returns` | 156 | PortfolioNavSelector, AnnualReturnsTable, AnnualReturnsChart, TimingToggle | `getAnnualReturns` | なし(Viewer可) | 年次リターンテーブル+棒グラフ |
| 8 | `/monthly-returns` | 144 | PortfolioNavSelector, MonthlyReturnsTable, TimingToggle | `getMonthlyReturns` | なし(Viewer可) | 月次リターンヒートマップ |
| 9 | `/rolling-returns` | 169 | PortfolioNavSelector, RollingReturnChart, RollingReturnsSummaryTable, TimingToggle | `getRollingReturns` | なし(Viewer可) | ローリングリターンチャート+サマリー |
| 10 | `/trades` | 163 | PortfolioNavSelector, RiskManagementTable, ModelTradesTable, TimingToggle | `getTrades` | なし(Viewer可) | リスク管理+モデルトレード一覧 |
| 11 | `/monthly-trade` | 155 | PortfolioNavSelector, MonthlyTradeTable, TimingToggle | `getMonthlyTrade` | なし(Viewer可) | 月次トレード詳細(SSOT Level 1) |
| 12 | `/drawdowns` | 177 | PortfolioNavSelector, DrawdownsTable, DrawdownsChart, TimingToggle | `getDrawdowns` | なし(Viewer可) | ドローダウン期間テーブル+チャート |
| 13 | `/docs` | 56 | MethodologyContent*, TermsContent*, DisclosuresContent*, Accordion | なし | なし | ドキュメント(方法論/用語/免責) |
| 14 | `/faq` | 440 | LanguageToggle, Accordion, FAQAnswer(内製) | なし | なし | FAQ(日英切替対応) |
| 15 | `/offline` | 18 | GlassCard | なし | なし | オフラインフォールバック(PWA) |
| 16 | `/admin` | 1013 | LoginModal, PortfolioEditor, AdvancedOperations, RecalculateStatus, MobileMenu, ErrorBoundary | `getPortfolios`, `savePortfolios`, `deletePortfolio`, `recalculateHistory`, `getDbStatus`, `getRecalculateStatus`, `syncPrices`, `syncTickers`, `syncStandard`, `syncFof`, `getSyncStatus`, `triggerFullBackfill`, `getBackfillStatus` | Admin必須 | PF管理。CRUD+再計算+層別同期+DB状態 |
| 17 | `/admin/fof` | 368 | LoginModal, FoFEditor, GlassCard | `getPortfolios`(via context), `savePortfolios`, `deletePortfolio`, `recalculateHistory` | Admin必須 | FoFポートフォリオ管理 |
| 18 | `/admin/folders` | 616 | LoginModal, GlassCard | `getPortfolios`(via context), `getFolders`, `createFolder`, `updateFolder`, `deleteFolder`, `reorderFolders`, `movePortfolioToFolder`, `clearSignalsCache` | Admin必須 | フォルダ管理(PF整理) |
| 19 | `/admin/visibility` | 816 | LoginModal, TierSelector, ManageTiersModal, ErrorBoundary | `getPortfolios`(via context), `getTiers`, `createTier`, `updateTier`, `deleteTier`, `copyTier`, `reorderTiers`, `getTierVisibility`, `updateTierVisibility`, `getGlobalVisibility`, `updateGlobalVisibility`, `rotateTierPassword`, `getAllTierPasswords`, `rotateAllTierPasswords`, `updateViewerPermissions` | Admin必須 | 閲覧権限・Tier管理(ページ/PF表示制御) |

\* = dynamic import (SSR無効)

### Layout構造

| Layout | パス | 行数 | 提供するProvider |
|--------|------|------|-----------------|
| RootLayout | `app/layout.tsx` | 71 | ThemeProvider, SignalsProvider, ExecutionTimingProvider, ViewerPermissionsProvider + Sidebar + ViewerAuthModal |
| AdminLayout | `app/admin/layout.tsx` | 9 | AdminAuthProvider |

### Admin詳細コンポーネント

| コンポーネント | パス | 用途 |
|---------------|------|------|
| LoginModal | `admin/components/LoginModal.tsx` | 管理者ログイン |
| PortfolioEditor | `admin/components/PortfolioEditor.tsx` | PF設定編集フォーム |
| AdvancedOperations | `admin/components/AdvancedOperations.tsx` | DB状態/再計算/バックフィル |
| LookbackEditor | `admin/components/LookbackEditor.tsx` | ルックバック期間編集 |
| RelativeAssetsEditor | `admin/components/RelativeAssetsEditor.tsx` | 相対アセット編集 |
| FoFEditor | `admin/fof/components/FoFEditor.tsx` | FoF構成編集 |
| ComponentSelectionModal | `admin/fof/components/ComponentSelectionModal.tsx` | FoF構成PF選択 |
| SelectionPipelineSection | `admin/fof/components/SelectionPipelineSection.tsx` | パイプラインブロック設定 |
| TerminalBlockSection | `admin/fof/components/TerminalBlockSection.tsx` | ターミナルブロック設定 |
| TierSelector | `admin/visibility/components/TierSelector.tsx` | Tier選択UI |
| ManageTiersModal | `admin/visibility/components/ManageTiersModal.tsx` | Tier CRUD管理 |

---

## §5 ページ→コンポーネント→API依存マップ

### Signal (/) — メインページ

```
page.tsx (/)
├── SignalsContext (layout.tsx)
│   └── api.getSignalsLight() → GET /api/signals
├── PortfolioNavSelector
├── PortfolioDetails
├── MomentumChart (dynamic)
│   └── history data from page
├── TotalReturnChart (dynamic)
│   └── performance data from page
├── FromYearSelector
├── api.getHistory(id, days) → GET /api/history/{id}?days={days}
├── api.getPerformance(id, years) → GET /api/performance/{id}?years={years}
└── api.getBenchmarkPerformance(ticker) → GET /api/benchmark/{ticker}?years={years}
```

### Dashboard (/dashboard)

```
page.tsx (/dashboard)
├── SignalsContext → api.getSignalsLight()
├── ViewerPermissionsContext → api.getViewerPermissions()
├── ExecutionTimingContext
├── PortfolioNavSelector
├── TotalReturnChart (dynamic)
├── SignalPieChart
├── MtdChart
├── MtdDailyTable
├── api.getHistory(id, 3650) → GET /api/history/{id}?days=3650
├── api.getPerformance(id, 10) → GET /api/performance/{id}?years=10
├── api.getBenchmarkPerformance(ticker) → GET /api/benchmark/{ticker}
└── api.getMtd(id) → GET /api/mtd/{id}
```

### Compare (/compare)

```
page.tsx (/compare)
├── SignalsContext → api.getSignalsLight()
├── PortfolioSelector (複数選択)
├── ComparisonChart (dynamic)
├── FromYearSelector
├── api.getPerformance(id, years) → GET /api/performance/{id}?years={years}  [per selected PF]
└── api.getBenchmarkPerformance(ticker) → GET /api/benchmark/{ticker}
```

### Compare Summary (/compare-summary)

```
page.tsx (/compare-summary)
├── SignalsContext → api.getSignalsLight()
├── ViewerPermissionsContext
├── ExecutionTimingContext
├── CompareSummaryTable
├── FolderFilterChip (フォルダフィルタ)
└── api.getMetricsSummary(years) → GET /api/metrics/summary?years={years}
```

### Summary (/summary)

```
page.tsx (/summary)
├── SignalsContext → api.getSignalsLight()
├── ViewerPermissionsContext (権限チェック: summary, metrics)
├── ExecutionTimingContext
├── PortfolioNavSelector
├── SummaryTable
└── api.getMetrics(id, 0) → GET /api/metrics/{id}?years=0
```

### Metrics (/metrics)

```
page.tsx (/metrics)
├── SignalsContext → api.getSignalsLight()
├── ExecutionTimingContext
├── PortfolioNavSelector
├── MetricsTable
├── UpDownMarketChart
├── api.getMetrics(id, 0) → GET /api/metrics/{id}?years=0
└── api.getUpDownMarketAnalysis(id) → GET /api/metrics/{id}/up-down-market
```

### Annual Returns (/annual-returns)

```
page.tsx (/annual-returns)
├── SignalsContext → api.getSignalsLight()
├── ExecutionTimingContext
├── PortfolioNavSelector
├── AnnualReturnsTable
├── AnnualReturnsChart
└── api.getAnnualReturns(id, limit) → GET /api/annual-returns/{id}?years={limit}&initial_balance=100000
```

### Monthly Returns (/monthly-returns)

```
page.tsx (/monthly-returns)
├── SignalsContext → api.getSignalsLight()
├── ExecutionTimingContext
├── PortfolioNavSelector
├── MonthlyReturnsTable
└── api.getMonthlyReturns(id, limit) → GET /api/monthly-returns/{id}?months={limit}&initial_balance=100000
```

### Rolling Returns (/rolling-returns)

```
page.tsx (/rolling-returns)
├── SignalsContext → api.getSignalsLight()
├── ExecutionTimingContext
├── PortfolioNavSelector
├── RollingReturnChart
├── RollingReturnsSummaryTable
└── api.getRollingReturns(id) → GET /api/rolling-returns/{id}
```

### Trades (/trades)

```
page.tsx (/trades)
├── SignalsContext → api.getSignalsLight()
├── ExecutionTimingContext
├── PortfolioNavSelector
├── RiskManagementTable
├── ModelTradesTable
└── api.getTrades(id, limit) → GET /api/trades/{id}?trades_limit={limit}
```

### Monthly Trade (/monthly-trade)

```
page.tsx (/monthly-trade)
├── SignalsContext → api.getSignalsLight()
├── ExecutionTimingContext
├── PortfolioNavSelector
├── MonthlyTradeTable
└── api.getMonthlyTrade(id, limit) → GET /api/monthly-trade/{id}?limit={limit}
```

### Drawdowns (/drawdowns)

```
page.tsx (/drawdowns)
├── SignalsContext → api.getSignalsLight()
├── ExecutionTimingContext
├── PortfolioNavSelector
├── DrawdownsTable
├── DrawdownsChart
└── api.getDrawdowns(id, limit) → GET /api/drawdowns/{id}?limit={limit}
```

### Admin (/admin)

```
page.tsx (/admin)
├── AdminAuthContext (admin/layout.tsx) → api.adminLogin(), api.getPortfolios()
├── useAdminPage hook
├── LoginModal
├── PortfolioEditor
│   ├── LookbackEditor
│   └── RelativeAssetsEditor
├── AdvancedOperations
├── RecalculateStatus → api.getRecalculateStatus(), api.getSyncStatus()
├── api.savePortfolios() → POST /api/portfolios/save
├── api.deletePortfolio(id) → DELETE /api/portfolios/{id}
├── api.recalculateHistory() → POST /admin/recalculate-sync
├── api.getDbStatus() → GET /admin/db-status
├── api.syncPrices() → POST /admin/sync-prices
├── api.syncTickers() → POST /admin/sync-tickers
├── api.syncStandard() → POST /admin/sync-standard
├── api.syncFof() → POST /admin/sync-fof
├── api.triggerFullBackfill() → POST /admin/long-term-backfill
└── api.getBackfillStatus() → GET /admin/backfill-status
```

### Admin FoF (/admin/fof)

```
page.tsx (/admin/fof)
├── AdminAuthContext → api.getPortfolios()
├── LoginModal
├── FoFEditor
│   ├── ComponentSelectionModal
│   ├── SelectionPipelineSection
│   └── TerminalBlockSection
├── api.savePortfolios() → POST /api/portfolios/save
├── api.deletePortfolio(id) → DELETE /api/portfolios/{id}
└── api.recalculateHistory({portfolioId, mode: "portfolio"}) → POST /admin/recalculate-sync
```

### Admin Folders (/admin/folders)

```
page.tsx (/admin/folders)
├── AdminAuthContext → api.getPortfolios()
├── SignalsContext.refresh
├── LoginModal
├── api.getFolders() → GET /api/admin/folders
├── api.createFolder() → POST /api/admin/folders
├── api.updateFolder() → PATCH /api/admin/folders/{id}
├── api.deleteFolder() → DELETE /api/admin/folders/{id}
├── api.reorderFolders() → PUT /api/admin/folders/reorder
├── api.movePortfolioToFolder() → POST /api/admin/folders/portfolios/{id}/move
└── api.clearSignalsCache()
```

### Admin Visibility (/admin/visibility)

```
page.tsx (/admin/visibility)
├── AdminAuthContext → api.getPortfolios()
├── useAdminPage hook
├── LoginModal
├── TierSelector
├── ManageTiersModal
├── api.getTiers() → GET /api/admin/tiers
├── api.createTier() → POST /api/admin/tiers
├── api.updateTier() → PUT /api/admin/tiers/{id}
├── api.deleteTier() → DELETE /api/admin/tiers/{id}
├── api.copyTier() → POST /api/admin/tiers/{id}/copy
├── api.reorderTiers() → PUT /api/admin/tiers/reorder
├── api.getTierVisibility() → GET /api/admin/tiers/{id}/visibility
├── api.updateTierVisibility() → PUT /api/admin/tiers/{id}/visibility
├── api.getGlobalVisibility() → GET /api/admin/tiers/visibility/global
├── api.updateGlobalVisibility() → PUT /api/admin/tiers/visibility/global
├── api.rotateTierPassword() → POST /api/admin/tiers/{id}/rotate
├── api.getAllTierPasswords() → GET /api/admin/tiers/passwords
├── api.rotateAllTierPasswords() → POST /api/admin/tiers/rotate-all
└── api.updateViewerPermissions() → POST /api/admin/viewer-permissions
```

### Docs (/docs) — API呼び出しなし

```
page.tsx (/docs)
├── MethodologyContent (dynamic)
├── TermsContent (dynamic)
├── DisclosuresContent (dynamic)
└── Accordion
```

### FAQ (/faq) — API呼び出しなし

```
page.tsx (/faq)
├── LanguageToggle
├── faqContent (static data from @/lib/faq-content)
├── FAQAnswer (内製レンダラー)
└── Accordion
```

### Offline (/offline) — API呼び出しなし

```
page.tsx (/offline)
└── GlassCard (オフラインメッセージ表示のみ)
```

---

## §6 API Client メソッド一覧 (api-client.ts, 1121行)

### インフラ

| メソッド | エンドポイント | 認証 | TTL | Timeout |
|---------|---------------|------|-----|---------|
| `adminLogin` | POST `/api/admin/login` | Basic | - | 8s |
| `logout` | POST `/api/auth/logout` | - | - | 8s |
| `verifyViewer` | POST `/api/auth/verify-viewer` | - | - | 8s |
| `testAuth` | (calls adminLogin) | Basic | - | - |

### ポートフォリオ管理

| メソッド | エンドポイント | 認証 | TTL | Timeout |
|---------|---------------|------|-----|---------|
| `getPortfolios` | GET `/api/portfolios/get` | Yes | - | 8s |
| `savePortfolios` | POST `/api/portfolios/save` | Admin | - | 10min |
| `deletePortfolio` | DELETE `/api/portfolios/{id}` | Admin | - | 30s |

### Admin操作

| メソッド | エンドポイント | 認証 | TTL | Timeout |
|---------|---------------|------|-----|---------|
| `runEtl` | POST `/admin/run-etl` | Admin | - | 8s |
| `recalculateHistory` | POST `/admin/recalculate-sync` | Admin | - | 10-60min |
| `getDbStatus` | GET `/admin/db-status` | Admin | - | 8s |
| `getRecalculateStatus` | GET `/admin/recalculate-status` | Admin | - | 5s |
| `syncPrices` | POST `/admin/sync-prices` | Admin | - | 2min |
| `syncTickers` | POST `/admin/sync-tickers` | Admin | - | 5min |
| `syncStandard` | POST `/admin/sync-standard` | Admin | - | 10min |
| `syncFof` | POST `/admin/sync-fof` | Admin | - | 15min |
| `getSyncStatus` | GET `/admin/sync-status` | Admin | - | 5s |
| `triggerFullBackfill` | POST `/admin/long-term-backfill` | Admin | - | 10min |
| `getBackfillStatus` | GET `/admin/backfill-status` | Admin | - | 8s |

### 公開データ (Viewer/Public)

| メソッド | エンドポイント | 認証 | TTL | Timeout |
|---------|---------------|------|-----|---------|
| `getSignalsLight` | GET `/api/signals` | No | 1h | 5s |
| `getHistory` | GET `/api/history/{id}` | No | 5min | 30s |
| `getPerformance` | GET `/api/performance/{id}` | No | 5min | 30s |
| `getMtd` | GET `/api/mtd/{id}` | No | 5min | 30s |
| `getBenchmarkPerformance` | GET `/api/benchmark/{ticker}` | No | 5min | 30s |
| `getMetrics` | GET `/api/metrics/{id}` | No | 5min | 30s |
| `getMetricsSummary` | GET `/api/metrics/summary` | No | 5min | 60s |
| `getUpDownMarketAnalysis` | GET `/api/metrics/{id}/up-down-market` | No | 5min | 30s |
| `getAnnualReturns` | GET `/api/annual-returns/{id}` | No | 5min | 30s |
| `getMonthlyReturns` | GET `/api/monthly-returns/{id}` | No | 5min | 30s |
| `getRollingReturns` | GET `/api/rolling-returns/{id}` | No | 5min | 30s |
| `getTrades` | GET `/api/trades/{id}` | No | 5min | 30s |
| `getMonthlyTrade` | GET `/api/monthly-trade/{id}` | No | 5min | 30s |
| `getDrawdowns` | GET `/api/drawdowns/{id}` | No | 5min | 30s |

### Viewer権限

| メソッド | エンドポイント | 認証 | TTL | Timeout |
|---------|---------------|------|-----|---------|
| `getViewerPermissions` | GET `/api/viewer-permissions` | Yes | - | 8s |
| `updateViewerPermissions` | POST `/api/admin/viewer-permissions` | Admin | - | 8s |

### Tier管理

| メソッド | エンドポイント | 認証 | TTL | Timeout |
|---------|---------------|------|-----|---------|
| `getTiers` | GET `/api/admin/tiers` | Admin | - | 8s |
| `createTier` | POST `/api/admin/tiers` | Admin | - | 8s |
| `updateTier` | PUT `/api/admin/tiers/{id}` | Admin | - | 8s |
| `deleteTier` | DELETE `/api/admin/tiers/{id}` | Admin | - | 8s |
| `copyTier` | POST `/api/admin/tiers/{id}/copy` | Admin | - | 8s |
| `reorderTiers` | PUT `/api/admin/tiers/reorder` | Admin | - | 8s |
| `getTierVisibility` | GET `/api/admin/tiers/{id}/visibility` | Admin | - | 8s |
| `updateTierVisibility` | PUT `/api/admin/tiers/{id}/visibility` | Admin | - | 8s |
| `getGlobalVisibility` | GET `/api/admin/tiers/visibility/global` | Admin | - | 8s |
| `updateGlobalVisibility` | PUT `/api/admin/tiers/visibility/global` | Admin | - | 8s |
| `rotateTierPassword` | POST `/api/admin/tiers/{id}/rotate` | Admin | - | 8s |
| `getAllTierPasswords` | GET `/api/admin/tiers/passwords` | Admin | - | 8s |
| `rotateAllTierPasswords` | POST `/api/admin/tiers/rotate-all` | Admin | - | 8s |

### フォルダ管理

| メソッド | エンドポイント | 認証 | TTL | Timeout |
|---------|---------------|------|-----|---------|
| `getFolders` | GET `/api/admin/folders` | Admin | - | 8s |
| `createFolder` | POST `/api/admin/folders` | Admin | - | 8s |
| `updateFolder` | PATCH `/api/admin/folders/{id}` | Admin | - | 8s |
| `deleteFolder` | DELETE `/api/admin/folders/{id}` | Admin | - | 8s |
| `reorderFolders` | PUT `/api/admin/folders/reorder` | Admin | - | 8s |
| `movePortfolioToFolder` | POST `/api/admin/folders/portfolios/{id}/move` | Admin | - | 8s |

### キャッシュ系ユーティリティ

`hasCached`, `hasHistoryCached`, `hasPerformanceCached`, `hasBenchmarkCached`, `hasMetricsCached`, `hasTradesCached`, `hasAnnualReturnsCached`, `hasMonthlyReturnsCached`, `hasRollingReturnsCached`, `hasDrawdownsCached`, `clearSignalsCache`

### アーキテクチャ特記事項

- **RequestSemaphore**: 同時リクエスト上限2（QUIC_TOO_MANY_RTOS防止）
- **リトライ**: 最大2回、指数バックオフ(500ms→1s→3s)
- **キャッシュ**: `apiCache`による2層キャッシュ。公開データにTTL設定(1h〜5min)
- **認証**: Cookie-based session + Basic Auth fallback + Bearer token (Viewer)

---

## §2 共有コンポーネントカタログ (frontend/components/)

全60ファイル（テスト除外）。

| ファイル | 行数 | exports | Props型 | 使用ページ |
|---------|------|---------|---------|-----------|
| ErrorBoundary.tsx | 63 | (no direct export) | Props | /admin, /admin/visibility, /dashboard, / |
| RecalculateStatus.tsx | 138 | RecalculateStatus | RecalculateStatusProps | /admin |
| annual-returns-chart.tsx | 447 | AnnualReturnsChart | Props | /annual-returns |
| annual-returns-table.tsx | 277 | AnnualReturnsTable | Props | /annual-returns |
| auth-status.tsx | 134 | AuthStatus | AuthStatusProps | (indirect) |
| chart/ChartAxes.tsx | 187 | ChartAxes | ChartAxesProps | (indirect) |
| chart/ChartControls.tsx | 30 | ChartControls, ChartControlsGroup | ChartControlsGroupProps, ChartControlsProps | (indirect) |
| chart/ChartLegend.tsx | 48 | ChartLegend, LegendItem | ChartLegendProps, LegendItemProps | (indirect) |
| chart/ChartTooltip.tsx | 72 | ChartTooltip, TooltipItem | ChartTooltipProps, TooltipItemProps | (indirect) |
| chart/FromYearSelector.tsx | 68 | FromYearSelector | FromYearSelectorProps | /compare, / |
| chart/PeriodModeToggle.tsx | 54 | PeriodModeToggle | PeriodModeToggleProps | /compare |
| chart/ScaleToggle.tsx | 33 | ScaleToggle | ScaleToggleProps | (indirect) |
| chart/TimingToggle.tsx | 37 | TimingToggle | TimingToggleProps | /annual-returns, /compare-summary, /dashboard, /drawdowns, /metrics, /monthly-returns, /monthly-trade, /rolling-returns, /summary, /trades |
| chart/YearRangeSelector.tsx | 84 | YearRangeSelector | YearRangeSelectorProps | (indirect) |
| compare-summary-table.tsx | 203 | CompareSummaryTable | CompareSummaryTableProps | /compare-summary |
| comparison-chart.tsx | 340 | ComparisonChart | ComparisonChartProps | /compare |
| docs/disclosures-content.tsx | 62 | DisclosuresContent | - | /docs |
| docs/methodology-content.tsx | 90 | MethodologyContent | - | /docs |
| docs/terms-content.tsx | 245 | TermsContent | - | /docs |
| drawdowns-chart.tsx | 288 | DrawdownsChart | DrawdownsChartProps | /drawdowns |
| drawdowns-table.tsx | 78 | DrawdownsTable | DrawdownsTableProps | /drawdowns |
| install-prompt.tsx | 84 | InstallPrompt | - | / |
| language-toggle.tsx | 40 | LanguageToggle | LanguageToggleProps | /faq |
| metrics-table.tsx | 92 | MetricsTable | MetricsTableProps | /metrics |
| mobile-menu.tsx | 216 | MobileMenu | MobileMenuProps | 全ページ(Sidebar経由) |
| model-trades-table.tsx | 314 | ModelTradesTable | ModelTradesTableProps | /trades |
| momentum-chart.tsx | 348 | MomentumChart | MomentumChartProps | / |
| monthly-returns-table.tsx | 322 | MonthlyReturnsTable | Props | /monthly-returns |
| monthly-trade-table.tsx | 441 | MonthlyTradeTable | MonthlyTradeRowProps, MonthlyTradeTableProps | /monthly-trade |
| mtd-chart.tsx | 288 | MtdChart | MtdChartProps | /dashboard |
| mtd-daily-table.tsx | 127 | MtdDailyTable | MtdDailyTableProps | /dashboard |
| period-notes.tsx | 73 | PeriodNotes | Props | (indirect) |
| portfolio-details.tsx | 236 | PortfolioDetails | - | / |
| portfolio-nav-selector.tsx | 118 | PortfolioNavSelector | - | /annual-returns, /dashboard, /drawdowns, /metrics, /monthly-returns, /monthly-trade, /, /rolling-returns, /summary, /trades |
| portfolio-select-items.tsx | 199 | PortfolioSelectItems, groupByFolder | PortfolioSelectItemsProps | (indirect) |
| portfolio-selector.tsx | 219 | PortfolioSelector | PortfolioSelectorProps | /compare |
| risk-management-table.tsx | 266 | RiskManagementTable | RiskManagementTableProps | /trades |
| rolling-return-chart.tsx | 357 | RollingReturnChart | RollingReturnChartProps | /rolling-returns |
| rolling-returns-summary-table.tsx | 261 | RollingReturnsSummaryTable | RollingReturnsSummaryTableProps | /rolling-returns |
| sidebar.tsx | 263 | Sidebar | - | (indirect/layout) |
| signal-pie-chart.tsx | 136 | SignalPieChart | SignalPieChartProps | /dashboard |
| summary-table.tsx | 205 | SummaryTable | SummaryTableProps | /summary |
| sw-register.tsx | 97 | ServiceWorkerRegister | - | (indirect) |
| theme-provider.tsx | 9 | ThemeProvider | ThemeProviderProps | (indirect/layout) |
| theme-toggle.tsx | 54 | ThemeToggle | - | (indirect) |
| total-return-chart.tsx | 344 | TotalReturnChart | TotalReturnChartProps | /dashboard, / |
| ui/accordion.tsx | 48 | Accordion | AccordionProps | /compare, /docs, /faq |
| ui/button.tsx | 37 | Button | ButtonProps | /admin/fof, /admin/folders, /admin, /admin/visibility |
| ui/dropdown-menu.tsx | 141 | DropdownMenu | DropdownMenuProps | (indirect) |
| ui/glass-card.tsx | 14 | GlassCard | GlassCardProps | /admin/fof, /admin/folders, /admin, /admin/visibility, /docs, /drawdowns, /faq, /monthly-returns, /offline, /rolling-returns |
| ui/input.tsx | 23 | Input | InputProps | (indirect) |
| ui/latex.tsx | 27 | Latex | LatexProps | (indirect) |
| ui/loading.tsx | 15 | Loading | - | /admin/fof, /admin/folders, /annual-returns, /compare, /dashboard, /docs, /drawdowns, /faq, /metrics, /monthly-returns, /monthly-trade, /, /rolling-returns, /summary, /trades |
| ui/message-banner.tsx | 30 | MessageBanner | MessageBannerProps | 大半のページ |
| ui/page-header.tsx | 74 | PageHeader | PageHeaderProps | /docs, /faq |
| ui/select.tsx | 374 | Select, SelectTrigger, SelectValue, SelectContent, SelectItem 等 | 各Props型 | /admin, /compare |
| ui/skeleton.tsx | 92 | Skeleton, ChartSkeleton, SignalDetailsSkeleton, GraphAreaSkeleton | SkeletonProps | (indirect) |
| ui/transition-overlay.tsx | 10 | TransitionOverlay | - | (indirect) |
| up-down-market-chart.tsx | 553 | UpDownMarketChart | Props | /metrics |
| viewer-auth-modal.tsx | 204 | ViewerAuthModal | - | (indirect/layout) |

---

## §3 ライブラリ (frontend/lib/)

### Core ユーティリティ (12ファイル)

| ファイル | 行数 | 役割 |
|---------|------|------|
| admin-auth.ts | 36 | Admin BasicAuth資格情報の保存・取得・破棄 |
| api-cache.ts | 126 | TTL付きLRUキャッシュ（keyごとの有効期限管理） |
| api-client.ts | 1121 | API呼び出し統合（認証、再試行、セマフォ、タイムアウト、キャッシュ連携）→ §6参照 |
| chart-utils.ts | 213 | 時系列チャート整形（ダウンサンプル、年フィルタ、ラベル整形） |
| colors.ts | 45 | チャート・PF色定義と色選択 |
| constants.ts | 9 | 共有定数（MAX_PORTFOLIOS等） |
| faq-content.ts | 1355 | FAQ/Docs向け静的コンテンツ定義（日英対応） |
| fof-validation.ts | 239 | FoF構成の循環参照検出と選択バリデーション |
| lookbackFormatter.ts | 138 | lookback期間表示の短縮/詳細フォーマット |
| portfolio-diff.ts | 196 | Portfolio編集差分検出と要約 |
| utils.ts | 6 | className結合ユーティリティ（cn） |
| viewer-auth.ts | 81 | Viewer認証トークン保存・有効期限管理 |

### 型定義 (frontend/lib/types/, 11ファイル)

| ファイル | 行数 | 主要型 |
|---------|------|--------|
| api.ts | 313 | PortfoliosPayload, SavePortfoliosRequest/Response, SignalsLightResponse, HistoryResponse, PerformanceResponse, MtdResponse, AnnualReturnsResponse, MonthlyReturnsResponse, MonthlyTradeResponse, RollingReturnsResponse, TradesResponse, ViewerPermissionsResponse 等 |
| auth.ts | 5 | AuthCredentials |
| chart.ts | 22 | YearRange, FromYear |
| compare-summary.ts | 94 | CompareSummaryRow, SortableColumn, SortDirection, SortState, ColumnDef |
| drawdowns.ts | 27 | DrawdownEntry, DrawdownsChartDataPoint, DrawdownsResponse |
| index.ts | 10 | (re-exports) |
| market.ts | 33 | MomentumValue, PortfolioMomentum, DailyMomentumValue, DailyTotalReturn |
| metrics.ts | 42 | MetricValue, MetricItem, MetricsResponse, MetricsSummaryResponse |
| pipeline.ts | 346 | BlockCategory, BlockType, BlockConfig, BlockDefinition, SelectionPipeline, PipelineConfig |
| portfolio.ts | 185 | MomentumMethod, LookbackPeriod, RebalanceTrigger, PortfolioFolder, Portfolio, PortfolioSignal |
| tiers.ts | 99 | ViewerTier, PortfolioVisibilitySetting, TierVisibilitySettings, GlobalVisibilitySettings 等 |

---

## §4 Context / Hooks (frontend/contexts/ + frontend/hooks/)

全12ファイル。

### Context Providers (4ファイル + index.ts)

| ファイル | 行数 | Provider / Hook | 管理状態 | 使用箇所 |
|---------|------|----------------|----------|---------|
| admin-auth-context.tsx | 135 | AdminAuthProvider, useAdminAuth | isAuthenticated, portfolios, loginError | admin/layout.tsx → admin配下全ページ |
| execution-timing-context.tsx | 99 | ExecutionTimingProvider, useExecutionTiming | timing, isInitialized | layout.tsx → 大半のデータページ |
| signals-context.tsx | 236 | SignalsProvider, useSignals | signals, folders, loading, error, selectedId | layout.tsx → 大半のデータページ |
| viewer-permissions-context.tsx | 111 | ViewerPermissionsProvider, useViewerPermissions | role, hiddenPages, loading | layout.tsx → 権限チェック対象ページ |
| index.ts | 3 | (re-export) | - | - |

### Custom Hooks (7ファイル)

| ファイル | 行数 | Hook名 | 管理状態 | 使用箇所 |
|---------|------|--------|----------|---------|
| useAdminPage.ts | 550 | useAdminPage | portfolios, selectedIndex, saving, recalculating, syncingLayer, dbStatus, message 等 | /admin, /admin/visibility |
| useAppVisibility.ts | 76 | useAppVisibility | - | (未使用) |
| useChartInteraction.ts | 198 | useChartInteraction | hoverIndex, tooltipPosition | comparison-chart, drawdowns-chart, momentum-chart, mtd-chart, rolling-return-chart, total-return-chart |
| useIsMobile.ts | 29 | useIsMobile | isMobile | comparison-chart, momentum-chart, mtd-chart, rolling-return-chart, total-return-chart |
| usePortfolioParam.ts | 63 | usePortfolioParam, getCurrentPortfolioId, buildUrlWithPortfolio | portfolioId | sidebar, dropdown-menu |
| usePrefetch.ts | 177 | usePrefetch | - | /, portfolio-nav-selector, signals-context |
| useSortableTable.ts | 76 | useSortableTable | sortState | compare-summary-table |
