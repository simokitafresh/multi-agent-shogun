# DM-signal フロントエンド コンテキスト（索引）
<!-- last_updated: 2026-08-26 T05 shogun doc lane reviewed source boundary (2026-08-26) -->
<!-- source_commit:d87339a4 reason:T05 shogun doc lane reviewed source boundary (2026-08-26) evidence:git -C /mnt/c/Python_app/DM-signal log <marker>..origin/main: core/ops=研究系(cmd_4372-4376)+記事のみ・core/ops知識変更なし; research=cmd_4372/4374/4376は末尾§へ反映済; frontend=frontend/配下変更は08-17 cmd_4324-4333のみで§28反映済、残りはbackend(ops§100反映済)/記事/研究。ローカルcloneはoriginと履歴分岐(同subject別hash)のためorigin/main tipを境界にする -->
<!-- source_commit:55b81b43 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/dm-signal-frontend.md commit=55b81b43 -->
<!-- source_commit:62f0fba0 reason:cmd_karo_hotfix_ga471_context_freshness_202608170345 content reflection evidence:Monthly Trade pending display simplified; source frontend tests and component diff reviewed -->
<!-- source_commit:c22362a9 reason:cmd_4298 reviewed source boundary evidence:SG7 LGTM and Karo ACCEPT; frontend scope one-file commit -->
<!-- source_commit:33ba0d96 reason:cmd_4297 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-frontend.md commit=33ba0d96 -->
<!-- source_commit:21892719 reason:GA-455 content reflection evidence:source frontier review: 3 commits; UI behavior indexed in context §0.1 -->
<!-- source_commit:21e80e30 reason:cmd_karo_hotfix_ga452_context_boundaries_202608100949 content-reflection evidence:source commits 21e80,9f09 reviewed and indexed -->
<!-- source_commit:9b094cff reason:cmd_4278 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-frontend.md commit=9b094cff -->
<!-- source_commit:2e494a5f reason:cmd_4277 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-frontend.md commit=2e494a5f -->
<!-- source_commit:85ef51ec reason:cmd_4257 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-frontend.md commit=85ef51ec -->
<!-- source_commit:16e8a561 reason:cmd_4256 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-frontend.md commit=16e8a561 -->
<!-- source_commit:07b13601 reason:GA-429 source commits since 2026-08-02 evidence:Render live + CDP DM-safe Simple Aug 2026/GLD -->

> 索引層。結論+参照のみ。
> 補足: frontend詳細索引は復旧済み。主要参照は `docs/research/frontend-components.md` / `docs/research/frontend-api-spec.md` / `docs/research/frontend-deploy.md`。
> **速度改善設計書**: `docs/research/fe-speed-improvement-design.md` — 計測データ(cmd_2262)+FE/BEコード分析+改善ロードマップ(§1-§5)。ボトルネック: `/api/signals`が全ページ共通律速(500-700ms)。

## 0.1 GA-455 source frontier review (2026-08-11)
- 一次境界: `/mnt/c/Python_app/DM-Signal` `origin/main=21892719`。cache無効dashboard gateの未反映source commitは **3件**（last_updated=2026-08-10との差異）。source本文・変更pathを照合し、UI仕様として次を反映した。
- `ec418726`（時系列最古）は Monthly Returns の `CONFIRMED` 行からStatusBadgeを除外し、未確定状態だけを表示する。`987c0237` は Monthly Trade のstale/mismatch拒否・fresh再取得・Signals refresh依存を除き、API応答を直接表示する。`21892719`（最新）はDashboardのobsolete holding/next-rebalance cardsと専用component/testを削除する。いずれも表示仕様の変更であり、旧カード・旧確認ラベルを現行UIの正本とみなさない。
- 監査順序（sourceの時系列、旧→新）: `ec418726 -> 987c0237 -> 21892719`。参照path: `frontend/components/monthly-returns-table.tsx`, `frontend/app/monthly-trade/page.tsx`, `frontend/app/dashboard/page.tsx`, `frontend/components/dashboard-holding-slots.tsx`。

パス: `/mnt/c/Python_app/DM-signal/frontend/`

## 0. 技術スタック

| カテゴリ | 技術 |
|---------|------|
| フレームワーク | Next.js 14.2.3 (App Router, Static Export) |
| UI | React 18 + TypeScript 5.4 + Tailwind CSS 3.4 |
| チャート | カスタムSVG (PieChartのみRecharts) |
| テスト | Jest 30 + React Testing Library |
| リンター/フォーマッター | Biome (ESLintから移行, cmd_971) |
| テーマ | next-themes (class方式dark mode) |

UIライブラリなし（全13コンポーネント手製）。
Modern Web Guidance: `skills/modern-web-guidance/SKILL.md`（Google Chrome公式のモダンWeb API/FEベストプラクティス検索スキル。FE作業開始時に参照）

## 1. 構造概要

20ページ / 72コンポーネント(non-test: shared61 + app-scoped11) / 4 Context / 7 Hook / lib 13ファイル

補助参照: `docs/research/frontend-components.md` §1
- L161: Next.js App Router(output=export)のルートディスコンは削除より差し替え+_deprecated退避が安全。nav/hooks/visibilityの同時整合が必要（cmd_527）
- L163: ルートディスコンは『差し替え+_deprecated退避』にすると復活が1コミットで戻せる（cmd_535）
- L189: ページ順序定義をsidebar/mobile-menu/page-navigationに重複保持すると導線不整合が発生しやすい（cmd_564）
- L216: frontend設定参照は next.config.js ではなく next.config.mjs を使え（cmd_719）

## 2. ページ一覧 (2026-07-22 コード確認)

### 稼働ページ(データ表示あり: 12ページ)

| ページ | ルート | データAPI |
|--------|--------|----------|
| Dashboard | `/dashboard` | Performance, MTD |
| Summary | `/summary` | Metrics |
| Compare | `/compare` | Performance (各PF) |
| Compare Summary | `/compare-summary` | MetricsSummary |
| Compare Returns | `/compare-returns` | CompareReturns |
| Metrics | `/metrics` | Metrics, UpDownMarket |
| Annual Returns | `/annual-returns` | AnnualReturns |
| Monthly Returns | `/monthly-returns` | MonthlyReturns |
| Monthly Trade | `/monthly-trade` | MonthlyTrade |
| Rolling Returns | `/rolling-returns` | RollingReturns |
| Drawdowns | `/drawdowns` | Drawdowns |
| Deterioration | `/deterioration` | Deterioration |
| Docs/FAQ | `/docs`, `/faq` | 静的(API参照なし) |

### 封鎖ページ(プレースホルダーのみ: ユーザーにデータ表示なし)

| ページ | ルート | 状態 |
|--------|--------|------|
| Home | `/` | 封鎖中(2026-03-04 e5d7c773)。dashboardへのリンクのみ |
| Trades | `/trades` | 封鎖画面は維持。殿裁定で廃止された`/signals`へのdead hrefを除去し、CTAは正規ホーム導線`/dashboard/`へ修正済み (`cf8da310`) |
| Signals | `/signals` | 殿裁定により独立page廃止確定。Dashboard内Current Signalを正規表示とする (`cf8da310`; `docs/research/dm-signal-page-style-diff-mece_20260722.md`) |

### Admin(認証必須)

| ページ | ルート | データAPI |
|--------|--------|----------|
| Admin | `/admin` | Portfolios, DB status |
| Admin FoF | `/admin/fof` | Portfolios — **WeightBreakdown実装済み**(cmd_1573) |
| Admin Visibility | `/admin/visibility` | Tiers, Visibility。`compare-summary`/`compare-returns` をPAGESに含む |

→ 詳細資料: `docs/research/frontend-components.md` §2
- L162: App Routerのルートディスコンは『ページ差し替え+private folder退避』が復活コスト最小（cmd_527）
- L164: ディスコン復元性はファイル存在確認だけでなく内容ハッシュ一致で検証すると誤判定を防げる（cmd_535）

## 2.5 直近FE変更索引（2026-05-06）

| 対象 | 結論 | 参照 |
|------|------|------|
| Compare Summary UWP | UWP系表示はAvg UWP / PTU(%) / MaxDD UWPの三指標。Total UWPはPTU(%)へ変換、MaxDD UWP未確定値はOngoing表示。 | cmd_2573-2576, cmd_2581; `frontend/app/compare-summary/page.tsx`, `frontend/components/compare-summary-table.tsx`, `frontend/lib/types/compare-summary.ts` |
| Compare Summary benchmark | Compare SummaryにTQQQをSPYと並列の追加ベンチマークとして表示。型はmetrics側にも追加。 | cmd_2578; `frontend/app/compare-summary/page.tsx`, `frontend/lib/types/metrics.ts` |
| Compare loading | `/compare` はchart data loading中もPF選択などの比較コントロールを保持。 | cmd_2569; `frontend/app/compare/page.tsx` |
| Compare Summary standalone BM | ベンチマーク行は`rawBenchmarks`からのみ生成し、PF由来benchmark列へfallbackしない。SPY/TQQQはPF集合・順序に依存しない。 | afe98d64; `frontend/app/compare-summary/summary-data.ts`, `frontend/app/compare-summary/summary-data.test.ts` |
| Compare Summary navigation | 通常PF行のname列は`/summary?portfolio=<uuid>`リンク。BM行は非リンク。クリック時は`selectPortfolio`で選択中PFも同期。 | 57dc3ffe, 34fceb54, 6d0d0e1; `frontend/components/compare-summary-table.tsx`, `frontend/app/compare-summary/page.tsx` |
| Compare Chart Y軸 | D1 LIN桁欠け/D2 LOG 500倍頭打ちを修正。`buildLogTicks`は1-2-5系列を動的生成、巨大倍率ラベルは`kx/Mx`等に圧縮。 | b061d876; `frontend/components/comparison-chart.tsx`, `frontend/components/__tests__/comparison-chart-yaxis.test.tsx` |
| Compare Returns | `/compare-returns`を追加。全PF+standalone benchmarkのMTD/1M/3M/6M/1Y/3Y/5Y/ALL比較テーブル、API client/SWR/prefetch/nav/admin visibility連携を持つ。 | 46e1b48c, 21901642; `frontend/app/compare-returns/page.tsx`, `frontend/app/compare-returns/returns-data.ts`, `frontend/components/compare-returns-table.tsx`, `frontend/lib/types/compare-returns.ts`, `frontend/lib/api-client.ts` |
| Drawdowns | all drawdowns表示変更(cmd_2571)は同日revert済み。現行Drawdowns/API/FAQはrevert後挙動を正とする。 | ab5eac9d → 1aa09525; `frontend/app/drawdowns/page.tsx`, `frontend/lib/api-client.ts`, `frontend/lib/faq-content.ts` |

- L654: FE設計書§2はcmd更新時に陳腐化。diff確認をAC化すべき（cmd_2297）
- L655: FE設計書§2陳腐化(L654と同根)（cmd_2297）

## 2.6 直近FE変更索引（2026-05-07〜05-27）

| 対象 | 結論 | 参照 |
|------|------|------|
| Monthly Trade FoF mask/display | masked monthly trade表示を修正。FoF ticker/weight表示はprecomputed weightsと月初Signal由来のdisplay_ticker_weightsを優先 | cmd_2451, cmd_2598; `frontend/components/monthly-trade-table.tsx`, `frontend/lib/monthly-trade-display.ts` |
| Auth token cleanup | count-based eviction削除により、viewer/admin tokenは期限切れのみcleanup。FE側でtoken数上限前提の挙動を置かない | cmd_2599; `backend/app/auth.py` |
| Home holiday awareness | 封鎖中Homeにも市場休日認識を追加。`date-fns`依存追加済み | cmd_2880; `frontend/app/page.tsx`, `frontend/package.json` |
| Admin backfill year | AdvancedOperationsのfull backfill開始年は`FULL_BACKFILL_START_YEAR=2000`に統一 | cmd_3077; `frontend/app/admin/components/AdvancedOperations.tsx` |

## 2.7 直近FE変更索引（2026-06-11）

| 対象 | 結論 | 参照 |
|------|------|------|
| 未使用FE成果物削除 | `_deprecated/signal`, `_deprecated/trades`, `transition-overlay`, `useAppVisibility`, `lookbackFormatter`と関連testを削除。`frontend/package.json`/lockも整理済み。Monthly Trade FoF表示維持コミットは同日revert済みで、現行表示仕様は§2.6のprecomputed weights/月初Signal優先を正とする | e0b59782, 0adde79f→8d28f75e; `frontend/_INDEX.md`, `frontend/package.json`, `frontend/lib/monthly-trade-display.ts` |

## 2.8 直近FE変更索引（2026-06-12）

| 対象 | 結論 | 参照 |
|------|------|------|
| Admin PF編集整理 | Active Status UIとmomentum method selectorを削除。Portfolio型/API差分処理も対応済みで、FE側にActive Status/momentum method入力前提を置かない | 9be200cd, 3d4255bf, 36e6137a; `frontend/app/admin/page.tsx`, `frontend/app/admin/components/PortfolioEditor.tsx`, `frontend/app/admin/components/LookbackEditor.tsx`, `frontend/lib/types/portfolio.ts`, `frontend/lib/portfolio-diff.ts` |
| Frontend lint/type整理 | Next/Biome lint baselineを有効化し、api-client response型を`frontend/lib/types/api.ts`へ抽出。admin/fof周辺はformat正規化済み | 138fe43d, 663b3354, b293806f; `frontend/.eslintrc.json`, `frontend/next.config.mjs`, `frontend/lib/api-client.ts`, `frontend/lib/types/api.ts`, `frontend/hooks/useAdminPage.ts`, `frontend/app/admin/fof/components/WeightBreakdown.tsx` |
| Dashboard MTD表示 | MTDチャートにas-of labelを追加し、MTD Daily Tableへdesktop-only daily columnsを追加。確定値計算ではなく表示層の精度・明示性改善 | 0ed68575, c530b4b3; `frontend/app/dashboard/page.tsx`, `frontend/components/mtd-chart.tsx`, `frontend/components/mtd-daily-table.tsx`, `frontend/lib/mtd-as-of-label.ts`, `frontend/lib/types/market.ts` |
| Metrics/Compare Summary表示 | MetricsのUp/Down Market chartはmobile横スクロールからviewport内に収まるbin統合へ変更。Compare SummaryのAvg UWPは小数第1位表示 | 46c50462, 509ed49b, 36e39ae3; `frontend/components/up-down-market-chart.tsx`, `frontend/components/compare-summary-table.tsx`, `frontend/lib/types/compare-summary.ts` |

## 2.9 直近FE変更索引（2026-06-25〜06-26）

| 対象 | 結論 | 参照 |
|------|------|------|
| Compare Summary / Deterioration benchmark | SPY/TQQQのP_det benchmark表示とpage_visibility enforcementを追加。Compare Summary/Deteriorationの型とsummary dataにbenchmark行前提あり | 59146c43; `frontend/app/compare-summary/page.tsx`, `frontend/app/compare-summary/summary-data.ts`, `frontend/app/deterioration/page.tsx`, `frontend/components/compare-summary-table.tsx`, `frontend/lib/types/compare-summary.ts`, `frontend/lib/types/deterioration.ts` |
| Compare Summary benchmark standalone | Compare SummaryのSPY/TQQQ benchmark行は`rawBenchmarks`のみから生成する。PF側`metricsMap.*.benchmark`列へのfallbackは禁止で、folder/PF順序変更によりbenchmark-SPY行が変動してはならない | cmd_3548 / afe98d64; `frontend/app/compare-summary/summary-data.ts`, `frontend/app/compare-summary/summary-data.test.ts`, `docs/spec/compare-summary-benchmark-row-period-instability-fix.md` |
| Metrics continuity risk | Metrics/Summary tableにcontinuity risk系指標を追加。Docs termsも対応済み | eaf2741d; `frontend/components/metrics-table.tsx`, `frontend/components/summary-table.tsx`, `frontend/lib/types/metrics.ts`, `frontend/components/docs/terms-content.tsx` |

## 2.10 直近FE変更索引（2026-06-27〜07-01）

| 対象 | 結論 | 参照 |
|------|------|------|
| PWA SWR cache | Service Worker cacheは`dm-signal-v10`。SWR API cacheはTTL 1時間で、`/api/compare-returns`/`/api/metrics/summary`から全12系統のSWR対象APIへ拡張済み。TTL内はcache即返却+background revalidate、TTL切れはnetwork first+cache fallback | 5713ec7d, 70332d29, 8911448e; `frontend/public/sw.js` |
| Compare table layout | Compare Summary / Compare ReturnsのPortfolio列はmobile 160px / desktop 200pxに固定し、tableをshrink-to-fitへ変更。行高は`py-3`で統一 | bab41462; `frontend/components/compare-summary-table.tsx`, `frontend/components/compare-returns-table.tsx` |
| Page header help UI | Dashboard / Compare Summary / Compare Returns / Deteriorationのheader内HelpLinkは削除済み。Sidebar/mobile-menuのDocs/FAQ navは維持 | fad5887b; `frontend/app/dashboard/page.tsx`, `frontend/app/compare-summary/page.tsx`, `frontend/app/compare-returns/page.tsx`, `frontend/app/deterioration/page.tsx`, `frontend/components/help-link.tsx` |
| Rolling Returns table periods | Rolling Returns summary tableは`3_months`/`6_months`/`1_year`/`2_years`/`3_years`/`5_years`/`7_years`/`10_years`順。chart側ではなくtable表示期間の拡張 | 86348160; `frontend/components/rolling-returns-summary-table.tsx`, `frontend/components/__tests__/rolling_returns_summary_open_toggle.test.tsx` |
| Compare Summary table header | Compare Summary table headerをtable内sticky化。横スクロール中の列ラベル視認性を改善 | eafa53df; `frontend/components/compare-summary-table.tsx` |
| Compare Summary sticky計測 | 非同期データ投入・loading解除・表示列変更後にもtable高を再計測し、page-sticky headerの位置を現DOMへ追従させる | 155ab5e0; `frontend/components/compare-summary-table.tsx` |
| Compare Chart benchmark dropdown | Compare Chartのbenchmark selectorにPFのbenchmark_tickerに依らない追加候補TQQQを常時合流。defaultはSPY優先を維持 | 099ccf20; `frontend/app/compare/page.tsx`, `frontend/app/compare/__tests__/benchmark-options.test.tsx` |

## 2.11 直近FE変更索引（2026-07-06）

| 対象 | 結論 | 参照 |
|------|------|------|
| Monthly Trade ledger badge | Monthly TradeのPosition表示は`signal_decision_ledger`優先。`decision_source`/`decided_at`/`is_correction`をAPI型へ追加し、既存Positionセル内に確定/訂正/確定前バッジ(UI表示: Confirmed/Corrected/Pending)を1個表示。Next SignalはPreview表示を持ち、日々変動が正常な未確定値として扱う | cmd_3706 / 99edb79b; `backend/app/api/monthly_trade.py`, `backend/app/services/monthly_trade_impl.py`, `frontend/components/monthly-trade-table.tsx`, `frontend/lib/types/api.ts` |
| Monthly Trade historical badge | `signal_decision_ledger`最古`effective_start_date`より前の月は`decision_source=historical`として暗黙確定表示(✓ Historical)。ledger開始後でledger行なしの月は従来通りPending。historical導入後は`precomputed_raw.endpoint='monthly_trade'`の無効化/再生成が必要 | cmd_3710 / f4f17af9; `backend/app/services/signal_decision_ledger.py`, `backend/app/services/monthly_trade_impl.py`, `frontend/components/monthly-trade-table.tsx` |

## 2.12 FoF表示cache鮮度修正（2026-08-01）

| 対象 | 結論 | 参照 |
|------|------|------|
| Dashboard / Monthly Trade | `/api/signals`はsignal更新時刻より古いrawを拒否し、Monthly Tradeの`fresh:true`はAPI cacheを実際に迂回する。本番CDPで対象FoFのDashboard=`GLD 78.1% / XLU 21.9%`、Monthly Trade 2026-08=`XLU 22% / GLD 78%`、旧Cash/raw UUID=0を確認 | e2b3d19e, 48c6bbfa; `frontend/lib/api-client.ts`, `backend/app/api/signals.py`, `backend/app/jobs/precompute_raw.py`; `/tmp/dm_signal_dashboard_fof_after_20260801.png`, `/tmp/dm_signal_monthly_trade_fof_after_20260801.png` |

## 3. 状態管理

4 Context: Signals(PF選択+prefetch), ExecutionTiming(OPEN/CLOSE), ViewerPermissions(3ロール), AdminAuth(Cookie+PFリスト)
7 Hook: usePrefetch, useAdminPage(550行), useChartInteraction, useAppVisibility, usePortfolioParam, useSortableTable, useIsMobile

データフロー: SignalsProvider(SWR: stale即表示+BG fresh fetch, cmd_765)→prefetch(selected PFのみ, budget=2, cmd_733)→IndexedDB+メモリ2層キャッシュ→PF切替即描画。次PFのprefetchは不在(cmd_2264設計書§3.3)。ナビゲーションは`window.location.href`統一=hard navigation→SignalsProvider毎回再初期化→`/api/signals`が全遷移の律速(cmd_2264設計書§3.2)

PF切替計測実績(CDP): 547.2ms中央値(cmd_2312, 2026-04-26)。旧1008ms(cmd_2304固定待機込み)比45.7%改善。フェーズ分解476ms(cmd_2307)比15%遅い。

→ 詳細資料: `docs/research/frontend-components.md` §3, §5
- L201: useEffectの依存配列にstate変数を含めると意図しないタイミングでeffectが発火する（cmd_642）
- L266: prefetchとpage effectに同一endpoint群を持たせるとorchestration重複とstate update重複が残る（cmd_831）

## 4. APIクライアント

`lib/api-client.ts` (1121行)。TTLキャッシュ(`/api/signals`=60min, 他=5min/LRU100)、セマフォ(`RequestSemaphore(4)`)、リトライ(2回/指数バックオフ)、AbortController(8s)。current-page prefetch budget=2。SWR対象: signals/mtd/performance/metrics/monthly-returns/annual-returns/monthly-trade/rolling-returns/drawdowns/deterioration/p-average(cmd_2264設計書§1.2)。
認証: Admin(Cookie+BasicAuth) / Viewer(Bearerトークン)。401→セッションクリア+イベント発火。

補助参照: `docs/research/frontend-api-spec.md` §1, §2
- L159: SignalsProvider層で障害判定すると全ページ一括でフォールバック制御できる（cmd_526）
- L181: DeteriorationページのAPIレスポンスにはfolder_idが含まれないためuseSignalsのportfoliosから別途マップ構築が必要（cmd_555）
- L204: API永続キャッシュはUI state用localStorageと分離し、auth-scope付きIndexedDBを主格にすべき（cmd_646）
- L228: api-client.tsが304をエラー扱い→既存ETag実装3件が実質無効（cmd_748）
- L229: SWR化はcache hit迂回fresh fetch経路が必要（cmd_748）
- L263: persistent data cacheにvalidatorを永続化しないとwarm reloadはfull refetchに崩れる（cmd_830）
- L267: etagStoreにdataを持たせるとapiCacheと二重保持でRAM倍増する（cmd_831）
- L272: IndexedDB非同期参照はSWRバックグラウンドrevalidationのタイミングを遅延させる（cmd_847）
- L326: slice後件数をtotal_monthsに使うとFEが全件ロード済みと誤認する（cmd_1003）
- L340: apiCache.has()はETag送信前のガード条件に最適（cmd_1011）

## 5. コンポーネント

チャート9種(カスタムSVG)、テーブル10種、チャート制御9種、UI部品13種。

→ 詳細資料: `docs/research/frontend-components.md` §4
**Phase2a FE共通化(cmd_784-787)**: formatJST→lib/date.ts共通化(10ファイル, cmd_784) / FolderFilterChip→ui/folder-filter-chip.tsx(4→1, cmd_785) / PersistentFolderFilter hook(multi+single, cmd_787) / PageShell(7ページshell共通化, cmd_787)。合計~600行削減。
- L182: FolderFilterChipがcompare-summaryとdeteriorationで完全重複しており共通コンポーネント抽出候補（cmd_555）→ **cmd_785で解消済み**
- L183: 同一UI改修を複数ページへ展開する際は状態モデル(Set/OR条件/Clear操作)を同一化するとレビュー密度が上がる（cmd_556）
- L185: テーブル列定義をSSOT(COLUMNS)で管理しておくと要件変更4点の同時反映が安全になる（cmd_557）
- L187: ジェネリックソートフックのnull処理は方向別(multiplier)との合成結果まで検証する（cmd_569）
- L191: TypeScript列追加時はtsc --noEmitでユニオンキー添字安全性を検証すべき（cmd_613）
- L192: レビューではUI挙動確認に加えて型系ユニオン拡張の添字安全性まで検査すべき（cmd_613）
- L245: フォルダフィルタ共通化は状態モデル(multi/single)を揃えてから抽出せよ（cmd_783）
- L277: 履歴グラフUIは時系列snapshot蓄積と取得窓の両方が揃わないと単月表示へ退化する（cmd_859）
- L280: 入替推奨UIは候補(candidate)語彙+連続月数条件+Progressive Disclosureで設計せよ（cmd_859）
- L719: FE表示名変更時は新名優先+旧名fallbackを同時実装せよ（cmd_karo_direct_fe_ptu_fix）
- L786: ComparisonChart Y軸は純粋関数抽出+動的生成で構造的解消（cmd_3565）
- L792: スワイプ除外はbutton全体でなくハンドル領域に限定せよ（cmd_3592）

## 6. デザインシステム

13色CSSトークン(Light/Dark)。チャート7色パレット。ブレークポイント: xs(375)/sidebar(1100)/sidebar-xl(1280)。
**A軸第3層完遂(cmd_4119)**: body=`text-sm text-foreground`、caption/note=`text-xs text-muted-foreground`、numeric=`font-mono text-sm tabular-nums`へ役割別token化。正当なcaptionのxsは維持し、数値桁揃えを全end-user表示へ適用。→ `docs/research/cmd_4119_body_numeric_inventory.md`
**A軸h1 DRY完遂(cmd_4117)**: 12ページ・14分岐のcanonical h1直書きを`PAGE_TITLE_CLASS` 1定義へ集約し、文言・DOM・配置を不変維持。→ `docs/research/cmd_4117_h1_dry_inventory.md`
**B軸B1完遂(cmd_4120)**: status text shadeを`STATUS_TEXT_CLASSES`へSSOT化（positive=`emerald-400`、negative=`red-400`、warning=`amber-400`、neutral=`muted-foreground`）。非正準13件→0件。→ `docs/research/cmd_4120_status_color_inventory.md`
- L284: 統計指標UIは信号機パターン(3色+灰)+Progressive Disclosure 3層。7±2超えは判断麻痺（cmd_860）
- L287: 確率値の単独表示は過信誘発。頻度リフレーミングを添えよ（cmd_860）
- L292: 統計指標UIの解釈可能性設計3原則（cmd_860）

→ 詳細資料: `docs/research/frontend-components.md` §4, `docs/research/frontend-deploy.md` §0

## 7. 認証・権限

4層可視性: L1(ページ), L2(PF), L3(シグナル), L4(コンポーネント)。Admin=バイパス。ティアシステム(グローバル+オーバーライド)。

→ 詳細資料: `docs/research/frontend-api-spec.md` §2.2, §2.4, §3
- L160: DM-signalの認証はin-memory token store方式。サーバー再起動(Renderデプロイ含む)で全セッション無効化（cmd_527）
- L226: Admin isCheckingAuth guardを!isAuthenticatedより後に置くと認証復元中にLoginModal誤表示（cmd_753）
- L227: HttpOnly cookie authをlocalStorage booleanで同期代替するとpublic UIにstale authが残る（cmd_753）
- L796: 同一タブlocalStorage認証変更はstorage eventで検知できない（cmd_3641）

## 8. 性能最適化

2パスロード / プリフェッチ / ダウンサンプリング(520-1040点) / RAF / セマフォ(4並列) / メモ化 / Static Export

**SPA遷移最終結論(cmd_644/654)**: Render Static Siteでnext/link SPA遷移は8回試行全て本番失敗→断念。3導線(sidebar/dropdown-menu/page-navigation)はwindow.location.hrefに復帰(cmd_654)。IndexedDB永続化(api-cache.ts + idb-keyval 2層キャッシュ)は維持(cmd_647)。
**prefetch縮退(cmd_733)**: 初期ロード83本一斉prefetch→selected PF用3本(mtd, performance(3), performance(0))に縮退。残りはオンデマンド取得。
**SWR化(cmd_765)**: clearSignalsCache()毎回呼出を廃止→stale-while-revalidate導入。キャッシュ即表示(stale)+BGでfresh fetch。初回ロード2-5秒空白画面を解消。admin操作後のみcache invalidation。
**バンドル最適化**: katex CSS→docsのみ(cmd_741, -27KB) / signal-pie-chart dynamic import(cmd_742, recharts~280KB排除) / date-fns除去+lucide optimizePackageImports+MtdChart/MtdDailyTable dynamic import(cmd_786, -12~20kB gzip)。
**request storm分析(cmd_783)**: prefetchは10N+3本(N=PF数)でO(N)スケーリング。route gate+request budget導入が次の課題。
**Next.js高速化知見**: バンドル分析+dynamic import(完了) → optimizePackageImports(完了) → Next.js 16アップグレード(React 19必須, 未着手)
**signals handoff/cache実装(cmd_2283)**: SignalsContextにhandoff cacheを追加。PF切替/ページ遷移時の初期表示データ引き継ぎを担う。→ `frontend/contexts/signals-context.tsx`, `frontend/lib/__tests__/constants.test.ts`
**next-portfolio predictive prefetch(cmd_2300)**: usePrefetchで次PF予測prefetchを計測・実装。SignalsContext/usePrefetchのテストを拡張。→ `frontend/hooks/usePrefetch.ts`, `frontend/contexts/signals-context.tsx`
**idle fetch defer(cmd_2308)**: dashboard/monthly-returns/annual-returnsのfull fetchをidle schedulerへ遅延。初期表示優先のため`frontend/lib/idle-scheduler.ts`を追加。→ `frontend/app/dashboard/page.tsx`, `frontend/app/monthly-returns/page.tsx`, `frontend/app/annual-returns/page.tsx`
**Lighthouse全ページ計測(cmd_3647)**: 本番FE 11ページをLighthouse 12.8.2 desktopで計測。平均Performance 98.5、最頻出対策は unused-javascript 11/11ページ 推定約8.3MB、legacy-javascript 11/11ページ 推定約122KB、TBT/Speed Index 11/11ページ。次cmd入力は影響度順対策候補として `docs/research/cmd_3647_lighthouse/report.md`、機械集計は `docs/research/cmd_3647_lighthouse/summary.json`。
**Monthly Returns prefetch fanout対策(cmd_3650)**: `/monthly-returns` はPAGE_APISを空にし、近隣PF prefetchも無効化。ページ本体のquick→idle full fetchをSSOTにしてmobile計測TBT 7274→320ms、SI 11447→4083ms。ローカルstatic export+Render backend計測のため、本番デプロイ後絶対値とmobile原票manifest保存は後続確認対象。
- L650: perf_measure.pyはviewer認証専用。admin計測にはCDPプリフライト手順か別スクリプトが必要（cmd_2271）
- L656: 固定待機排除はDOMポーリングで行う（cmd_2310）

**本番ベースライン計測(cmd_719+720)**: /dashboard First Load JS 238kB(最重量)。最遅API=monthly-returns 1721.5ms/62.7KB。キャッシュヒット率85-90%。偵察時に記載された「Renderコールドスタート15s+」は、backend が `plan: pro` のため本件では誤認。
完了済み施策: SignalsContext useMemo化(cmd_740) / katex CSS→docs移動(cmd_741) / signal-pie-chart dynamic import(cmd_742) / prefetch縮退83→3本(cmd_733) / uvicorn workers 2→revert→再投入(cmd_743/751/763) / SWR化(cmd_765) / date-fns除去+lucide optimize+MtdChart dynamic import(cmd_786) / ETag FE対応(cmd_760) / 401連鎖崩壊修正(cmd_758) / Phase2a共通化4件(cmd_784-787)。
- L265: Next.js App Router output:exportでもclient-side routingは動作する（cmd_831）
- L270: Portal内shared navのclient-side routingは遷移開始より先に閉じるなを絶対条件にせよ（cmd_832）
- L333: FoF UUID生値を含む/api/signals cacheは壊れたpayloadとみなしfresh再取得へ倒す（cmd_1006）
改善Top3(未完了): (1)`/api/monthly-returns`最適化(1721ms, cmd_775取組中) (2)route gate+request budget導入(cmd_783指摘) (3)N+1クエリ最適化(cmd_764調査済み)
→ `docs/research/cmd_719_720_performance-baseline.md`

→ 詳細資料: `docs/research/frontend-components.md` §5, `docs/research/frontend-api-spec.md` §4
- L188: window.location遷移を採用する構成ではContext単独の状態共有は永続化要件を満たさない（cmd_570）
- L195: Static Exportのビルド成果物を実際に確認してから原理的制約を主張せよ（cmd_638）
- L196: Static Exportの回帰調査では局所実績とplatform原理の議論を分離して検証する（cmd_638）
- L197: Static Export SPA遷移はホスティングサービスの.txt配信挙動に依存する（cmd_639）
- L198: Static Export + custom SW構成ではroute flight(index.txt/_rsc)を明示bypassせよ（cmd_639）
- L200: Portal内のnext/linkはクリック中に自己アンマウントさせるとSPA遷移がキャンセルされる（cmd_642）
- L203: SWのAPIバイパス設定がキャッシュ永続化の阻害要因（cmd_646）
- L205: SW SWRとContent-Type書き換えは同一sw.js更新で統合可能（cmd_646）
- L206: prefetchキャッシュキー不一致はprefetch戦略の致命的バグ（cmd_666）
- L207: years=0 prefetch追加単独では本番9秒級遅延は解消しない（cmd_670）
- L208: Tier分離は設計書だけでは維持されず、prefetch即時対象の逆流で初動性能が崩れる（cmd_681）
- L209: warm cache計測はSPA遷移とhard reloadを分離しないとAPI本数が歪む（cmd_681）
- L210: CDP awaitPromise=trueの長時間非同期JSは空応答を返す(fire-and-forget+pollingで回避)（cmd_676）
- L211: 本番CDP検証ではviewer認証を先に確立してから計測せよ（cmd_686）
- L212: CDP性能計測ではtiming計測前に正常画面かを先に検査すべき（cmd_686）
- L213: 本番CDP検証ではviewer認証未確立のまま開くとUnauthorized shellになりAPI観測0本で誤判定する（cmd_686）
- L214: CDP性能計測の前提確認では timing より先に『正常画面か』を検査すべき（cmd_686）
- L215: 本番viewer認証の自動化ではrepo内.envよりRender live envを優先せよ（cmd_695）
- L217: 全PF全API prefetchは selected PF 表示経路と同じ転送路を塞ぎ、軽量入口APIの直後に性能を崩す（cmd_720）
- L219: 静的ホスト切替だけでは本番UXの主因は消えず、heavy APIが残る限り backend 待ちが支配する（cmd_728）
- L220: CDP計測のwait_for_readyがダッシュボードAPI応答遅延で恒常的にタイムアウトする（cmd_725）
- L221: CDP計測の `spa` は実ナビゲーション実装と一致させ、hard reload と別ラベルで報告せよ（cmd_737）
- L222: summarize_runs()のfloat出力をshell整数比較に渡す時はint変換必須（cmd_737）
- L244: usePrefetch request stormは10N+3本。route gate+request budget導入が先決（cmd_783）
- L247: 全PFプリフェッチは1PFあたり約10API自動発火でrequest storm化する（cmd_783）
- L248: グローバルProviderのroute非依存prefetchは別ページでAPIファンアウト再発する（cmd_783）

- L651: cdp_measure.sh curl CDP check: WSL2でcurlがWindowsローカルポートに接続不可（cmd_2288）
- L653: cdp_measure baseline比較は生成JSONへの統合確認を必須にする（cmd_2291）
- L798: 重いページはPAGE_APIS prefetchを空にしページ本体fetchをSSOTにする（cmd_3650）
- L801: App Router共通chunkはmodule分割だけではhash不変 — 初期レンダー計算量削減が正道（cmd_3659）

## 9. PWA・テスト・デプロイ

PWA: manifest + SW(dm-signal-v8) + オフラインページ。CacheFirst(static) / NetworkOnly(API)。
テスト: 29ファイル / 5 FAIL, 24 PASS / Lines 71.4% / **現状テスト未完了**
- L193: 公開FAQ/Docsの最終レビューではadmin/owner文言をgrepで機械検査する（cmd_618）
- L199: Next.js buildのpages-manifest欠落はstale .nextを疑ってから回帰判定せよ（cmd_639）
- L218: SPA遷移化の完了宣言とコード実態の乖離（cmd_728）
- L224: full Jestではapi-client singletonのpendingRequestsがtest間に残留しうる（cmd_742）
- L230: api-client/api-cache importするJestではcleanup intervalを明示停止必須（cmd_758）
- L231: 大フック/大APIクライアントはhelper testだけでは保守性劣化を防げない（cmd_762）
- L243: Static Export buildがcleanup失敗でも.next manifestは先に生成されることがある（cmd_774）
- L251: Jest 30では--testPathPatternが廃止され--testPathPatternsへ置換が必要（cmd_792）
- L300: バッチ手法追加は新バッチ並走が安全（cmd_861）
- L253: Next.js大バージョンアップではpeer dep対応が最大リスク変数（cmd_807）
- L309: static export(output:'export')アプリでは\<Link\>SPA遷移を使うな — window.location.hrefで統一せよ（cmd_886）
i18n: EN/JPの2言語のみ(FAQページ)。本格フレームワーク未導入。
SEO: グローバルmetadataのみ。OG/robots.txt/sitemap未実装。
環境変数: `NEXT_PUBLIC_API_HOST`(APIベースURL), `NODE_ENV`(ログ制御)の2つのみ。

→ 補助参照: `docs/research/frontend-deploy.md` §2-§4
→ 補助参照: `docs/research/cmd_485_dm-signal-environment-catalog.md` AC2-3（環境変数の広域カタログ）

## 10. lib関数カタログ

12ファイル(types/test除外)。chart-utils(10関数), colors(1), lookbackFormatter(6), fof-validation(6), portfolio-diff(2), utils(1), admin-auth(4), viewer-auth(7), api-cache(6), api-client(50+メソッド)。

→ 詳細資料: `docs/research/frontend-api-spec.md` §2, §4

## 11. PFフォルダー機能 (cmd_283)

実装済み。3 subtask: API(folder_id追加) + Admin画面(CRUD 611行) + PFセレクタ(グループ表示)。
10ページでフォルダーグループ化適用。未分類PFはUncategorized末尾。DB書き込みなし。
フィルタリング方式: ドロップダウン内フィルター（コンポーネント内完結、PD-032殿裁定）。

→ 詳細資料: `docs/research/frontend-components.md` §2, §4 / `docs/research/frontend-api-spec.md` §2.4

## 11.5 Visibility表示不具合修正 (cmd_298, PD-033)

cmd_295 Phase1の全tier hide_portfolio=trueがGlobal変更をブロックしていた不具合。
修正: 全TierのTierVisibilitySettings.portfolio_settingsを空dict化(DB操作)。_safe_json_field防御も同時追加。
- L702: FoF UUID漏れはFEキャッシュだけでなくAPI display fallbackも検証する（cmd_2451）
- L704: FoF Monthly Trade表示は動的展開よりprecomputed weightsを優先せよ（cmd_2452）
- L705: Monthly Trade FoF表示はyear_month月初Signalのdisplay_ticker_weightsを優先参照（cmd_2453）

## 11.6 Visibility vis_L2/L3/L4 MECEマトリクス (cmd_2596)

全13API×vis_L2/L3/L4マスク対象のMECE一覧+FoF signal展開マスク+FE追加マスク+未実装5API特定。
→ `docs/research/cmd_2596_visibility_matrix.md`

## 11.7 Visibility UI監査 — CDP全ページスクショ+要素判定 (cmd_2597)

本番FE 14ページ×(standard+FoF)=28スクショ+UI要素signal/component二値判定。
→ `docs/research/cmd_2597_visibility_ui_audit.md` / CDPスクショ: `outputs/cdp/cmd_2597/`

## 12. Frontend関連教訓

L122(キャッシュ無効化), L121(API実コード確認) → `context/dm-signal-ops.md` 教訓索引に記載済み
- （L340は§4 APIクライアントへ振り分け済）
- （L650/L651/L653/L656→§8性能最適化、L654/L655→§2.5、L702/L704/L705→§11.5、L719→§5に振り分け済み 2026-06-16）
- （L786/L792→§5、L796→§7、L798/L801→§8に振り分け済み 2026-07-16）
- （L804/L850/L858/L873/L878/L880→ops/core、L861→research、L865/L867/L868/L890/L902→infraに振り分け済み 2026-07-16）
<!-- last_synced_lesson: L1585 -->
- L906: lint修正時もmasked表示のkey一意性を保持する（cmd_4116）
- L907: 共有style定数化では既存formatter debtを先に分離する（cmd_4117）
- L910: mobile表は文字列列を先に圧縮し数値列をnowrap固定する（cmd_4139）
- L911: 表示分類はラベル文字列でなくDOM軸を現読する（cmd_4141）
- L912: cancel済みeffectは共有phase遷移前に停止する（cmd_4145）
- L913: Tailwind罫線監査はliteral tokenでなくcomputed styleまで測る（cmd_karo_hotfix_compare_border_slate200_20260724）
- L914: overflow-x-autoは縦stickyの中立祖先ではない（cmd_karo_hotfix_three_tables_page_sticky_20260724）
- L915: 文字列一致contract testはsource変更commitのscope外だと静かに陳腐化する（cmd_karo_hotfix_n2_deterioration_sticky_20260724）
- L919: logical flushの前処理はphysical chunk外で1回化する（cmd_karo_hotfix_fullrecalc_deferred_flush_extreme_runtime_ready_20260729）
- L924: 非支配的最適化撤回がimmutable artifact契約を破壊（cmd_karo_hotfix_dm_signal_l3_monthly_restore_20260801）
- L925: TTLだけではsource更新後のartifact鮮度を保証できない（cmd_karo_hotfix_dm_signal_dashboard_fof_stale_cash_20260801）
- L926: canonical移行時は旧contract assertionも同一scopeで更新する（cmd_karo_hotfix_dm_signal_market_type_ui_batch_n_20260801）
- L927: 横scrollportとpage-sticky headerは同一要素階層で両立しない（cmd_4209）
- L930: ledger欠落と未確定を同じNoneで扱うと確定済み期間がsilent fallbackする（cmd_karo_recon_cagr_drop_20260802_recon2）
- L936: 共有worktreeでは検証直後もHEAD世代をcommit helperで再検証する（cmd_karo_goal_b2e_guard_mode）
- L944: 未開始判定は欠落判定より先行させる（cmd_karo_recon_cx_unstarted_contract_20260803）
- L1545: invalidationはcommit後single-flight再生成へ接続する（cmd_4241）
- L1546: 偵察正本の群数記載と列挙数の不一致（cmd_4242）
- L1585: Unique as-of keys defeat memoization-only fallback optimization（cmd_karo_hotfix_fallback_prod_key_rc_202608110401）

## 13. 2026-03 holding表示バグ (cmd_499)

結論: monthly PFの計算値は正しいが、Signalページのcurrent signal表示が`as_of`依存で月替わりpending投影を持たず、2026-03-02時点で2月保有表示が起きうる。

→ 詳細: `docs/research/cmd_499_march-holding-signal-validation.md` §6

## 14. cmd_494 monthly pending表示整合修正

結論: `/api/signals` に monthly向け月替わりpending投影（`signal_pending`含む）を追加し、frontend Current Signalへ`Pending Rebalance`表示を反映。non-monthly挙動は維持。

→ 詳細: `docs/research/cmd_494_signal-pending-display-fix.md`

## 15. cmd_3839/cmd_3787 FE側変更 (2026-07-09〜10、GA-238で反映)

結論: (1) cmd_3839 admin visibility folder非表示(L1.5)の全閲覧EP適用に伴い、`frontend/app/admin/visibility/page.tsx`へ楽観ロック+FE tier切替時の未保存編集ガードを追加(`frontend/lib/types/tiers.ts`型更新含む)。(2) cmd_3787 monthly trade fail-closed化に伴い、`frontend/lib/types/api.ts`へ`missing_tickers`フィールドを追加。両方ともbackend側の主変更は`context/dm-signal-ops.md` §63.1/§63.2 と `context/dm-signal-core.md`(cmd_3787行)に既に反映済みであり、本節はFE側の変更箇所のみを索引する(重複記載を避ける)。

→ 詳細: `context/dm-signal-ops.md` §63.1/§63.2、`/mnt/c/Python_app/DM-signal/docs/research/cmd_3839_folder_hide_rollout.md`、`/mnt/c/Python_app/DM-signal/docs/research/cmd_3787_monthly_trade_missing_ticker_fail_closed.md`

## 16. cmd_4114 Rolling Returns distribution Phase 1 (2026-07-22、GA-314で反映)

結論: `/rolling-returns` にDistribution表を追加し、chartへ中央値・P10・0%基準線・best/worst window表示を追加。API型へmedian/P10/positive rate/sample count/best-worst期間を追加した。境界後一次差分は1 commit、FE 4 paths、+603/-112行。

→ 実装: `/mnt/c/Python_app/DM-signal/frontend/app/rolling-returns/page.tsx`、`/mnt/c/Python_app/DM-signal/frontend/components/rolling-return-chart.tsx`、`/mnt/c/Python_app/DM-signal/frontend/components/rolling-returns-distribution-table.tsx`、`/mnt/c/Python_app/DM-signal/frontend/lib/types/api.ts`

## 17. cmd_4116 A軸第2層 section heading統一 (2026-07-22)

結論: 全h2/h3をコード現読で88/88抽出し、section-heading 57/57を `text-lg font-semibold text-foreground` へ統一。sub-label・意味色status-label・エディタ/モーダル等の役割外見出しは保持した。

→ 詳細: `/mnt/c/Python_app/DM-signal/docs/research/cmd_4116_a2_heading_inventory.md`

## 18. cmd_4122 A4数値表統一 (2026-07-22)

結論: 数値表示13/13表を `font-mono tabular-nums`、符号状態色を `getValueColorClass` SSOTへ統一し、font未適用表を4→0へ解消。→ `/mnt/c/Python_app/DM-signal/docs/research/cmd_4122_table_text_inventory.md`

## 20. cmd_4127 表フォント14px統一 (2026-07-23)

結論: 表フォントcanonicalは本体14px・数値`ui-monospace tabular-nums`・文字Inter・ヘッダ14px。方向矢印はアイコン役割として18pxを維持。→ `docs/research/cmd_4127_font_unify_result.md`

## 21. cmd_4128 Up vs. Down Market表の残存是正 (2026-07-23)

結論: `up-down-market-chart`の数値28セルもcanonical mono/14pxへ統一し、文字ラベルInterを維持。コード側の表フォント統一は全数完了し、本番CDP逸脱0証明は将軍の出口責務。→ `docs/research/cmd_4128_updown_font_result.md`

## 19. cmd_4124 値配色の基準復旧 (2026-07-23)

結論: 値の色は正値=`text-foreground`（lightは黒寄り、darkは白）、負値=`text-red-400`（両モード）。フォント種類・サイズはlight/dark共通で不変。→ `/mnt/c/Python_app/DM-signal/docs/research/cmd_4124_color_baseline_restore.md`

## 22. cmd_4153 admin UI全数偵察 (2026-07-24)

結論: admin 4ルート・17 TSX全数調査。一覧性低下根因=FoFカード縦積み/DB Status collapsed default/folders全collapsed/modal退避。改善提案5案 (FoF→table canonical/DB Status展開default/split-view編集/nav compact/folders全展開) を5要件形式で記載。→ `docs/research/admin-ui-redesign-asis-tobe-5w1h_20260724.md`

## 23. N2/N5 モバイルsticky根治+rolling列幅統一 (2026-07-24 殿実機確認済)

結論(N2): 全行展開3長大表(compare-returns/compare-summary/deterioration)のモバイルtierは、ラッパーを非スクロールコンテナ化(overflow visible/visible)してth sticky top:0をviewport追従させる。**overflow-y-clipは無効**(CSS仕様: 片軸clipは他軸auto/scroll併用時hiddenへ計算される)。commit=60a69234(compare系2表)+6f03e892(deterioration。60a69234はdeterioration変更0件=「兼用」想定誤りが差戻し根因)。検証=将軍CDP mobile 412×915でthTop=0全数+殿実機確認(19:10/19:41)。

結論(N5): rolling-returnsのSummary Statistics/Distribution 2表はtable-fixed+colgroupで列幅統一(Roll Period=151px・データ列156px)。外形幅が同一でも列幅配分差は「幅が違う」と見える。commit=3c23d0d4。検証=将軍CDP両表全列幅同一+殿実機確認(19:10)。

→ 経緯全量: `docs/research/dm-signal-page-style-diff-mece_20260722.md` v3.0(§RETRO/§PLAYBOOK付き完成版、gist c50699ea)

## 24. Monthly Trade 当月保有行・Simple Month列 (2026-08-04、本番確認済)

結論: Monthly Tradeはリバランス発生有無によらず当月のcanonical `holding_signal`を先頭行へ表示する。SWRの5分キャッシュに当月行が欠ける場合は表示可能な応答とみなさず再取得し、Simple表示でもMonth列を常時表示する。frontend commit=`07b13601`、backend commit=`a1111735`。本番CDPでDM-safeの先頭行=`Aug 2026 / GLD / Pending`、Month header/cell=`table-cell`、loading=0、error=falseを確認。

→ 実装: `/mnt/c/Python_app/DM-signal/frontend/lib/monthly-trade-display.ts`、`/mnt/c/Python_app/DM-signal/frontend/components/monthly-trade-table.tsx`
→ 本番証跡: `/tmp/dm-signal-monthly-trade-after-07b13601.png`

## §25 Monthly Trade stale cacheとDashboard同期 (2026-08-04)

- `9f09b128` はFoF Monthly Tradeのcurrent-month holdingをDashboardの`selectedPortfolio.signal`と正規化比較し、raw UUID混入またはholding不一致のcached responseを表示せずfresh再取得へ回す。freshでも不一致なら表示をnullにしてstale値を露出しない。参照: `frontend/app/monthly-trade/page.tsx`, `frontend/lib/monthly-trade-display.ts`, `frontend/lib/__tests__/monthly-trade-display.test.ts`、commit `9f09b128`。
- `21e80e30` はfresh responseが表示妥当ならholding不一致でも先に表示し、`SignalsProvider`のstableな`refresh()`でDashboard signalsをbackground再取得する。これによりMonthly Tradeを古い信号へ戻さず、両表示を再同期する。参照: `frontend/app/monthly-trade/page.tsx`, `frontend/contexts/signals-context.tsx`、commit `21e80e30`。

## 26. Admin Visibility両面実測 (cmd_4299, 2026-08-13)

結論: `/admin/visibility`は本番CDPで全開scrollHeight=`6556px`・全閉=`980px`、PF行=`54.33–54.67px`、folder header=`40px`、viewport内PF完全表示=`2行`（交差=`3行`）だった。`collapsedFolders`はReact stateのみでSave永続化経路はコード上0件。→ `docs/research/admin-ui-redesign-asis-tobe-5w1h_20260724.md` §5

## 27. Monthly Trade pending表示の現行境界 (cmd_4324, 2026-08-17)

結論: `MonthlyTradeTable` はdeprecatedなNext Signal panelとdecision-sourceバッジ（Confirmed/Corrected/Historical/Pending）を描画せず、行単位のpending indicatorと指定列のopacityだけで未確定状態を示す。FoFのticker/weight表示とraw UUID非露出は維持する。参照: `frontend/components/monthly-trade-table.tsx`, `frontend/components/__tests__/monthly_trade_table_fof_uuid.test.tsx`、source commit `62f0fba0`。

## 28. ログイン境界 第0段 live+是正2件 (cmd_4325-4327/4332/4333, 2026-08-17)

結論: 認証は`/login`ルート境界(`components/route-access-boundary.tsx`)で切替、認証主体が変わる瞬間に7層(React state/handoff sessionStorage/localStorage/api-cache+ETag IndexedDB/SW CacheStorage)をハードリセット(`resetAuthScopedClientState`)、キャッシュキーとBE ETag/Cache-Controlに主体(tier/admin)を含める(no-store)。adminは`/admin/login`のみ(一般UIからリンクなし)。是正: 文言=「パスワードもしくはクーポンコード」(cmd_4332)、`/admin`配下は認証後protectedツリー(Provider内)で描画(cmd_4333、useViewerPermissions Provider外例外の根治)。殿確認14:28 OK。origin/main `55b81b43` FE live。第1段(identity/entitlement)は殿合図待ち。
→ 正本 `docs/research/dm-login-boundary-asis-tobe_20260817.md`(gist 0d23e0c3)
