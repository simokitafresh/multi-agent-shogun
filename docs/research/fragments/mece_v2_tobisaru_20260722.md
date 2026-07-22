# MECE v2 fragment — admin/fof, admin/folders, admin/visibility

検証日: 2026-07-22。実装root: `/mnt/c/Python_app/DM-signal/frontend`。A–Jは既存完成版の軸（typography, color, spacing, card, table, interaction, chart, navigation, state, responsive）、K=PC/mobile二重DOM×状態色、L=説明文・注釈・凡例・caption。最終MECE文書は未編集。

## A–L matrix（3ページ × 12軸 = 36セル）

| page | A typography | B color | C spacing | D card | E table | F interaction | G chart | H navigation | I state | J responsive | K viewport×state color | L explanatory copy |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| admin/fof | h1 `text-2xl font-bold tracking-tight`; card title `text-lg font-semibold` (`admin/fof/page.tsx:310-313,418-421`) | semantic background/primary/muted/destructive (`:299,392,409,418,493-510`) | page `p-4 md:p-8`, stack6; cards p4/space3 (`:299-300,376-380`) | list/empty are GlassCard (`:342-356,376-379`); editor also GlassCard (`FoFEditor.tsx:139-147`) | WeightBreakdown `w-full text-sm`, header xs/border, numeric rows (`WeightBreakdown.tsx:165-213`) | create/reorder/recalc/copy/edit/delete Button; hover/disabled (`page.tsx:331-354,383-413,437-517`) | N/A: page/import graph has no chart; WeightBreakdown is table only (`page.tsx:3-26`; `WeightBreakdown.tsx:176-210`) | back `/admin` + local title; shared PageHeaderなし (`page.tsx:301-319`) | auth Loading/Login, list loading/empty, MessageBanner, recalc spinner (`:286-296,321-356,454-462`) | same DOM: outer md padding, card row flex-col→md:flex-row and gaps (`:299,380-382`) | **N/A（二重DOMなし）**。同一DOM・同一semantic state classesを共有。状態色helperのPC/mobile別適用なし (`:299-517`; componentsにhidden/md:hidden 0) | subtitle sm muted (`:313-316`); empty explanation default muted via parent (`:342-349`); Components sm muted/Allocation xs (`:421-432`); editor field help xs muted (`FoFEditor.tsx:156-209`); composition preview sm/xs (`:290-304`); WeightBreakdown headings/errors/notes sm/xs muted (`WeightBreakdown.tsx:90-118,165-213`) |
| admin/folders | h1 2xl bold tracking; h2 lg semibold; item sm/count xs (`admin/folders/page.tsx:281-285,299,456,639-642,679-712`) | semantic background/border/muted/primary/destructive (`:270,312-323,396-499`) | page p4→md8, stack6; card p4; list space2 (`:270-271,297,311-363`) | create/list sections GlassCard; move dialog fixed overlay + GlassCard (`:297,369-650,742-830`) | N/A: no `<table>`/table component in page import/JSX; folders/PFs are div/button lists (`:3-30,352-724`) | create/edit/delete/expand/select/bulk move; fixed selection bar and modal (`:300-349,369-650,725-830`) | N/A: imports/JSX contain no chart (`:3-30`) | back `/admin` + local title (`:272-290`) | auth/loading/login; folder/PF empty messages; MessageBanner; saving spinner (`:256-266,292-294,353-361,616-616,692,811-817`) | same DOM only: page md padding; no hidden/md:hidden; fixed bar/modal widths shrink naturally (`:270,725-830`) | **N/A（二重DOMなし）**。selection/error/destructive colors are same elements at all widths; viewport別helperなし (`:270-830`, hidden/md:hidden 0) | subtitle sm muted (`:284-287`); no-folders sentence centered muted (`:358-360`); folder/PF counts xs muted (`:456,642,680,712,796`); empty PF messages sm muted (`:616,692`); move labels sm and saving note sm muted (`:774-817`) |
| admin/visibility | h1 2xl bold; section h2 lg; subhead/table text sm; metadata xs mono (`admin/visibility/page.tsx:596,654,670,776,1028,1209`) | semantic + explicit emerald/amber/red/sky status palettes (`:684-730,756-759,1000,1038-1048,1204,1222-1228`) | page p4→md8, stack6→8; cards/sections and table cells py2/3 (`:581-582,650-776,1055,1185`) | configuration sections GlassCard; modal components use bordered surfaces (`:648-776`; `ManageTiersModal.tsx:249-310`) | full-width text-sm visibility matrix, header/cell centering, overflow container (`page.tsx:772-869,930-1360`) | tier/page chips; global/folder/PF L2-L4 toggles; save/manage modal (`:623-750,790-915,930-1360`) | N/A: no chart import/JSX; visual encoding is toggles/badges/table (`:3-34`) | back `/admin`, local title + TierSelector; PageHeaderなし (`:581-623`; `TierSelector.tsx:18-48`) | login/error/loading, MessageBanner, ErrorBoundary; disabled/folder-hidden opacity (`page.tsx:550-580,626-642,930-1360`) | same DOM: page/grid md; TierSelector and modal rows flex-col→md:flex-row; table horizontally scrolls, no desktop/mobile duplicate (`page.tsx:581-582,668`; `TierSelector.tsx:18`; `ManageTiersModal.tsx:299`) | **N/A（二重DOMなし）**。同一table/toggle DOMがscroll/reflowし、red/amber/sky/emerald statesを共有 (`page.tsx:772-1360`); hidden/md:hidden 0、状態色helper分岐0 | auth/error text muted (`:560`); page-section descriptions sm muted (`:661,768`); folder count/status labels xs (`:1028-1048`); PF id xs mono and type badges xs (`:1209-1228`); ManageTiers subtitle/help/password notes sm/xs/11px (`ManageTiersModal.tsx:215,279,327-337,375,403-409`). tableはcaption/legend要素なし（`page.tsx:772-1360`） |

## K軸全数結果

- 3ページおよび表示依存4 component (`FoFEditor`, `WeightBreakdown`, `ManageTiersModal`, `TierSelector`) を `hidden md:block|md:hidden|hidden lg|lg:hidden` で検索: **0件**。
- PC/mobile二重DOM: **0/3ページ**。よって状態色比較は3ページとも根拠付きN/Aであり、未確認ではない。
- responsiveは同一DOMのpadding/flex/grid/scroll変更。状態色helperまたは色classのviewport別適用: **0件**、不一致 **0件**、一致（同一DOM共有） **3/3**。

## L軸全数結果

- FoF: subtitle、empty explanation、Components/Allocation、editor help/preview、WeightBreakdown loading/error/empty/noteを抽出。主に `text-sm|text-xs text-muted-foreground`、配置はheader/card/table直下。
- Folders: subtitle、empty説明2種、folder/PF counts、move dialog labels/saving noteを抽出。主に sm/xs muted、emptyはcenter。
- Visibility: section descriptions、folder status/count、PF id/type badge、ManageTiers help/password notesを抽出。sm/xs/11px、mutedまたは意味色。明示 `<caption>` とchart凡例は **0件**（chart/table caption不在をコード全域検索）。
- L確認: **3/3、未確認0**。

## 二値集計

- page: **3/3**
- matrix: **36/36セル**
- K: **3/3、未確認0、根拠なしN/A 0**
- L: **3/3、未確認0、根拠なしN/A 0**
- 最終MECE文書変更: **0**
- 判定: **PASS**

origin: `[[cmd_karo_recon2_mece_v2_tobisaru_20260722]] -> [[admin_3page_A_L全数調査]] -> [[36セル_KL未確認0]]`
