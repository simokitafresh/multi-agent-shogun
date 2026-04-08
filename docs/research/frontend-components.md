# DM-signal フロントエンド — コンポーネント・UI詳細
<!-- source: context/dm-signal-frontend.md (cmd_256 佐助補完) -->
<!-- moved: cmd_286 索引化+圧縮 -->

> 索引: `context/dm-signal-frontend.md` → このファイル

## §1 ディレクトリ構造

```
frontend/
├── app/                    # Next.js App Router (18ページ)
│   ├── layout.tsx          # ルートレイアウト (Providers, Sidebar)
│   ├── page.tsx            # ホーム (シグナル + チャート)
│   ├── dashboard/          # MTDフォーカス
│   ├── summary/            # メトリクス概要テーブル
│   ├── metrics/            # 詳細メトリクス + Up/Down分析
│   ├── trades/             # 取引履歴
│   ├── compare/            # マルチPF比較チャート (最大7PF)
│   ├── compare-summary/    # マルチPF比較テーブル
│   ├── monthly-returns/    # 月次リターンヒートマップ
│   ├── annual-returns/     # 年次リターン (棒グラフ+テーブル)
│   ├── monthly-trade/      # 月次リバランス詳細
│   ├── drawdowns/          # ドローダウン分析 (worst 10)
│   ├── rolling-returns/    # ローリングCAGR分析
│   ├── docs/               # Methodology/Terms/Disclosures (静的)
│   ├── faq/                # FAQ + 用語集 (en/jp切替)
│   ├── offline/            # PWAオフラインフォールバック
│   └── admin/              # 管理画面
│       ├── page.tsx        # PF管理 + DB状態 + レイヤー同期
│       ├── fof/            # FoF作成・編集・再計算
│       └── visibility/     # ティア別ページ・PF可視性設定
├── components/             # 65ファイル
│   ├── ui/                 # 汎用UI (13ファイル: button, select, accordion等)
│   ├── chart/              # チャート制御 (9ファイル: Axes, Tooltip, Legend等)
│   ├── docs/               # 静的コンテンツ (3ファイル)
│   └── [ルート]            # ページ固有コンポーネント (35ファイル)
├── contexts/               # React Context (4ファイル)
├── hooks/                  # カスタムフック (6ファイル)
├── lib/                    # ユーティリティ
│   ├── api-client.ts       # APIクライアント (1061行, 核心)
│   ├── api-cache.ts        # TTLキャッシュ (LRU, 100エントリ上限)
│   ├── types/              # 型定義 (9ファイル)
│   ├── colors.ts           # チャートカラーパレット
│   ├── chart-utils.ts      # ダウンサンプリング・フィルタ・フォーマット
│   ├── admin-auth.ts       # Admin認証ヘルパー
│   └── viewer-auth.ts      # Viewer認証ヘルパー
└── public/                 # PWA manifest, アイコン, sw.js
```

## §2 ページ一覧と機能

| ページ | ルート | 主要機能 | データAPI |
|--------|--------|---------|----------|
| Home | `/` | PFセレクタ, モメンタムチャート, トータルリターンチャート, PF詳細 | Performance, History |
| Dashboard | `/dashboard` | シグナルPieChart, MTDチャート+日次テーブル, TRチャート | Performance, MTD |
| Summary | `/summary` | CAGR/Sharpe/Sortino/MDD等メトリクステーブル | Metrics |
| Metrics | `/metrics` | 詳細メトリクス + Up/Down市場分析 | Metrics, UpDownMarket |
| Trades | `/trades` | モデル取引履歴(12件初期) + リスク管理テーブル | Trades |
| Compare | `/compare` | マルチPF比較(最大7PF), log/linearスケール | Performance (各PF) |
| Compare Summary | `/compare-summary` | 全PF横並びメトリクステーブル(バッチAPI) | MetricsSummary |
| Monthly Returns | `/monthly-returns` | 月次リターンヒートマップ(12件初期) | MonthlyReturns |
| Annual Returns | `/annual-returns` | 年次棒グラフ + テーブル(12年初期) | AnnualReturns |
| Monthly Trade | `/monthly-trade` | 月次リバランス詳細(24件初期) | MonthlyTrade |
| Drawdowns | `/drawdowns` | ドローダウンチャート + worst10テーブル | Drawdowns |
| Rolling Returns | `/rolling-returns` | ローリングCAGR(1Y/3Y/5Y/7Y/10Y) | RollingReturns |
| Docs | `/docs` | Methodology/Terms/Disclosures (静的) | なし |
| FAQ | `/faq` | FAQ+用語集(en/jp) | faqContent定数 |
| Admin | `/admin` | PF管理, DB状態, L0-L3レイヤー同期, バルク操作 | Portfolios, DB status |
| Admin FoF | `/admin/fof` | FoF作成/編集/削除/複製/再計算 | Portfolios |
| Admin Visibility | `/admin/visibility` | グローバル+ティア別可視性(L1ページ/L2PF/L3シグナル/L4コンポーネント) | Tiers, Visibility |

## §3 状態管理

### §3.1 Context一覧

| Context | ファイル | 役割 |
|---------|---------|------|
| SignalsContext | `contexts/signals-context.tsx` | 全PFシグナル + 選択PF管理。localStorage+URLパラメータ同期。バックグラウンドprefetch |
| ExecutionTimingContext | `contexts/execution-timing-context.tsx` | OPEN/CLOSE実行タイミング切替。localStorage永続化。デフォルトCLOSE |
| ViewerPermissionsContext | `contexts/viewer-permissions-context.tsx` | Viewer認証+ページ可視性。Admin/Viewer/未認証の3ロール |
| AdminAuthContext | `contexts/admin-auth-context.tsx` | Admin認証+PFリスト。Cookie+localStorage。ログイン時PF自動取得 |

### §3.2 カスタムフック

| フック | ファイル | 役割 |
|--------|---------|------|
| usePrefetch | `hooks/usePrefetch.ts` | PF切替の即時描画のためバックグラウンドデータプリフェッチ。BATCH_SIZE=1, DELAY=500ms |
| useAdminPage | `hooks/useAdminPage.ts` (550行) | Admin画面の状態マシン。楽観更新+ロールバック。差分検出でスマートrecalc |
| useChartInteraction | `hooks/useChartInteraction.ts` | マウス/タッチのツールチップ追跡。RAF最適化+DOMRectキャッシュ |
| useAppVisibility | `hooks/useAppVisibility.ts` | バックグラウンド→フォアグラウンド遷移検知。30秒最小間隔 |
| usePortfolioParam | `hooks/usePortfolioParam.ts` | URLのportfolioパラメータ同期 |
| useSortableTable | `hooks/useSortableTable.ts` | テーブルソート。3クリックサイクル(昇順→降順→クリア) |

### §3.3 データフロー

```
初回ロード:
  RootLayout
  ├─ SignalsProvider → api.getSignalsLight() → キャッシュ(5min)
  │   └─ usePrefetch → 全PFのHistory/Performance/Metricsをバックグラウンド取得
  ├─ ExecutionTimingProvider → localStorage読込
  └─ ViewerPermissionsProvider → Admin/Viewer判定 → api.getViewerPermissions()

PF切替:
  selectPortfolio(newId)
  ├─ Context state更新
  ├─ localStorage + URL更新
  └─ ページコンポーネント useEffect発火
      └─ api.getHistory/Performance/Metrics() → キャッシュヒット(prefetchから)で即描画
```

## §4 コンポーネント分類

### §4.1 チャート (カスタムSVG — PieChart以外)

| コンポーネント | 行数 | 機能 |
|--------------|------|------|
| total-return-chart.tsx | 370+ | 累積リターン(PF vs ベンチマーク), log/linearスケール |
| comparison-chart.tsx | 600+ | マルチPF比較(最大7PF), カラーパレット |
| momentum-chart.tsx | 350 | 絶対/リスクフリーモメンタム, 折り畳み |
| annual-returns-chart.tsx | 450 | 年次棒グラフ(PF vs ベンチマーク並列) |
| rolling-return-chart.tsx | 360 | ローリングCAGR(1Y/3Y/5Y/7Y/10Y) |
| drawdowns-chart.tsx | 200+ | ドローダウン時系列 |
| up-down-market-chart.tsx | 200+ | 上昇/下降市場パフォーマンス |
| mtd-chart.tsx | 312 | MTDパフォーマンス(日次精度) |
| signal-pie-chart.tsx | 137 | シグナル配分(Recharts PieChart) |

### §4.2 テーブル

| コンポーネント | 行数 | 機能 |
|--------------|------|------|
| summary-table.tsx | 300+ | CAGR/Sharpe/Sortino/MDD等 |
| model-trades-table.tsx | 400+ | 取引履歴(12件ページング) |
| monthly-trade-table.tsx | 500+ | 月次リバランス(24件ページング) |
| annual-returns-table.tsx | 400+ | 年次リターン(12年ページング) |
| monthly-returns-table.tsx | 500+ | 月次リターン(12ヶ月ページング) |
| compare-summary-table.tsx | 250+ | マルチPFメトリクス比較 |
| rolling-returns-summary-table.tsx | 350+ | ローリングリターン統計 |
| metrics-table.tsx | 150+ | 詳細メトリクス |
| drawdowns-table.tsx | 150+ | ドローダウン期間 |
| risk-management-table.tsx | 300+ | リスク管理指標 |

### §4.3 チャート制御 (`components/chart/`)

ChartAxes, ChartTooltip, ChartLegend, ChartControls, TimingToggle, ScaleToggle, YearRangeSelector, FromYearSelector, PeriodModeToggle

### §4.4 UI部品 (`components/ui/`)

button(6バリアント), select(ポータル+キーボードナビ), accordion, dropdown-menu, input, glass-card, skeleton, loading, message-banner, page-header, latex, transition-overlay

## §5 デザインシステム

### §5.1 カラー (CSSカスタムプロパティ, 13トークン)

| トークン | Light | Dark |
|---------|-------|------|
| background | Slate 50 (#f8fafc) | Slate 900 (#0f172a) |
| foreground | Slate 900 (#0f172a) | Slate 100 |
| primary | Sky 600 (#0284c7) | Sky 400 (#38bdf8) |
| card | White | Slate 800 |
| success | Emerald 600 | Emerald 400 |
| error | Red 600 | Red 400 |

チャートカラーパレット(7段階): Sky → Emerald → Orange → Violet → Rose → Yellow → Indigo

### §5.2 レスポンシブ

カスタムブレークポイント: `xs`(375px), `sidebar`(1100px), `sidebar-xl`(1280px)
モバイルメニュー: ハンバーガー + トランジション

### §5.3 アニメーション

fade-in(200ms), slide-up(250ms), menu-pop(100ms)

### §5.4 Z-Index

tooltip:10 → floating:30 → sticky:40 → sidebar:50 → modal:60 → notifications:100 → dropdown:9999

## §6 性能最適化パターン

| パターン | 詳細 |
|---------|------|
| 2パスロード | Home/Dashboard/Compare: キャッシュ即表示→バックグラウンド更新 |
| プリフェッチ | 全PFのHistory/Performance/Metricsをバッチ取得(BATCH=1, DELAY=500ms) |
| キャッシュ認識ロード | キャッシュ済みならスピナー非表示 |
| ダウンサンプリング | 大量データを520-1040点に削減(SVGチャート性能) |
| RAF最適化 | チャートインタラクションのrequestAnimationFrame制御 |
| セマフォ | 同時最大2リクエスト(QUIC_TOO_MANY_RTOS防止) |
| メモ化 | useMemo(ソート・計算), memo()(チャートコンポーネント) |
| Static Export | 全ページ事前レンダリング(サーバーサイド不要) |
