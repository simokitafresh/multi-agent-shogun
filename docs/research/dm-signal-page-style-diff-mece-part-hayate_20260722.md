# DM-Signal page style MECE — Dashboard / Summary / Signals

検証日: 2026-07-22。対象実装: `/mnt/c/Python_app/DM-signal/frontend`。軸定義は `docs/research/dm-signal-page-style-diff-mece_20260722.md` §1。コード現物だけを根拠とし、推測値は含めない。

## 1. ルート・依存グラフ（3/3）

| 項目 | page.tsx / 到達性 | import component依存 | 判定 |
|---|---|---|---|
| Dashboard | `frontend/app/dashboard/page.tsx` 実在。main/header/contentは同ファイル L560-751 | `PageNavigation`, `HomeButton`, `MobileMenu`, `PortfolioNavSelector`, `TimingToggle` (L5-10)、dynamic `TotalReturnChart`, `SignalPieChart`, `MtdChart`, `MtdDailyTable` (L38-90) | 実在 |
| Summary | `frontend/app/summary/page.tsx` 実在。`PageShell`配下に`SummaryTable` (L90-129) | `PageShell`, `SummaryTable`, `Loading`, `MessageBanner` (L9-12)。Shellは`PageNavigation`, `HomeButton`, `MobileMenu`, `TimingToggle`, `PortfolioNavSelector`を使用 (`frontend/components/page-shell.tsx` L3-10,22-66) | 実在 |
| Signals | `frontend/app/signals/`および`page.tsx`不在（`find frontend/app -maxdepth 2 -name page.tsx`と`test -d`で確認） | 代替表示はDashboard内 Current Signal + `SignalPieChart` (`dashboard/page.tsx` L620-680)。`trades/page.tsx` L17-22は`href="/signals"`を持つが到達先なし | **BLOCK: `/signals` hrefがdead route** |

## 2. 30セル全数マトリクス

| 項目 | 軸 | 実測値（class / prop / CSS） | 根拠 |
|---|---|---|---|
| Dashboard | A タイポ | h1=`text-2xl md:text-3xl font-bold tracking-tight text-foreground`; metadata=`text-sm text-muted-foreground`; signal=`text-3xl font-bold text-primary tracking-tight text-center` | `dashboard/page.tsx` L568-584,625-635 |
| Dashboard | B カラー | page=`bg-background`; text tokens=`text-foreground/text-muted-foreground/text-primary`; chart error=`text-destructive`; deterioration dotsはinline `backgroundColor` + border | 同 L561,568-580,216-218,688-691 |
| Dashboard | C スペース | header/content=`px-4 sm:px-8`, `pt-4 sm:pt-8`, content `pb-4 sm:pb-8 pt-4 sm:pt-6 space-y-6`; sections=`gap-6`, table前=`mt-6` | 同 L563,601,619-622,729 |
| Dashboard | D カード | page/sectionsにカードborder/radiusなし。sticky selectorのみmobile `shadow-md`、desktop `shadow-none`; pie tooltipだけ`rounded-lg border ... shadow-lg` | 同 L591; `signal-pie-chart.tsx` L52-54 |
| Dashboard | E テーブル | MTD table=`w-full text-sm border-collapse`, horizontal scroll、header/rows=`border-b border-border`, sticky date、数値=`text-right font-mono text-xs`, mobile列非表示 | `mtd-daily-table.tsx` L118-158,174-200 |
| Dashboard | F ボタン等 | HomeButton=`p-1 rounded`, disabled opacity、enabled hover muted。TimingToggleをheader/モバイル/MTDで使用。本文リンクなし | `page-navigation.tsx` L13-37; `dashboard/page.tsx` L571,654-657,719-724 |
| Dashboard | G チャート | Pie=Recharts、legend top prop、tooltip border/shadow、slice色+dark/light stroke。Total/MTD=custom SVG、primary実線/benchmark破線、crosshair tooltip | `signal-pie-chart.tsx` L4,52-54,104-133; `total-return-chart.tsx` L300-325; `mtd-chart.tsx` L308-448 |
| Dashboard | H ナビ | 独自header。PageNavigationは実際はnull、HomeButton disabled、MobileMenuあり。selectorはmobile sticky/中央、dashboard title配置 | `dashboard/page.tsx` L563-597; `page-navigation.tsx` L9-10 |
| Dashboard | I 状態 | loading=spinner+`animate-pulse`文言/h-[60vh]、page error=MessageBanner、chart error=destructive text、empty=MessageBanner | `dashboard/page.tsx` L602-616,687-704,741-749 |
| Dashboard | J responsive | `sm`でpadding、`md`でtitle/selector shadow、`lg:grid-cols-2`; Current Signalは`hidden lg:flex`、mobileはpie上にtoggle/label。MTD desktop列は`hidden md:table-cell` | 同 L563,591-601,622-680; `mtd-daily-table.tsx` L121-158 |
| Summary | A タイポ | Shell h1はDashboard同一。table h2=`text-lg font-semibold ... text-primary`; table=`text-sm`; values=`font-mono`; period metadata=`text-sm ... text-center` | `page-shell.tsx` L30,38; `summary-table.tsx` L139-165; `summary/page.tsx` L120-123 |
| Summary | B カラー | Shell=`bg-background`; table header muted、PF primary、benchmark foreground/70、negative=`text-red-400`; row hover=`bg-white/5` | `page-shell.tsx` L23; `summary-table.tsx` L140-166,158,194-205 |
| Summary | C スペース | Shell header/content=`px-4 md:px-8`, content `pb-4 md:pb-8 pt-4 md:pt-6 space-y-6 md:space-y-8`; table h2 mb-4、cells py-2/pl-2/px-4/pr-2、period mt-4 | `page-shell.tsx` L25,47,56; `summary-table.tsx` L140-165; `summary/page.tsx` L121 |
| Summary | D カード | SummaryTable wrapper `w-full`のみでborder/radius/shadow/backgroundなし。table row separatorのみ | `summary-table.tsx` L138-146 |
| Summary | E テーブル | `overflow-x-auto`; `w-full text-sm text-left`; header bottom border slate-700、stripeなし、row hover、数値right+mono、currencyはIntl桁区切り | 同 L105-112,138-165,218-252 |
| Summary | F ボタン等 | Shell共通HomeButton（enabled）+TimingToggle+MobileMenu。SummaryTable内button/linkなし | `page-shell.tsx` L27-36; `summary-table.tsx` L138-260 |
| Summary | G チャート | N/A: page imports/childrenはSummaryTableのみ、chart component/propなし | `summary/page.tsx` L3-12,90-129 |
| Summary | H ナビ | `PageShell pageTitle="Summary" currentPage="summary"`; PageNavigationはnull、HomeButton enabled、MobileMenu、TimingToggle、selectorは左寄せmax-w-sm（Dashboardはmx-auto） | `summary/page.tsx` L91; `page-shell.tsx` L22-56; `page-navigation.tsx` L9-10 |
| Summary | I 状態 | hidden=error MessageBanner、page/metrics loading=300px centered Loading、fetch error=MessageBanner。`!data`でもSummaryTable内部Loading | `summary/page.tsx` L80-110; `summary-table.tsx` L63-69 |
| Summary | J responsive | Shell padding/titleは`md`; selector mobile sticky、desktop relative/shadow-none; table horizontal scroll。ただし列非表示なし | `page-shell.tsx` L25-56; `summary-table.tsx` L143-257 |
| Signals | A タイポ | 独立page N/A。代替Dashboard signalはlabel `text-sm`、値`text-3xl font-bold tracking-tight text-center`、pending `text-xs` | `dashboard/page.tsx` L625-635,651-669 |
| Signals | B カラー | 独立page N/A。代替はlabel muted、signal primary、pieは配列色+light/dark stroke | 同 L625-668; `signal-pie-chart.tsx` L123-125 |
| Signals | C スペース | 独立page N/A。代替section grid `gap-6`, signal `py-4`, label `mb-2`, pending `mt-2`, legend `gap-2/mb-2` | `dashboard/page.tsx` L622-667; `signal-pie-chart.tsx` L89-106 |
| Signals | D カード | 独立page N/A。代替signal/pie本体はカードなし、tooltipのみrounded/border/shadow | `dashboard/page.tsx` L621-680; `signal-pie-chart.tsx` L52-54 |
| Signals | E テーブル | N/A: 独立pageなし、代替Current Signalはpie/textでtableなし | route不在 + `dashboard/page.tsx` L620-680 |
| Signals | F ボタン等 | dead-route入口だけoutline Link=`rounded-md border ... px-4 py-2 ... hover:bg-muted`; 到達先なし | `trades/page.tsx` L17-22 |
| Signals | G チャート | 代替SignalPieChart=Recharts Pie、legend top、120px、tooltip、slice stroke。単一銘柄はstrokeWidth=0 | `signal-pie-chart.tsx` L4,85-86,104-133 |
| Signals | H ナビ | 独立header/nav N/A。`/trades`から`/signals` hrefはあるがroute不在。実表示へはDashboardナビしかない | `trades/page.tsx` L17-22; route実在検査 |
| Signals | I 状態 | 独立loading/empty/error N/A。代替pieは空データ時150px中央`No signal data available`、Dashboard親がloading/error/emptyを処理 | `signal-pie-chart.tsx` L75-78; `dashboard/page.tsx` L602-616,741-749 |
| Signals | J responsive | 独立page N/A。代替はdesktop signal text=`hidden lg:flex`、mobile/tabletはpie上header+toggle、dots size mobile 10px/desktop 12px | `dashboard/page.tsx` L199-207,622-680 |

## 3. 軸別差異・guide逸脱・統一候補（単一主軸帰属）

1. **H ナビ**: Dashboardはselector `mx-auto`、PageShellは左寄せ。共通Shellへ統一候補。ただしDashboard HomeButton disabledは現在地を表すため挙動差として維持可。
2. **H ナビ**: `/trades`の`/signals`リンクはdead route。`/dashboard`へ修正するか、正規`/signals` pageを作るかは仕様判断が必要。現状はBLOCK。
3. **C スペーシング**: Dashboardは`sm` breakpoint、PageShellは`md` breakpointで外周paddingが切替わる。共通Shell tokenへ統一候補。
4. **H ナビ**: selectorはDashboard中央、Summary左寄せ。`Keep patterns consistent` (`ui-design-guide.md` L15)逸脱。
5. **E テーブル**: Dashboard MTD header border=`border-border`、Summary=`border-slate-700`でsemantic token不統一。`border-border`へ統一候補。
6. **B カラー**: Summary hover=`bg-white/5`はlight themeで意味が弱く、theme tokenでない。`hover:bg-muted`候補（purposeful color: guide L24）。
7. **F インタラクション**: HomeButtonの実hit areaは`p-1`+20px iconで48pt floor未達の可能性が高い。guide L28/L59に逸脱。共通48px target候補。
8. **D カード**: 3項目とも本文を不要なカードで囲わずspace主体で、guide L20-21に準拠。tooltip border/shadowは浮遊面の意味あり。
9. **A タイポ**: Dashboard/Summary h1は同一。Summary tableだけ数値monoを使用し役割明確。本文の独自font-family指定はなく共通CSS継承。
10. **I 状態**: Dashboard loadingは文言付き60vh、Summaryは無言300px、Signals独立状態なし。共通loading/empty/error contractへ統一候補。
11. **G チャート**: Dashboardはcustom SVGとRechartsを混用。Signals代替pieのみRecharts。色token/tooltipの統一対象だが、Summaryはchart N/A。
12. **J responsive**: Dashboardはdesktop/mobileでsignal表現を切替、Summary tableは全列を横scroll。用途差はあるが外周breakpointは統一候補。

ME検証: 所見12件を主軸 A=1, B=1, C=1, D=1, E=1, F=1, G=1, H=3, I=1, J=1へ一意帰属。重複帰属0件。

## 4. 二値検証

- CE項目: 3/3 (`Dashboard`, `Summary`, `Signals`)。
- CE軸: 10/10 (A-J)。
- CEセル: 30/30。N/A 8セルはすべてsignals独立route欠落またはSummary chart非実装のコード根拠付き。
- ME所見: 候補12、単一主軸帰属12、重複0、false positive 0。ただしdead `/signals` 1件は未解消なので全体判定は **BLOCK**。
- 実装変更: 0。docs-only調査でありtest作成対象外。一次検査はroute列挙、`test -d frontend/app/signals` (rc=1)、全参照`rg`で実施。

origin: `[[殿指示_デザイン統一_20260722]] -> [[signals_dead_route_and_page_style_drift]] -> [[cmd_karo_recon2_page_style_mece_hayate_20260722]]`
