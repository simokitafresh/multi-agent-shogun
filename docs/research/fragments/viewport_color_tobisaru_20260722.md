# Viewport × state-color adversarial audit — FAQ / Offline / coverage

検証日: 2026-07-22。一次情報は `/mnt/c/Python_app/DM-signal/frontend` と `queue/tasks/*.yaml`。最終MECE文書は参照のみで未編集。

## FAQ / Offline（2/2）

| 対象 | PC/mobile二重table/card | 状態色 | 判定 |
|---|---|---|---|
| FAQ `/faq` | なし。tableは単一DOM (`frontend/app/faq/page.tsx:45-68`)、GlassCardも単一DOM (`:357-433`)。同一DOM上の `p-4 md:p-8`、`space-y-6 md:space-y-8`、`p-4 md:p-6`、table scrollのみ (`:342-360`) | 同一classを共有。link `text-sky-400 dark:text-sky-300` とborder tokenにviewport別定義なし (`:45-68,223-231,362-423`) | PASS |
| Offline `/offline` | なし。単一page/card (`frontend/app/offline/page.tsx:6-15`)、page固有breakpoint 0件 | `bg-secondary/20 text-muted-foreground` と本文mutedを共有 (`:8-14`) | PASS |

FAQ/Offline **2/2**、二重実装 **0**、状態色不一致 **0**、未確認 **0**。

## 16対象の現行割当

| 担当 | 対象 | 件数 |
|---|---|---:|
| kagemaru | Metrics / Monthly Returns / Annual Returns | 3 |
| hanzo | Rolling Returns / Drawdowns / Monthly Trade | 3 |
| saizo | Trades / Compare Returns / Compare Chart | 3 |
| kotaro | Compare Summary / Deterioration | 2 |
| tobisaru | FAQ / Offline | 2 |
| 割当なし | Dashboard / Summary / Signals（Dashboard内Current Signal） | 3 |

hayateの現行YAMLは旧page-style MECE taskでありviewport taskではない。従って集合和 **13/16**、重複 **0**、欠落 **3**。

## 横断検索の追加候補（12群）

| # | 候補 | 根拠 | 状態 |
|---:|---|---|---|
| 1 | Dashboard desktop/mobile Signal | `dashboard/page.tsx:623-676` | 割当欠落・未確認 |
| 2 | Dashboard MTD mobile header | `mtd-daily-table.tsx:150,157` | 割当欠落・未確認 |
| 3 | Dashboard mobile chart分岐 | `mtd-chart.tsx:8,35,247-283`; `total-return-chart.tsx:7,54` | 割当欠落・未確認 |
| 4 | Rolling summary二重table | `rolling-returns-summary-table.tsx:97,309` | hanzo |
| 5 | Rolling distribution二重table | `rolling-returns-distribution-table.tsx:71,136` | hanzo |
| 6 | Monthly/Annual mobile Bal label | `monthly-returns-table.tsx:330,341,392`; `annual-returns-table.tsx:191,198` | kagemaru |
| 7 | Monthly Trade lg列 | `monthly-trade-table.tsx:287,746` | hanzo |
| 8 | Compare Returns mobileVisible | `compare-returns-table.tsx:131,152,187,269` | saizo |
| 9 | Compare Summary mobileVisible | `compare-summary-table.tsx:260,292,335,372` | kotaro |
| 10 | Deterioration mobileVisible/isMobile | `deterioration/page.tsx:176-275,1004,1296-1417` | kotaro |
| 11 | Compare Chart useIsMobile | `comparison-chart.tsx:19,158,528,540` | saizo |
| 12 | 共通MobileMenu/PageHeader/PageShell | `mobile-menu.tsx:330-334`; `ui/page-header.tsx:21,58-59`; `page-shell.tsx:7,35` | 全担当共通 |

追加候補 **12群**、担当不在で未確認 **3群**。FAQ/Offline自身の追加候補0。

## 結論

総合 **BLOCK**。FAQ/Offlineは2/2確認済みだが、全体は13/16で割当欠落3・未確認候補3が残るためAC5によりPASS禁止。

origin: `[[cmd_karo_recon2_viewport_color_tobisaru_20260722]] -> [[viewport割当13_of_16]] -> [[Dashboard_Summary_Signals未確認BLOCK]]`
