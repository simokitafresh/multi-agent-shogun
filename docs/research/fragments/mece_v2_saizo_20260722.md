# DM-Signal MECE v2 — monthly-trade / compare-returns / compare

検証日: 2026-07-22。一次情報root: `/mnt/c/Python_app/DM-signal`。A–Jは完成版の軸定義、Kはviewport二重DOMと状態色、Lは説明文・注釈・凡例・caption。最終MECE文書は未編集。

## A–L 36/36セル

| page | A typography | B color | C spacing | D container/card | E table | F interaction | G chart | H header/nav | I states | J responsive | K viewport/state color | L explanation/legend/caption |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Monthly Trade | h2 `text-lg font-semibold`; count `text-sm`; badges `text-xs` (`frontend/components/monthly-trade-table.tsx:122-132`) | semantic foreground/muted、active sky、warning amber、return red/emerald (`:138-160,502-507`) | toolbar `gap-2 mb-4`; cells `px-4 py-3` (`:122,239-289`) | root `w-full overflow-x-auto`; Next Signalだけamber border/surface (`:120,349-398`) | 単一wide table、9列、full/simpleで列制御 (`:239-312`) | View/Show/pager buttons、Load All (`:135-223`) | N/A: pageは`MonthlyTradeTable`のみ、chart import/JSX 0 (`frontend/app/monthly-trade/page.tsx:4-18,194-203`) | `PageShell pageTitle="Monthly Trade"` (`frontend/app/monthly-trade/page.tsx:164-165`) | loading 300px、error/no-data banner (`:166-205`) | toolbar `flex-col sm:flex-row`; columns `md/lg` hide、横scroll (`monthly-trade-table.tsx:120-138,239-289`) | 単一table。Return cellは全viewport共通`returnColor`; desktop限定列は根拠付きN/A。差0 (`:502-507,514-741`) | count/FoF、Next Signal/Preview、MTD/Partial/Pending badgeを全抽出。詳細はL表 (`:123-132,349-398,529-547`) |
| Compare Returns | h1 `2xl→md:3xl`; metadata/table `text-sm`; legend `text-xs` (`frontend/app/compare-returns/page.tsx:161-177,233-252`) | return green/red、FoF purple、BM amber、semantic borders (`frontend/components/compare-returns-table.tsx:29-34,177-283`) | shell `px-4 md:px-8`; legend `mt-4 gap-4` (`compare-returns/page.tsx:156,182,234`) | borderless page、sticky table background/borders (`compare-returns-table.tsx:177-191`) | 単一sortable table、8期間、sticky name、md列hide (`:177-283`) | timing、folder chips、clear、sortable headers (`compare-returns/page.tsx:164,188-222`; table`:183-199`) | N/A: page childはtableのみ、chart import/JSX 0 (`compare-returns/page.tsx:3-17,225-252`) | 独自header、Home/Mobile、PageNavigation(null) (`:156-178`) | hidden/error banners、skeleton/empty (`:138-149,183-186`; table`:120-175`) | `md/xl/lg`; 単一tableの非mobile列を`hidden md:table-cell` (`table:122-155,177-191`) | 二重DOMなし。全return cellが共通`getReturnColor`; N/A、差0 (`table:29-34,264-275`) | as-of metadata + FoF/BM/sort/期間説明の4群を全抽出。詳細はL表 (`page:171-177,233-252`) |
| Compare Chart | h1 `2xl→md:3xl`; labels `text-sm`; chart h3 `text-lg` (`frontend/app/compare/page.tsx:261-274,299-325`; `comparison-chart.tsx:478-504`) | semantic page、PF palette/BM color、positive/negative tokens (`comparison-chart.tsx:519-543,645-680`) | outer `p-4 sm:p-8`; stack `space-y-6 md:space-y-8`; controls gap4 (`compare/page.tsx:254-347`) | page/chart bare、tooltipだけcard/border/shadow (`ChartTooltip.tsx:31-53`) | N/A: page/componentにtable JSX 0 (`compare/page.tsx:253-384`; `comparison-chart.tsx:478-756`) | Accordion、Select、reset、chart toggles (`compare/page.tsx:277-347`; chart`:480-504`) | 単一interactive SVG、axes、tooltip、legend (`comparison-chart.tsx:505-753`) | title/Home/Mobile/PageNavigation(null) (`compare/page.tsx:257-275`) | page error/loading、zero selection、chart loading (`:230-250,349-381`) | `sm/md` shell、wrap、`useIsMobile`はstroke widthのみ (`compare/page.tsx:254-296`; chart`:158,525-540`) | 二重DOMなし。tooltip/final returnは共通positive/negative条件; N/A、差0 (`chart:622-753`) | as-of、selector max7、Bench/From labels、SVG title、tooltip date、legend/`Since`を全抽出。詳細はL表 |

## K軸全数（未確認0）

| page | 二重DOM | PC/mobile状態色比較 | 判定・根拠 |
|---|---|---|---|
| Monthly Trade | なし。1 tableの列visibility | Returnは同じcell・同じ`returnColor`（null無色、非負foreground/dark emerald、負red）。Month/Signal/Return Period/Cumulative/Price Movementはdesktop限定で比較対象なし | 一致1、N/A5、不一致0。`frontend/components/monthly-trade-table.tsx:239-312,502-507,514-750` |
| Compare Returns | なし。1 tableの`mobileVisible`列制御 | 表示される全return cellが同じ`getReturnColor`（正green、負red、0/null無色） | N/A（共通DOM）、不一致0。`frontend/components/compare-returns-table.tsx:29-34,177-188,264-275` |
| Compare Chart | なし。1 SVG/tooltip/legend | tooltipとfinal returnが全viewportで同じ`text-chart-positive`/`text-chart-negative`条件 | N/A（共通DOM）、不一致0。`frontend/components/comparison-chart.tsx:505-753` |

K集計: 二重DOM **0/3**、一致 **1パターン**、根拠付きN/A **7件**（Monthly Trade desktop限定5 + 単一DOM2）、不一致 **0**、未確認 **0**。

## L軸全数（未確認0）

| page | 抽出対象 | font-size / color / placement | 根拠 |
|---|---|---|---|
| Monthly Trade | `FoF`, `(N months)` | `text-xs` muted badge、`text-sm text-muted-foreground`; h2 inline | `frontend/components/monthly-trade-table.tsx:123-132` |
| Monthly Trade | `Next Signal`, date、`Preview` tooltip注釈 | label `text-xs uppercase text-amber-500`; date `text-sm muted`; Preview `text-xs amber`; table直上amber panel | `:349-398` |
| Monthly Trade | `MTD` / `Partial` / `Pending` | `text-xs`; muted borderまたはamber; Month cell内inline | `:529-547` |
| Compare Returns | `as of` / MTD as-of / loading | `text-sm text-muted-foreground`; header下 | `frontend/app/compare-returns/page.tsx:171-177` |
| Compare Returns | `FoF` / `Benchmark`凡例 | 親`text-xs muted`; purple/amber 12px swatch; table下 | `:233-242` |
| Compare Returns | `Click column header to sort` | `text-xs muted`; `hidden md:flex`; table下 | `:243-245` |
| Compare Returns | MTD/1M/3M/6M/1Y/3Y/5Y/ALL定義 | `text-xs muted`; table下、全viewport | `:246-251` |
| Compare Chart | as-of/calculated-at | `text-sm text-muted-foreground`; header下 | `frontend/app/compare/page.tsx:270-274` |
| Compare Chart | `Select Portfolios (max 7)`, `Bench:`, `From:` | Accordion title + labels `text-sm muted`; chart前control領域 | `:277-330` |
| Compare Chart | SVG title `ポートフォリオ比較チャート` | SVG `<title>`（視覚font/colorなし）、chart内部 | `frontend/components/comparison-chart.tsx:510-518` |
| Compare Chart | tooltip date + PF/BM return | date `text-sm muted`; value rows `text-base font-bold`; absolute tooltip card | `ChartTooltip.tsx:31-53`; `comparison-chart.tsx:622-691` |
| Compare Chart | PF/BM legend + `Since date` | legend親`text-sm` center/mt4; names `text-sm`; Since `text-[10px] muted ml-5`; chart下 | `ChartLegend.tsx:12-16`; `comparison-chart.tsx:694-753` |

L集計: 説明・注釈・凡例・caption群 **12/12抽出**、font-size **12/12**、color **12/12**、配置 **12/12**（SVG titleは視覚style N/Aの根拠明記）、未確認 **0**。

## 二値結論

- pages **3/3**、axes **12/12**、matrix cells **36/36**。
- K未確認 **0**、L未確認 **0**、根拠なしN/A **0**。
- 最終MECE文書の変更 **0件**。

## 因果リンク

`[[cmd_karo_recon2_mece_v2_saizo_20260722]] -> [[dm_signal_page_style_A_L]] -> [[mece_v2_saizo_20260722]]`
