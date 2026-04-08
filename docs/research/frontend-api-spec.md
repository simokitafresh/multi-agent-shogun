# DM-signal フロントエンド — API・認証・lib関数詳細
<!-- source: context/dm-signal-frontend.md (cmd_256 佐助補完) -->
<!-- moved: cmd_286 索引化+圧縮 -->

> 索引: `context/dm-signal-frontend.md` → このファイル

## §1 APIクライアント (`lib/api-client.ts`, 1061行)

### §1.1 リクエストパイプライン

```
request()
├─ キャッシュチェック (TTLベース)
├─ リトライループ (最大2回, 指数バックオフ 500ms→1s→2s)
│   └─ requestOnce()
│       ├─ RequestSemaphore (同時最大2リクエスト — QUIC_TOO_MANY_RTOS対策)
│       └─ requestOnceInternal()
│           ├─ 認証ヘッダ設定 (Cookie優先→Bearerフォールバック)
│           ├─ AbortController (タイムアウト: デフォルト8秒)
│           └─ レスポンスアンラップ (ApiResponse→ApiResult)
└─ キャッシュ保存 (GET & ttl > 0のみ)
```

### §1.2 キャッシュ

- デフォルトTTL: 5分(300秒)
- 最大エントリ: 100 (LRU eviction)
- 自動クリーンアップ: 60秒ごと
- GETのみキャッシュ。POST/PUT/DELETEはバイパス
- `/api/signals`だけTTL 1時間(3600秒)

### §1.3 認証モデル

| 認証種別 | 方式 | 保存先 | 用途 |
|---------|------|--------|------|
| Admin | Cookie(HttpOnly) + Basic Auth | localStorage(`admin_session_active`フラグ) | 管理画面全般 |
| Viewer | Bearerトークン | localStorage(`dm_viewer_token` + 有効期限) | 閲覧制限ページ |

認証ヘッダ優先順位: 明示ヘッダ → Adminクッキー → Viewerトークン → レガシー資格情報
401レスポンス時: セッションクリア + `viewer-auth-required`イベント発火

### §1.4 主要エンドポイント

**公開データ (キャッシュ有効)**:

| エンドポイント | 用途 | キャッシュTTL | タイムアウト |
|--------------|------|-------------|------------|
| GET /api/signals | 全PFシグナル | 3600s | 5s |
| GET /api/performance/{id} | パフォーマンス(デフォルト10年) | 300s | 30s |
| GET /api/history/{id} | 日次履歴(デフォルト30日) | 300s | 30s |
| GET /api/mtd/{id} | MTD日次パフォーマンス | 300s | 30s |
| GET /api/metrics/{id} | リスク/リターンメトリクス | 300s | 30s |
| GET /api/metrics/summary | 全PFメトリクス(バッチ) | 300s | 60s |
| GET /api/metrics/{id}/up-down-market | Up/Down市場分析 | 300s | 30s |
| GET /api/benchmark/{ticker} | ベンチマーク(SPY等) | 300s | 30s |
| GET /api/trades/{id} | 取引履歴(limit=500) | 300s | 30s |
| GET /api/monthly-trade/{id} | 月次取引+シグナル(24ヶ月) | 300s | 30s |
| GET /api/annual-returns/{id} | 年次リターン | 300s | 30s |
| GET /api/monthly-returns/{id} | 月次リターン | 300s | 30s |
| GET /api/rolling-returns/{id} | ローリングリターン | 300s | 30s |
| GET /api/drawdowns/{id} | ドローダウン(limit=10) | 300s | 30s |

**認証・権限**:

| エンドポイント | メソッド | 用途 |
|--------------|---------|------|
| /api/admin/login | POST | Adminログイン(Basic Auth) |
| /api/auth/logout | POST | ログアウト |
| /api/auth/verify-viewer | POST | Viewerパスワード検証→トークン発行 |
| /api/viewer-permissions | GET | 非表示ページ一覧取得 |

**Admin操作**:

| エンドポイント | メソッド | 用途 | タイムアウト |
|--------------|---------|------|------------|
| /api/portfolios/get | GET | PF一覧 | 8s |
| /api/portfolios/save | POST | PF保存(差分検出→スマートrecalc) | 600s |
| /api/portfolios/{id} | DELETE | PF削除(FoF参照チェック) | 30s |
| /admin/sync-prices | POST | L0: 価格同期 | 120s |
| /admin/sync-tickers | POST | L1: ティッカー計算 | 300s |
| /admin/sync-standard | POST | L2: Standard PF計算 | 600s |
| /admin/sync-fof | POST | L3: FoF計算 | 900s |
| /admin/recalculate-sync | POST | フルrecalc | 3600s |
| /admin/recalculate-status | GET | recalc進捗 | 5s |
| /admin/db-status | GET | DB健全性 | 8s |

**Viewer権限管理**:

| エンドポイント | メソッド | 用途 |
|--------------|---------|------|
| /api/admin/tiers | GET/POST | ティア一覧/作成 |
| /api/admin/tiers/{id} | PUT/DELETE | ティア更新/削除 |
| /api/admin/tiers/{id}/visibility | GET/PUT | ティア別可視性 |
| /api/admin/tiers/visibility/global | GET/PUT | グローバル可視性 |
| /api/admin/tiers/{id}/rotate | POST | パスワードローテーション |

## §2 認証・権限アーキテクチャ

### §2.1 4層可視性制御

| レベル | 制御対象 | 設定場所 |
|--------|---------|---------|
| L1 | ページ全体の非表示 | Admin Visibility |
| L2 | PF完全非表示 | Admin Visibility |
| L3 | シグナル値のマスク | Admin Visibility |
| L4 | モメンタムコンポーネント非表示 | Admin Visibility |

Adminはバイパス。階層的無効化(L2 ONならL3/L4自動ロック)。

### §2.2 ティアシステム

グローバルデフォルト + ティア別オーバーライド。パスワードローテーション対応。

## §3 lib/ユーティリティ関数カタログ（cmd_256 AC1）

対象: `/mnt/c/Python_app/DM-signal/frontend/lib/`（`types/` と `__tests__/` を除く12ファイル）

### §3.1 export関数/メソッドシグネチャ一覧

#### `lib/chart-utils.ts`

- `getStrokeWidth(range: TimeRange, isPrimary = true, isMobile = false): number`
- `getRollingStrokeWidth(period: RollingPeriod, isPrimary = true, isMobile = false): number`
- `formatDateLabel(dateStr: string | Date, range: TimeRange): string`
- `sliceBenchmarkToPortfolioPeriod<T extends { date: string }>(benchmarkData: T[], startDate: string, endDate: string): T[]`
- `downsampleData<T>(data: T[], maxPoints: number): T[]`
- `findNearestByDate<T extends { date: string }>(data: T[], targetDate: string): T | null`
- `filterDataByYearRange<T extends { date: string }>(data: T[], years: YearRange): T[]`
- `filterDataByFromYear<T extends { date: string }>(data: T[], fromYear: number, durationYears = 3): T[]`
- `getDataStartYear<T extends { date: string }>(data: T[]): number`
- `generateFromYearOptions(minYear: number): FromYear[]`

#### `lib/colors.ts`

- `getPortfolioColor(index: number): string`

#### `lib/lookbackFormatter.ts`

- `formatLookbackShort(period: LookbackPeriod): string`
- `formatLookbackFull(period: LookbackPeriod): string`
- `formatLookbackTooltip(period: LookbackPeriod): string`
- `formatLookbackPeriods(periods: LookbackPeriod[]): string`
- `formatMonthLabel(months: number): string`
- `formatDaysLabel(days: number): string`

#### `lib/fof-validation.ts`

- `buildFoFGraph(portfolios: Portfolio[]): Map<string, Set<string>>`
- `detectCircularReference(fofId: string, newComponents: Set<string>, fofGraph: Map<string, Set<string>>): string[] | null`
- `validateFoFComponents(fofId: string, componentIds: string[], allPortfolios: Portfolio[]): ValidationResult`
- `canSelectComponent(fofId: string, currentComponents: string[], candidateId: string, allPortfolios: Portfolio[]): boolean`
- `canSelectComponentWithGraph(fofId: string, currentComponents: string[], candidateId: string, fofGraph: Map<string, Set<string>>): boolean`
- `getCircularRiskFoFs(fofId: string, currentComponents: string[], candidateFoFs: string[], allPortfolios: Portfolio[]): Set<string>`

#### `lib/portfolio-diff.ts`

- `detectChanges(before: Portfolio[], after: Portfolio[]): ChangeSet`
- `summarizeChanges(changeSet: ChangeSet): string`

#### `lib/utils.ts`

- `cn(...inputs: ClassValue[])`

#### `lib/admin-auth.ts`（`export const adminAuth` の公開メソッド）

- `login(user: string, pass: string): Promise<boolean>`
- `isAuthenticated(): boolean`
- `logout(): Promise<void>`
- `getCredentials(): { user: string; pass: string } | null`

#### `lib/viewer-auth.ts`（`export const viewerAuth` の公開メソッド）

- `saveToken(token: string, expires: string, tier_name?: string): void`
- `parseExpires(expires: string): Date | null`
- `getToken(): string | null`
- `getTierName(): string | null`
- `clearToken(): void`
- `isAuthenticated(): boolean`
- `getExpires(): Date | null`

#### `lib/api-cache.ts`（`export class APICache`）

- `get<T>(key: string): T | null`
- `set<T>(key: string, data: T, ttl = defaultTTL): void`
- `clear(): void`
- `destroy(): void`
- `has(key: string): boolean`
- `getStats(): { size: number; maxSize: number }`

#### `lib/api-client.ts`（`export const api = new ApiClient()` の公開メソッド）

- 認証:
`getStoredCredentials()`, `adminLogin(credentials)`, `logout()`, `testAuth(credentials)`, `verifyViewer(password)`
- Portfolio管理:
`getPortfolios(options?)`, `savePortfolios(request)`, `deletePortfolio(portfolioId)`
- Sync/Backfill:
`runEtl()`, `recalculateHistory(options?)`, `getDbStatus()`, `getRecalculateStatus()`, `syncPrices(days?)`, `syncTickers()`, `syncStandard(options?)`, `syncFof(options?)`, `getSyncStatus()`, `triggerFullBackfill(startYear?)`, `getBackfillStatus()`
- 公開データ取得:
`getSignalsLight()`, `getHistory(portfolioId, days?)`, `getPerformance(portfolioId, years?)`, `getMtd(portfolioId)`, `getBenchmarkPerformance(ticker, years?)`, `getMetrics(portfolioId, years?)`, `getMetricsSummary(years?)`, `getUpDownMarketAnalysis(portfolioId)`, `getAnnualReturns(portfolioId, years?, initialBalance?)`, `getMonthlyReturns(portfolioId, months?, initialBalance?)`, `getRollingReturns(portfolioId)`, `getTrades(portfolioId, tradesLimit?)`, `getMonthlyTrade(portfolioId, limit?)`, `getDrawdowns(portfolioId, limit?)`
- キャッシュ確認:
`hasCached(endpoint)`, `hasHistoryCached(portfolioId, days)`, `hasPerformanceCached(portfolioId, years)`, `hasBenchmarkCached(ticker, years?)`, `hasMetricsCached(portfolioId, years?)`, `hasTradesCached(portfolioId, tradesLimit?)`, `hasAnnualReturnsCached(portfolioId, years?, initialBalance?)`, `hasMonthlyReturnsCached(portfolioId, months?, initialBalance?)`, `hasRollingReturnsCached(portfolioId)`, `hasDrawdownsCached(portfolioId, limit?)`
- Viewer権限:
`getViewerPermissions()`, `updateViewerPermissions(hiddenPages)`
- Tier管理:
`getTiers()`, `createTier(tier)`, `updateTier(tierId, updates)`, `deleteTier(tierId)`, `copyTier(tierId)`, `reorderTiers(tierIds)`, `getTierVisibility(tierId)`, `updateTierVisibility(tierId, settings)`, `getGlobalVisibility()`, `updateGlobalVisibility(settings)`, `rotateTierPassword(tierId, expiresAt?)`, `getAllTierPasswords()`, `rotateAllTierPasswords(expiresAt?)`

#### `lib/constants.ts` / `lib/faq-content.ts`

- export関数なし（定数・型のみ）

### §3.2 データ変換パターン（date / currency / percent）

| 区分 | 実装箇所 | パターン |
|------|---------|---------|
| 日付ラベル変換 | `lib/chart-utils.ts` `formatDateLabel()` | 1M表示は `M/D`、それ以外は `YYYY-MM` |
| 年範囲フィルタ | `lib/chart-utils.ts` `filterDataByYearRange()` / `filterDataByFromYear()` | `Date` からcutoff算出して `date` 文字列比較 |
| 日数↔月数変換 | `lib/lookbackFormatter.ts` | 1M=21営業日換算表で短縮/詳細/tooltip表記を統一 |
| 比率(%)表示 | `lib/lookbackFormatter.ts` `formatLookbackPeriods()` | `weight * 100` を `%` 文字列化 |
| 通貨表示 | `components/summary-table.tsx` | `Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' })` |
| 損益率表示 | `components/*table.tsx`, `components/*chart.tsx` | `value * 100` + `toFixed()` + 符号（`+/-`） |

### §3.3 エラーハンドリングパターン（ErrorBoundary / API失敗表示）

| レイヤー | 実装 | 挙動 |
|---------|------|------|
| レンダリング例外捕捉 | `components/ErrorBoundary.tsx` | `getDerivedStateFromError` + `componentDidCatch` でfallback表示。`Try again`で局所復帰 |
| API呼び出し | `lib/api-client.ts` | `ApiResult`（success/error）で返却。最大2回リトライ、指数バックオフ、Abort timeout、401時セッション整理 |
| 認証失効通知 | `lib/api-client.ts` + `contexts/viewer-permissions-context.tsx` | 401時 `viewer-auth-required` 発火、Provider側で再評価 |
| ページ表示エラー | `app/page.tsx`, `app/dashboard/page.tsx` 他 | `MessageBanner type="error"` で明示表示。チャート失敗時はRetry導線あり |
| Signals初期取得失敗 | `contexts/signals-context.tsx` | `setError("Failed to load signal data.")` をUIへ伝播 |
