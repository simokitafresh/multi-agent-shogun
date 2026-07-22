# DM-Signal page style MECE — Metrics / Monthly Returns / Annual Returns

検証日: 2026-07-22。対象実装: `/mnt/c/Python_app/DM-signal/frontend`。軸定義は `docs/research/dm-signal-page-style-diff-mece_20260722.md` §1。コード現物だけを根拠とし、推測値は含めない。

## 1. ルート・import component依存グラフ（3/3）

| ページ | page.tsx / 直接import | import component依存 | 判定 |
|---|---|---|---|
| Metrics | `frontend/app/metrics/page.tsx` L1-17、描画L133-196。`MetricsTable`, `PageShell`, `Loading`, `MessageBanner`, `UpDownMarketChart` | `PageShell`→`PortfolioNavSelector`, `MobileMenu`, `TimingToggle`, `PageNavigation/HomeButton` (`page-shell.tsx` L3-10,22-66)。`MetricsTable`→`Loading`, `cn`, timing context (`metrics-table.tsx` L1-5)。`UpDownMarketChart`→`Loading` (`up-down-market-chart.tsx` L3-4) | 実在・全直接component追跡済み |
| Monthly Returns | `frontend/app/monthly-returns/page.tsx` L1-22、描画L230-280。`MonthlyReturnsTable`, `PageShell`, `Loading`, `MessageBanner` | Shell依存は上記共通。`MonthlyReturnsTable`→`PeriodNotes`, `Loading`, timing context, `cn` (`monthly-returns-table.tsx` L3-8) | 実在・全直接component追跡済み |
| Annual Returns | `frontend/app/annual-returns/page.tsx` L1-25、描画L203-267。`AnnualReturnsChart`, `AnnualReturnsTable`, `PageShell`, `Loading`, `MessageBanner` | Shell依存は上記共通。`AnnualReturnsChart`→`Loading` (`annual-returns-chart.tsx` L3-5)。`AnnualReturnsTable`→`Loading`, `cn`, timing context (`annual-returns-table.tsx` L3-7) | 実在・全直接component追跡済み |

## 2. 30セル全数マトリクス

| ページ | 軸 | 実測値（class / prop / CSS） | 根拠 |
|---|---|---|---|
| Metrics | A タイポ | Shell h1=`text-2xl md:text-3xl font-bold tracking-tight text-foreground`。table h2=`text-lg font-semibold ... text-primary`、table=`text-sm`、数値=`font-mono`。chart h3=`text-xl font-semibold text-primary`、月数metadata=`text-sm font-normal text-muted-foreground` | `page-shell.tsx` L30,38-40; `metrics-table.tsx` L62-73,91-109; `up-down-market-chart.tsx` L270-276 |
| Metrics | B カラー | page=`bg-background`。table header=`border-slate-700 text-muted-foreground`、PF primary、負値red-400、hover=`bg-white/5`。chart paletteはinline `#3B82F6/#2DD4BF`、status emerald/red、chart card=`bg-card border-border` | `page-shell.tsx` L23; `metrics-table.tsx` L68-109; `up-down-market-chart.tsx` L53-55,312-466,486 |
| Metrics | C スペース | Shell外周`px-4 md:px-8`、content=`pb-4 md:pb-8 pt-4 md:pt-6 space-y-6 md:space-y-8`。table見出し`mb-4`、cells `py-2 pl-2/px-4/pr-2`。period `mt-4`、chart section `mt-8 pt-8`、chart内部`space-y-6/p-4` | `page-shell.tsx` L25,47,56; `metrics-table.tsx` L62-75; `metrics/page.tsx` L178-186; `up-down-market-chart.tsx` L270,486 |
| Metrics | D カード | MetricsTableはカードなし (`w-full`)。UpDown chartのみ`bg-card border border-border rounded-xl p-4`、tooltip=`bg-card/95 ... rounded-lg p-3 shadow-xl`。section境界に`border-t` | `metrics-table.tsx` L60-65; `metrics/page.tsx` L186; `up-down-market-chart.tsx` L486,637 |
| Metrics | E テーブル | Metrics table=`overflow-x-auto`, `w-full text-sm text-left`、header slate border、body `divide-slate-800`、stripeなし、hover、数値right+mono。chart summary tableは`border-collapse`、semantic border、全数値right、monoなし | `metrics-table.tsx` L65-121; `up-down-market-chart.tsx` L280-310,312-466 |
| Metrics | F ボタン等 | 本文table/chartにbutton/linkなし。Shell共通 HomeButton、TimingToggle、MobileMenu、PortfolioNavSelector。PF矢印は`w-11 h-11 rounded-lg ... hover:bg-muted/50`（44px） | `metrics/page.tsx` L133-196; `page-shell.tsx` L27-36,45-50; `portfolio-nav-selector.tsx` L67-108 |
| Metrics | G チャート | custom SVG bar chart、固定900×400、最大12 bars。portfolio blue `#3B82F6`、benchmark cyan `#2DD4BF`。grid=`currentColor`/muted、legend下中央、absolute tooltip border/shadow。横scroll不要を意図 | `up-down-market-chart.tsx` L53-60,200-210,486-530,549-619,625-715 |
| Metrics | H ナビ | `PageShell pageTitle="Metrics" currentPage="metrics"`。共通h1横にTimingToggle、右にHomeButton/MobileMenu、selectorはmobile sticky・desktop relative、`max-w-sm`左寄せ | `metrics/page.tsx` L134; `page-shell.tsx` L25-56 |
| Metrics | I 状態 | page/metrics loadingは遅延300ms、Metrics固有`min-h-[920px]`中央Loading。error/no-dataはMessageBanner。UpDownはloading 400px、emptyは`null`で独立空表示なし | `metrics/page.tsx` L33,47-48,135-165; `ui/message-banner.tsx` L18-40; `up-down-market-chart.tsx` L168-179 |
| Metrics | J responsive | Shellは`md`でpadding/title/sticky解除。tableは横scrollだが列非表示なし。chart SVG=`w-full h-auto`、bar最大12にmergeしhorizontal scrollを避ける | `page-shell.tsx` L25,30,46-56; `metrics-table.tsx` L65-121; `up-down-market-chart.tsx` L57-60,280,492 |
| Monthly Returns | A タイポ | Shell h1共通。table h2=`text-lg font-semibold text-foreground`、metadata=`text-sm font-normal muted`。table=`text-sm`、mobile cells=`text-xs md:text-sm`、数値`font-mono`、notes=`text-xs` | `page-shell.tsx` L30,38; `monthly-returns-table.tsx` L194-199,285-349,387-485,567 |
| Monthly Returns | B カラー | page token共通。header/bordersは`slate-700`、row classはreturn状態色、controls active=`bg-sky-500/20 text-sky-400`、load-all=`bg-primary/20 text-primary`、partial badge amber、nav hover slate | `monthly-returns-table.tsx` L205-265,288-349,400-428 |
| Monthly Returns | C スペース | Shell共通。table header controls=`gap-2 mb-4`, action group=`gap-4`、buttons `px-3 py-1.5` / `px-2 py-1`、table cells `py-3 px-1 md:px-2`、footer `mt-4` | `page-shell.tsx` L56; `monthly-returns-table.tsx` L194-265,285-349,383-567 |
| Monthly Returns | D カード | table wrapperは`w-full overflow-x-auto`、border/radius/shadow/card backgroundなし。badgesのみborder+rounded、loading overlayはbackground colorをinline styleで付与 | `monthly-returns-table.tsx` L194,275-285,363-428,549-566 |
| Monthly Returns | E テーブル | 2段header、`border-slate-700`、stripeなし、row status class、PF/benchmark groupに左border。数値right+mono、mobile `text-xs`。ticker列は`hidden md:table-cell`、overflow-x。年月表示とbalance、tickerを全表示 | `monthly-returns-table.tsx` L285-361,383-544 |
| Monthly Returns | F ボタン等 | Load all=`primary/20`、Show 12/Allはactive sky chip・inactive text、pagination arrowsはhover slate/disabled opacity。いずれも`rounded-lg`、focus class明記なし。Shell共通controlsあり | `monthly-returns-table.tsx` L205-265; `page-shell.tsx` L27-50 |
| Monthly Returns | G チャート | N/A: page import/childrenはMonthlyReturnsTableのみでchart component/propなし | `monthly-returns/page.tsx` L3-22,256-271 |
| Monthly Returns | H ナビ | `PageShell pageTitle="Monthly Returns" currentPage="monthly-returns"`。Shell共通TimingToggle/Home/Mobile/selector。table内にShow/pagination controls | `monthly-returns/page.tsx` L231; `page-shell.tsx` L22-56; `monthly-returns-table.tsx` L196-265 |
| Monthly Returns | I 状態 | page loading/data loading=`min-h-[400px]`中央Loading、error/no-data MessageBanner。quick→idle full中は既存tableを維持し`isLoadingMore`をpropで渡す。table内部にも400px loading | `monthly-returns/page.tsx` L57-58,230-272; `monthly-returns-table.tsx` L42-55,185-190 |
| Monthly Returns | J responsive | Shell `md`。header controls `flex-col sm:flex-row`。cells `px-1 md:px-2`, `text-xs md:text-sm`、Balance短縮、ticker列desktop限定、table横scroll | `monthly-returns-table.tsx` L194-265,285-349,387-544 |
| Annual Returns | A タイポ | Shell h1共通。chart h3=`text-xl font-semibold text-primary`、table h2=`text-lg font-semibold text-foreground`、metadata small muted。table数値mono・`text-xs md:text-sm`、chart axis inline 11/12px | `annual-returns-chart.tsx` L210-215,281-295,361-377; `annual-returns-table.tsx` L100-105,165-256 |
| Annual Returns | B カラー | chart paletteはMetricsと同じ blue/cyan、positive emerald/negative red、tooltip card token。tableはslate borders/hover、active controls sky、primary load-all。page backgroundはShell token | `annual-returns-chart.tsx` L11-12,393-440; `annual-returns-table.tsx` L113-154,168-256; `page-shell.tsx` L23 |
| Annual Returns | C スペース | Shell共通。chart=`space-y-4`、header `gap-2`、actions `gap-4`、legend `gap-6 mt-4`。table controls/cells/footerはMonthlyと同じ `mb-4`, `py-3 px-1 md:px-2`, `mt-4` | `annual-returns-chart.tsx` L210-252,426-440; `annual-returns-table.tsx` L100-165,215-284 |
| Annual Returns | D カード | chart/table本体にカードborder/radius/shadowなし。chart tooltipのみ`bg-card/95 border rounded-lg p-3 shadow-xl`。partial-note separatorはborder-t | `annual-returns-chart.tsx` L210,252,393; `annual-returns-table.tsx` L100,272-284 |
| Annual Returns | E テーブル | Monthlyと同型の2段header、slate border、stripeなし、hover、right+mono、ticker `hidden md:table-cell`、horizontal scroll。年単位、PF/benchmark return+balance | `annual-returns-table.tsx` L165-272 |
| Annual Returns | F ボタン等 | ChartとTableの双方にLoad all / Show 12-All controlsが存在し、同じprimary/sky chip classを重複表示し得る。Tableにはpagination arrows。focus class明記なし | `annual-returns-chart.tsx` L221-241; `annual-returns-table.tsx` L111-154 |
| Annual Returns | G チャート | custom SVG grouped bars、portfolio blue/benchmark cyan。`overflow-x-auto`, `touchAction:none`、15超は50px/bar minWidth。grid currentColor、legend下中央、absolute tooltip。Metricsとpalette/tooltipは同型だがoverflow戦略が異なる | `annual-returns-chart.tsx` L252-295,324-440 |
| Annual Returns | H ナビ | `PageShell pageTitle="Annual Returns" currentPage="annual-returns"`。共通Shell navに加え、chart/table双方が期間controlsを持つ | `annual-returns/page.tsx` L204; `page-shell.tsx` L22-56; `annual-returns-chart.tsx` L212-241; `annual-returns-table.tsx` L102-154 |
| Annual Returns | I 状態 | page loading/error/no-dataは300px。chart/table内部loadingは400px。quick→full切替で`setAnnualReturns`、AnnualはMonthlyの`isLoadingMore` overlay propなし | `annual-returns/page.tsx` L61-62,203-259; `annual-returns-chart.tsx` L51-56; `annual-returns-table.tsx` L37-42 |
| Annual Returns | J responsive | Shell `md`。chart header `sm:flex-row`、SVGは長期時minWidthで横scroll。table header `sm:flex-row`、cells/ticker表示はMonthly同型`md`切替 | `annual-returns-chart.tsx` L212,252-256; `annual-returns-table.tsx` L102,165-256 |

## 3. 軸別差異・guide逸脱・統一候補（単一主軸帰属）

1. **A タイポ**: page h1は共通Shellで一致。section headingはMetrics table/Monthly/Annual tableがh2 18px、Metrics/Annual chartがh3 20pxで、視覚サイズとHTML階層が逆転。section title token（例 h2 20px / subsection h3 18px）へ統一候補。guide「clear hierarchy」L18。
2. **B カラー**: data tablesは`border-slate-*`, `hover:bg-white/5`、Metrics chart summaryはsemantic `border-border`, `hover:bg-muted/30`。theme-safe semantic tokenへ統一候補。guide「purposeful color」L24。
3. **C スペース**: Metrics chart sectionだけ`mt-8 pt-8 border-t`、Annualはchart→table間をShell `space-y-6 md:space-y-8`へ委任。section separator spacing contractへ統一候補。
4. **D カード**: Metrics UpDown chartだけ`bg-card border rounded-xl`で囲み、Annual chartは裸。類似chartのcontainer treatment不一致はguide「keep patterns consistent」L15逸脱。不要ならMetrics cardを除去、必要ならchart共通surfaceへ寄せる。
5. **E テーブル**: Metrics main=`py-2 px-2/4`, Monthly/Annual=`py-3 px-1 md:px-2`; Metrics chart summary=`py-2 px-3`。header/body border tokenも3系統。共通dense/regular table variantを明示し、用途なき個別値を削減候補。
6. **F インタラクション**: Monthly/Annual controlsは高さ約28-30px (`py-1/1.5`)でguide 48pt floor L28/L59未達。さらにAnnualはChartとTableに同じLoad all/Show controlsを二重表示し、一画面一primary action L19に逸脱。1組へ統合し48px target候補。
7. **G チャート**: Metricsは12 barsへmergeしてscrollを避け、Annualは50px/barでscroll。palette/tooltipは同型。用途差は維持しつつ共通palette/axis/tooltip component token化候補。
8. **H ナビ**: 3ページはPageShellで一致。ただし期間controlの所有はMonthly=tableのみ、Annual=chart+table重複、Metrics=TimingToggleのみ。期間controlをpage headerまたは単一section headerへ統一候補。
9. **I 状態**: Metrics page min-height 920px、Monthly 400px、Annual 300px。child loadingはMonthly/Annual/UpDownすべて400px。共通page loading height/tokenへ統一候補。Annualだけquick→full upgrading状態を可視化しない点もMonthlyと不一致。
10. **J responsive**: Monthly/Annual tableは同型で一致。chartはMetrics merge、Annual horizontal scroll。Shell `md`とcontrols `sm`は役割差として妥当だが、44px PF arrowsと28px期間buttonsはtouch floor未達。

ME検証: 所見10件をA-J各1件へ一意帰属。候補10、単一主軸帰属10、重複0、false positive 0。

## 4. 二値検証

- CEページ: 3/3 (`Metrics`, `Monthly Returns`, `Annual Returns`)。
- CE軸: 10/10 (A-J)。
- CEセル: 30/30。N/AはMonthly ReturnsのGチャート1セルのみで、page import/描画根拠付き。
- import component依存: page direct import 13/13、各style-bearing child dependency 15/15を追跡（共通Shell dependencyは重複排除して1系統として記載）。
- ME所見: 候補10、true positive 10、false positive 0、重複0、未解消条件0。判定 **PASS**。
- 実装変更: 0。docs-only偵察のため実装test対象外。二値検査はpage 3、軸10、表body 30行、所見10主軸を機械計数する。

origin: `[[殿指示_デザイン統一_20260722]] -> [[returns_pages_style_drift]] -> [[cmd_karo_recon2_page_style_mece_kagemaru_20260722]]`
