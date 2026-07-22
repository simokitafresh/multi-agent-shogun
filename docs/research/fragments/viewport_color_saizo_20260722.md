# Viewport state-color audit — Saizo (2026-07-22)

対象: Trades / Compare Returns / Compare Chart の PC・mobile 表示実装と状態色。一次情報は `/mnt/c/Python_app/DM-signal/frontend` の現行コード。

## 実装形態（3/3確認）

| 画面 | PC実装 | mobile実装 | 二重実装判定 | 根拠 |
|---|---|---|---|---|
| Trades (`ModelTradesTable`) | 10列table | 4列table | あり | `frontend/components/model-trades-table.tsx:200-266` が `hidden md:block`、同`:268-306` が `block md:hidden`。ただし現行 `/trades` は廃止案内のみ (`frontend/app/trades/page.tsx:3-17`) で、`ModelTradesTable` の利用箇所は定義自身以外0件。 |
| Compare Returns | 1つのtable | 同じtableの列をresponsive非表示 | なし | `frontend/components/compare-returns-table.tsx:177-283` は単一table。非mobile列だけ `hidden md:table-cell` (`:187-188`, `:269-270`)。mobile専用table/cardは0件。 |
| Compare Chart | 1つのSVG + tooltip + legend | 同じSVG + tooltip + legend | なし | `frontend/components/comparison-chart.tsx:505-621` は単一SVG、`:622-692` は単一tooltip、`:694-753` は単一legend。`isMobile` は線幅引数にのみ使用 (`:525-540`) し、別DOMを生成しない。 |

## 状態色のPC/mobile交差

| 画面・値 | PC色 | mobile色 | 判定 | 根拠 / 修正対象 |
|---|---|---|---|---|
| Trades: Portfolio Return | `getValueColor`: `>=0` は `text-foreground dark:text-emerald-400`、負値は `text-red-400` | 同じ `getValueColor` | 一致 | helper `frontend/components/model-trades-table.tsx:57-60`; PC適用 `:244-246`; mobile適用 `:299-301`。修正対象なし。 |
| Trades: Min/Max P&L | 同helper | mobile列なし | N/A | PC `:247-254`; mobileの4列定義 `:268-301` に対応値なし。 |
| Trades: Benchmark Return | 常時 `text-muted-foreground`（状態色helper欠落） | mobile列なし | N/A | PC `:256-258`; mobileの4列定義 `:268-301` に対応値なし。二重表示差ではないため本調査の修正対象なし。将来mobileへ追加する場合はPC側も `getValueColor(getReturn(..., "benchmark_return"))` 適用要否を決める必要あり。 |
| Trades: Excess Return | `getValueColor` | mobile列なし | N/A | PC `:259-261`; mobileの4列定義 `:268-301` に対応値なし。 |
| Compare Returns: 全returnセル | `getReturnColor`: 正 `text-green-400`、負 `text-red-400`、0/null空 | 同一DOM・同一helper | N/A（二重実装なし） | helper `frontend/components/compare-returns-table.tsx:29-34`; 単一セル適用 `:264-275`。responsiveは列visibilityのみ。修正対象なし。 |
| Compare Chart: hover return | `text-chart-positive` / `text-chart-negative` | 同一DOM | N/A（二重実装なし） | PF `frontend/components/comparison-chart.tsx:630-660`; BM `:662-690`。 |
| Compare Chart: final return legend | `text-chart-positive` / `text-chart-negative` | 同一DOM | N/A（二重実装なし） | PF `frontend/components/comparison-chart.tsx:694-725`; BM `:726-752`。 |

## 数値結論

- 担当画面確認: **3/3**。
- PC/mobile二重実装: **1/3画面**（Tradesのみ）。
- 二重実装の双方に存在する状態値: **1件**（Trades Portfolio Return）。一致 **1件**、不一致 **0件**、未確認 **0件**。
- 片側にしか存在せずN/A: **3件**（Trades Min/Max P&L、Benchmark Return、Excess Return）。
- helper欠落: **1件**（Trades PC Benchmark Return）だがmobile対応値自体がなく、PC/mobile不一致件数には含めない。
- 修正対象: **0件**。最終MECE文書は未編集。

## 因果リンク

`[[cmd_karo_recon2_viewport_color_saizo_20260722]] -> [[responsive_dual_implementation_audit]] -> [[viewport_color_saizo_20260722]]`
