# DM-Signal フロントエンド性能ベースライン
<!-- cmd: cmd_719(領域分割偵察) + cmd_720(GSD式偵察) | date: 2026-03-10 | integrated: cmd_722 -->

> 8名の偵察報告を統合した恒久ドキュメント。
> cmd_719: sasuke(バンドル), hayate(API応答), hanzo(API依存マップ), kotaro(キャッシュ)
> cmd_720: tobisaru(UX), hayate(データフロー), kagemaru(コード構造), hanzo(インフラ) + karo統合

---

## §1 計測ベースライン（cmd_719 定量データ）

### §1.1 バンドルサイズ上位モジュール（sasuke報告）

| チャンク | raw | gzip | 内容 | 共有ルート数 |
|---------|-----|------|------|------------|
| 8756 | 375.4kB | 109.4kB | recharts, date-fns, decimal.js-light, redux, immer | 17 |
| d3ac728e | 268.5kB | 77.0kB | katex | docs dynamic chunk |
| fd9d1056 | 172.8kB | 53.7kB | (共通) | 21 |
| framework | 141.0kB | 45.3kB | React framework | 全ルート |
| 7023 | 123.8kB | 31.8kB | (共通) | 全ルート |
| main | 111.0kB | 32.4kB | Next.js main | 全ルート |
| polyfills | 91.4kB | 31.2kB | polyfills | 全ルート |
| faq/page | 63.3kB | 21.0kB | FAQページ固有 | 1 |
| admin/page | 52.1kB | 12.4kB | Adminページ固有 | 1 |
| admin/fof/page | 45.7kB | 10.8kB | Admin FoFページ固有 | 1 |

**ページ別 First Load JS（next build出力）**:

| ページ | First Load JS | 備考 |
|--------|--------------|------|
| /dashboard | 238kB | 最重量。chunk 8756(recharts)含む |
| /admin | 138kB | |
| /faq | 128kB | |
| /admin/visibility | 127kB | |
| /admin/fof | 127kB | |
| /deterioration | 127kB | |
| shared by all | 87.5kB | chunk 7023(31.7kB) + fd9d1056(53.6kB) + other(2.16kB) |

**ページ別 総アセットサイズ（JS + CSS, gzip）**:

| ページ | JS gzip | CSS gzip |
|--------|---------|----------|
| /dashboard | 278.7kB | 13.6kB |
| /admin | 182.5kB | 13.6kB |
| /admin/visibility | 171.8kB | 13.6kB |
| /admin/fof | 171.3kB | 13.6kB |
| /faq | 170.2kB | 13.6kB |
| /deterioration | 166.8kB | 13.6kB |
| /compare-summary | 165.0kB | 13.6kB |
| /rolling-returns | 162.4kB | 13.6kB |
| /drawdowns | 161.6kB | 13.6kB |
| /annual-returns | 160.4kB | 13.6kB |

**Dynamic import現状**: TotalReturnChart, ComparisonChart, docs内コンテンツ(Methodology/Terms等)の3箇所。
**Dynamic import候補**: signal-pie-chart(recharts含む), admin LoginModal/PortfolioEditor等, ManageTiersModal。

### §1.2 API応答時間（hayate報告 — 本番viewer計測, 各5回中央値）

| エンドポイント | 中央値(ms) | payload | 備考 |
|-------------|-----------|---------|------|
| GET /api/viewer-permissions | 171.8 | 19B | 最軽量 |
| GET /api/metrics/{id}?years=0 | 183.2 | 7.6KB | |
| GET /api/metrics/summary?years=0 | 202.6 | 58.5KB | 8PF×42metrics一括 |
| GET /api/performance/{id}?years=0 | 203.8 | 50.6KB | 231 points |
| GET /api/history/{id}?days=3650 | 268.1 | 272.6KB | 2512 points。転送最大 |
| GET /api/signals | 284.9 | 3.4KB | 全ページ基盤 |
| GET /api/monthly-returns/{id}?years=10 | 1721.5 | 62.7KB | **最遅**。120行×複数フィールド |

計測対象PF: `DM-safe` (`45eb0c3a-a256-48f3-b3e3-d2a9d5c3bbfa`)。
admin-only `/api/portfolios/get` はviewer 401のためスキップ。

**over-fetching所見**:
- `/api/monthly-returns`: 120ヶ月分に`tickers`, `tickers_open`, `expanded_tickers`, `trading_days`, `partial_note`まで含む。最遅API
- `/api/history`: 2512 points / 272.6KBと最重量。初期表示には不要
- `/api/performance`: 各pointに`signal`と`raw_signal`が重複。片方不使用の画面では圧縮余地
- `/api/metrics/summary`: 8PF×42metricsの一括。Compare Summary用としては妥当だが他ページからのprefetchは無駄

### §1.3 ページ別API依存マップ（hanzo報告）

**グローバル基盤（layout.tsx — 全ページ共通）**:
- SignalsProvider: GET /api/signals (マウント時即座, TTL 1h, timeout 5s)
- ViewerPermissionsProvider: GET /api/viewer/permissions (マウント時)
- signals成功後→`prefetchAll()` 4段階プリフェッチ発火

| ページ | 直接API | 合計 | チェーン深度 | クリティカルパス |
|--------|---------|------|------------|--------------|
| / | 0 | 0 | 0 | なし(静的) |
| /dashboard | 4 | 6 | 2 | SignalsCtx→performance(3yr)→チャート表示 |
| /compare-summary | 2 | 4 | 2 | SignalsCtx→metricsSummary→テーブル表示 |
| /deterioration | 1+N | 3+N | 1 | deterioration list→テーブル(SignalsCtx非依存) |

/dashboardのクリティカルパス: signals→performance(3yr)の直列2段。D1完了後にD3/D5/D6が並列発行。
2-pass loading(3yr即表示→全期間後追い)でUX最適化済み。

### §1.4 キャッシュ戦略（kotaro報告）

**3層構成**:

| 層 | 実装 | 特徴 |
|----|------|------|
| L1 | Memory Map | max 1000エントリ, 60秒ごとcleanup |
| L2 | IndexedDB (idb-keyval) | dm-signal-api-cache, ブラウザ再起動後も存続 |
| L3 | pendingRequests Map | 同一endpoint同時リクエストDedup |

**キャッシュキー**: `{scope}::{endpoint}` — scope = admin/viewer:{tier}/unauth。パラメータ違い=別キー。

**TTL**: /api/signals=60min(ただし`clearSignalsCache()`で実質毎回再取得), 他15種=5min統一。`APICache.defaultTTL`(30min)は未使用。

**プリフェッチ4段階**:

| Tier | タイミング | 対象 | API本数 |
|------|----------|------|---------|
| Tier1 | 即時 | 選択PF Dashboard必須 | 3 (mtd, perf3yr, perf全) |
| Tier1Extra | 1.5秒遅延 | 選択PF 他ページ用 | 8 (history, metrics, perf20yr, monthly-returns等) |
| Tier3 | Tier1と並行 | グローバル | 2 (metricsSummary, deteriorationList) |
| 全PFバッチ | Tier1完了後 | 全PF | 10本/PF, batch=3, delay=200ms, Semaphore=4 |

**キャッシュヒット率**:
- 選択PF→他ページ遷移: 11/13 ≈ 85%（ミス: Metrics years=0 vs prefetch years=10, Summary同様）
- PF切替後Dashboard: 9/10 = 90%（ミス: performance(0)が全PFバッチに未含）

**教訓解消状況**: L206(prefetchキーミス)=解消, L207(Semaphore競合)=解消, L208(Tier1肥大化)=解消。

**残存GAP**:
- GAP-1(low): Metrics/Summary years=0 vs prefetch years=10 不一致→ネットワークfetch発生
- GAP-2(low): 全PFバッチにperformance(0)欠損→PF切替時Dashboard再fetch

---

## §2 GSD式統合所見（cmd_720 karo統合）

### §2.1 一致点（複数観点で合意: 高確信度）

| # | ボトルネック | 合意観点 | 概要 |
|---|-----------|---------|------|
| 1 | Renderコールドスタート | UX+Data+Infra (3/4) | 初回15-30秒+白画面。signals timeout=5sでリトライ→最悪90秒。COLD_LOAD_WAIT=15s(CDP計測値) |
| 2 | prefetch fan-out | UX+Data+Code (3/4) | signals成功後に83本候補化(8PF×10API+Tier1+global)。Semaphore=4で21wave相当 |
| 3 | recharts+katexバンドル | UX+Code (2/4+) | 375KB+268KB=643KB(gzip ~190KB)が不要ページでもDL対象。katex CSSは全ページに27KB注入 |

### §2.2 相違点

**改善優先1位の分岐**:
- UX+Infra: コールドスタート対策(healthz ping cron)
- Code: SignalsContext useMemo化(5行変更)
- Data flow: prefetch縮退(fan-out 83本の大半をカット)
→ 実装コスト順: useMemo(5行) < katex CSS移動(1行) < healthz ping(cron追加) < prefetch縮退(中規模)

**指標の単位差異**: UX=体感秒, Data=リクエスト本数/payload, Code=再レンダー回数/バンドルKB, Infra=RTT/ワーカー数/プール数

### §2.3 盲点（単一観点でのみ発見: GSD式の真価）

| 発見 | 発見観点 | 効果 | 工数 | 備考 |
|------|---------|------|------|------|
| SignalsContext value useMemo欠如 | Code | 高(全13ページ再レンダー防止) | 極低(5行) | **最小コスト最大効果** |
| ETag未実装API(signals, performance等) | Infra | 低-中(304で帯域節約) | 中 | 3/20+APIのみ実装済み |
| uvicorn 1ワーカー | Infra | 中(同時処理倍増) | 極低(--workers 2) | Render Pro RAM内で2-3可能 |
| clearSignalsCache()キャッシュ無効化 | UX+Data | 中(stale-while-revalidate化) | 中 | IndexedDB永続キャッシュの価値回復 |
| Dashboard 3 useEffect→7+再レンダーサイクル | Code | 中(描画サイクル削減) | 中 | Promise.all+バッチsetState |

### §2.4 統合改善優先順位（7項目 — 効果×実装コスト）

| # | 改善策 | 効果 | 工数 | 合意度 | 根拠 |
|---|-------|------|------|--------|------|
| 1 | SignalsContext value useMemo化 | 高 | 極低(5行) | 1/4 | selectedPortfolio+value毎レンダー新規生成→全ツリー再描画 |
| 2 | katex CSS→docs配下移動 | 高 | 極低(1行) | 2/4 | layout.tsxのglobal import除去で全ページ-27KB CSS |
| 3 | コールドスタート対策(healthz ping) | 高 | 低 | 3/4 | Render cronで5-10分間隔ping。初回15s→<1s |
| 4 | signal-pie-chart dynamic import化 | 高 | 低(3行) | 2/4 | recharts~280KBを初期バンドルから排除 |
| 5 | prefetch fan-out縮退 | 最大 | 中 | 3/4 | prefetchAllPortfolios()をidle/hover起動に変更 |
| 6 | uvicorn --workers 2 | 中 | 極低 | 1/4 | render.yaml 1行変更。同時処理能力倍増 |
| 7 | stale-while-revalidate化 | 中 | 中 | 2/4 | clearSignalsCache除去→キャッシュ即表示+バックグラウンド更新 |

---

## §3 方式比較（領域分割 vs GSD式）

### §3.1 各方式の発見内容

| 観点 | cmd_719（領域分割） | cmd_720（GSD式） |
|------|------------------|----------------|
| 発見の性質 | **定量データ**: 数値・テーブル・ヒット率 | **構造的洞察**: ボトルネック因果・盲点・優先順位 |
| バンドル | 全チャンクのraw/gzip数値、ルート別First Load JS | rechartsは1箇所のみ使用、katex CSSはdocs限定→分離可能 |
| API | エンドポイント別ms/KB（5回中央値） | monthly-returns最遅の原因=120行×多フィールド、history最重量の原因=日次全走査 |
| キャッシュ | 3層構成、TTL一覧、ヒット率85-90% | clearSignalsCacheが永続キャッシュ価値を毀損、fan-out 83本の内訳 |
| ページ構造 | API依存マップ（テーブル形式） | SignalsContext useMemo欠如→全ツリー再描画（Codeのみ発見） |
| インフラ | — | uvicorn 1ワーカー、ETag 3/20+のみ、コールドスタート15s |

### §3.2 有用性の比較

**領域分割の強み**:
- ベースライン数値の網羅性。改善前後の比較に不可欠
- 異なる計測対象を並列に調査できるため効率的
- 数値の客観性が高く、恣意的な判断が入りにくい

**GSD式の強み**:
- 盲点の発見力。useMemo欠如はCode観点のみの発見で最小コスト最大効果
- 同一テーマの多角分析により一致点の確信度が高い
- 改善優先順位の根拠が厚い（複数観点の合意度で重み付け）

**GSD式でなければ見逃していた可能性が高い発見**:
1. SignalsContext useMemo欠如（Code観点のみ）
2. uvicorn 1ワーカー問題（Infra観点のみ）
3. clearSignalsCacheのキャッシュ価値毀損（UX+Data観点の交差）

### §3.3 今後の偵察方式選択への示唆

| 目的 | 推奨方式 | 理由 |
|------|---------|------|
| 改善前のベースライン取得 | 領域分割 | 定量データの網羅性が必要 |
| ボトルネック特定・優先順位決定 | GSD式 | 盲点発見と合意度評価が優位 |
| 改善後の効果検証 | 領域分割 | 同一計測手法での前後比較 |
| 未知領域の初回調査 | **水平+垂直同時投入** | 定量データ(水平)+盲点炙り出し(垂直)の両方が必要 |

**結論**: 水平(領域分割)だけでは盲点を見落とし、垂直(GSD式)だけでは定量データが薄い。cmd_719+720の同時投入が改善優先順位の確度を最大化した。

---

## §4 インフラ構成サマリー（hanzo cmd_720報告より）

| 層 | サービス | プラン | リージョン |
|----|---------|-------|----------|
| FE | Static Site (Next.js export) | static | CDN配信 |
| BE | FastAPI + uvicorn | pro | singapore |
| DB | PostgreSQL | basic-1gb | singapore |
| Cron | 5ジョブ | cron | singapore |

**主要設定値**:

| 項目 | 値 | ソース |
|------|-----|--------|
| uvicorn workers | 1 (デフォルト) | render.yaml |
| DB pool_size / max_overflow | 5 / 10 | database.py |
| FE Semaphore | 4 | api-client.ts L239 |
| Prefetch batch/delay | 3 / 200ms | usePrefetch.ts |
| API cache TTL | 30分 | api-cache.ts |
| signals timeout | 5000ms | api-client.ts L893 |
| GZip minimum_size | 1000B | main.py L143 |
| Rate limit (general) | 60/min | 各API route |
| ETag対応 | 3/20+ API | monthly_returns, annual_returns, monthly_trade |
| preconnect hint | あり | layout.tsx L43-44 |
| Service Worker API | Network Only | sw.js L82 |
| SW Static Assets | Cache First | sw.js |

---

## §5 データフロー詳細（hayate cmd_720報告より）

**ボトルネックTop3（データフロー観点）**:

1. **signals後の全PF prefetch fan-out**: signals(3.4KB)成功→83本候補化→Semaphore=4で21wave。Contextがnetwork fan-outの起爆点
2. **heavy payload APIのeager取得**: monthly-returns(62.7KB/1721.5ms), history(272.6KB/268.1ms)を初期表示不要でもprefetch
3. **selected PFのcritical pathとbackground prefetchが同一pipe共有**: high/low priorityはqueue順のみ。running中のlow requestを追い出せない

**改善案**: (1)全PF prefetchをidle/hover起動に縮退 → (2)heavy payload APIのeager取得停止 → (3)selected PF用reserved slot設置

---

## §6 コード構造詳細（kagemaru cmd_720報告より）

**ボトルネックTop3（コード構造観点）**:

1. **SignalsContext value useMemo未使用**: signals-context.tsx L151, L204-213。selectedPortfolioが`signals?.portfolios.find()`でレンダーごと計算。valueも毎レンダー新規生成。全13ページ+sidebar+GlobalErrorBanner+ViewerAuthModalが影響
2. **recharts(~280KB)+katex(~300KB+CSS27KB)バンドル肥大化**: recharts使用はsignal-pie-chart.tsx 1箇所のみ。katex CSSはlayout.tsx L12で全ページglobal import
3. **Dashboard 3並列useEffect→7+再レンダーサイクル**: performance 2-pass(4回) + MTD(2回) + deterioration(1回)

**数値根拠**: コンポーネント46ファイル/8166行、ページ13、Context 4、useSignals消費者15箇所、既存dynamic import 8箇所、memo/useMemo/useCallback 108箇所/18ファイル
