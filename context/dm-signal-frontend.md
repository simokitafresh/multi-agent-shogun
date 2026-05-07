# DM-signal フロントエンド コンテキスト（索引）
<!-- last_updated: 2026-05-06 cmd_karo_direct_context_refresh: Compare Summary UWP/PTU/TQQQ+loading改善+4/26 FE性能変更索引追記 -->

> 索引層。結論+参照のみ。
> 補足: frontend詳細索引は復旧済み。主要参照は `docs/research/frontend-components.md` / `docs/research/frontend-api-spec.md` / `docs/research/frontend-deploy.md`。
> **速度改善設計書**: `docs/research/fe-speed-improvement-design.md` — 計測データ(cmd_2262)+FE/BEコード分析+改善ロードマップ(§1-§5)。ボトルネック: `/api/signals`が全ページ共通律速(500-700ms)。

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

## 1. 構造概要

19ページ / 71コンポーネント(non-test: shared60 + app-scoped11) / 4 Context / 7 Hook / lib 12ファイル

補助参照: `docs/research/frontend-components.md` §1
- L161: Next.js App Router(output=export)のルートディスコンは削除より差し替え+_deprecated退避が安全。nav/hooks/visibilityの同時整合が必要（cmd_527）
- L163: ルートディスコンは『差し替え+_deprecated退避』にすると復活が1コミットで戻せる（cmd_535）
- L189: ページ順序定義をsidebar/mobile-menu/page-navigationに重複保持すると導線不整合が発生しやすい（cmd_564）
- L216: frontend設定参照は next.config.js ではなく next.config.mjs を使え（cmd_719）

## 2. ページ一覧 (2026-05-07 コード確認)

### 稼働ページ(データ表示あり: 12ページ)

| ページ | ルート | データAPI |
|--------|--------|----------|
| Dashboard | `/dashboard` | Performance, MTD |
| Summary | `/summary` | Metrics |
| Compare | `/compare` | Performance (各PF) |
| Compare Summary | `/compare-summary` | MetricsSummary |
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
| Trades | `/trades` | 封鎖中(2026-03-04 e5d7c773 discontinue trades page)。signalsページへのリンクのみ。既知: `docs/future-01/004.md` L194, `docs/research/fe-speed-improvement-design.md` L14 |
| Signals | `/signals` | ルート不在(ディレクトリなし) |

### Admin(認証必須)

| ページ | ルート | データAPI |
|--------|--------|----------|
| Admin | `/admin` | Portfolios, DB status |
| Admin FoF | `/admin/fof` | Portfolios — **WeightBreakdown実装済み**(cmd_1573) |
| Admin Visibility | `/admin/visibility` | Tiers, Visibility |

→ 詳細資料: `docs/research/frontend-components.md` §2
- L162: App Routerのルートディスコンは『ページ差し替え+private folder退避』が復活コスト最小（cmd_527）
- L164: ディスコン復元性はファイル存在確認だけでなく内容ハッシュ一致で検証すると誤判定を防げる（cmd_535）

## 2.5 直近FE変更索引（2026-05-06）

| 対象 | 結論 | 参照 |
|------|------|------|
| Compare Summary UWP | UWP系表示はAvg UWP / PTU(%) / MaxDD UWPの三指標。Total UWPはPTU(%)へ変換、MaxDD UWP未確定値はOngoing表示。 | cmd_2573-2576, cmd_2581; `frontend/app/compare-summary/page.tsx`, `frontend/components/compare-summary-table.tsx`, `frontend/lib/types/compare-summary.ts` |
| Compare Summary benchmark | Compare SummaryにTQQQをSPYと並列の追加ベンチマークとして表示。型はmetrics側にも追加。 | cmd_2578; `frontend/app/compare-summary/page.tsx`, `frontend/lib/types/metrics.ts` |
| Compare loading | `/compare` はchart data loading中もPF選択などの比較コントロールを保持。 | cmd_2569; `frontend/app/compare/page.tsx` |
| Drawdowns | all drawdowns表示変更(cmd_2571)は同日revert済み。現行Drawdowns/API/FAQはrevert後挙動を正とする。 | ab5eac9d → 1aa09525; `frontend/app/drawdowns/page.tsx`, `frontend/lib/api-client.ts`, `frontend/lib/faq-content.ts` |

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

## 6. デザインシステム

13色CSSトークン(Light/Dark)。チャート7色パレット。ブレークポイント: xs(375)/sidebar(1100)/sidebar-xl(1280)。
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

## 11.6 Visibility vis_L2/L3/L4 MECEマトリクス (cmd_2596)

全13API×vis_L2/L3/L4マスク対象のMECE一覧+FoF signal展開マスク+FE追加マスク+未実装5API特定。
→ `docs/research/cmd_2596_visibility_matrix.md`

## 12. Frontend関連教訓

L122(キャッシュ無効化), L121(API実コード確認) → `context/dm-signal-ops.md` 教訓索引に記載済み
- （L340は§4 APIクライアントへ振り分け済）
- L650: perf_measure.pyはviewer認証専用。admin計測にはCDPプリフライト手順か別スクリプトが必要（cmd_2271）
- L651: cdp_measure.sh curl CDP check: WSL2でcurlがWindowsローカルポートに接続不可（cmd_2288）
- L653: cdp_measure baseline比較は生成JSONへの統合確認を必須にする（cmd_2291）
- L654: FE設計書§2計測セクションはcmd更新時に陳腐化。diff確認をAC化すべき（cmd_2297）
- L655: FE設計書§2陳腐化(L654と同根)（cmd_2297）
- L656: 計測スクリプトの固定待機排除はDOMポーリングで行う（cmd_2310）
- L702: FoF UUID漏れはFEキャッシュだけでなくAPI display fallbackも検証する（cmd_2451）
- L704: FoF Monthly Trade表示は動的展開よりprecomputed weightsを優先せよ（cmd_2452）
- L705: Monthly Trade FoF表示はyear_month月初Signalのdisplay_ticker_weightsを優先参照（cmd_2453）
- L719: FE表示名変更時は新名優先+旧名fallbackを同時実装せよ（cmd_karo_direct_fe_ptu_fix）

## 13. 2026-03 holding表示バグ (cmd_499)

結論: monthly PFの計算値は正しいが、Signalページのcurrent signal表示が`as_of`依存で月替わりpending投影を持たず、2026-03-02時点で2月保有表示が起きうる。

→ 詳細: `docs/research/cmd_499_march-holding-signal-validation.md` §6

## 14. cmd_494 monthly pending表示整合修正

結論: `/api/signals` に monthly向け月替わりpending投影（`signal_pending`含む）を追加し、frontend Current Signalへ`Pending Rebalance`表示を反映。non-monthly挙動は維持。

→ 詳細: `docs/research/cmd_494_signal-pending-display-fix.md`
