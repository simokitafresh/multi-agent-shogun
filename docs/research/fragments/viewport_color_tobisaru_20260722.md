# Viewport × state-color adversarial audit — FAQ / Offline / 16-target coverage

検証日: 2026-07-22。コード一次情報: `/mnt/c/Python_app/DM-signal/frontend`。割当一次情報: `queue/tasks/{hayate,kagemaru,hanzo,saizo,kotaro,tobisaru}.yaml`。最終MECE文書 `docs/research/dm-signal-page-style-diff-mece_20260722.md` は参照のみで未編集。

## 1. FAQ / Offline（2/2）

| 対象 | PC/mobile二重table/card | viewport根拠 | 状態色一致 | 判定 |
|---|---|---|---|---|
| FAQ `/faq` | なし。FAQ tableは単一DOM（`frontend/app/faq/page.tsx:45-68`）、各GlassCardも単一DOM（`:357-433`） | responsive差は同一DOM上の `p-4 md:p-8`、`space-y-6 md:space-y-8`、`p-4 md:p-6`、table `overflow-x-auto`（`:342-360`） | PC/mobileが同一要素・同一classを共有するため一致。link `text-sky-400 dark:text-sky-300`、border tokenも二重定義なし（`:45-68,223-231,362-423`） | PASS |
| Offline `/offline` | なし。page/cardは単一DOM（`frontend/app/offline/page.tsx:6-15`） | page固有 breakpoint class 0件。`w-full max-w-md`で同一cardが縮退（`:6-7`） | PC/mobileが `bg-secondary/20 text-muted-foreground` と本文mutedを共有（`:8-14`）。二重状態色なし | PASS |

FAQ/Offline確認数 **2/2**、二重実装 **0件**、状態色不一致 **0件**、未確認 **0件**。

## 2. 最終MECE 16対象と現行割当の再対応付け

| 担当 | 現行viewport task対象 | route/component | 件数 |
|---|---|---|---:|
| kagemaru | Metrics / Monthly Returns / Annual Returns | `/metrics` `MetricsTable`; `/monthly-returns` `MonthlyReturnsTable`; `/annual-returns` `AnnualReturnsChart/Table` | 3 |
| hanzo | Rolling Returns / Drawdowns / Monthly Trade | `/rolling-returns` summary/distribution tables; `/drawdowns` `DrawdownsTable`; `/monthly-trade` `MonthlyTradeTable` | 3 |
| saizo | Trades / Compare Returns / Compare Chart | `/trades`; `/compare-returns` `CompareReturnsTable`; `/compare` `ComparisonChart` | 3 |
| kotaro | Compare Summary / Deterioration | `/compare-summary` `CompareSummaryTable`; `/deterioration` page table/detail | 2 |
| tobisaru | FAQ / Offline | `/faq`; `/offline` | 2 |
| **割当なし** | **Dashboard / Summary / Signals** | `/dashboard`; `/summary` `SummaryTable`; Signalsは独立route廃止でDashboard内Current Signal | **3** |

現行6 task YAMLを照合すると、hayateは旧page-style MECE taskのままでviewport taskではない。したがってviewport割当の集合和は **13/16**、重複 **0**、欠落 **3**（Dashboard・Summary・Signals）。「6担当の割当和16/16」は成立しない。

## 3. 横断検索で得た見落とし候補

viewer範囲の `hidden md:block` / `md:hidden` / `sm|lg` 分岐 / `Mobile*` / `useIsMobile` を全数検索し、次の **12候補群**を再確認対象とした。

| # | 候補群 | 一次根拠 | 帰属・状態 |
|---:|---|---|---|
| 1 | Dashboard Current Signalのdesktop/mobile別表示 | `frontend/app/dashboard/page.tsx:623-676` (`hidden lg:flex`, `lg:hidden`, mobile prop) | **割当欠落・未確認** |
| 2 | Dashboard MTD tableのmobile header短縮 | `frontend/components/mtd-daily-table.tsx:150,157` (`md:hidden`) | **割当欠落・未確認** |
| 3 | Dashboard配下chartのmobile描画分岐 | `frontend/components/mtd-chart.tsx:8,35,247-283`; `total-return-chart.tsx:7,54` | **割当欠落・未確認** |
| 4 | Rolling summary desktop/mobile二重table | `rolling-returns-summary-table.tsx:97,309` | hanzo positive control対象 |
| 5 | Rolling distribution desktop/mobile二重table | `rolling-returns-distribution-table.tsx:71,136` | hanzo追加確認対象 |
| 6 | Monthly/Annual returnsのmobile Bal label | `monthly-returns-table.tsx:330,341,392`; `annual-returns-table.tsx:191,198` | kagemaru追加確認対象 |
| 7 | Monthly Tradeのlg列分岐 | `monthly-trade-table.tsx:287,746` | hanzo追加確認対象 |
| 8 | Compare ReturnsのmobileVisible列分岐 | `compare-returns-table.tsx:131,152,187,269` | saizo追加確認対象 |
| 9 | Compare SummaryのmobileVisible列分岐 | `compare-summary-table.tsx:260,292,335,372` | kotaro追加確認対象 |
| 10 | DeteriorationのmobileVisible/isMobile/detail分岐 | `deterioration/page.tsx:176-275,1004,1296-1417` | kotaro追加確認対象 |
| 11 | Compare ChartのuseIsMobile描画分岐 | `comparison-chart.tsx:19,158,528,540` | saizo追加確認対象 |
| 12 | 共通MobileMenu/PageHeader/PageShell | `mobile-menu.tsx:330-334`; `ui/page-header.tsx:21,58-59`; `page-shell.tsx:7,35` | 全担当の共通shell確認候補 |

検索は追加候補を列挙できたが、候補1-3は担当不在で未確認のまま残る。FAQ/Offline自身への追加候補は0件。

## 4. 二値結論

- FAQ/Offline: **2/2 PASS**（二重実装0、色差0、未確認0）。
- 16対象再対応付け: **13/16、重複0、欠落3**。
- 横断追加候補: **12群**、うち担当不在により未確認 **3群**。
- 総合: **BLOCK**。割当欠落・未確認候補が1件以上ならPASS禁止というAC5を適用。

origin: `[[cmd_karo_recon2_viewport_color_tobisaru_20260722]] -> [[viewport割当13_of_16]] -> [[Dashboard_Summary_Signals未確認BLOCK]]`
