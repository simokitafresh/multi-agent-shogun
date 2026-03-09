# DM-signal フロントエンド コンテキスト（索引）
<!-- last_updated: 2026-03-03 cmd_503 frontend知識復旧3ファイル再作成 -->

> 索引層。結論+参照のみ。
> 補足: frontend詳細索引は復旧済み。主要参照は `docs/research/frontend-components.md` / `docs/research/frontend-api-spec.md` / `docs/research/frontend-deploy.md`。

パス: `/mnt/c/Python_app/DM-signal/frontend/`

## 0. 技術スタック

| カテゴリ | 技術 |
|---------|------|
| フレームワーク | Next.js 14.2.3 (App Router, Static Export) |
| UI | React 18 + TypeScript 5.4 + Tailwind CSS 3.4 |
| チャート | カスタムSVG (PieChartのみRecharts) |
| テスト | Jest 30 + React Testing Library |
| テーマ | next-themes (class方式dark mode) |

UIライブラリなし（全13コンポーネント手製）。

## 1. 構造概要

19ページ / 71コンポーネント(non-test: shared60 + app-scoped11) / 4 Context / 7 Hook / lib 12ファイル

補助参照: `docs/research/frontend-components.md` §1
- L161: Next.js App Router(output=export)のルートディスコンは削除より差し替え+_deprecated退避が安全。nav/hooks/visibilityの同時整合が必要（cmd_527）
- L163: ルートディスコンは『差し替え+_deprecated退避』にすると復活が1コミットで戻せる（cmd_535）
- L189: ページ順序定義をsidebar/mobile-menu/page-navigationに重複保持すると導線不整合が発生しやすい（cmd_564）

## 2. ページ一覧

| ページ | ルート | データAPI |
|--------|--------|----------|
| Home | `/` | Performance, History |
| Dashboard | `/dashboard` | Performance, MTD |
| Summary | `/summary` | Metrics |
| Metrics | `/metrics` | Metrics, UpDownMarket |
| Trades | `/trades` | Trades |
| Compare | `/compare` | Performance (各PF) |
| Compare Summary | `/compare-summary` | MetricsSummary |
| Monthly Returns | `/monthly-returns` | MonthlyReturns |
| Annual Returns | `/annual-returns` | AnnualReturns |
| Monthly Trade | `/monthly-trade` | MonthlyTrade |
| Drawdowns | `/drawdowns` | Drawdowns |
| Rolling Returns | `/rolling-returns` | RollingReturns |
| Docs/FAQ | `/docs`, `/faq` | 静的 |
| Admin | `/admin` | Portfolios, DB status |
| Admin FoF | `/admin/fof` | Portfolios |
| Admin Visibility | `/admin/visibility` | Tiers, Visibility |

→ 詳細資料: `docs/research/frontend-components.md` §2
- L162: App Routerのルートディスコンは『ページ差し替え+private folder退避』が復活コスト最小（cmd_527）
- L164: ディスコン復元性はファイル存在確認だけでなく内容ハッシュ一致で検証すると誤判定を防げる（cmd_535）

## 3. 状態管理

4 Context: Signals(PF選択+prefetch), ExecutionTiming(OPEN/CLOSE), ViewerPermissions(3ロール), AdminAuth(Cookie+PFリスト)
7 Hook: usePrefetch, useAdminPage(550行), useChartInteraction, useAppVisibility, usePortfolioParam, useSortableTable, useIsMobile

データフロー: SignalsProvider→prefetch→キャッシュ→PF切替即描画

→ 詳細資料: `docs/research/frontend-components.md` §3, §5
- L201: useEffectの依存配列にstate変数を含めると意図しないタイミングでeffectが発火する（cmd_642）

## 4. APIクライアント

`lib/api-client.ts` (1121行)。TTLキャッシュ(5min/LRU100)、セマフォ(同時2)、リトライ(2回/指数バックオフ)、AbortController(8s)。
認証: Admin(Cookie+BasicAuth) / Viewer(Bearerトークン)。401→セッションクリア+イベント発火。

補助参照: `docs/research/frontend-api-spec.md` §1, §2
- L159: SignalsProvider層で障害判定すると全ページ一括でフォールバック制御できる（cmd_526）
- L181: DeteriorationページのAPIレスポンスにはfolder_idが含まれないためuseSignalsのportfoliosから別途マップ構築が必要（cmd_555）
- L204: API永続キャッシュはUI state用localStorageと分離し、auth-scope付きIndexedDBを主格にすべき（cmd_646）

## 5. コンポーネント

チャート9種(カスタムSVG)、テーブル10種、チャート制御9種、UI部品13種。

→ 詳細資料: `docs/research/frontend-components.md` §4
- L182: FolderFilterChipがcompare-summaryとdeteriorationで完全重複しており共通コンポーネント抽出候補（cmd_555）
- L183: 同一UI改修を複数ページへ展開する際は状態モデル(Set/OR条件/Clear操作)を同一化するとレビュー密度が上がる（cmd_556）
- L185: テーブル列定義をSSOT(COLUMNS)で管理しておくと要件変更4点の同時反映が安全になる（cmd_557）
- L187: ジェネリックソートフックのnull処理は方向別(multiplier)との合成結果まで検証する（cmd_569）
- L191: TypeScript列追加時はtsc --noEmitでユニオンキー添字安全性を検証すべき（cmd_613）
- L192: レビューではUI挙動確認に加えて型系ユニオン拡張の添字安全性まで検査すべき（cmd_613）

## 6. デザインシステム

13色CSSトークン(Light/Dark)。チャート7色パレット。ブレークポイント: xs(375)/sidebar(1100)/sidebar-xl(1280)。

→ 詳細資料: `docs/research/frontend-components.md` §4, `docs/research/frontend-deploy.md` §0

## 7. 認証・権限

4層可視性: L1(ページ), L2(PF), L3(シグナル), L4(コンポーネント)。Admin=バイパス。ティアシステム(グローバル+オーバーライド)。

→ 詳細資料: `docs/research/frontend-api-spec.md` §2.2, §2.4, §3
- L160: DM-signalの認証はin-memory token store方式。サーバー再起動(Renderデプロイ含む)で全セッション無効化（cmd_527）

## 8. 性能最適化

2パスロード / プリフェッチ / ダウンサンプリング(520-1040点) / RAF / セマフォ(2並列) / メモ化 / Static Export

**SPA遷移問題(005)**: 全ナビゲーション箇所(sidebar/dropdown-menu/page-navigation)が`window.location.href`でフルリロード→キャッシュ全消滅→prefetchAll()毎回再実行。`<Link>`/`router.push()`への切替で解決済み(cmd_647/650)。
**SPA Link化+IndexedDB永続化(cmd_647/650)**: 3箇所(dropdown-menu/sidebar/page-navigation)をnext/link化→SPA遷移でキャッシュ維持。api-cache.ts(idb-keyval 2層キャッシュ)でAPI応答をIndexedDB永続化。sw.jsにRSC bypass追加。preview検証→本番push(eec7f2f)完了。
**Next.js高速化知見**: SPA遷移化(完了) → バンドル分析+dynamic import → Next.js 16アップグレード(React 19必須) → optimizePackageImports

→ 詳細資料: `docs/research/frontend-components.md` §5, `docs/research/frontend-api-spec.md` §4
- L188: window.location遷移を採用する構成ではContext単独の状態共有は永続化要件を満たさない（cmd_570）
- L195: Static Exportのビルド成果物を実際に確認してから原理的制約を主張せよ（cmd_638）
- L196: Static Exportの回帰調査では局所実績とplatform原理の議論を分離して検証する（cmd_638）
- L197: Static Export SPA遷移はホスティングサービスの.txt配信挙動に依存する（cmd_639）
- L198: Static Export + custom SW構成ではroute flight(index.txt/_rsc)を明示bypassせよ（cmd_639）
- L200: Portal内のnext/linkはクリック中に自己アンマウントさせるとSPA遷移がキャンセルされる（cmd_642）
- L203: SWのAPIバイパス設定がキャッシュ永続化の阻害要因（cmd_646）
- L205: SW SWRとContent-Type書き換えは同一sw.js更新で統合可能（cmd_646）

## 9. PWA・テスト・デプロイ

PWA: manifest + SW(dm-signal-v8) + オフラインページ。CacheFirst(static) / NetworkOnly(API)。
テスト: 29ファイル / 5 FAIL, 24 PASS / Lines 71.4% / **現状テスト未完了**
- L193: 公開FAQ/Docsの最終レビューではadmin/owner文言をgrepで機械検査する（cmd_618）
- L199: Next.js buildのpages-manifest欠落はstale .nextを疑ってから回帰判定せよ（cmd_639）
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

## 12. Frontend関連教訓

L122(キャッシュ無効化), L121(API実コード確認) → `context/dm-signal-ops.md` 教訓索引に記載済み

## 13. 2026-03 holding表示バグ (cmd_499)

結論: monthly PFの計算値は正しいが、Signalページのcurrent signal表示が`as_of`依存で月替わりpending投影を持たず、2026-03-02時点で2月保有表示が起きうる。

→ 詳細: `docs/research/cmd_499_march-holding-signal-validation.md` §6

## 14. cmd_494 monthly pending表示整合修正

結論: `/api/signals` に monthly向け月替わりpending投影（`signal_pending`含む）を追加し、frontend Current Signalへ`Pending Rebalance`表示を反映。non-monthly挙動は維持。

→ 詳細: `docs/research/cmd_494_signal-pending-display-fix.md`
