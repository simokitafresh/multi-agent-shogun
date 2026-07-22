# DM-Signal 全15項目ページスタイル差分 — MECE完成版

検証日: 2026-07-22  
目的: viewer向け指定15項目を、実装一次情報に基づきA-J全10軸で比較し、統一候補を確定する。  
照合基準: `context/ui-design-guide.md`。実装root: `/mnt/c/Python_app/DM-signal`。本文中のfrontend相対pathは同rootから解決する。

## §0 対象・route inventory・依存証拠

### 指定15項目と実在性

| # | 指定項目 | route / 実在判定 | 主な表示依存（一次根拠） |
|---:|---|---|---|
| 1 | Dashboard | `/dashboard` 実在 | page imports `PageNavigation/HomeButton/MobileMenu/PortfolioNavSelector/TimingToggle`、dynamic charts/tables (`frontend/app/dashboard/page.tsx:5-10,38-90`) |
| 2 | Summary | `/summary` 実在 | `PageShell`, `SummaryTable`, `Loading`, `MessageBanner` (`frontend/app/summary/page.tsx:9-12`) |
| 3 | Signals | **独立page不在 / BLOCKED** | Dashboard内Current Signalが代替 (`dashboard/page.tsx:620-680`)。`/trades` の `href="/signals"` はdead (`frontend/app/trades/page.tsx:17-22`) |
| 4 | Metrics | `/metrics` 実在 | `MetricsTable`, `PageShell`, `Loading`, `MessageBanner`, `UpDownMarketChart` (`frontend/app/metrics/page.tsx:1-17`) |
| 5 | Monthly Returns | `/monthly-returns` 実在 | `MonthlyReturnsTable`, `PageShell`, `Loading`, `MessageBanner` (`frontend/app/monthly-returns/page.tsx:1-22`) |
| 6 | Annual Returns | `/annual-returns` 実在 | `AnnualReturnsChart/Table`, `PageShell`, `Loading`, `MessageBanner` (`frontend/app/annual-returns/page.tsx:1-25`) |
| 7 | Rolling Returns | `/rolling-returns` 実在 | `PageShell`, chart, distribution/summary tables, `GlassCard`, states (`frontend/app/rolling-returns/page.tsx:4-10`) |
| 8 | Drawdowns | `/drawdowns` 実在 | `PageShell`, `GlassCard`, chart/table, states (`frontend/app/drawdowns/page.tsx:9-14`) |
| 9 | Monthly Trade | `/monthly-trade` 実在 | `MonthlyTradeTable`, `PageShell`, states (`frontend/app/monthly-trade/page.tsx:4-7`) |
| 10 | Trades | `/trades` 実在（封鎖画面） | Next `Link`のみ。CTAはdead `/signals` (`frontend/app/trades/page.tsx:1-27`) |
| 11 | Compare Returns | `/compare-returns` 実在 | `TimingToggle`, `CompareReturnsTable`, Mobile/Home, folder chips, banner (`frontend/app/compare-returns/page.tsx:3-17`) |
| 12 | Compare / Compare Summary | `/compare` + 補助`/compare-summary` 実在 | compare: chart/selectors/Accordion/state (`frontend/app/compare/page.tsx:3-26`)。補助: `CompareSummaryTable`, filters, banner (`frontend/app/compare-summary/page.tsx:4-9`) |
| 13 | Deterioration | `/deterioration` 実在 | `ChartTooltip`, Mobile/Home, Accordion, folder chip (`frontend/app/deterioration/page.tsx:4-8`) |
| 14 | FAQ | `/faq` 実在 | `GlassCard`, Accordion, LanguageToggle, Loading, PageHeader (`frontend/app/faq/page.tsx:3-13`) |
| 15 | Offline | `/offline` 実在 | `GlassCard`, `WifiOff` (`frontend/app/offline/page.tsx:1-2`) |

`find frontend/app -name page.tsx -type f` は21件。admin 4件を明示除外後viewer routeは17件: `/`, `/annual-returns`, `/compare`, `/compare-returns`, `/compare-summary`, `/dashboard`, `/deterioration`, `/docs`, `/drawdowns`, `/faq`, `/metrics`, `/monthly-returns`, `/monthly-trade`, `/offline`, `/rolling-returns`, `/summary`, `/trades`。指定15項目との非1:1差分は、対象外route `/`・`/docs`、Signals非実在、Compare 2 route集約の4類型。adminは本調査対象外。

### 統合した6断片（6/6）

`dm-signal-page-style-diff-mece-part-hayate_20260722.md`、`...-kagemaru_...`、`...-hanzo_...`、`...-saizo_...`、`...-kotaro_...`、`...-tobisaru_...`。各断片のpage/component import graphを保持し、主表は次の親軸へ再帰属した。

## §1 MECE軸

| 軸 | 排他的な主対象 |
|---|---|
| A | タイポグラフィ（size/weight/alignment/font） |
| B | カラー（background/text/border/status palette） |
| C | スペーシング（outer padding/gap/margin/cell padding） |
| D | コンテナ・カード（surface/radius/shadow/elevation） |
| E | テーブル（header/row/cell/numeric format） |
| F | ボタン・リンク・interaction（hover/focus/active/hit area） |
| G | チャート・グラフ（palette/axis/legend/tooltip/library） |
| H | ヘッダー・ナビ・タブ（page chrome/title placement） |
| I | loading/empty/error/offline/blocked状態 |
| J | responsive（breakpoint/reflow/hide/scroll） |

## §2 15項目 × A-J = 150セル

| 項目 | A タイポ | B カラー | C スペース | D カード | E テーブル | F 操作 | G チャート | H ナビ | I 状態 | J responsive |
|---|---|---|---|---|---|---|---|---|---|---|
| Dashboard | h1=`text-2xl md:text-3xl font-bold tracking-tight`; signal=`text-3xl font-bold text-center` (`dashboard/page.tsx:568-584,625-635`) | `bg-background`, foreground/muted/primary、error destructive (`:561,568-580,688-691`) | `px-4 sm:px-8`, `pt-4 sm:pt-8`, `space-y-6`, `gap-6` (`:563,601,619-622`) | 本文cardなし。mobile selector `shadow-md`; pie tooltip rounded/border/shadow (`:591`; `signal-pie-chart.tsx:52-54`) | MTD=`text-sm border-collapse`, sticky date、right+mono、border token (`mtd-daily-table.tsx:118-200`) | Home=`p-1 rounded hover:bg-muted`; TimingToggle複数 (`page-navigation.tsx:24-37`; `dashboard/page.tsx:571,654-657`) | Recharts pie + custom SVG Total/MTD、tooltip/crosshair (`signal-pie-chart.tsx:104-133`; `total-return-chart.tsx:300-325`) | 独自header、PageNavigationはnull、Home disabled、selector中央 (`dashboard/page.tsx:563-597`; `page-navigation.tsx:9-11`) | loading=`h-[60vh]` spinner+文、error/empty banner (`dashboard/page.tsx:602-616,741-749`) | `sm` padding、`lg:grid-cols-2`; signal表示desktop/mobile分岐 (`:563,622-680`) |
| Summary | Shell h1共通、h2=`text-lg font-semibold text-primary`、数値mono (`page-shell.tsx:30,38`; `summary-table.tsx:139-165`) | background token、header muted、negative red、hover=`bg-white/5` (`summary-table.tsx:140-205`) | Shell `px-4 md:px-8`, `space-y-6 md:space-y-8`; cells `py-2 px-4` (`page-shell.tsx:25,56`; table:140-165) | table wrapper `w-full`のみ、surface/shadowなし (`summary-table.tsx:138-146`) | horizontal scroll、left header、right+mono、Intl桁区切り (`summary-table.tsx:105-112,138-252`) | Shell Home/Timing/Mobile、table内button/link N/A（import/JSX `summary-table.tsx:138-260`） | N/A: page childはSummaryTableのみ (`summary/page.tsx:3-12,90-129`) | `PageShell pageTitle="Summary"`; selector左寄せ (`summary/page.tsx:91`; `page-shell.tsx:22-56`) | hidden/error banner、loading 300px、table内部Loading (`summary/page.tsx:80-110`; table:63-69) | Shell `md`; table全列horizontal scroll、列hideなし (`page-shell.tsx:25-56`; table:143-257) |
| Signals | 独立page N/A。代替label `text-sm`、signal `text-3xl font-bold` (`dashboard/page.tsx:625-635`) | 独立page N/A。代替muted/primary + pie palette (`dashboard/page.tsx:625-668`) | 独立page N/A。代替`gap-6`, `py-4`, `mb-2` (`dashboard/page.tsx:622-667`) | 独立page N/A。代替本体cardなし、tooltipのみsurface (`dashboard/page.tsx:621-680`) | N/A: routeなし、代替はpie/textでtableなし (`dashboard/page.tsx:620-680`) | dead入口Link=`rounded-md border px-4 py-2 hover:bg-muted` (`trades/page.tsx:17-22`) | 代替Recharts Pie、legend top、120px (`signal-pie-chart.tsx:85-133`) | **BLOCKED**: 独立headerなし、`/trades→/signals` dead (`trades/page.tsx:17-22`) | 独立状態N/A。代替pie empty 150px、親がloading/error処理 (`signal-pie-chart.tsx:75-78`) | 独立page N/A。代替signal `hidden lg:flex`、mobile header分岐 (`dashboard/page.tsx:622-680`) |
| Metrics | Shell h1、h2 18px、chart h3 20px、mono数値 (`metrics-table.tsx:62-109`; `up-down-market-chart.tsx:270-276`) | slate borders/white hover、blue/cyan chart、emerald/red status (`metrics-table.tsx:68-109`; chart:53-55,312-466) | Shell共通、table `py-2 px-2/4`; chart `mt-8 pt-8 p-4` (`metrics/page.tsx:178-186`) | main table裸、chartのみ`bg-card border rounded-xl p-4` (`up-down-market-chart.tsx:486`) | scroll、left label/right mono、stripeなし (`metrics-table.tsx:65-121`) | 本文control N/A、Shell controls、PF arrows `w-11 h-11` (`portfolio-nav-selector.tsx:67-108`) | custom SVG 900×400、最大12 bars、legend下、tooltip (`up-down-market-chart.tsx:200-210,486-715`) | PageShell Metrics、Timing/Home/Mobile/selector (`metrics/page.tsx:134`; `page-shell.tsx:25-56`) | Metrics loading `min-h-[920px]`; error/no-data banner、chart empty null (`metrics/page.tsx:135-165`; chart:168-179) | Shell md、table scroll、SVG `w-full h-auto` (`metrics-table.tsx:65-121`; chart:492) |
| Monthly Returns | h2 18px、table text-sm、mobile xs、mono、notes xs (`monthly-returns-table.tsx:194-199,285-567`) | slate borders、active sky、primary action、amber partial (`monthly-returns-table.tsx:205-428`) | controls `gap-2 mb-4`; cells `py-3 px-1 md:px-2` (`:194-349`) | table裸、badgeのみrounded/border (`:194,363-428`) | 2段header、right+mono、ticker md hide、horizontal scroll (`:285-544`) | Load/Show/pagination `py-1/1.5 rounded-lg`、focus classなし (`:205-265`) | N/A: MonthlyReturnsTableのみ (`monthly-returns/page.tsx:3-22,256-271`) | PageShell + table内期間/pagination (`monthly-returns/page.tsx:231`; table:196-265) | page/table loading 400px、error/no-data banner、upgrade overlay (`monthly-returns/page.tsx:230-272`) | controls sm row化、cells md、ticker md限定、scroll (`monthly-returns-table.tsx:194-544`) |
| Annual Returns | h1共通、chart h3 20px、table h2 18px、mono (`annual-returns-chart.tsx:210-215`; table:100-105) | blue/cyan chart、emerald/red、slate table、sky active (`annual-returns-chart.tsx:393-440`; table:113-256) | chart `space-y-4`, legend `gap-6 mt-4`; cells `py-3 px-1 md:px-2` (`chart:210-252`; table:100-284) | chart/table裸、tooltipだけcard/shadow (`annual-returns-chart.tsx:210,252,393`) | 2段header、right+mono、ticker md hide、scroll (`annual-returns-table.tsx:165-272`) | chart/table双方にLoad/Show重複、small controls (`chart:221-241`; table:111-154) | custom SVG grouped bars、50px/bar、scroll、legend下 (`annual-returns-chart.tsx:252-440`) | PageShellに加え期間control二重 (`annual-returns/page.tsx:204`; chart/table refs前記) | page 300px、children 400px loading、error/no-data banner (`annual-returns/page.tsx:203-259`) | Shell md、headers sm row、long chart scroll、table md (`chart:212,252-256`; table:102,165-256) |
| Rolling Returns | h2=`text-lg font-semibold text-foreground`; table labels/数値 left/center/right (`rolling-returns/page.tsx:117-166`; distribution table:75-92) | cyan/slate chart、negative red、PF primary/BM muted (`rolling-return-chart.tsx:548,588-614`) | stack `space-y-6 md:space-y-8`; cards `p-4 md:p-6` (`rolling-returns/page.tsx:113,136-163`) | 3 GlassCard、loadingもcard (`rolling-returns/page.tsx:116-166`) | summary/distribution tables、desktop/mobile branches (`rolling-returns/page.tsx:140-173`) | chart period pills flex-wrap (`rolling-return-chart.tsx:325-356`) | interactive SVG + summary/distribution (`rolling-returns/page.tsx:140-173`; chart:363-370) | PageShell共有 (`rolling-returns/page.tsx:86`; `page-shell.tsx:25-56`) | page 350px、data skeleton 200/350、shared banners (`rolling-returns/page.tsx:88-131`) | md padding、desktop/mobile table別実装 (`rolling-returns/page.tsx:116-174`) |
| Drawdowns | h2 18px + decorative bar、note centered italic、table right numeric (`drawdowns/page.tsx:108-146`; table:36-43) | primary/muted bars、negative red (`drawdowns/page.tsx:109,134`; table:64) | stack `space-y-6 md:space-y-8`; cards fixed `p-6` (`drawdowns/page.tsx:105-132`) | 2/3 GlassCard (`drawdowns/page.tsx:107,120,132`) | labels left、drawdown right、md列hide (`drawdowns-table.tsx:36-61`) | N/A: page/chart/tableにlocal button/controlなし (`drawdowns/page.tsx:104-140`) | interactive responsive SVG (`drawdowns-chart.tsx:186-193`) | PageShell共有 (`drawdowns/page.tsx:80`) | page/data 300px loading、shared banners (`drawdowns/page.tsx:81-103`) | md列hide、chart width responsive (`drawdowns-table.tsx:39-61`; chart:186-193) |
| Monthly Trade | h2 18px、labels xs/sm、numeric right+mono (`monthly-trade-table.tsx:123-130,736-741`) | active sky、actions primary、warning amber (`monthly-trade-table.tsx:143-160,350-392`) | single table、toolbar/cell spacing local (`monthly-trade/page.tsx:187-205`; table:120-216) | GlassCard N/A; root `w-full overflow-x-auto` (`monthly-trade-table.tsx:120`) | wide trade table + detail rows (`monthly-trade-table.tsx:239-287,816`) | toggles/load/show/pagination small rounded (`monthly-trade-table.tsx:136-216`) | N/A: tableのみ、chart import/JSXなし (`monthly-trade/page.tsx:4-18,194-203`) | PageShell共有 (`monthly-trade/page.tsx:165`) | page/data 300px、shared banners (`monthly-trade/page.tsx:166-191`) | toolbar `flex-col sm:flex-row`; columns md/lg hide、scroll (`monthly-trade-table.tsx:122,278-287`) |
| Trades | emoji 4xl、h1 2xl→md3xl、body muted (`trades/page.tsx:7-14`) | page background、card/CTA semantic tokens (`trades/page.tsx:5-22`) | outer px4、card `max-w-2xl p-8 space-y-4` (`trades/page.tsx:5-6`) | `border bg-card/60 shadow-sm rounded-2xl` (`trades/page.tsx:6`) | N/A: static JSXにtableなし (`trades/page.tsx:1-27`) | outline Link `py-2`; destination `/signals` dead (`trades/page.tsx:17-22`) | N/A: chart import/JSXなし (`trades/page.tsx:1-27`) | 共通headerなし、CTAだけ（dead route） (`trades/page.tsx:17-22`) | 封鎖状態そのもの。非同期loading/error N/A (`trades/page.tsx:3-27`) | single column、h1のみmd (`trades/page.tsx:5-10`) |
| Compare Returns | h1共通scale、metadata sm、table sm/tabular nums (`compare-returns/page.tsx:161-175`; table:179,268) | border/sticky tokens、green/red returns、purple FoF、amber BM (`compare-returns-table.tsx:181-272`) | wide shell px4→md8、filter gap1 mb3、legend mt4 gap4 (`compare-returns/page.tsx:156,182,190,234`) | mostly borderless、table borders/sticky bg (`compare-returns-table.tsx:181-191`) | 8期間sortable、sticky/name列、md hide (`compare-returns-table.tsx:177-285`) | timing px2/py1、chips py0.5、sortable header cursor (`TimingToggle.tsx:18-35`; folder chip:12-24) | N/A: CompareReturnsTableのみ (`compare-returns/page.tsx:3-17,182-252`) | title+Timing、right Home/Mobile、PageNavigation null (`compare-returns/page.tsx:157-177`) | permission/API banners、table skeleton/empty (`compare-returns/page.tsx:140-186`; table:120-175) | md/xl shell、md列hide、height 70→82vh (`compare-returns-table.tsx:122-191`) |
| Compare / Compare Summary | compare h1 common、labels sm、chart heading 18px。補助CS h1同型 (`compare/page.tsx:261-324`; `compare-summary/page.tsx:256`) | compare borderless+primary Select/card tint。補助CS green/red、FoF purple/BM amber (`portfolio-selector.tsx:101-133`; `compare-summary-table.tsx:377-393`) | compare `p-4 sm:p-8`, stack 6→8、controls gap4。補助CS px4→md8 (`compare/page.tsx:254-346`; CS page:251,278) | compare Accordion divider/Select popup shadow、CS表裸 (`accordion.tsx:42`; `select.tsx:240-265`; CS table:324) | 主compare N/A（chart）。補助CS sticky sortable table、cell py3 (`compare-summary-table.tsx:324-376`) | Accordion/checkbox/Select/reset h8/py1。補助CS timing/chips/link (`compare/page.tsx:278-380`; CS table:422-431) | 主=interactive ComparisonChart + axes/legend/tooltip (`comparison-chart.tsx:478-756`); 補助CS N/A | 主title+Home/Mobile、補助CS title+Timing/Home/Mobile (`compare/page.tsx:257-275`; CS page:252-272) | 主loading/error/zero selection (`compare/page.tsx:233-250,350-359`); 補助CS banner/skeleton/empty (`CS page:237-284`; table:248-320) | 主 sm/md + mobile hook。補助CS md/xl、table md hide/70→82vh (`compare/page.tsx:254-296`; CS table:324-376) |
| Deterioration | h1=`text-2xl font-bold`、metadata sm、table mono (`deterioration/page.tsx:1178-1196,1390-1413`) | label green/yellow/orange等、dots/badge/trend (`deterioration/page.tsx:73-105,1253-1408`) | outer `px-4 py-8`, header mb6、filters gap1/2 (`deterioration/page.tsx:1172-1239`) | tableはAccordion内、expanded row `bg-muted/10`; page cardなし (`deterioration/page.tsx:1281-1432`) | full-width text-sm、py3、desktop列多数、row detail (`deterioration/page.tsx:1281-1432`) | 2種chips、sort、desktop row click、Accordion (`deterioration/page.tsx:1239-1275,1289-1342`) | expanded detailにhistory SVG/tooltip、max400/500 (`deterioration/page.tsx:442-850,971-1000`) | title+Home/Mobile、Timing N/A (`deterioration/page.tsx:1174-1200`) | 5 skeleton、裸`text-red-500` error、empty中央 (`deterioration/page.tsx:1124-1167,1438-1444`) | px固定、md列hide、dots10→12、mobile detail無効 (`deterioration/page.tsx:1289-1413`) |
| FAQ | Inter、PageHeader h1 2xl→md3xl、question sm medium (`layout.tsx:2,14`; `page-header.tsx:52-65`; FAQ:149-160) | token背景/前景、固定sky link (`faq/page.tsx:342,362-423`) | `p-4 md:p-8`, stack6→8、cards4→6 (`faq/page.tsx:342-343,357`) | sections GlassCard rounded2xl/shadow (`faq/page.tsx:289,357,385,407`; `globals.css:119-146`) | Markdown/glossary `text-sm`, border /50,/30、py2 px3 (`faq/page.tsx:45-68,359-379`) | Accordion/question hover opacity、LanguageToggle、sky links下線/focusなし (`accordion.tsx:23-42`; FAQ:223-231) | N/A: chart import/JSXなし (`faq/page.tsx:3-13,341-458`) | PageHeader + language + Mobile/Theme (`faq/page.tsx:345-349`; `page-header.tsx:52-72`) | Suspense Loading min400 role=status、固有empty/errorなし (`faq/page.tsx:444-457`) | md padding/gap/title/card、table scroll (`faq/page.tsx:342-360`) |
| Offline | Inter、h1=`text-2xl font-bold`、body muted (`offline/page.tsx:11-14`) | background tokens、icon `bg-secondary/20 text-muted` (`offline/page.tsx:6-14`) | outer p4、card p8 space-y4、icon p4 (`offline/page.tsx:6-8`) | single GlassCard max-w-md rounded/shadow (`offline/page.tsx:7`; `globals.css:119-146`) | N/A: JSX 1-18にtableなし | N/A: JSX 1-18にbutton/link/handlerなし | N/A: JSX 1-18にchartなし | PageHeader不使用、card内素h1 (`offline/page.tsx:6-15`) | WifiOff 48px + connection-lost文。分岐なし (`offline/page.tsx:6-14`) | page固有breakpointなし、w-full max-w-md (`offline/page.tsx:6-7`) |

## §3 軸別差異・guide逸脱・統一基準候補

断片の所見を削らず、意味を次の単一主軸へ正規化した。各IDは一度だけ出現する。

| 主軸 | 具体的不統一・逸脱（統合所見） | 統一基準候補 |
|---|---|---|
| A | h1はPageShell系が`2xl md:3xl tracking-tight`だが Deterioration/Offline は2xl固定。section hierarchyはh2 18pxに対しchart h3 20pxで逆転。 | PageHeader typography tokenをSSOT化。section h2=20px/subsection h3=18pxを候補にする。 |
| B | tablesに`border-slate-*`/`bg-white/5`固定値と`border-border`/`bg-muted`が混在。意味色もinline hexとtokenが混在。guide「purposeful color」に反する。 | semantic theme tokenへ統一し、chart palette/status paletteを共通定数化。 |
| C | outer breakpointがDashboard `sm`、PageShell `md`、Deterioration固定。page loading高さも関連するが状態はIへ分離。 | shell spacing=`p/px-4 md:p/px-8`, page stack=`space-y-6 md:space-y-8`を既定化。 |
| D | similar chartでMetricsだけcard、Annual裸。Rolling responsive card、Drawdowns固定card、Monthly裸。guide「keep patterns consistent」「remove unnecessary containers」逸脱。 | `DataSection surface=bare|card`を明示し、default bare、浮遊/独立surfaceのみcard。 |
| E | table cell densityがpy2/px2-4、py3/px1-3に分散。sticky、column hide、mobile duplicateも無名。 | `TableShell density=dense|regular`, sticky/critical-column policy、semantic borderを共通化。 |
| F | Home p1、chips py0.5、period/reset py1、Select h8など48pt touch floor未達。FAQ linkは色だけ/underlineなし。Annual primary controls二重。 | mobile `min-h-12 min-w-12`、filled/outline/underlined三段階、links underline+focus-visible、primary action一組。 |
| G | custom SVG/Recharts混在自体は用途差だが、tooltip/palette/legend/overflow戦略が個別。Deterioration dot意味も視覚凡例不足。 | libraryは維持し `ChartTooltip/Axis/Legend/palette` tokenを共有。color-onlyには符号/label/legendを併設。 |
| H | 独自header/PageShell/PageHeader/素h1の4系統。PageNavigationは呼ばれるがnull。selector中央/左差。**Signals dead hrefは未解消BLOCKED**。 | `PageHeader` slots(title, metadata, controls, selector, actions) + route policy。`/signals`は仕様決定まで解消済み扱い禁止。 |
| I | loading高さ300/350/400/920/60vh、banner/裸red/nullが混在。Offline/Tradesは別意味の状態。 | `PageState` variants loading/error/empty/blocked/offline、reserved-height tokenとaria契約を共有。 |
| J | shell breakpoint、tableのhide/scroll/duplicate、chart merge/scrollがページごと。Deterioration mobileはdetail到達不能。 | shell breakpointのみ統一し、data surfaceは情報criticality別policy。mobile detail disclosureを必須化。 |

## §4 CE / ME / 機械検証

- 指定項目: **15/15**、軸: **10/10**、matrix cell: **150/150**。
- 断片: **6/6**。各担当の一次根拠を本表へ統合。
- N/A: すべてroute/import/JSX不在または静的分岐不在の根拠付き。根拠なしN/A **0件**。
- route inventory: page.tsx **21/21**、admin除外 **4/4**、viewer route **17/17**。対象外 `/`・`/docs` を明記。
- Compareは指定項目内で `/compare` を主、`/compare-summary` を補助実装として保持。
- Signals: 独立page不在、dead hrefを **BLOCKED finding 1件**として維持。解消済み扱い0件。
- ME attribution候補: **10軸統合所見**、true positive **10**、false positive **0**、主軸重複 **0件**。
- placeholder残存: **0件**。
- 全体調査判定: **PASS with BLOCKED finding retained**。成果物の完全性はPASS、製品側dead `/signals` は未解消。

## §5 因果リンク

origin: `[[殿指示_デザイン統一_20260722]] -> [[15項目スタイル差分全数調査]] -> [[150セルMECE完成版]]`  
blocked-origin: `[[trades_href_signals]] -> [[signals_page不在]] -> [[dead_route未解消]]`
