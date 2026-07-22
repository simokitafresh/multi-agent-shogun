# Viewport color cross-check — Compare Summary / Deterioration

<!-- origin: [[cmd_karo_recon2_viewport_color_kotaro_20260722]] -> [[viewport_dual_implementation_audit]] -> [[dm_signal_page_style_mece_20260722]] -->

## 判定

担当ページは **2/2確認済み**。PC用tableとmobile用card/tableを別々に描画する二重実装は **0/2件**、単一tableのresponsive列制御は **2/2件**。したがってPC/mobile間の色実装差分は **0件**、未確認は **0件**。desktop専用セルはmobile色を持たないため不一致ではなくN/Aとした。

## 二重実装の有無

| ページ | PC/mobile構造 | 判定 | 一次根拠 |
|---|---|---|---|
| Compare Summary | 実データは単一`table`。各列の`mobileVisible`がfalseなら同じ`th`/`td`へ`hidden md:table-cell`を付与 | 二重実装なし | `frontend/components/compare-summary-table.tsx:323-325,328-336,357-373`; 列SSOT `frontend/lib/types/compare-summary.ts:96-113` |
| Deterioration | 単一`table`/単一row。`COLUMNS.mobileVisible`を同じheaderへ、各desktop専用cellへ`hidden md:table-cell`を付与 | 二重実装なし | `frontend/app/deterioration/page.tsx:172-180,1281-1298,1323-1348,1387-1415` |

注: Compare Summaryのloading skeletonにも別tableはあるが、viewport別実装ではなくloading状態専用であり、同じ`mobileVisible`/`hidden md:table-cell`契約を使う (`compare-summary-table.tsx:248-261,279-305`)。Deteriorationの`StatsTable`は展開detail用で、mobileではdetail自体を描画しない (`deterioration/page.tsx:862-919,1417-1431`)。

## 色・状態表現のPC/mobile比較

| ページ/表現 | PC | mobile | 判定 | 一次根拠・修正対象 |
|---|---|---|---|---|
| Compare Summary: Portfolio FoF/BM | `text-purple-400` / `text-amber-400` | 同一cell・同一class | 一致 | nameはmobile表示対象 (`compare-summary.ts:113-120`)、classは単一cell (`compare-summary-table.tsx:366-382`)。修正対象なし |
| Compare Summary: CAGR正/負 | `>=0 text-green-400` / `<0 text-red-400` | 同一cell・同一条件 | 一致 | CAGRはmobile表示対象 (`compare-summary.ts:121-127`)、分岐は単一cell (`compare-summary-table.tsx:383-390`)。修正対象なし |
| Compare Summary: MDD | `text-red-400` | 列非表示 | N/A | MDDは`mobileVisible:false` (`compare-summary.ts:142-148`)、色classは`compare-summary-table.tsx:391-393`。mobile helper欠落ではなく列policy。修正対象なし |
| Compare Summary: deterioration dots | helper自体は`getDotColor`から共通`g1ToColorDot`/`g2ToColorDot`/`labelToColorDot`/`pBarToColorDot`を呼ぶ | viewport別分岐なし | N/A（現行列SSOTからdot列定義なし） | helper `compare-summary-table.tsx:144-171,396-417`; `COMPARE_SUMMARY_COLUMNS`全定義は`compare-summary.ts:113-249`でdot keyの列定義0件。viewport間不一致ではなく双方で未描画。修正要否は本調査scope外 |
| Deterioration: G1/G2/P/p̄ dots | 共通helper、size=12 | 同一helper、size=10 | 色一致（寸法のみ差） | 4列とも`mobileVisible:true` (`deterioration/page.tsx:194-220`)、呼出しは単一row (`1351-1385`)、色SSOTは`deterioration-colors.ts:28-86`。修正対象なし |
| Deterioration: Label badge | `LABEL_COLORS`のbg/text | 列非表示 | N/A | labelは`mobileVisible:false` (`deterioration/page.tsx:222-228`)、badge色は`77-102,402-414`、描画cellは`1387-1389`。mobile helper欠落ではなく列policy。修正対象なし |
| Deterioration: Trend | `TREND_DISPLAY`のgreen/gray/orange/red | 列非表示 | N/A | trendは`mobileVisible:false` (`deterioration/page.tsx:257-263`)、色SSOTは`146-152`、描画cellは`1402-1408`。修正対象なし |

## 数値チェック

| 二値項目 | 結果 |
|---|---:|
| 担当ページ確認 | 2/2 |
| viewport二重実装 | 0/2 |
| responsive単一table | 2/2 |
| 色比較対象 | 7/7 |
| 一致 | 3 |
| N/A（mobile非表示または双方未描画） | 4 |
| 不一致 | 0 |
| 欠落helperによるviewport差 | 0 |
| 修正対象行 | 0 |
| 未確認 | 0 |

## 因果リンク

- [[dm_signal_page_style_mece_20260722]]
- [[viewport_dual_implementation_audit]]
- 実ファイル: `docs/research/fragments/viewport_color_kotaro_20260722.md`
