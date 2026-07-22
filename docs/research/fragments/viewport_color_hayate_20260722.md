# Viewport color audit — Dashboard / Summary / Signals alternative

検証日: 2026-07-22。対象: `/mnt/c/Python_app/DM-signal/frontend`。PC/mobile の別実装有無と、二重表示箇所の状態色をコード一次情報で全数確認した。

## 全数表（担当 3/3）

| 対象 | PC/mobile 実装 | viewport 根拠 | 状態色比較 | 判定 |
|---|---|---|---|---|
| Dashboard（MTD Daily Returns） | **別table/cardなし**。単一`table`内でPC専用Daily列と共通MTD列を切替 | PC専用見出し/セル=`hidden md:table-row`、`hidden md:table-cell` (`frontend/components/mtd-daily-table.tsx` L121-159, L182-200)。mobile label=`md:hidden`、PC label=`hidden md:inline` (L149-159) | PC Daily 2セルとPC/mobile共通MTD 2セルの全4セルが同じ`getReturnColorClass`を使用 (L183-200)。helperはundefined=`text-muted-foreground`、>=1=`text-green-600 dark:text-green-400`、<1=`text-red-600 dark:text-red-400` (L38-44) | **一致**。色差0、欠落helper 0 |
| Summary | **別table/cardなし**。単一tableを`overflow-x-auto`で全viewport共用 | wrapper/tableはresponsive hidden classなし (`frontend/components/summary-table.tsx` L138-158, L257-259)。全列を同一DOMで表示 | PC/mobile分岐自体がないため比較はN/A。共通DOMでは負値のみ`text-red-400`、非負はportfolio=`text-foreground`、benchmark=`text-foreground/70` (L190-206, L225-246) | **N/A（単一実装）**。viewport間差0 |
| Signals代替（Dashboard Current Signal） | **二表示あり**。PCはsignal text block、mobile/tabletはpie header/chart | PC=`hidden lg:flex` (`frontend/app/dashboard/page.tsx` L623-645)。mobile/tablet header/pending=`lg:hidden` (L647-679) | signal text/pie allocationにはnegative/positive状態の概念なしでN/A。両表示の状態色対象である劣化dotは同じ`DeteriorationDots`を呼ぶ (PC L638-644、mobile L671-677)。component内で両者が同じ`g1ToColorDot`/`g2ToColorDot`/`labelToColorDot`を使用し、`mobile`差はdot寸法10px対12pxのみ (L192-217)。色helper正本は`frontend/lib/constants/deterioration-colors.ts` L28-75 | **一致**。色差0、欠落helper 0 |

## 不一致・陰性証拠

- 不一致: **0件**。したがってPC色/mobile色/修正対象行の列挙対象なし。
- 一致: Dashboard MTDは状態色呼出し **4/4** が同一helper。Signals代替の劣化dotはPC/mobile **2/2** が同一componentかつ同一3 helperを使用。
- N/A: Summary **1件**（viewport別DOMなし）。Signalsのsignal allocation **1件**（正負状態色という意味領域なし）。いずれもコード根拠あり。
- 未確認: **0件**。担当対象 **3/3**、二表示対象 **1/1**、responsive単一table **1/1**、単一共通table **1/1** を確認した。

## 二値結論

- AC1: 3/3について二重実装有無とresponsive classを特定 — yes。
- AC2: 二重/切替表示の状態色をPC/mobile双方で全数比較 — yes。
- AC3: 不一致0件、一致の陰性証拠2系統、N/A 2件を根拠行付きで記録 — yes。
- AC4: 本断片へ保存し、担当3/3・差分0件を数値化 — yes。
- AC5: 未確認0件 — yes。

origin: `[[cmd_karo_recon2_viewport_color_hayate_20260722]] -> [[viewport_dual_render_color_audit]] -> [[viewport_color_hayate_20260722]]`
