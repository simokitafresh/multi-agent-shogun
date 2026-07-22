# DM-Signal page style MECE: trades / compare-returns / compare

- 検証日: 2026-07-22
- 方法: `page.tsx`から描画component importを再帰追跡し、Tailwind class・prop・分岐を行番号付きで全数照合。
- 対象: `/trades`, `/compare-returns`, `/compare`
- 10軸（相互排他的な主帰属）: A shell、B width/padding、C header/navigation、D typography、E grouping/spacing、F controls/affordance、G color/border/elevation、H state feedback、I responsive、J primary content/data display。

## 1. AC1: routeとcomponent依存グラフ（3/3）

### trades

`frontend/app/trades/page.tsx:1-27` → Next `Link`のみ。共通component importは0件。shell/card/text/CTAをpage内で直接描画し、CTAは`/signals`へ遷移する（同:5-24）。

### compare-returns

`frontend/app/compare-returns/page.tsx:3-17,154-254`

- `TimingToggle` → `frontend/components/chart/TimingToggle.tsx:14-35`（switch button）→ `cn`。
- `CompareReturnsTable` → `frontend/components/compare-returns-table.tsx:40-285`（sortable/sticky table）→ `useSortableTable`, `Link`, `COMPARE_RETURNS_COLUMNS`, `cn`。
- `MobileMenu` → `frontend/components/mobile-menu.tsx:3-6,8-360` → `AuthStatus`, `ThemeToggle`, `DropdownMenu`, permissions。該当routeはmenu itemとして同:108-145。
- `HomeButton`, `PageNavigation` → `frontend/components/page-navigation.tsx:9-39`。重要: `PageNavigation`は同:9-11で`return null`; `HomeButton`のみbuttonを描画。
- `FolderFilterChip` → `frontend/components/ui/folder-filter-chip.tsx:10-26` → `cn`。
- `MessageBanner` → `frontend/components/ui/message-banner.tsx:11-43` → lucide icons, `cn`。
- データ専用依存: `returns-data.ts`, contexts 3件, persistent folder hook, API/types（page:10-17）。スタイル描画は上記componentへ閉じる。

### compare

`frontend/app/compare/page.tsx:3-26,253-384`

- `ComparisonChart`（dynamic, SSR false）→ `frontend/components/comparison-chart.tsx:3-34,478-756` → `ChartAxes`, `ChartLegend`, `ChartTooltip`, `ScaleToggle`, `TimingToggle`, `YearRangeSelector`, chart interaction/mobile hooks, colors/types/cn。
- `FromYearSelector` → `frontend/components/chart/FromYearSelector.tsx:31-68` → shared `Select` primitives。
- `PortfolioSelector` → `frontend/components/portfolio-selector.tsx:57-190` → `FolderFilterChip`, persistent folder hook, colors/cn。
- `Accordion` → `frontend/components/ui/accordion.tsx:14-48` → lucide chevrons/cn。
- `Loading` → `frontend/components/ui/loading.tsx:8-15` → lucide spinner。
- `Select*` → `frontend/components/ui/select.tsx:31-374` → portal, lucide check/chevron, cn。triggerは同:95-108、contentは同:240-265、itemは同:288-335。
- `MobileMenu`, `HomeButton`, `PageNavigation`はcompare-returnsと同じ共有依存。`PageNavigation`は描画0。

依存グラフ検証: route 3/3、pageの描画component import 14/14を解決、未解決0。

## 2. AC2: 3ページ × 10軸（30/30セル）

| 軸 | trades | compare-returns | compare |
|---|---|---|---|
| A shell | 中央寄せ封鎖画面: `min-h-screen ... items-center justify-center` (`trades/page.tsx:5`) | 通常文書flow: `min-h-screen bg-background` (`compare-returns/page.tsx:154`) | 中央column: `min-h-screen flex flex-col items-center` (`compare/page.tsx:254`) |
| B width/padding | `px-4`; card `max-w-2xl p-8` (`trades/page.tsx:5-6`) | header/contentとも`max-w-7xl xl:max-w-[120rem] px-4 md:px-8`; pt/py分離 (`compare-returns/page.tsx:156,182`) | main `p-4 sm:p-8`; inner `max-w-6xl` (`compare/page.tsx:254-255`) |
| C header/navigation | 共通headerなし。CTAのみ`href=/signals` (`trades/page.tsx:17-22`) | title + null `PageNavigation` + `TimingToggle`; rightにHome/Mobile (`compare-returns/page.tsx:157-177`; `page-navigation.tsx:9-11`) | title + null `PageNavigation`; rightにHome/Mobile (`compare/page.tsx:257-275`; `page-navigation.tsx:9-11`) |
| D typography | emoji `text-4xl`, h1 `text-2xl md:text-3xl font-bold tracking-tight`, body muted (`trades/page.tsx:7-14`) | 同じh1 scale、metadata `text-sm muted`; table `text-sm`, numeric `tabular-nums` (`compare-returns/page.tsx:161-175`; `compare-returns-table.tsx:179,268`) | 同じh1 scale/metadata; control labels `text-sm muted`; chart heading `text-lg font-semibold` (`compare/page.tsx:261-274,299-324`; `comparison-chart.tsx:482`) |
| E grouping/spacing | card `space-y-4`, centered text (`trades/page.tsx:6`) | header `space-y-2`; filter `gap-1 mb-3`; legend `mt-4 gap-4` (`compare-returns/page.tsx:157,190,234`) | page `space-y-6 md:space-y-8`; controls `gap-4`, subgroups `gap-2` (`compare/page.tsx:255,296-346`) |
| F controls/affordance | 1 outline Link `rounded-md border ... hover:bg-muted`; hit heightは`py-2`のみで48pt保証なし (`trades/page.tsx:17-22`) | timing switch `px-2 py-1`; chips `px-2 py-0.5`; clear `px-2 py-0.5`; sort headers cursor+icon (`TimingToggle.tsx:18-35`; `folder-filter-chip.tsx:12-24`; page:214-220; table:183-199) | Accordion、checkbox cards、2 Select、ALL reset、chart toggles。Select `h-8`、reset `py-1`で48pt未満 (`compare/page.tsx:278-380`; `select.tsx:67-70`; page:331-345) |
| G color/border/elevation | card `border bg-card/60 shadow-sm rounded-2xl`; CTA border (`trades/page.tsx:6,19`) | mostly borderless page; table borders/sticky bg; semantic green/red returns、purple FoF、amber benchmark (`compare-returns-table.tsx:29-33,181-191,220-248,268-272`) | page borderless; Accordion divider; Select primary border+popup shadow; Portfolio cards border/primary tint (`accordion.tsx:42`; `select.tsx:99-108,240-265`; `portfolio-selector.tsx:101-133`) |
| H state feedback | 封鎖状態そのもの。loading/error/emptyはN/A: static componentで非同期分岐なし (`trades/page.tsx:3-27`) | permissions error banner (`page:140-149`)、API errors (`page:183-186`)、table skeleton (`table:120-167`)、empty (`table:169-175`) | page loading/error (`compare/page.tsx:233-250`)、zero-selection empty、data loading (`compare/page.tsx:350-359`) |
| I responsive | h1 `md:`のみ; card/mobile layoutは単一column (`trades/page.tsx:5-10`) | width/padding `md/xl`; table columns `hidden md:table-cell`; heights `70vh/lg:82vh`; name width 160→200 (`page:156,182`; `table:122-155,178-191`) | padding `sm`; spacing/title `md`; controls wrap; chart hook `useIsMobile` (`compare/page.tsx:254-261,296`; `comparison-chart.tsx:19`) |
| J primary content/data | 封鎖説明+戻るCTA。data viewはN/A（静的route） (`trades/page.tsx:7-23`) | 8期間sortable returns table + legend (`compare-returns-table.tsx:36-39,177-285`; `page:225-252`) | 最大7 PF selector + benchmark/from-year + interactive comparison chart (`compare/page.tsx:277-380`) |

## 3. AC3: 軸別差異・guide逸脱・統一候補

所見は各1主軸へ一度だけ帰属（重複0）。

| ID | 主軸 | 証拠付き差異/逸脱 | 統一候補 |
|---|---|---|---|
| F1 | A | 3 shellが中央card / wide table / centered chartで別実装（各page:5 / :154 / :254） | 共通PageShell variant (`status`,`wide`,`standard`)で背景・min-heightのみ統一 |
| F2 | B | content幅が2xl / 7xl+120rem / 6xl | data densityを明示したwidth tokenへ命名しmagic widthを除去 |
| F3 | C | tradesだけHome/Mobileなし、しかも`/signals`へ戻る。一方`PageNavigation`は2ページで呼ぶが描画0 | header有無とreturn destinationをroute policyとして確定。dead `PageNavigation`呼出は整理候補 |
| F4 | D | h1 scaleは3ページ一致。tableだけtabular numsを正しく採用 | h1/metadata tokenは共有し、数表だけtabular維持 |
| F5 | E | group gapはtrades 4、returns 1/4、compare 2/4/6-8と役割別だが命名なし | `control-group`, `section-stack`, `page-stack`の3段階へ対応付け |
| F6 | F | guide §3の48pt touch floorに対しCTA `py-2`, toggle/reset `py-1`, chip `py-0.5`, Select `h-8`で明示的floor未達 | mobileで`min-h-12 min-w-12`、desktop dense例外は根拠付きtoken化 |
| F7 | G | tradesはcard+shadow、returns/compareはborderless主体。guide §5は不要container回避を推奨 | status cardのみelevationを許可し、data pagesはspace grouping維持 |
| F8 | H | state vocabularyが封鎖文言 / MessageBanner+skeleton / plain destructive text+Loadingで不統一 | `PageState`へ blocked/error/loading/empty を集約しaria契約も統一 |
| F9 | I | breakpointがtrades md、returns md/xl/lg、compare sm/md+JS mobile hookに分散 | shell breakpointは共通化し、table/chart固有breakpointだけ局所維持 |
| F10 | J | primary contentはstatus / table / chartで本質的に異なる | 同一見た目へ寄せず、共通shell/header/stateのみ統一 |
| F11 | F | returns値はgreen/red colorのみ（`getReturnColor`, table:29-33,268-274）。guide §1/§6「color alone禁止」に抵触 | 符号文字は既に`+/-`を持つため意味は残るが、色なしでも凡例/列説明で状態を確認 |
| F12 | C | HomeButtonは`p-1`の20px iconで48pt floor未達 (`page-navigation.tsx:24-37`) | shared component側でhit areaを修正すればcompare系へ一括波及 |

## 4. AC4: CE/ME二値検証

- CE pages: 3/3 = yes。
- CE axes: A-J 10/10 = yes。
- CE cells: table body 10行 × 3ページ = 30/30 = yes。
- 各セルのコード根拠: 30/30 = yes（N/A 2セルも静的/非同期分岐不在を根拠化）。
- ME findings: 12件、主軸帰属12/12、ID重複0、同一主張重複0 = yes。
- import component解決: 14/14、未解決0 = yes。
- FP測定: 候補30セル、コード根拠ありTP=30、根拠なしFP=0、precision=100%。
- 未解消条件: 0。調査成果としてPASS。

結論: 内容固有のtable/chart/status差は維持し、共通化対象はshell/header/state/touch targetへ限定する。最大のguide逸脱は共有HomeButtonを含む小型controlの48pt未達である。
