# DM-Signal page style MECE v2 — 全21 page × A–L

検証日: 2026-07-22。一次情報root: `/mnt/c/Python_app/DM-signal/frontend`。6断片の詳細を保持し、本書は21 pageの検索索引兼統合判定とする。

## §0 Route inventory — 21/21

`find frontend/app -name page.tsx -type f | sort` の現物はviewer **17** + admin **4** = **21**。重複0、欠落0。

| # | route | page.tsx | 区分 |
|---:|---|---|---|
| 1 | `/` | `frontend/app/page.tsx` | viewer |
| 2 | `/annual-returns` | `frontend/app/annual-returns/page.tsx` | viewer |
| 3 | `/compare` | `frontend/app/compare/page.tsx` | viewer |
| 4 | `/compare-returns` | `frontend/app/compare-returns/page.tsx` | viewer |
| 5 | `/compare-summary` | `frontend/app/compare-summary/page.tsx` | viewer |
| 6 | `/dashboard` | `frontend/app/dashboard/page.tsx` | viewer |
| 7 | `/deterioration` | `frontend/app/deterioration/page.tsx` | viewer |
| 8 | `/docs` | `frontend/app/docs/page.tsx` | viewer |
| 9 | `/drawdowns` | `frontend/app/drawdowns/page.tsx` | viewer |
| 10 | `/faq` | `frontend/app/faq/page.tsx` | viewer |
| 11 | `/metrics` | `frontend/app/metrics/page.tsx` | viewer |
| 12 | `/monthly-returns` | `frontend/app/monthly-returns/page.tsx` | viewer |
| 13 | `/monthly-trade` | `frontend/app/monthly-trade/page.tsx` | viewer |
| 14 | `/offline` | `frontend/app/offline/page.tsx` | viewer |
| 15 | `/rolling-returns` | `frontend/app/rolling-returns/page.tsx` | viewer |
| 16 | `/summary` | `frontend/app/summary/page.tsx` | viewer |
| 17 | `/trades` | `frontend/app/trades/page.tsx` | viewer |
| 18 | `/admin` | `frontend/app/admin/page.tsx` | admin |
| 19 | `/admin/fof` | `frontend/app/admin/fof/page.tsx` | admin |
| 20 | `/admin/folders` | `frontend/app/admin/folders/page.tsx` | admin |
| 21 | `/admin/visibility` | `frontend/app/admin/visibility/page.tsx` | admin |

### 統合した断片 — 6/6

`docs/research/fragments/mece_v2_{hayate,hanzo,kagemaru,kotaro,saizo,tobisaru}_20260722.md`。各断片の行番号付き詳細を削除せず参照し、本表では検索判断点を21行へ圧縮する。

## §1 Axes A–L

| 軸 | 定義 |
|---|---|
| A | typography: size/weight/alignment/font |
| B | color: background/text/border/status palette |
| C | spacing: outer padding/gap/margin/cell padding |
| D | container/card: surface/radius/shadow/elevation |
| E | table: header/row/cell/numeric format |
| F | interaction: button/link/hover/focus/active |
| G | chart: palette/axis/legend/tooltip/library |
| H | header/nav: page chrome/title/control placement |
| I | states: loading/empty/error/offline/blocked |
| J | responsive: breakpoint/reflow/hide/scroll |
| K | viewport state color: PC/mobile DOMとhelper適用差 |
| L | copy/caption: description/note/legend/captionのtype/color/placement |

## §2 Main matrix — 21 rows × 12 axes = 252/252 cells

各cell末尾の`ref`は一次コード行。詳細な複数行証跡は該当fragmentに保持する。

| page | A | B | C | D | E | F | G | H | I | J | K | L |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `/` | icon4xl/h1 2xl→3xl (`page.tsx:27-39`) | semantic bg/card/muted (`:25-44`) | px4/card p8 (`:25-26`) | rounded2xl card (`:26`) | N/A table0 (`:3-50`) | dashboard Link (`:41-47`) | N/A chart0 (`:3-50`) | dashboard CTAのみ (`:41-47`) | holiday注記 (`:7-40`) | h1 mdのみ (`:25-30`) | 単一DOM、差N/A (`:25-49`) | 説明+休日note muted中央 (`:33-39`) |
| `/annual-returns` | canonical PageShell h1 (`page.tsx:204`; `page-shell.tsx:30`); section差分=chart h3 text-xl/table h2 text-lg (`annual-returns-chart.tsx:212-215`; table`:102-108`); numeric cells mono (`table:225-256`) | blue/cyan bars、return helper (`chart:319-347`; table`:68-74`) | gap2/cell py3 (`chart:212`; table`:165-256`) | bare、tooltip card (`chart:393`) | 2段header table (`table:165-268`) | Show All/hover (`chart:221-244`; table`:112-157`) | custom SVG+legend (`chart:251-443`) | PageShell (`page.tsx:204`) | loading/error/empty (`:205-258`) | chart scroll/table md (`chart:252-256`; table`:180`) | return helper同一、差0 (`table:218-236`) | YTD/Partial notes+axis+legend (`table:218-284`; chart`:273-443`) |
| `/compare` | canonical h1 2xl→3xl (`page.tsx:261-263`); section差分=chart h3 lg (`comparison-chart.tsx:482`) | PF palette/positive-negative (`comparison-chart.tsx:519-680`) | p4→sm8、space6→8 (`page.tsx:254-347`) | bare、tooltip card (`ChartTooltip.tsx:31-53`) | N/A table0 (`page.tsx:253-384`) | Accordion/Select/reset (`:277-347`) | interactive SVG (`comparison-chart.tsx:505-753`) | title/Home/Mobile (`page.tsx:257-275`) | loading/error/zero (`:230-381`) | responsive outer padding/gaps (`page.tsx:254-296`); single responsive SVG (`comparison-chart.tsx:506-621`) | single DOM、pos/neg共通 (`chart:622-753`) | as-of/max7/Bench/Since/legend (`page:270-330`; chart`:694-753`) |
| `/compare-returns` | h1 2xl→3xl、table sm (`page.tsx:161-177`; table`:179`) | return green/red、FoF purple/BM amber (`table:29-34,264-283`) | shell px4→8 (`page:156,182`) | borderless/sticky bg (`table:177-191`) | 8期間sortable (`table:177-285`) | timing/chips/sort (`page:164-222`) | N/A chart0 (`page:3-17`) | Home/Mobile/title (`:156-178`) | banners/skeleton/empty (`:138-186`; table`:120-175`) | md列hide/scroll (`table:122-191`) | one DOM/getReturnColor共通 (`table:29-34,264-275`) | as-of+FoF/BM/sort/period notes (`page:171-252`) |
| `/compare-summary` | h1 2xl→3xl、table sm (`page.tsx:251-273`; table`:325`) | FoF purple/BM amber/CAGR green-red (`table:377-393`) | px4→8/cell p3 (`page:251,278`; table`:370`) | bare wide surface (`page:249-327`) | sticky sortable (`table:323-440`) | timing/chips/link (`page:259-318`; table`:420-431`) | N/A chart0 (`page:1-10`) | title/Timing/Home/Mobile (`page:250-274`) | banners/skeleton/empty (`page:279-282`; table`:248-320`) | mobileVisible列hide (`table:335-376`) | common CAGR/name一致、MDD N/A (`table:377-417`) | as-of + FoF/BM/sort legend (`page:266-342`) |
| `/dashboard` | h1 2xl→3xl/signal3xl (`page.tsx:568-632`) | semantic/chart destructive (`:561-691`) | px4→sm8/gap6 (`:563-622`) | mostly bare (`:589-597`) | MTD sticky table (`mtd-daily-table.tsx:117-200`) | selectors/range (`page:565-703`) | return/pie/MTD charts (`:659-725`) | independent header (`:563-586`) | hidden/loading/error (`:548-616,741-749`) | lg signal/pie分岐 (`:622-680`) | return+dot helper一致 (`mtd table:38-44`; page`:638-677`) | as-of/signal/pending/pie legend/MTD note (`page:579-668`; table`:211-220`) |
| `/deterioration` | canonical h1 2xl→3xl (`page.tsx:1178-1180`); section差分=table sm (`page.tsx:1282`) | label/dot/trend palette (`:77-152`) | px4 py8/cell p3 (`:1172-1239,1289`) | Accordion bare (`:1279-1431`) | 14-col sortable (`:154-278,1281-1435`) | chips/sort/expand (`:1203-1339`) | detail SVG+tooltip (`:437-1000`) | title/Home/Mobile (`:1174-1201`) | skeleton/error/empty (`:1124-1167,1438`) | md hide/detail PC only (`:1296-1417`) | 4 dot helpers一致、badge/trend N/A (`:1351-1408`) | as-of/chart legend/detail headings; Accordion title only・hintなし (`:819-855,976-994,1193-1198,1280`) |
| `/docs` | PageHeader/accordion/body xs-sm (`page-header.tsx:54-65`; accordion`:28-38`) | semantic/sky/amber (`docs/*.tsx`) | p4→8/cards p4→6 (`page.tsx:32-60`) | 4 GlassCard (`:38-63`) | 2 content tables (`methodology-content.tsx:58-77`) | 4 accordions (`page:38-62`) | N/A chart0 (`docs/*.tsx`) | PageHeader/Mobile/Theme (`page-header:53-70`) | dynamic loading (`page:9-28`) | md gaps/table scroll (`:32-60`) | single content DOM、差N/A (`:32-64`) | subtitle/hints/definitions/disclosures/references全抽出 (`docs/*.tsx`) |
| `/drawdowns` | canonical PageShell h1 (`page.tsx:80`; `page-shell.tsx:30`); section差分=h2 lg/numeric right (`page.tsx:108-145`; table`:43-67`) | primary/muted/drawdown red (`page:109,134`; table`:64`) | space6→8/card p6 (`page:105-145`) | GlassCard 2/3 (`:107-140`) | one responsive table (`table:32-75`) | chart pointerのみ (`chart:186-193`) | responsive SVG (`chart:186-193`) | PageShell (`page:80`) | loading/banner/empty (`:81-103`; table`:27-29`) | md column hide (`table:39-62`) | drawdown red共通、差0 (`table:64-69`) | worst10/recovery note + chart legend/tooltip (`page:143-146`) |
| `/faq` | h1 2xl→3xl/question sm (`page-header:54-65`; page`:149-160`) | semantic/sky links (`page:45-68,390-430`) | p4→8/card p4→6 (`:342-358`) | GlassCards (`:287-438`) | markdown/glossary tables (`:42-68,359-380`) | Accordion/language/links (`:257-438`) | N/A chart0 (`:3-13`) | PageHeader+language (`:345-349`) | Suspense loading (`:444-458`) | md/table scroll (`:342-360`) | single DOM、link色共通 (`:45-68,223-231`) | subtitle/answers/glossary/references (`:31-68,149-160,359-430`) |
| `/metrics` | canonical PageShell h1 (`page.tsx:134`; `page-shell.tsx:30`); section差分=table h2 lg/chart h3 xl (`metrics-table.tsx:62-66`; chart`:272-274`) | negative red/up-down palette (`table:89-116`; chart`:272-305`) | table py2/chart mt8 (`table:68-116`; page`:177-191`) | table bare/chart card (`chart:486`) | metric+chart aux tables (`table:65-121`; chart`:281-308`) | PF nav/tooltip (`page:133-196`; chart`:630-689`) | custom SVG bars (`chart:486-715`) | PageShell (`page:133`) | loading/error/no-data (`:135-166`) | scroll/responsive SVG (`table:65`; chart`:486`) | metric inline condition共通 (`table:89-116`) | Analysis Period/tooltip/legend (`page:177-183`; chart`:272-715`) |
| `/monthly-returns` | canonical PageShell h1 (`page.tsx:231`; `page-shell.tsx:30`); section差分=h2 lg/cell xs→sm mono (`table:196-199,387-430`) | getValueClass/amber pending (`:289-466`) | gap2/cell px1→2 py3 (`:196,285`) | bare table/badges (`:285-425`) | 2-row header (`:285-544`) | show/pager (`:205-268`) | N/A chart0 (`page.tsx:3-22`) | PageShell (`page:231`) | loading/banner/pending (`page:232-269`) | month label/ticker md (`table:391-544`) | one row/helper、一致 (`table:428-490`) | MTD/Partial/PeriodNotes/footer (`table:398-572`; period-notes`:38-71`) |
| `/monthly-trade` | canonical PageShell h1 (`page.tsx:165`; `page-shell.tsx:30`); section差分=h2 lg/labels xs-sm (`table:122-132`) | active sky/warning amber/return helper (`:138-160,502`) | toolbar gap2/cell p4x3 (`:122,239`) | bare/Next amber panel (`:120,349-398`) | wide 9-col table (`:239-312`) | toggles/load/pager (`:135-223`) | N/A chart0 (`page:4-18`) | PageShell (`page:164`) | loading/error/no-data (`page:166-205`) | toolbar sm/columns md-lg (`table:120-289`) | same returnColor、差0 (`:502-741`) | count/FoF/Next/Preview/MTD badges (`:123-132,349-398,529-547`) |
| `/offline` | h1 2xl/body default (`page.tsx:8-14`) | secondary icon/muted (`:6-14`) | p4/card p8 (`:6-8`) | GlassCard max-md (`:7`) | N/A table0 (`:1-18`) | N/A control0 (`:1-18`) | N/A chart0 (`:1-18`) | no nav (`:1-18`) | offline static state (`:4-18`) | fluid max-width (`:6-7`) | single DOM、差N/A (`:6-15`) | connection explanation muted中央 (`:12-14`) |
| `/rolling-returns` | canonical PageShell h1 (`page.tsx:86`; `page-shell.tsx:30`); section差分=h2 lg/tables sm (`page.tsx:117-166`; dist`:72`) | summary helper/distribution PC red (`summary:47-51`; dist`:41-44`) | space6→8/card p4→6 (`page:113-164`) | 3 GlassCard (`:116-174`) | summary+distribution dual tables (`:135-160`) | period pills (`chart:325-356`) | rolling CAGR SVG (`chart:363-370`) | PageShell (`page:86`) | loading/error/no-data (`:87-131`) | desktop/mobile table branches (`summary:97,309`; dist`:71,136`) | distribution negative PC red/mobile継承=不一致1 (`dist:104-169`) | 3 headings+axis/legend/tooltip、caption0 (`page:136-166`; chart) |
| `/summary` | canonical PageShell h1 (`page.tsx:91`; `page-shell.tsx:30`); section差分=h2 lg/mono (`summary-table.tsx:138-165`) | negative red/hover (`:140-205`) | shell md/cell py2 px4 (`page-shell:25-56`; table`:143`) | bare wrapper (`table:138-146`) | single scroll table (`:143-257`) | shell controls (`page.tsx:90-129`) | N/A chart0 (`:9-12`) | PageShell (`:90`) | hidden/loading/error/no-data (`:80-110`) | table scroll (`table:143-257`) | single DOM inline color共通 (`:190-259`) | Analysis Period muted中央 (`page:120-125`) |
| `/trades` | emoji4xl/h1 2xl→3xl (`page.tsx:7-15`) | semantic card/muted (`:5-22`) | px4/card p8 (`:5-6`) | rounded2xl card (`:6`) | N/A route table0 (`:1-27`) | dashboard Link (`:16-22`) | N/A chart0 (`:1-27`) | CTAのみ (`:16-22`) | blocked static (`:3-27`) | h1 md (`:5-10`) | route single DOM、差N/A (`:5-24`) | blocked explanation muted中央 (`:13-15`) |
| `/admin` | h1 2xl→3xl/h3 lg-sm (`page.tsx:211-219,409`) | health emerald/amber/layer palette (`:275-473`) | p4→8/space6→8 (`:211-214`) | max6xl GlassCards (`:212,399,1202`) | DB portfolio table (`:799-1152`) | save/sync/CRUD (`:223-270,1271-1433`) | N/A chart0 (`:3-41`) | title/Mobile/toolbars (`:213-381`) | auth/login/loading/banner/empty (`:170-205,388-449,1453`) | md/hide/grid reflow (`:211-269,452-520`) | health short copy shares parent state color、一致 (`:452-506`) | auth/DB hints/card descriptions/count/empty (`:170-203,409-515,1204-1455`) |
| `/admin/fof` | h1 2xl/card h3 lg (`page.tsx:310-418`) | primary/muted/destructive (`:392-510`) | p4→8/stack6 (`:299-380`) | GlassCard list/editor (`:342-376`; FoFEditor`:139`) | WeightBreakdown table (`WeightBreakdown:165-213`) | CRUD/recalc/reorder (`page:331-517`) | N/A chart0 (`:3-26`) | back admin/title (`:301-319`) | auth/loading/empty/banner (`:286-356`) | same DOM/md flex (`:299-380`) | double DOM0、semantic states共通 (`:299-517`) | subtitle/empty/components/editor notes (`:313-432`; FoFEditor`:156-304`) |
| `/admin/folders` | h1 2xl/h2 lg/item sm (`page.tsx:281-712`) | semantic primary/destructive (`:312-499`) | p4→8/space2-6 (`:270-363`) | create/list/move cards (`:297-830`) | N/A table0 (`:3-30,352-724`) | CRUD/expand/bulk (`:300-830`) | N/A chart0 (`:3-30`) | back admin/title (`:272-290`) | auth/loading/empty/saving (`:256-361,616-817`) | same DOM/fixed bar shrink (`:270,725-830`) | double DOM0、selection色共通 (`:369-830`) | subtitle/empty/count/move note (`:284-287,358-817`) |
| `/admin/visibility` | h1 2xl/h2 lg/table sm (`page.tsx:596-1209`) | emerald/amber/red/sky (`:756-1228`) | p4→8/space6→8/cell py2-3 (`:581-1185`) | GlassCard/modal (`:648-776`; modal`:249-310`) | visibility matrix (`page:772-1360`) | tier/page toggles/save/modal (`:623-1360`) | N/A chart0 (`:3-34`) | back admin/TierSelector (`:581-623`) | auth/error/loading/disabled (`:550-1360`) | same DOM/grid/table scroll (`:668-1360`) | double DOM0、status色共通 (`:772-1360`) | section descriptions/status/PF metadata/modal help (`:661-1228`; modal`:215-409`) |

## §2.5 Viewport state-color differences — 21/21

| page | dual DOM / helper result | verdict |
|---|---|---|
| `/` | single DOM; no state-color concept (`page.tsx:25-49`) | N/A |
| `/annual-returns` | one return cell/helper (`annual-returns-table.tsx:68-74,218-236`) | match |
| `/compare` | one SVG/tooltip positive-negative condition (`comparison-chart.tsx:622-753`) | N/A |
| `/compare-returns` | one table/getReturnColor (`compare-returns-table.tsx:29-34,264-275`) | match |
| `/compare-summary` | one table; common CAGR/name, MDD desktop-only (`compare-summary-table.tsx:323-417`) | match/N/A |
| `/dashboard` | MTD and deterioration dots share helpers, size only differs (`mtd-daily-table.tsx:38-44`; `dashboard/page.tsx:638-677`) | match |
| `/deterioration` | G1/G2/P/p̄ share four helpers; badge/trend desktop-only (`page.tsx:1351-1408`) | match/N/A |
| `/docs` | single content DOM (`docs/page.tsx:32-64`) | N/A |
| `/drawdowns` | one drawdown red cell (`drawdowns-table.tsx:64-69`) | match |
| `/faq` | single DOM semantic/link color (`faq/page.tsx:45-68,223-231`) | N/A |
| `/metrics` | single table inline state condition (`metrics-table.tsx:89-116`) | N/A |
| `/monthly-returns` | same row/getValueClass (`monthly-returns-table.tsx:428-490`) | match |
| `/monthly-trade` | same row/returnColor (`monthly-trade-table.tsx:502-741`) | match |
| `/offline` | single static DOM (`offline/page.tsx:6-15`) | N/A |
| `/rolling-returns` | distribution PC uses `valueClass`; mobile Median/P10/Positive omits it (`rolling-returns-distribution-table.tsx:41-44,104-169`) | **mismatch 1 pattern / 6 logical fields** |
| `/summary` | single table inline condition (`summary-table.tsx:190-259`) | N/A |
| `/trades` | current route single blocked DOM (`trades/page.tsx:3-24`) | N/A |
| `/admin` | short/long health copy shares emerald/amber parent (`admin/page.tsx:452-506`) | match |
| `/admin/fof` | no dual DOM; semantic states shared (`admin/fof/page.tsx:299-517`) | N/A |
| `/admin/folders` | no dual DOM; selection/destructive shared (`admin/folders/page.tsx:369-830`) | N/A |
| `/admin/visibility` | no dual DOM; toggle/status shared (`admin/visibility/page.tsx:772-1360`) | N/A |

Rolling P10一次訂正: `rolling-returns-summary-table.tsx`の`p10|P10`は **0件**。P10実表示はdistribution `rolling-returns-distribution-table.tsx:108,145,158-159`。PC helper適用=`:41-44,112-121`、mobile helper欠落=`:155-169`。

## §2.6 Explanatory-copy / note / legend differences — 21/21

| page | L inventory (font/color/placement) |
|---|---|
| `/` | description default muted中央、holiday note sm muted同card (`page.tsx:33-39`) |
| `/annual-returns` | YTD/Partial xs muted row内、partial notes xs muted table下、axis 11/12px、legend sm chart下 (`annual-returns-table.tsx:218-284`; chart`:273-443`) |
| `/compare` | as-of sm muted header下、control labels sm muted、legend sm chart下、Since 10px muted (`page.tsx:270-330`; chart`:694-753`) |
| `/compare-returns` | as-of sm muted header下、FoF/BM/sort/period definitions xs muted table下 (`page.tsx:171-252`) |
| `/compare-summary` | as-of sm muted header下、FoF/BM/sort xs muted table下 (`page.tsx:266-342`) |
| `/dashboard` | as-of/signal sm muted、Pending/pie/MTD notes xs muted near widgets (`dashboard/page.tsx:579-668`; `mtd-daily-table.tsx:211-220`) |
| `/deterioration` | as-of sm muted、chart legend xs muted、detail headings sm muted、Accordion titleのみ・hintなし (`page.tsx:819-855,976-994,1193-1198,1280`) |
| `/docs` | subtitle sm muted、Accordion hint xs muted、definitions/disclosures/references xs-sm muted in sections (`components/docs/*.tsx`) |
| `/drawdowns` | worst10/recovery note sm muted italic centered page末尾、chart legend/tooltip (`page.tsx:143-146`) |
| `/faq` | subtitle/answers/glossary/references sm muted in header/cards (`faq/page.tsx:31-68,149-160,359-430`) |
| `/metrics` | Analysis Period sm muted table下、chart period sm muted、tooltip/legend sm (`metrics/page.tsx:177-183`; chart`:272-715`) |
| `/monthly-returns` | MTD/Partial/Pending xs badges row内、PeriodNotes sm muted table下、footer xs muted (`monthly-returns-table.tsx:398-572`; period-notes`:38-71`) |
| `/monthly-trade` | count/FoF xs-sm heading横、Next/Preview/MTD badges xs panel/row内 (`monthly-trade-table.tsx:123-132,349-398,529-547`) |
| `/offline` | connection explanation default muted centered card内 (`offline/page.tsx:12-14`) |
| `/rolling-returns` | three headings lg card上、chart axis/legend/tooltip; table caption/note absent (`rolling-returns/page.tsx:136-166`) |
| `/summary` | Analysis Period sm muted centered table下 (`summary/page.tsx:120-125`) |
| `/trades` | blocked explanation default muted centered card内 (`trades/page.tsx:13-15`) |
| `/admin` | auth/loading default muted中央、DB hint xs muted、management descriptions sm muted、count xs muted (`admin/page.tsx:170-203,409-515,1204-1455`) |
| `/admin/fof` | subtitle sm muted、empty/help/preview/allocation xs-sm near cards/editor (`admin/fof/page.tsx:313-432`; `FoFEditor.tsx:156-304`) |
| `/admin/folders` | subtitle sm muted、empty/count/move/saving xs-sm near lists/fixed bar (`admin/folders/page.tsx:284-817`) |
| `/admin/visibility` | section descriptions sm muted、status/PF metadata xs、modal help xs/11px (`admin/visibility/page.tsx:661-1228`; `ManageTiersModal.tsx:215-409`) |

HTML `<caption>`/`<figcaption>`の採用は21ページで0。凡例・注記は個別div/p/spanへ分散している。

## §3 Unified design candidates

| axis | observed divergence | unified candidate |
|---|---|---|
| A | **将軍全21自己検証**: ページタイトルは器3系統(PageShell/PageHeader/独自)とも同一canonical h1で**15/21がcanonical**。noncanonical6のみ: offline・trades・admin・admin/fof・admin/folders・admin/visibility（独自h1/専用静的画面）。section/table見出し(h2/h3)のサイズ階層は別途混在(要token化) | **基準=summary(PageShell canonical=`text-2xl md:text-3xl font-bold tracking-tight text-foreground`)**。①noncanonical6のh1/専用画面を適用対象ごとに整理しcanonical classへ統一 ②タイトル器をPageShell/PageHeaderへ一本化(独自canonical7のclassコピー=DRY解消) ③section見出しh2/h3階層をtoken化 |
| B | semantic token/inline hex/status class混在 | semantic palette + chart/status constants |
| C | sm/md shell breakpoint、cell density分散 | shell=`p/px-4 md:p/px-8`; named density |
| D | equivalent data surfaceがbare/card混在 | `DataSection surface=bare|card` |
| E | sticky/hide/dual-mobile table policy無名 | `TableShell` + critical-column policy |
| F | touch target不足、link affordance不統一 | mobile 48px floor + focus/underline contract |
| G | SVG/Recharts/tooltip/legend/palette個別 | shared ChartTooltip/Axis/Legend/palette |
| H | header 4系統、PageNavigation null | slotted `PageHeader` + route policy |
| I | loading height/banner/naked error混在 | `PageState` variants + reserved-height token |
| J | hide/scroll/duplicate/detail policy分散 | named responsive data-surface policy |
| K | Rolling distributionだけmobile負値helper欠落 | PC/mobile cell rendererを共有し、同一state-color helper適用を型/rendererで強制 |
| L | caption0、notes/legend typographyがxs/sm・位置とも個別 | `DataNote`/`Legend`/semantic `<caption>` token（note=xs muted、section description=sm muted、placement slots） |

## §4 CE / ME / numeric verification

- route inventory: viewer **17/17** + admin **4/4** = **21/21**、重複0、欠落0。
- axes: **12/12** (A-L)。matrix: **21×12 = 252/252** cells。
- fragments: **6/6** integrated。
- K: **21/21**、未確認0、mismatch 1 pattern / 6 logical fields、根拠付きN/Aのみ。
- L: **21/21**、font/color/placement確認、未確認0。caption/figcaption不在は現物根拠付き。
- Rolling P10: summary **0件**、distribution実所在確認済み。
- target files changed by this task: **1件**（本書のみ）。
- placeholder 0、根拠なしN/A 0。全体判定 **PASS**。

### §4.1 Three-fragment element/file-line re-verification

- source fragments: `fragments/mece_reverify_hanzo_20260722.md`, `fragments/mece_reverify_saizo_20260722.md`, `fragments/mece_reverify_kotaro_20260722.md` = **3/3**。
- fragment coverage: **84/84 × 3 = 252/252** cells、pages **21/21**、axes **12/12**、未確認 **0**。
- corrections: hanzo **5** + saizo **4** + kotaro **2** = **11/252**。二次再照合のtrue positive **11/11**、false positive **0/11**。
- A-axis page-title verdict: canonical **15/21**、noncanonical **6/21**。page title器とsection/table headingは分離して記録。
- preserved facts: Rolling P10はsummary **0件**、distribution実所在。viewport色差はdistribution **1 pattern / 6 logical fields**。

| # | page/axis | before | after | primary file:line |
|---:|---|---|---|---|
| 1 | annual-returns A | heading refsに`mono`を混在 | PageShell h1、section h3/h2、numeric monoを分離 | `annual-returns/page.tsx:204`; `annual-returns-chart.tsx:212-215`; `annual-returns-table.tsx:102-108,225-256` |
| 2 | compare A | page範囲をchart h3根拠化 | canonical h1とchart h3を分離 | `compare/page.tsx:261-263`; `comparison-chart.tsx:482` |
| 3 | compare J | page controls範囲をsingle SVG根拠化 | responsive shellとSVG所在を分離 | `compare/page.tsx:254-296`; `comparison-chart.tsx:506-621` |
| 4 | deterioration A | h1を2xlのみと記述 | canonical 2xl→3xl h1 + table heading | `deterioration/page.tsx:1178-1180,1282` |
| 5 | deterioration L | 存在しないAccordion hint | as-of/legend/detail heading + Accordion titleのみ | `deterioration/page.tsx:819-855,976-994,1193-1198,1280` |
| 6 | drawdowns A | section h2のみ | canonical PageShell h1 + section h2 | `drawdowns/page.tsx:80,108-145`; `page-shell.tsx:30` |
| 7 | metrics A | table h2/chart h3のみ | canonical PageShell h1 + section headings | `metrics/page.tsx:134`; `page-shell.tsx:30`; `metrics-table.tsx:62-66`; `up-down-market-chart.tsx:272-274` |
| 8 | monthly-returns A | table h2/cellのみ | canonical PageShell h1 + section/table typography | `monthly-returns/page.tsx:231`; `page-shell.tsx:30`; `monthly-returns-table.tsx:196-199,387-430` |
| 9 | monthly-trade A | table h2/labelsのみ | canonical PageShell h1 + section labels | `monthly-trade/page.tsx:165`; `page-shell.tsx:30`; `monthly-trade-table.tsx:122-132` |
| 10 | rolling-returns A | section/table headingsのみ | canonical PageShell h1 + local headings | `rolling-returns/page.tsx:86,117-166`; `page-shell.tsx:30`; `rolling-returns-distribution-table.tsx:72` |
| 11 | summary A | PageShell名のみでh1根拠欠落 | canonical PageShell h1 + table typography | `summary/page.tsx:91`; `page-shell.tsx:30`; `summary-table.tsx:138-165` |

差分要約: A軸9件はpage title器を先頭に固定してlocal headingを後置、Compare-JはSVG所在をcomponentへ移動、Deterioration-Lは不存在hintを除去。3 fragmentの他241セルは現記述と一次実装が一致したため変更なし。

## §5 Causal links

origin: `[[殿指示_デザイン統一_20260722]] -> [[6断片_A_L全数調査]] -> [[21x12_252セル_MECE_v2]]`  
viewport-origin: `[[Rolling_distribution_mobile_helper欠落]] -> [[PC_mobile状態色不一致]] -> [[共通cell_renderer提案]]`  
copy-origin: `[[caption不在_notes分散]] -> [[L軸全数抽出]] -> [[DataNote_Legend_caption_token提案]]`
reverify-origin: `[[三分割252セル再検証]] -> [[要素種別_所在混同11件]] -> [[MECE正本訂正11_252]]`
