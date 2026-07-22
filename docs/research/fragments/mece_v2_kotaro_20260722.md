# MECE v2 fragment — Compare Summary / Deterioration / Admin root

<!-- origin: [[cmd_karo_recon2_mece_v2_kotaro_20260722]] -> [[A_L_36_cell_audit]] -> [[dm_signal_page_style_mece_v2]] -->

軸定義は最終MECE正本 `docs/research/dm-signal-page-style-diff-mece_20260722.md:40-49` のA-Jに、K=viewport二重DOM・状態色、L=説明文・注釈・凡例・captionを追加したもの。

## Compare Summary (`/compare-summary`)

| 軸 | 現物結果 | 一次根拠 |
|---|---|---|
| A Typography | h1=`text-2xl md:text-3xl font-bold tracking-tight`、as-of=`text-sm`、表=`text-sm`、凡例=`text-xs` | `frontend/app/compare-summary/page.tsx:251-273,329-342`; `frontend/components/compare-summary-table.tsx:323-325` |
| B Color | page background token、FoF紫/BM amber、CAGR正green/負red、MDD red | `page.tsx:248-249,329-337`; `compare-summary-table.tsx:377-393` |
| C Spacing | shell `px-4 md:px-8`、header `pt-4 md:pt-8`、content `py-4 md:py-8`、cell `px-3 py-3` | `page.tsx:251,278`; `compare-summary-table.tsx:333,370` |
| D Container/Card | `max-w-7xl xl:max-w-[120rem]`の裸surface。データcard/radius/shadowなし | `page.tsx:249-251,277-278,321-327` |
| E Table | 単一sortable table、sticky header/name列、row border/hover、縦70→82vh | `compare-summary-table.tsx:323-376,428-440` |
| F Interaction | TimingToggle、folder chip、sortable header、PF Link hover underline | `page.tsx:259,284-318`; `compare-summary-table.tsx:329-352,420-431` |
| G Chart | N/A。page/component import・描画にchart/canvas/svg可視化なし（sort icon SVGのみ） | `page.tsx:1-10,321-342`; `compare-summary-table.tsx:193-245` |
| H Header/Nav | PageNavigation+title+Timing、右HomeButton/MobileMenu、as-of別行 | `page.tsx:250-274` |
| I State | signals/errorはMessageBanner、loadingはtable skeleton 5行、empty中央muted | `page.tsx:279-282`; `compare-summary-table.tsx:248-320` |
| J Responsive | shell md/xl、列`mobileVisible:false`を`hidden md:table-cell`、name幅160→200、凡例sort説明はmdのみ | `page.tsx:251,278,339-341`; `compare-summary-table.tsx:335-340,372-376` |
| K Viewport color | PC/mobile別table/cardは0。単一cellなのでFoF/BM・CAGR色は一致。MDDはmobile非表示=N/A。deterioration dot helperは列SSOTに定義0で双方未描画=N/A。不一致0 | `compare-summary-table.tsx:323-440`; `frontend/lib/types/compare-summary.ts:113-249`; `compare-summary-table.tsx:144-171,377-417` |
| L Copy/caption | as-of注釈=`text-sm muted` header下。凡例はFoF/BM=`text-xs muted`、sort説明だけ`hidden md:flex`。HTML caption/figcaption・他説明文なし | `page.tsx:266-273,329-342` |

## Deterioration (`/deterioration`)

| 軸 | 現物結果 | 一次根拠 |
|---|---|---|
| A Typography | h1=`text-2xl font-bold`、as-of/表=`text-sm`、chip/badge=`text-xs`、trend=`text-lg` | `frontend/app/deterioration/page.tsx:1178-1198,1253-1265,1282,1402-1408` |
| B Color | label palette green/yellow/orange/indigo/red/gray、dot helper SSOT、trend green/gray/orange/red | `deterioration/page.tsx:77-102,146-152`; `frontend/lib/constants/deterioration-colors.ts:28-86` |
| C Spacing | outer `px-4 py-8`、header mb6、filters gap1/2 mb3/4、cells `px-3 py-3` | `deterioration/page.tsx:1172-1174,1203-1239,1289-1298,1343-1414` |
| D Container/Card | max7xl単一container、表はAccordion内でcard surfaceなし、detail `bg-muted/10` | `deterioration/page.tsx:1172,1279-1282,1417-1431`; `components/ui/accordion.tsx:22-46` |
| E Table | single full-width sortable table、14列、横scroll、desktop row detail | `deterioration/page.tsx:154-278,1281-1435` |
| F Interaction | folder/status chips、sort、desktop row click、Accordion開閉。mobile row expand無効 | `deterioration/page.tsx:1203-1277,1285-1339`; `components/ui/accordion.tsx:24-45` |
| G Chart | desktop展開detailにStepGraph/ProbabilityChart、custom SVG、ChartTooltip、凡例 | `deterioration/page.tsx:437-858,971-1000` |
| H Header/Nav | PageNavigation+title、右HomeButton/MobileMenu、as-of別行。Timingなし | `deterioration/page.tsx:1174-1201` |
| I State | loading skeleton5、error裸`text-red-500`、empty中央muted、detail loading/error/no-history | `deterioration/page.tsx:1124-1167,954-970,1438-1444` |
| J Responsive | desktop専用列=`hidden md:table-cell`、dot 10→12px、detailは`!isMobile`のみ | `deterioration/page.tsx:1296-1298,1351-1417` |
| K Viewport color | 二重table/card 0。mobile可視G1/G2/P/p̄はPCと同じ4 helperで色一致、sizeのみ10/12。Label/Trendはmobile非表示=N/A。不一致0 | `deterioration/page.tsx:194-263,1351-1408`; `deterioration-colors.ts:28-86` |
| L Copy/caption | as-of=`text-sm muted mt-1`。Accordion hint=`text-xs muted`。chart凡例5項目=`text-xs muted`。detail見出し=`text-sm muted`。empty/error文あり。HTML caption/figcaptionなし | `deterioration/page.tsx:1195-1198,819-855,976-994,1438-1444`; `components/ui/accordion.tsx:28-38` |

## Admin root (`/admin`)

| 軸 | 現物結果 | 一次根拠 |
|---|---|---|
| A Typography | h1=`text-2xl md:text-3xl bold tracking-tight`、section h3=`text-lg`/`text-sm`、body sm、metadata xs、numeric mono | `frontend/app/admin/page.tsx:211-219,409-417,476-484,513-524` |
| B Color | background/theme tokens、health emerald/amber、layer blue/amber/emerald/purple、link cards primary/amber/purple | `admin/page.tsx:211,275-378,452-473,1202-1264` |
| C Spacing | outer `p-4 md:p-8`、stack `space-y-6 md:space-y-8`、header space4、cards p4、grids gap4/8 | `admin/page.tsx:211-214,399-441,519-522,1267-1270` |
| D Container/Card | max-w-6xl、GlassCard共通`glass-card`、DB/editor/nav/link surfacesにp4 | `admin/page.tsx:212,399,1202-1269`; `components/ui/glass-card.tsx:8-12` |
| E Table | DB portfolio table=`overflow-x-auto w-full text-sm`、header xs muted、row borders、numeric right mono | `admin/page.tsx:799-802,1031-1152` |
| F Interaction | save/sync/logout、DB disclosure/refresh、sort/select、CRUD/move/copy、3管理リンク | `admin/page.tsx:223-270,400-438,1201-1264,1271-1433` |
| G Chart | N/A。Admin root/page依存にchart/canvas可視化なし。DBはcards/tableのみ | `admin/page.tsx:3-41,397-1199` |
| H Header/Nav | title+MobileMenu、次行action toolbar、展開layer toolbar。HomeButton/PageNavigationなし | `admin/page.tsx:213-381` |
| I State | auth check/loading、LoginModal、portfolio loading、MessageBanner、DB loading/failure、editor empty、ErrorBoundary | `admin/page.tsx:170-205,388-397,440-449,1192-1196,1437-1459` |
| J Responsive | outer/title/button sizes md、labels xs/sm/mdでhide、health flex-col→row、stats 1→2→4、toolbar wrap | `admin/page.tsx:211-269,452-520,714-755,1270-1361` |
| K Viewport color | Admin全体のPC/mobile二重page/table/cardは0。healthの短縮copyだけ`hidden sm:inline`/`sm:hidden`だが親health状態class/emerald・amber dotを共有し色一致。button labelsのhideも同一DOM。不一致0 | `admin/page.tsx:452-506,223-270,1271-1361` |
| L Copy/caption | auth/loading文はdefault muted中央。DB disclosure hint=`text-xs muted`、health説明=`text-xs muted`、各管理card説明=`text-sm muted`、portfolio count=`text-xs muted`、empty文=muted中央。table/chart caption・凡例なし | `admin/page.tsx:170-203,409-417,476-515,1204-1254,1294-1301,1453-1455` |

## 完全性・二値計測

| 指標 | 結果 |
|---|---:|
| ページ | 3/3 |
| A-Lセル | 36/36 |
| K確認 | 3/3 |
| K不一致 | 0 |
| K根拠付きN/A | Compare 2、Deterioration 2、Admin 1 |
| K未確認 | 0 |
| L確認 | 3/3 |
| L未確認 | 0 |
| 根拠なしN/A | 0 |

## 因果リンク

- [[dm_signal_page_style_mece_v2]]
- [[A_L_36_cell_audit]]
- 実ファイル: `docs/research/fragments/mece_v2_kotaro_20260722.md`
