<!-- provenance: DM-signal repo docs/research/cmd_4295_dm-signal-ssot-audit-map.md @ 2064a5ab を全文複製(2026-08-26 将軍doc lane)。原本はrollback 233c2303で本番treeから除去。内容は原本と同一 -->
<!-- gist-master: c47e3efb3d64f397a9a3423f669b42f7 cmd_4295_dm-signal-ssot-audit-map.md -->
# DM-Signal 表示項目→API→生成元 SSOT 監査マップ

検証日: 2026-08-12  
任務: `cmd_4295` / `cmd_4295_readonly`  
対象: `/mnt/c/Python_app/DM-signal`  
監査時 HEAD: `2c15cd4eb7cff2350718dc20c91e0d6a44b2926a`  
前提: `cmd_4294_dm-signal-page-data-api-map.md` の route/API 粒度マップを入力に、表示項目単位へ展開した。DB/API 本番接触、アプリコード変更は行っていない。

## 1. 監査境界と母数

`cmd_4294` の route 母数は FE の `frontend/app/**/page.tsx` 現物から 21 ページ。今回の台帳は静的・封鎖ページも含め、数値/率/系列/テーブル列が存在するページでは列・系列を列挙し、管理ページでは表示される設定値・操作対象を列挙した。

`precomputed_raw` は L5 応答キャッシュであり、数値の新しい SSOT ではない。数値の生成元は以下の台帳で L1/L2/L3 または永続テーブルまで遡った。

## 2. FE/BE 関連構造ツリー

```text
frontend/
├── app/                         # route/page composition (21 page.tsx)
│   ├── dashboard/               # MTD/performance/deterioration
│   ├── summary/ metrics/        # single-PF metrics tables
│   ├── compare/                 # daily cumulative comparison chart
│   ├── compare-summary/         # all-PF metrics/deterioration table
│   ├── compare-returns/         # all-PF trailing-return table
│   ├── monthly-returns/ annual-returns/
│   ├── monthly-trade/ drawdowns/ rolling-returns/
│   ├── deterioration/
│   └── admin/ admin/{fof,folders,visibility}/
├── components/                  # table/chart rendering and display transforms
├── contexts/                    # signals, viewer permissions, timing
├── hooks/                       # prefetch, filters, table/chart interaction
└── lib/
    ├── api-client.ts            # endpoint client boundary
    ├── types/                   # response and display contracts
    └── *_data.ts                # compare page row projection helpers

backend/app/
├── api/                         # FastAPI endpoint/response facade (30 modules)
├── services/                    # metrics/return/drawdown/rolling calculators
├── jobs/                        # L1/L2/L3 recalculation and L5 precompute
├── generators/                  # persisted derived-table generators
├── db/models.py                 # PostgreSQL persistence models
└── main.py                      # router registration
```

## 3. 表示項目台帳（21 routes）

| route | 表示項目（数値・率・系列・列） | FE 現物（component/function） | 発生元 API | BE 生成元（file + function/class） |
|---|---|---|---|---|
| `/` | 日付、休日/営業日メッセージ、ナビゲーション。portfolio 数値なし。 | `frontend/app/page.tsx` (`useEffect`) | route 固有なし。layout の signals/pageview は共通。 | `holiday_jp` の FE ローカル判定。portfolio 数値生成なし。 |
| `/dashboard` | 保有シグナルの配分（pie）；累積 portfolio/benchmark 系列；MTD 日次 portfolio/benchmark return；MTD 日次表の date/portfolio/benchmark；G1/G2/P の状態点。 | `SignalPieChart`; `TotalReturnChart`; `MtdChart`; `MtdDailyTable`; `DeteriorationDots`; `toMtdChartData`; `mtdData` の `useMemo`。 | `/api/signals`, `/api/performance/{id}`, `/api/mtd/{id}`, `/api/deterioration`。 | `signals.get_signals_light`; `performance.get_portfolio_performance`/`build_performance_raw`; `performance.get_mtd_performance`; `deterioration.get_deterioration_list`。L2/L3 signals/monthly_returns、L3 deterioration snapshots。 |
| `/summary` | Start Balance、End Balance、Annualized Return (CAGR)、Standard Deviation、Best Year、Worst Year、Maximum Drawdown、Sharpe Ratio、Sortino Ratio、Benchmark Correlation。各 portfolio/benchmark 列。 | `frontend/components/summary-table.tsx` `SummaryTable`; `calculateTrueCAGR`; End Balance calculation。 | `/api/metrics/{id}` | `metrics.get_portfolio_metrics`; `MetricsCalculator.calculate_metrics` (`backend/app/services/metrics_impl.py`)。 |
| `/metrics` | API が返す全 metric name × portfolio/benchmark の close/open 値；regime の bull/neutral/bear/total の count、pct、active return、bins の model/benchmark return。 | `MetricsTable`; `UpDownMarketChart` (`frontend/components/up-down-market-chart.tsx`)。 | `/api/metrics/{id}`, `/api/regime-analysis/{id}` | `metrics.get_portfolio_metrics`; `regime_analysis.get_regime_analysis` → `RegimeAnalysisService` の BE 分類/集計。 |
| `/compare` | 選択 PF ごとの累積 return 系列、最終 return、benchmark 累積系列、date/tooltip、対数/線形軸。 | `ComparisonChart`; `filteredPortfolios`; `alignedData`/`alignedBenchmark` (`frontend/components/comparison-chart.tsx`)。 | `/api/performance/{id}`, `/api/benchmark/{ticker}` | `performance.get_portfolio_performance`; `benchmark.get_benchmark_performance`。L2/L3 monthly_returns と L1 ticker return。 |
| `/compare-summary` | Portfolio、CAGR、Sharpe、Sortino、MDD、Stdev、Max Run-up、Tail Contrib、Left Jumps、New High、Up Cap、Down Cap、Alpha、Min Mo. vs BM、Calmar、UWP、Avg UWP、PTU、および G1/G2/P/p̄。 | `buildCompareSummaryRows`, `extractMetricsFrom`, `CompareSummaryTable`; `COMPARE_SUMMARY_COLUMNS`。 | `/api/metrics/summary`, `/api/deterioration`, `/api/p-average` | `metrics.get_metrics_summary`/`build_metrics_summary_bulk_raw`; deterioration list; `p_average.get_p_average_list`。元の metric 計算は `MetricsCalculator.calculate_metrics`。 |
| `/compare-returns` | Portfolio/benchmark 名、MTD、1M、3M、6M、1Y、3Y、5Y、ALL。Open/Close 切替、as-of。 | `buildCompareReturnsRows` (`app/compare-returns/returns-data.ts`); `CompareReturnsTable`; `COMPARE_RETURNS_COLUMNS`。 | `/api/compare-returns` | `compare_returns.get_compare_returns`; `_trailing_return`, `_all_return`, `_period_values`, `build_compare_returns_bulk_raw`。MonthlyReturn の completed 行を複利集計。 |
| `/monthly-returns` | 年/月、partial/MTD/pending、portfolio Return/Balance、benchmark Return/Balance、構成 ticker ごとの Return。Open/Close、初期投資額、全履歴件数。 | `MonthlyReturnsTable`; `getReturn`, `getBalance`, `formatPercent`, `formatBalance` (`monthly-returns-table.tsx`)。 | `/api/monthly-returns/{id}` | `monthly_returns.get_monthly_returns`; `MonthlyReturnsCalculator.calculate`, `_calculate_ticker_monthly_returns`。SSOT は MonthlyReturn、ticker 系列は価格入力から同 calculator が生成。 |
| `/annual-returns` | 年、partial/YTD 注記、portfolio Return/Balance、benchmark Return/Balance、ticker 年次 Return、初期投資額。Open/Close、12件/全件表示。棒グラフは portfolio/benchmark 年次率。 | `AnnualReturnsTable`; `AnnualReturnsChart`; `formatPercent`, `formatBalance`。 | `/api/annual-returns/{id}` | `annual_returns.get_annual_returns`; `AnnualReturnsCalculator.calculate`, `_calculate_from_monthly`, `_calculate_ticker_annual_returns`。MonthlyReturn を年単位に複利。 |
| `/monthly-trade` | 月、signal date、signal、position start、position、return period、Return、Cumulative、ticker price movement。pending/corrected/confirmed badge、next signal preview。 | `MonthlyTradeTable`; `MonthlyTradeRow`; `NextSignalPanel`; `getDecisionBadge`; `parseTickersWithWeights`。 | `/api/monthly-trade/{id}` | `monthly_trade.get_monthly_trade`; `MonthlyTradeCalculator`（API facade の fallback）; `recalculate_fast.py`/`recalculate_fof.py` が signals/monthly returns を生成。`monthly_return` が表示 SSOT、`calculated_return_*` は検証用。 |
| `/drawdowns` | chart の date/portfolio drawdown/benchmark drawdown；表の Rank、Start、End、Length、Recovery By、Recovery Time、Underwater、Drawdown。 | `DrawdownsChart`; `DrawdownsTable`; Open/Close は `drawdown_open`/`drawdown` を選択。 | `/api/drawdowns/{id}` | `drawdowns.get_drawdowns`; `DrawdownsCalculator.calculate`, `_get_drawdown_series`, `_extract_worst_drawdowns`; persisted `drawdown_periods` を優先。 |
| `/rolling-returns` | 期間 3M/6M/1Y/2Y/3Y/5Y/7Y/10Y ごとの average/high/low、median、p10、positive rate、sample count、best/worst window；分布表；期間別 rolling chart。 | `RollingReturnsSummaryTable`; `RollingReturnsDistributionTable`; `RollingReturnChart`; chart 側の bins/win-rate/best-worst detail。 | `/api/rolling-returns/{id}` | `rolling_returns.get_rolling_returns`; `RollingReturnsCalculator.calculate`, `_get_precomputed_summary`, `_get_precomputed_chart_data`; persisted `rolling_returns_summary`/`rolling_returns_chart` は generator が生成。 |
| `/deterioration` | portfolio/type、G1、G2、P、p̄、Label、P6、P12、P24、Trend、G1 value、G2 value；history chart の P6/P12/P24；stats の Data Months、Long Mean Return、Recent Mean Return、Z Value、G1 slope、G2 P erosion。 | `COLUMNS`; `DeteriorationTable`; `PdetLineChart`; `StatsTable`; `filteredData` が p̄ を結合。 | `/api/deterioration`, `/api/deterioration/{id}`, `/api/p-average` | `deterioration.get_deterioration_list`/`get_deterioration_history`; `p_average.get_p_average_list`; deterioration batch が snapshots を生成。 |
| `/docs` | Methodology、Terms and Definitions、Notes and Disclosures、Deterioration Monitor の accordion。数値データなし。 | `frontend/app/docs/page.tsx`; `frontend/components/docs/*-content.tsx`。 | route 固有なし（共通 signals/permissions/pageview）。 | BE の portfolio 数値生成なし。 |
| `/faq` | FAQ の section/question/answer、glossary、references、CTA。数値データなし。 | `frontend/app/faq/page.tsx`; content 配列の map。 | route 固有なし（共通）。 | BE の portfolio 数値生成なし。 |
| `/offline` | Offline 見出し、再試行/ホーム導線。数値データなし。 | `frontend/app/offline/page.tsx`。 | route 固有なし（共通）。 | BE の portfolio 数値生成なし。 |
| `/trades` | 封鎖/利用不可メッセージ。trade 数値表はこの route には表示されない。 | `frontend/app/trades/page.tsx`。 | route 固有なし（共通）。`/api/trades/{id}` は別 route の API だが現 page から呼ばれない。 | `trades.get_trades`/`TradesCalculator` は API として存在するが、この page の表示生成元ではない。 |
| `/admin` | portfolio 名/type、folder、benchmark、visibility、signal/DB 状態、price/ticker symbol、layer status、操作結果。 | `frontend/app/admin/page.tsx`; `useAdminPage`; `getSortedPortfolios`; `dbStatus` 表示。 | `/api/portfolios/get`, `/api/viewer-permissions`, `/admin/db-status`, `/api/portfolios/save`, `/admin/recalculate-sync`, `/admin/sync-*`。 | `portfolios.get_portfolios`/`save_portfolios`; `viewer_permissions.get_viewer_permissions`; `db_admin.get_db_status`; `etl_trigger` の sync handlers。 |
| `/admin/fof` | FoF 名、component portfolio 名/順序、recalculate/copy 操作状態。 | `frontend/app/admin/fof/page.tsx`; `fofPortfolios`/`component_portfolios` map。 | `/api/portfolios/get`, `/api/portfolios/{id}`, `/api/portfolios/save`, `/admin/recalculate-sync`。 | `portfolios` handlers; `recalculate_fast.recalculate_history_fast`; `recalculate_fof._recalculate_fof_history`。 |
| `/admin/folders` | folder 名、folder 内 portfolio 名、uncategorized 名、並び順、操作状態。 | `frontend/app/admin/folders/page.tsx`; `loadFolders`, `portfoliosByFolder`, `uncategorizedPortfolios`。 | `/api/admin/folders`, `/api/admin/folders/{id}`, `/api/admin/folders/reorder`, `/api/admin/folders/portfolios/{id}/move`。 | `folders.py` handlers (`get/create/update/delete/reorder/move`); persisted `portfolio_folders`/`Portfolio.folder_id`。 |
| `/admin/visibility` | tier 名、core/info page visibility、folder/PF visibility の hide/mask 状態、global setting、unsaved state。 | `frontend/app/admin/visibility/page.tsx`; `fetchTiers`, `fetchFolders`, `fetchGlobalSettings`, `fetchTierSettings`, `folderGroups`。 | `/api/admin/tiers`, `/api/admin/tiers/{id}/visibility`, `/api/admin/tiers/visibility/global`, `/api/admin/folders`, `/api/viewer-permissions`, `/api/admin/viewer-permissions`。 | `viewer_tiers.py` handlers; `folders.py`; `viewer_permissions.py`; visibility tables。 |

## 3.1 正規化表示項目台帳（1表示項目=1行）

§3のroute/API対応表は監査の入口として保持し、AC1の追跡単位は以下の正規化台帳とする。`none` は当該項目にroute固有のAPIまたはBE生成元がないことを示す。API endpoint、BE file+function、FE file+functionは各行に一つずつ記載し、同一routeで複数項目を束ねない。

| item_id | route | display_item | API endpoint | BE file+function | FE file+function |
|---|---|---|---|---|---|
| D001 | `/` | date | none | none | `frontend/app/page.tsx:useEffect` |
| D002 | `/` | holiday/business-day message | none | none | `frontend/app/page.tsx:useEffect` |
| D003 | `/` | navigation | none | none | `frontend/app/page.tsx:default export` |
| D004 | `/dashboard` | holdings allocation pie | `/api/signals` | `backend/app/api/signals.py:get_signals_light` | `frontend/components/signal-pie-chart.tsx:SignalPieChart` |
| D005 | `/dashboard` | cumulative portfolio series | `/api/performance/{id}` | `backend/app/api/performance.py:get_portfolio_performance` | `frontend/components/total-return-chart.tsx:TotalReturnChart` |
| D006 | `/dashboard` | cumulative benchmark series | `/api/performance/{id}` | `backend/app/api/performance.py:build_performance_raw` | `frontend/components/total-return-chart.tsx:TotalReturnChart` |
| D007 | `/dashboard` | MTD daily portfolio return | `/api/mtd/{id}` | `backend/app/api/performance.py:get_mtd_performance` | `frontend/app/dashboard/page.tsx:mtdData` |
| D008 | `/dashboard` | MTD daily benchmark return | `/api/mtd/{id}` | `backend/app/api/performance.py:get_mtd_performance` | `frontend/app/dashboard/page.tsx:mtdData` |
| D009 | `/dashboard` | MTD table date | `/api/mtd/{id}` | `backend/app/api/performance.py:get_mtd_performance` | `frontend/components/mtd-daily-table.tsx:MtdDailyTable` |
| D010 | `/dashboard` | MTD table portfolio value | `/api/mtd/{id}` | `backend/app/api/performance.py:get_mtd_performance` | `frontend/components/mtd-daily-table.tsx:MtdDailyTable` |
| D011 | `/dashboard` | MTD table benchmark value | `/api/mtd/{id}` | `backend/app/api/performance.py:get_mtd_performance` | `frontend/components/mtd-daily-table.tsx:MtdDailyTable` |
| D012 | `/dashboard` | G1 state point | `/api/deterioration` | `backend/app/api/deterioration.py:get_deterioration_list` | `frontend/components/deterioration-dots.tsx:DeteriorationDots` |
| D013 | `/dashboard` | G2 state point | `/api/deterioration` | `backend/app/api/deterioration.py:get_deterioration_list` | `frontend/components/deterioration-dots.tsx:DeteriorationDots` |
| D014 | `/dashboard` | P state point | `/api/deterioration` | `backend/app/api/deterioration.py:get_deterioration_list` | `frontend/components/deterioration-dots.tsx:DeteriorationDots` |
| D015 | `/summary` | Start Balance | `/api/metrics/{id}` | `backend/app/api/metrics.py:get_portfolio_metrics` | `frontend/components/summary-table.tsx:SummaryTable` |
| D016 | `/summary` | End Balance | `/api/metrics/{id}` | `backend/app/api/metrics.py:get_portfolio_metrics` | `frontend/components/summary-table.tsx:SummaryTable` |
| D017 | `/summary` | Annualized Return (CAGR) | `/api/metrics/{id}` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/summary-table.tsx:calculateTrueCAGR` |
| D018 | `/summary` | Standard Deviation | `/api/metrics/{id}` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/summary-table.tsx:SummaryTable` |
| D019 | `/summary` | Best Year | `/api/metrics/{id}` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/summary-table.tsx:SummaryTable` |
| D020 | `/summary` | Worst Year | `/api/metrics/{id}` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/summary-table.tsx:SummaryTable` |
| D021 | `/summary` | Maximum Drawdown | `/api/metrics/{id}` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/summary-table.tsx:SummaryTable` |
| D022 | `/summary` | Sharpe Ratio | `/api/metrics/{id}` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/summary-table.tsx:SummaryTable` |
| D023 | `/summary` | Sortino Ratio | `/api/metrics/{id}` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/summary-table.tsx:SummaryTable` |
| D024 | `/summary` | Benchmark Correlation | `/api/metrics/{id}` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/summary-table.tsx:SummaryTable` |
| D025 | `/metrics` | metric name | `/api/metrics/{id}` | `backend/app/api/metrics.py:get_portfolio_metrics` | `frontend/components/metrics-table.tsx:MetricsTable` |
| D026 | `/metrics` | portfolio close value | `/api/metrics/{id}` | `backend/app/api/metrics.py:get_portfolio_metrics` | `frontend/components/metrics-table.tsx:MetricsTable` |
| D027 | `/metrics` | portfolio open value | `/api/metrics/{id}` | `backend/app/api/metrics.py:get_portfolio_metrics` | `frontend/components/metrics-table.tsx:MetricsTable` |
| D028 | `/metrics` | benchmark close value | `/api/metrics/{id}` | `backend/app/api/metrics.py:get_portfolio_metrics` | `frontend/components/metrics-table.tsx:MetricsTable` |
| D029 | `/metrics` | benchmark open value | `/api/metrics/{id}` | `backend/app/api/metrics.py:get_portfolio_metrics` | `frontend/components/metrics-table.tsx:MetricsTable` |
| D030 | `/metrics` | regime bull count | `/api/regime-analysis/{id}` | `backend/app/api/regime_analysis.py:get_regime_analysis` | `frontend/components/up-down-market-chart.tsx:UpDownMarketChart` |
| D031 | `/metrics` | regime neutral count | `/api/regime-analysis/{id}` | `backend/app/api/regime_analysis.py:get_regime_analysis` | `frontend/components/up-down-market-chart.tsx:UpDownMarketChart` |
| D032 | `/metrics` | regime bear count | `/api/regime-analysis/{id}` | `backend/app/api/regime_analysis.py:get_regime_analysis` | `frontend/components/up-down-market-chart.tsx:UpDownMarketChart` |
| D033 | `/metrics` | regime total count | `/api/regime-analysis/{id}` | `backend/app/api/regime_analysis.py:get_regime_analysis` | `frontend/components/up-down-market-chart.tsx:UpDownMarketChart` |
| D034 | `/metrics` | regime percentage | `/api/regime-analysis/{id}` | `backend/app/api/regime_analysis.py:get_regime_analysis` | `frontend/components/up-down-market-chart.tsx:UpDownMarketChart` |
| D035 | `/metrics` | regime active return | `/api/regime-analysis/{id}` | `backend/app/api/regime_analysis.py:get_regime_analysis` | `frontend/components/up-down-market-chart.tsx:UpDownMarketChart` |
| D036 | `/metrics` | regime model return bin | `/api/regime-analysis/{id}` | `backend/app/api/regime_analysis.py:RegimeAnalysisService` | `frontend/components/up-down-market-chart.tsx:UpDownMarketChart` |
| D037 | `/metrics` | regime benchmark return bin | `/api/regime-analysis/{id}` | `backend/app/api/regime_analysis.py:RegimeAnalysisService` | `frontend/components/up-down-market-chart.tsx:UpDownMarketChart` |
| D038 | `/compare` | portfolio cumulative return series | `/api/performance/{id}` | `backend/app/api/performance.py:get_portfolio_performance` | `frontend/components/comparison-chart.tsx:alignedData` |
| D039 | `/compare` | portfolio final return | `/api/performance/{id}` | `backend/app/api/performance.py:get_portfolio_performance` | `frontend/components/comparison-chart.tsx:ComparisonChart` |
| D040 | `/compare` | benchmark cumulative series | `/api/benchmark/{ticker}` | `backend/app/api/benchmark.py:get_benchmark_performance` | `frontend/components/comparison-chart.tsx:alignedBenchmark` |
| D041 | `/compare` | chart date | `/api/performance/{id}` | `backend/app/api/performance.py:get_portfolio_performance` | `frontend/components/comparison-chart.tsx:alignedData` |
| D042 | `/compare` | chart tooltip | `/api/performance/{id}` | `backend/app/api/performance.py:get_portfolio_performance` | `frontend/components/comparison-chart.tsx:ComparisonChart` |
| D043 | `/compare` | logarithmic/linear axis | none | none | `frontend/components/comparison-chart.tsx:ComparisonChart` |
| D044 | `/compare-summary` | Portfolio | `/api/metrics/summary` | `backend/app/api/metrics.py:get_metrics_summary` | `frontend/components/compare-summary-table.tsx:buildCompareSummaryRows` |
| D045 | `/compare-summary` | CAGR | `/api/metrics/summary` | `backend/app/api/metrics.py:build_metrics_summary_bulk_raw` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D046 | `/compare-summary` | Sharpe | `/api/metrics/summary` | `backend/app/api/metrics.py:build_metrics_summary_bulk_raw` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D047 | `/compare-summary` | Sortino | `/api/metrics/summary` | `backend/app/api/metrics.py:build_metrics_summary_bulk_raw` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D048 | `/compare-summary` | MDD | `/api/metrics/summary` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D049 | `/compare-summary` | Stdev | `/api/metrics/summary` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D050 | `/compare-summary` | Max Run-up | `/api/metrics/summary` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D051 | `/compare-summary` | Tail Contrib | `/api/metrics/summary` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D052 | `/compare-summary` | Left Jumps | `/api/metrics/summary` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D053 | `/compare-summary` | New High | `/api/metrics/summary` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D054 | `/compare-summary` | Up Cap | `/api/metrics/summary` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D055 | `/compare-summary` | Down Cap | `/api/metrics/summary` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D056 | `/compare-summary` | Alpha | `/api/metrics/summary` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D057 | `/compare-summary` | Min Mo. vs BM | `/api/metrics/summary` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D058 | `/compare-summary` | Calmar | `/api/metrics/summary` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D059 | `/compare-summary` | UWP | `/api/metrics/summary` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D060 | `/compare-summary` | Avg UWP | `/api/metrics/summary` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D061 | `/compare-summary` | PTU | `/api/metrics/summary` | `backend/app/services/metrics_impl.py:MetricsCalculator.calculate_metrics` | `frontend/components/compare-summary-table.tsx:extractMetricsFrom` |
| D062 | `/compare-summary` | G1 | `/api/deterioration` | `backend/app/api/deterioration.py:get_deterioration_list` | `frontend/components/compare-summary-table.tsx:buildCompareSummaryRows` |
| D063 | `/compare-summary` | G2 | `/api/deterioration` | `backend/app/api/deterioration.py:get_deterioration_list` | `frontend/components/compare-summary-table.tsx:buildCompareSummaryRows` |
| D064 | `/compare-summary` | P | `/api/deterioration` | `backend/app/api/deterioration.py:get_deterioration_list` | `frontend/components/compare-summary-table.tsx:buildCompareSummaryRows` |
| D065 | `/compare-summary` | p-bar | `/api/p-average` | `backend/app/api/p_average.py:get_p_average_list` | `frontend/components/compare-summary-table.tsx:buildCompareSummaryRows` |
| D066 | `/compare-returns` | portfolio name | `/api/compare-returns` | `backend/app/api/compare_returns.py:get_compare_returns` | `frontend/app/compare-returns/returns-data.ts:buildCompareReturnsRows` |
| D067 | `/compare-returns` | benchmark name | `/api/compare-returns` | `backend/app/api/compare_returns.py:get_compare_returns` | `frontend/app/compare-returns/returns-data.ts:buildCompareReturnsRows` |
| D068 | `/compare-returns` | MTD | `/api/compare-returns` | `backend/app/api/compare_returns.py:_period_values` | `frontend/app/compare-returns/returns-data.ts:buildCompareReturnsRows` |
| D069 | `/compare-returns` | 1M | `/api/compare-returns` | `backend/app/api/compare_returns.py:_trailing_return` | `frontend/app/compare-returns/returns-data.ts:buildCompareReturnsRows` |
| D070 | `/compare-returns` | 3M | `/api/compare-returns` | `backend/app/api/compare_returns.py:_trailing_return` | `frontend/app/compare-returns/returns-data.ts:buildCompareReturnsRows` |
| D071 | `/compare-returns` | 6M | `/api/compare-returns` | `backend/app/api/compare_returns.py:_trailing_return` | `frontend/app/compare-returns/returns-data.ts:buildCompareReturnsRows` |
| D072 | `/compare-returns` | 1Y | `/api/compare-returns` | `backend/app/api/compare_returns.py:_trailing_return` | `frontend/app/compare-returns/returns-data.ts:buildCompareReturnsRows` |
| D073 | `/compare-returns` | 3Y | `/api/compare-returns` | `backend/app/api/compare_returns.py:_trailing_return` | `frontend/app/compare-returns/returns-data.ts:buildCompareReturnsRows` |
| D074 | `/compare-returns` | 5Y | `/api/compare-returns` | `backend/app/api/compare_returns.py:_trailing_return` | `frontend/app/compare-returns/returns-data.ts:buildCompareReturnsRows` |
| D075 | `/compare-returns` | ALL | `/api/compare-returns` | `backend/app/api/compare_returns.py:_all_return` | `frontend/app/compare-returns/returns-data.ts:buildCompareReturnsRows` |
| D076 | `/compare-returns` | open/close selector | none | none | `frontend/components/compare-returns-table.tsx:CompareReturnsTable` |
| D077 | `/compare-returns` | as-of date | `/api/compare-returns` | `backend/app/api/compare_returns.py:get_compare_returns` | `frontend/components/compare-returns-table.tsx:CompareReturnsTable` |
| D078 | `/monthly-returns` | year | `/api/monthly-returns/{id}` | `backend/app/api/monthly_returns.py:get_monthly_returns` | `frontend/components/monthly-returns-table.tsx:MonthlyReturnsTable` |
| D079 | `/monthly-returns` | month | `/api/monthly-returns/{id}` | `backend/app/api/monthly_returns.py:get_monthly_returns` | `frontend/components/monthly-returns-table.tsx:MonthlyReturnsTable` |
| D080 | `/monthly-returns` | partial/MTD/pending status | `/api/monthly-returns/{id}` | `backend/app/api/monthly_returns.py:get_monthly_returns` | `frontend/components/monthly-returns-table.tsx:MonthlyReturnsTable` |
| D081 | `/monthly-returns` | portfolio Return | `/api/monthly-returns/{id}` | `backend/app/services/monthly_returns_impl.py:MonthlyReturnsCalculator.calculate` | `frontend/components/monthly-returns-table.tsx:getReturn` |
| D082 | `/monthly-returns` | portfolio Balance | `/api/monthly-returns/{id}` | `backend/app/services/monthly_returns_impl.py:MonthlyReturnsCalculator.calculate` | `frontend/components/monthly-returns-table.tsx:getBalance` |
| D083 | `/monthly-returns` | benchmark Return | `/api/monthly-returns/{id}` | `backend/app/services/monthly_returns_impl.py:MonthlyReturnsCalculator.calculate` | `frontend/components/monthly-returns-table.tsx:getReturn` |
| D084 | `/monthly-returns` | benchmark Balance | `/api/monthly-returns/{id}` | `backend/app/services/monthly_returns_impl.py:MonthlyReturnsCalculator.calculate` | `frontend/components/monthly-returns-table.tsx:getBalance` |
| D085 | `/monthly-returns` | component ticker Return | `/api/monthly-returns/{id}` | `backend/app/services/monthly_returns_impl.py:_calculate_ticker_monthly_returns` | `frontend/components/monthly-returns-table.tsx:getReturn` |
| D086 | `/monthly-returns` | open/close selector | none | none | `frontend/components/monthly-returns-table.tsx:MonthlyReturnsTable` |
| D087 | `/monthly-returns` | initial investment | `/api/monthly-returns/{id}` | `backend/app/api/monthly_returns.py:get_monthly_returns` | `frontend/components/monthly-returns-table.tsx:formatBalance` |
| D088 | `/monthly-returns` | all-history count | `/api/monthly-returns/{id}` | `backend/app/api/monthly_returns.py:get_monthly_returns` | `frontend/components/monthly-returns-table.tsx:MonthlyReturnsTable` |
| D089 | `/annual-returns` | year | `/api/annual-returns/{id}` | `backend/app/api/annual_returns.py:get_annual_returns` | `frontend/components/annual-returns-table.tsx:AnnualReturnsTable` |
| D090 | `/annual-returns` | partial/YTD note | `/api/annual-returns/{id}` | `backend/app/api/annual_returns.py:get_annual_returns` | `frontend/components/annual-returns-table.tsx:AnnualReturnsTable` |
| D091 | `/annual-returns` | portfolio Return | `/api/annual-returns/{id}` | `backend/app/services/annual_returns_impl.py:AnnualReturnsCalculator.calculate` | `frontend/components/annual-returns-table.tsx:formatPercent` |
| D092 | `/annual-returns` | portfolio Balance | `/api/annual-returns/{id}` | `backend/app/services/annual_returns_impl.py:AnnualReturnsCalculator.calculate` | `frontend/components/annual-returns-table.tsx:formatBalance` |
| D093 | `/annual-returns` | benchmark Return | `/api/annual-returns/{id}` | `backend/app/services/annual_returns_impl.py:AnnualReturnsCalculator.calculate` | `frontend/components/annual-returns-table.tsx:formatPercent` |
| D094 | `/annual-returns` | benchmark Balance | `/api/annual-returns/{id}` | `backend/app/services/annual_returns_impl.py:AnnualReturnsCalculator.calculate` | `frontend/components/annual-returns-table.tsx:formatBalance` |
| D095 | `/annual-returns` | ticker annual Return | `/api/annual-returns/{id}` | `backend/app/services/annual_returns_impl.py:_calculate_ticker_annual_returns` | `frontend/components/annual-returns-table.tsx:formatPercent` |
| D096 | `/annual-returns` | initial investment | `/api/annual-returns/{id}` | `backend/app/api/annual_returns.py:get_annual_returns` | `frontend/components/annual-returns-table.tsx:formatBalance` |
| D097 | `/annual-returns` | chart portfolio annual rate | `/api/annual-returns/{id}` | `backend/app/services/annual_returns_impl.py:_calculate_from_monthly` | `frontend/components/annual-returns-chart.tsx:AnnualReturnsChart` |
| D098 | `/annual-returns` | chart benchmark annual rate | `/api/annual-returns/{id}` | `backend/app/services/annual_returns_impl.py:_calculate_from_monthly` | `frontend/components/annual-returns-chart.tsx:AnnualReturnsChart` |
| D099 | `/annual-returns` | open/close selector | none | none | `frontend/components/annual-returns-table.tsx:AnnualReturnsTable` |
| D100 | `/annual-returns` | 12/all display selector | none | none | `frontend/components/annual-returns-table.tsx:AnnualReturnsTable` |
| D101 | `/monthly-trade` | month | `/api/monthly-trade/{id}` | `backend/app/api/monthly_trade.py:get_monthly_trade` | `frontend/components/monthly-trade-table.tsx:MonthlyTradeTable` |
| D102 | `/monthly-trade` | signal date | `/api/monthly-trade/{id}` | `backend/app/api/monthly_trade.py:get_monthly_trade` | `frontend/components/monthly-trade-table.tsx:MonthlyTradeRow` |
| D103 | `/monthly-trade` | signal | `/api/monthly-trade/{id}` | `backend/app/api/monthly_trade.py:get_monthly_trade` | `frontend/components/monthly-trade-table.tsx:MonthlyTradeRow` |
| D104 | `/monthly-trade` | position start | `/api/monthly-trade/{id}` | `backend/app/services/monthly_trade_impl.py:MonthlyTradeCalculator` | `frontend/components/monthly-trade-table.tsx:MonthlyTradeRow` |
| D105 | `/monthly-trade` | position | `/api/monthly-trade/{id}` | `backend/app/services/monthly_trade_impl.py:MonthlyTradeCalculator` | `frontend/components/monthly-trade-table.tsx:MonthlyTradeRow` |
| D106 | `/monthly-trade` | return period | `/api/monthly-trade/{id}` | `backend/app/services/monthly_trade_impl.py:MonthlyTradeCalculator` | `frontend/components/monthly-trade-table.tsx:MonthlyTradeRow` |
| D107 | `/monthly-trade` | Return | `/api/monthly-trade/{id}` | `backend/app/api/monthly_trade.py:get_monthly_trade` | `frontend/components/monthly-trade-table.tsx:MonthlyTradeRow` |
| D108 | `/monthly-trade` | Cumulative | `/api/monthly-trade/{id}` | `backend/app/api/monthly_trade.py:get_monthly_trade` | `frontend/components/monthly-trade-table.tsx:MonthlyTradeRow` |
| D109 | `/monthly-trade` | ticker price movement | `/api/monthly-trade/{id}` | `backend/app/services/monthly_trade_impl.py:MonthlyTradeCalculator` | `frontend/components/monthly-trade-table.tsx:MonthlyTradeRow` |
| D110 | `/monthly-trade` | status badge | `/api/monthly-trade/{id}` | `backend/app/api/monthly_trade.py:get_monthly_trade` | `frontend/components/monthly-trade-table.tsx:getDecisionBadge` |
| D111 | `/monthly-trade` | next signal preview | `/api/monthly-trade/{id}` | `backend/app/api/monthly_trade.py:get_monthly_trade` | `frontend/components/monthly-trade-table.tsx:NextSignalPanel` |
| D112 | `/drawdowns` | chart date | `/api/drawdowns/{id}` | `backend/app/api/drawdowns.py:get_drawdowns` | `frontend/components/drawdowns-chart.tsx:DrawdownsChart` |
| D113 | `/drawdowns` | chart portfolio drawdown | `/api/drawdowns/{id}` | `backend/app/services/drawdowns_impl.py:DrawdownsCalculator.calculate` | `frontend/components/drawdowns-chart.tsx:DrawdownsChart` |
| D114 | `/drawdowns` | chart benchmark drawdown | `/api/drawdowns/{id}` | `backend/app/services/drawdowns_impl.py:DrawdownsCalculator.calculate` | `frontend/components/drawdowns-chart.tsx:DrawdownsChart` |
| D115 | `/drawdowns` | Rank | `/api/drawdowns/{id}` | `backend/app/services/drawdowns_impl.py:_extract_worst_drawdowns` | `frontend/components/drawdowns-table.tsx:DrawdownsTable` |
| D116 | `/drawdowns` | Start | `/api/drawdowns/{id}` | `backend/app/services/drawdowns_impl.py:_extract_worst_drawdowns` | `frontend/components/drawdowns-table.tsx:DrawdownsTable` |
| D117 | `/drawdowns` | End | `/api/drawdowns/{id}` | `backend/app/services/drawdowns_impl.py:_extract_worst_drawdowns` | `frontend/components/drawdowns-table.tsx:DrawdownsTable` |
| D118 | `/drawdowns` | Length | `/api/drawdowns/{id}` | `backend/app/services/drawdowns_impl.py:_extract_worst_drawdowns` | `frontend/components/drawdowns-table.tsx:DrawdownsTable` |
| D119 | `/drawdowns` | Recovery By | `/api/drawdowns/{id}` | `backend/app/services/drawdowns_impl.py:_extract_worst_drawdowns` | `frontend/components/drawdowns-table.tsx:DrawdownsTable` |
| D120 | `/drawdowns` | Recovery Time | `/api/drawdowns/{id}` | `backend/app/services/drawdowns_impl.py:_extract_worst_drawdowns` | `frontend/components/drawdowns-table.tsx:DrawdownsTable` |
| D121 | `/drawdowns` | Underwater | `/api/drawdowns/{id}` | `backend/app/services/drawdowns_impl.py:_extract_worst_drawdowns` | `frontend/components/drawdowns-table.tsx:DrawdownsTable` |
| D122 | `/drawdowns` | Drawdown | `/api/drawdowns/{id}` | `backend/app/services/drawdowns_impl.py:_extract_worst_drawdowns` | `frontend/components/drawdowns-table.tsx:DrawdownsTable` |
| D123 | `/drawdowns` | open/close selector | none | none | `frontend/components/drawdowns-table.tsx:DrawdownsTable` |
| D124 | `/rolling-returns` | rolling period | `/api/rolling-returns/{id}` | `backend/app/api/rolling_returns.py:get_rolling_returns` | `frontend/components/rolling-returns-summary-table.tsx:RollingReturnsSummaryTable` |
| D125 | `/rolling-returns` | average | `/api/rolling-returns/{id}` | `backend/app/services/rolling_returns_impl.py:RollingReturnsCalculator.calculate` | `frontend/components/rolling-returns-summary-table.tsx:RollingReturnsSummaryTable` |
| D126 | `/rolling-returns` | high | `/api/rolling-returns/{id}` | `backend/app/services/rolling_returns_impl.py:_get_precomputed_summary` | `frontend/components/rolling-returns-summary-table.tsx:RollingReturnsSummaryTable` |
| D127 | `/rolling-returns` | low | `/api/rolling-returns/{id}` | `backend/app/services/rolling_returns_impl.py:_get_precomputed_summary` | `frontend/components/rolling-returns-summary-table.tsx:RollingReturnsSummaryTable` |
| D128 | `/rolling-returns` | median | `/api/rolling-returns/{id}` | `backend/app/services/rolling_returns_impl.py:_get_precomputed_summary` | `frontend/components/rolling-returns-summary-table.tsx:RollingReturnsSummaryTable` |
| D129 | `/rolling-returns` | p10 | `/api/rolling-returns/{id}` | `backend/app/services/rolling_returns_impl.py:_get_precomputed_summary` | `frontend/components/rolling-returns-summary-table.tsx:RollingReturnsSummaryTable` |
| D130 | `/rolling-returns` | positive rate | `/api/rolling-returns/{id}` | `backend/app/services/rolling_returns_impl.py:_get_precomputed_summary` | `frontend/components/rolling-returns-summary-table.tsx:RollingReturnsSummaryTable` |
| D131 | `/rolling-returns` | sample count | `/api/rolling-returns/{id}` | `backend/app/services/rolling_returns_impl.py:_get_precomputed_summary` | `frontend/components/rolling-returns-summary-table.tsx:RollingReturnsSummaryTable` |
| D132 | `/rolling-returns` | best window | `/api/rolling-returns/{id}` | `backend/app/services/rolling_returns_impl.py:_get_precomputed_summary` | `frontend/components/rolling-returns-summary-table.tsx:RollingReturnsSummaryTable` |
| D133 | `/rolling-returns` | worst window | `/api/rolling-returns/{id}` | `backend/app/services/rolling_returns_impl.py:_get_precomputed_summary` | `frontend/components/rolling-returns-summary-table.tsx:RollingReturnsSummaryTable` |
| D134 | `/rolling-returns` | distribution | `/api/rolling-returns/{id}` | `backend/app/services/rolling_returns_impl.py:_get_precomputed_chart_data` | `frontend/components/rolling-returns-distribution-table.tsx:RollingReturnsDistributionTable` |
| D135 | `/rolling-returns` | rolling chart | `/api/rolling-returns/{id}` | `backend/app/services/rolling_returns_impl.py:_get_precomputed_chart_data` | `frontend/components/rolling-return-chart.tsx:RollingReturnChart` |
| D136 | `/deterioration` | portfolio | `/api/deterioration` | `backend/app/api/deterioration.py:get_deterioration_list` | `frontend/components/deterioration-table.tsx:DeteriorationTable` |
| D137 | `/deterioration` | type | `/api/deterioration` | `backend/app/api/deterioration.py:get_deterioration_list` | `frontend/components/deterioration-table.tsx:DeteriorationTable` |
| D138 | `/deterioration` | G1 | `/api/deterioration` | `backend/app/api/deterioration.py:get_deterioration_list` | `frontend/components/deterioration-table.tsx:DeteriorationTable` |
| D139 | `/deterioration` | G2 | `/api/deterioration` | `backend/app/api/deterioration.py:get_deterioration_list` | `frontend/components/deterioration-table.tsx:DeteriorationTable` |
| D140 | `/deterioration` | P | `/api/deterioration` | `backend/app/api/deterioration.py:get_deterioration_list` | `frontend/components/deterioration-table.tsx:DeteriorationTable` |
| D141 | `/deterioration` | p-bar | `/api/p-average` | `backend/app/api/p_average.py:get_p_average_list` | `frontend/components/deterioration-table.tsx:filteredData` |
| D142 | `/deterioration` | Label | `/api/deterioration` | `backend/app/api/deterioration.py:get_deterioration_list` | `frontend/components/deterioration-table.tsx:DeteriorationTable` |
| D143 | `/deterioration` | P6 history | `/api/deterioration/{id}` | `backend/app/api/deterioration.py:get_deterioration_history` | `frontend/components/pdet-line-chart.tsx:PdetLineChart` |
| D144 | `/deterioration` | P12 history | `/api/deterioration/{id}` | `backend/app/api/deterioration.py:get_deterioration_history` | `frontend/components/pdet-line-chart.tsx:PdetLineChart` |
| D145 | `/deterioration` | P24 history | `/api/deterioration/{id}` | `backend/app/api/deterioration.py:get_deterioration_history` | `frontend/components/pdet-line-chart.tsx:PdetLineChart` |
| D146 | `/deterioration` | Trend | `/api/deterioration/{id}` | `backend/app/api/deterioration.py:get_deterioration_history` | `frontend/components/deterioration-table.tsx:DeteriorationTable` |
| D147 | `/deterioration` | G1 value | `/api/deterioration/{id}` | `backend/app/api/deterioration.py:get_deterioration_history` | `frontend/components/stats-table.tsx:StatsTable` |
| D148 | `/deterioration` | G2 value | `/api/deterioration/{id}` | `backend/app/api/deterioration.py:get_deterioration_history` | `frontend/components/stats-table.tsx:StatsTable` |
| D149 | `/deterioration` | Data Months | `/api/deterioration/{id}` | `backend/app/api/deterioration.py:get_deterioration_history` | `frontend/components/stats-table.tsx:StatsTable` |
| D150 | `/deterioration` | Long Mean Return | `/api/deterioration/{id}` | `backend/app/api/deterioration.py:get_deterioration_history` | `frontend/components/stats-table.tsx:StatsTable` |
| D151 | `/deterioration` | Recent Mean Return | `/api/deterioration/{id}` | `backend/app/api/deterioration.py:get_deterioration_history` | `frontend/components/stats-table.tsx:StatsTable` |
| D152 | `/deterioration` | Z Value | `/api/deterioration/{id}` | `backend/app/api/deterioration.py:get_deterioration_history` | `frontend/components/stats-table.tsx:StatsTable` |
| D153 | `/deterioration` | G1 slope | `/api/deterioration/{id}` | `backend/app/api/deterioration.py:get_deterioration_history` | `frontend/components/stats-table.tsx:StatsTable` |
| D154 | `/deterioration` | G2 P erosion | `/api/deterioration/{id}` | `backend/app/api/deterioration.py:get_deterioration_history` | `frontend/components/stats-table.tsx:StatsTable` |
| D155 | `/docs` | Methodology | none | none | `frontend/components/docs/methodology-content.tsx:default export` |
| D156 | `/docs` | Terms and Definitions | none | none | `frontend/components/docs/terms-content.tsx:default export` |
| D157 | `/docs` | Notes and Disclosures | none | none | `frontend/components/docs/notes-content.tsx:default export` |
| D158 | `/docs` | Deterioration Monitor accordion | none | none | `frontend/components/docs/deterioration-content.tsx:default export` |
| D159 | `/faq` | FAQ section | none | none | `frontend/app/faq/page.tsx:map` |
| D160 | `/faq` | question | none | none | `frontend/app/faq/page.tsx:map` |
| D161 | `/faq` | answer | none | none | `frontend/app/faq/page.tsx:map` |
| D162 | `/faq` | glossary | none | none | `frontend/app/faq/page.tsx:map` |
| D163 | `/faq` | references | none | none | `frontend/app/faq/page.tsx:map` |
| D164 | `/faq` | CTA | none | none | `frontend/app/faq/page.tsx:default export` |
| D165 | `/offline` | Offline heading | none | none | `frontend/app/offline/page.tsx:default export` |
| D166 | `/offline` | retry action | none | none | `frontend/app/offline/page.tsx:default export` |
| D167 | `/offline` | home action | none | none | `frontend/app/offline/page.tsx:default export` |
| D168 | `/trades` | unavailable message | none | none | `frontend/app/trades/page.tsx:default export` |
| D169 | `/admin` | portfolio name | `/api/portfolios/get` | `backend/app/api/portfolios.py:get_portfolios` | `frontend/app/admin/page.tsx:getSortedPortfolios` |
| D170 | `/admin` | portfolio type | `/api/portfolios/get` | `backend/app/api/portfolios.py:get_portfolios` | `frontend/app/admin/page.tsx:getSortedPortfolios` |
| D171 | `/admin` | folder | `/api/portfolios/get` | `backend/app/api/portfolios.py:get_portfolios` | `frontend/app/admin/page.tsx:useAdminPage` |
| D172 | `/admin` | benchmark | `/api/portfolios/get` | `backend/app/api/portfolios.py:get_portfolios` | `frontend/app/admin/page.tsx:useAdminPage` |
| D173 | `/admin` | visibility | `/api/viewer-permissions` | `backend/app/api/viewer_permissions.py:get_viewer_permissions` | `frontend/app/admin/page.tsx:useAdminPage` |
| D174 | `/admin` | signal/DB status | `/admin/db-status` | `backend/app/api/db_admin.py:get_db_status` | `frontend/app/admin/page.tsx:dbStatus` |
| D175 | `/admin` | price/ticker symbol | `/api/portfolios/get` | `backend/app/api/portfolios.py:get_portfolios` | `frontend/app/admin/page.tsx:useAdminPage` |
| D176 | `/admin` | layer status | `/admin/db-status` | `backend/app/api/db_admin.py:get_db_status` | `frontend/app/admin/page.tsx:dbStatus` |
| D177 | `/admin` | operation result | `/admin/recalculate-sync` | `backend/app/api/etl_trigger.py:recalculate_sync` | `frontend/app/admin/page.tsx:useAdminPage` |
| D178 | `/admin/fof` | FoF name | `/api/portfolios/get` | `backend/app/api/portfolios.py:get_portfolios` | `frontend/app/admin/fof/page.tsx:fofPortfolios` |
| D179 | `/admin/fof` | component portfolio name | `/api/portfolios/{id}` | `backend/app/api/portfolios.py:get_portfolio` | `frontend/app/admin/fof/page.tsx:component_portfolios` |
| D180 | `/admin/fof` | component order | `/api/portfolios/{id}` | `backend/app/api/portfolios.py:get_portfolio` | `frontend/app/admin/fof/page.tsx:component_portfolios` |
| D181 | `/admin/fof` | recalculate operation state | `/admin/recalculate-sync` | `backend/app/jobs/recalculate_fast.py:recalculate_history_fast` | `frontend/app/admin/fof/page.tsx:default export` |
| D182 | `/admin/fof` | copy operation state | `/api/portfolios/save` | `backend/app/api/portfolios.py:save_portfolios` | `frontend/app/admin/fof/page.tsx:default export` |
| D183 | `/admin/folders` | folder name | `/api/admin/folders` | `backend/app/api/folders.py:get_folders` | `frontend/app/admin/folders/page.tsx:loadFolders` |
| D184 | `/admin/folders` | folder portfolio name | `/api/admin/folders` | `backend/app/api/folders.py:get_folders` | `frontend/app/admin/folders/page.tsx:portfoliosByFolder` |
| D185 | `/admin/folders` | uncategorized portfolio name | `/api/admin/folders` | `backend/app/api/folders.py:get_folders` | `frontend/app/admin/folders/page.tsx:uncategorizedPortfolios` |
| D186 | `/admin/folders` | display order | `/api/admin/folders/reorder` | `backend/app/api/folders.py:reorder_folders` | `frontend/app/admin/folders/page.tsx:loadFolders` |
| D187 | `/admin/folders` | move/reorder operation state | `/api/admin/folders/portfolios/{id}/move` | `backend/app/api/folders.py:move_portfolio` | `frontend/app/admin/folders/page.tsx:default export` |
| D188 | `/admin/visibility` | tier name | `/api/admin/tiers` | `backend/app/api/viewer_tiers.py:get_tiers` | `frontend/app/admin/visibility/page.tsx:fetchTiers` |
| D189 | `/admin/visibility` | core/info visibility | `/api/admin/tiers/{id}/visibility` | `backend/app/api/viewer_tiers.py:get_tier_visibility` | `frontend/app/admin/visibility/page.tsx:fetchTierSettings` |
| D190 | `/admin/visibility` | folder/PF hide/mask state | `/api/viewer-permissions` | `backend/app/api/viewer_permissions.py:get_viewer_permissions` | `frontend/app/admin/visibility/page.tsx:folderGroups` |
| D191 | `/admin/visibility` | global setting | `/api/admin/tiers/visibility/global` | `backend/app/api/viewer_tiers.py:get_global_visibility` | `frontend/app/admin/visibility/page.tsx:fetchGlobalSettings` |
| D192 | `/admin/visibility` | unsaved state | none | none | `frontend/app/admin/visibility/page.tsx:default export` |

機械集計: `awk -F'|' '$2 ~ /^ D[0-9]+ / {n++} END {print n+0}' docs/research/cmd_4295_dm-signal-ssot-audit-map.md` → **192 normalized item rows**。route母数は§3の21行を別集計し、正規化台帳のitem_id重複は0件。

## 4. API→BE handler→永続/生成 owner 対応

| API | handler | 直接入力/永続テーブル | 数値・系列の生成 owner |
|---|---|---|---|
| `/api/signals` | `signals.get_signals_light` | `signals`, `signal_decision_ledger`, portfolio config | L2/L3 signal generation; L5 `precompute_raw.py` signals builder |
| `/api/performance/{id}` / `/api/mtd/{id}` | `performance.get_portfolio_performance` / `get_mtd_performance` | `monthly_returns`, `precomputed_mtd`, prices | L2/L3 MonthlyReturn; MTD batch/precompute |
| `/api/metrics/{id}` / `/api/metrics/summary` | `metrics.get_portfolio_metrics` / `get_metrics_summary` | `portfolio_metrics`, `monthly_returns`, ticker returns, prices | `MetricsCalculator.calculate_metrics`; summary bulk wrapper |
| `/api/regime-analysis/{id}` | `regime_analysis.get_regime_analysis` | `monthly_returns`, benchmark series | BE regime classification/aggregation in API/service path |
| `/api/monthly-returns/{id}` | `monthly_returns.get_monthly_returns` | MonthlyReturn, prices, signals | `MonthlyReturnsCalculator.calculate` |
| `/api/annual-returns/{id}` | `annual_returns.get_annual_returns` | MonthlyReturn, prices | `AnnualReturnsCalculator._calculate_from_monthly` |
| `/api/monthly-trade/{id}` | `monthly_trade.get_monthly_trade` | signals, MonthlyReturn, precomputed raw | Monthly trade calculation + `monthly_trade.py` payload normalization |
| `/api/compare-returns` | `compare_returns.get_compare_returns` | MonthlyReturn, PrecomputedMtd, ticker monthly rows | `_trailing_return`/`_all_return`/`_period_values` |
| `/api/drawdowns/{id}` | `drawdowns.get_drawdowns` | `drawdown_periods`, MonthlyReturn | `DrawdownsCalculator.calculate`; fallback `_extract_worst_drawdowns` |
| `/api/rolling-returns/{id}` | `rolling_returns.get_rolling_returns` | `rolling_returns_summary`, `rolling_returns_chart` | `RollingReturnsCalculator` response projection; generator owns rows |
| `/api/deterioration` / `/{id}` | `get_deterioration_list` / `get_deterioration_history` | deterioration snapshots | deterioration batch |
| `/api/p-average` | `p_average.get_p_average_list` | p-average result tables | p-average batch |
| `/api/benchmark/{ticker}` | `benchmark.get_benchmark_performance` | ticker monthly/daily returns | `_build_monthly_series_from_ticker_monthly_return` or daily fallback |
| `/api/admin/folders*` | `folders.py` handlers | `portfolio_folders`, `Portfolio.folder_id` | persisted configuration; no return metric generation |
| `/api/admin/tiers*` / viewer permissions | `viewer_tiers.py`, `viewer_permissions.py` | tier/global visibility tables | persisted visibility configuration |

`recalculate_fast.py` establishes the layer boundary: L1 ticker returns, L2 standard portfolio signals/monthly returns, L3 FoF/derived outputs. `precompute_raw.py` only materializes response payloads and must not be treated as a competing calculator.

## 5. 重複生成候補と単一生成元

| candidate | 現在の複数経路 | 正とすべき単一生成元 | 判定 |
|---|---|---|---|
| CAGR | `/api/metrics` の `Geometric Mean (annualized)`、`/summary` の `SummaryTable.calculateTrueCAGR(total_return, period_months)` | BE の `MetricsCalculator.calculate_metrics` が返す canonical metric。Summary は同値を表示するだけにする候補。 | **重複候補**。FE の再計算は値の意味を再定義しうる。 |
| Maximum Drawdown | `MetricsCalculator.calculate_metrics` の `DrawdownPeriod`/price/monthly fallback、`DrawdownsCalculator.calculate` の `drawdown_periods`/series fallback | `drawdown_periods` を生成する drawdown pipeline と `DrawdownsCalculator` の persisted row。Metrics は rank=1 を読む。 | **重複候補**。fallback は障害時限定で、通常経路を一つに固定すべき。 |
| Monthly/annual/trailing returns | `MonthlyReturnsCalculator`、`AnnualReturnsCalculator`、`compare_returns._trailing_return/_all_return` | PostgreSQL `MonthlyReturn.monthly_return(_open)` を一次値とし、共通の period aggregation helper を一つにする。 | **経路重複候補**。各画面の期間投影は必要だが、複利実装は共通化対象。 |
| MTD | `/api/mtd`、dashboard の performance fallback、compare-returns の `PrecomputedMtd`/batch fallback | `PrecomputedMtd` と `build_compare_mtd_values_batch` の値。fallback は同一 helper に限定する。 | **重複候補**。as-of/preliminary の扱いを一箇所へ集約。 |
| Benchmark series | portfolio endpoint の `MonthlyReturn.benchmark_*`、compare の `/api/benchmark/{ticker}` | portfolio 期間の benchmark は MonthlyReturn、standalone ticker 比較は ticker return tables、と境界を明示し共有 formatter のみ再利用。 | **境界明示が必要**。同一 ticker の二重計算と誤認しないための分類候補。 |
| Rolling statistics | persisted `rolling_returns_summary` の median/p10/positive_rate/best/worst、FE `RollingReturnChart` の bins/win-rate/best-worst detail | summary 数値は rolling generator/table。FE は chart interaction 用の表示集計だけに限定。 | **表示集計と数値生成を分離**。FE の win-rate を別 SSOT にしない。 |
| Monthly trade return | API の `monthly_return(_open)` と `calculated_return_*`/price movement | `MonthlyReturn` の `monthly_return(_open)`。`calculated_return_*` は parity/debug 専用で表示値に使わない。 | **現物で分離済み**。監査契約として維持。 |

## 6. FE 再計算・派生表示の分類（AC3）

| FE 派生 | 現物 | BE 移管要否 | 判定理由 |
|---|---|---|---|
| End Balance | `SummaryTable`: `INITIAL_BALANCE * (1 + total_return)` | 原則不要。 | 表示用の初期残高換算。canonical return は BE。 |
| Summary CAGR | `SummaryTable.calculateTrueCAGR` | **移管候補**（または FE は API metric を表示）。 | 同じ CAGR が BE metric と別計算されるため、一意性を保つには BE 値を優先。 |
| Dashboard MTD multiplier | `dashboard/page.tsx` `mtdData`: `1 + pct / 100`; fallback `toMtdChartData` は first value で正規化。 | 不要。 | chart の軸形式・base normalization であり業務数値の新規生成ではない。 |
| Compare chart baseline | `comparison-chart.tsx` `alignedData`/`alignedBenchmark`: `returnValue / baseValue - 1`; date union/intersection と最近傍補間。 | 不要。 | 選択期間・比較軸に依存する可視化変換。API 値を置き換えない。 |
| Compare rows | `buildCompareReturnsRows`, `buildCompareSummaryRows`, `extractMetricsFrom` は timing 選択、ticker 正規化、metric projection。 | 不要。 | 新規の投資指標を計算せず、API payload を表の形へ射影する。 |
| Monthly/annual table | `getReturn`/`getBalance`、Open/Close 選択、currency/percent/date formatting。 | 不要。 | API の portfolio/benchmark/ticker 値を表示形式へ変換するだけ。 |
| Monthly trade | ticker を均等 weight として表示する `parseTickersWithWeights`、price movement の表示整形。 | 不要。 | position 表示用。Return 本体は `entry.monthly_return` を使用済み。 |
| Rolling chart detail | `RollingReturnChart` が chart points から bins、win-rate、best/worst detail を作る。 | **移管しない**。 | persisted summary にある統計と重複する範囲は summary を表示し、bins は chart 専用 UI 集計に限定する。 |
| Deterioration table/history | `filteredData` が p-average の `p_bar` を結合、dot/label/color と SVG path を生成。 | 不要。 | G1/G2/P/p̄ の値は BE、FE は表示状態・系列 path のみ。 |

## 7. 抽出コマンドと件数

以下は監査時に実行した一次コード抽出コマンド。`rg` の結果は生成物を参照せず、対象 checkout の現物を直接読んだ。

```bash
rg --files frontend/app | rg '/page\.tsx$' | sort
for f in $(rg --files frontend/app | rg '/page\.tsx$' | sort); do
  rg -n 'api\.|use[A-Z][A-Za-z]+\(|<[^>]*(Table|Chart|Card|Metric|Grid)|columns|data\.' "$f"
done
rg -n '^@(router|app)\.(get|post|put|patch|delete)' backend/app/api
rg -n '^class |^    def |^def ' backend/app/services backend/app/jobs
rg -n '<th|<td|dataKey|COLUMNS|COMPARE_.*_COLUMNS' frontend/components frontend/app
test -s docs/research/cmd_4294_dm-signal-page-data-api-map.md
```

実測件数:

| 測定対象 | 件数 |
|---|---:|
| FE `page.tsx` routes | 21 |
| backend API modules | 30 |
| backend route decorators | 92 |
| frontend app/components/hooks/contexts/lib source files | 220 |
| backend/app source files | 161 |
| 今回の表示項目台帳 route rows | 21 |
| AC2 重複生成候補 | 7 |
| AC3 FE 派生分類 | 8 |
| 正規化表示項目台帳 | 192 |

## 8. 結論

1. 表示値の大半は BE が生成し、FE は table/chart への射影・Open/Close 選択・formatting を行う。L5 `precomputed_raw` を別 SSOT とみなす経路はない。
2. 要注意の重複候補は CAGR、MDD、期間別 return、MTD。特に Summary CAGR は FE で再計算されるため、BE metric と一致する単一生成元を次の実装/レビューで固定する。
3. Monthly Trade は `monthly_return` を表示 SSOT とし、`calculated_return_*` は parity 用であることがコードに明記されている。これは維持すべき境界。
4. FE 派生のうち、End Balance/CAGR/比較 chart は表示目的の変換だが、CAGR だけは同一意味の数値を BE と二重生成しているため、AC2 の重複候補として扱う。
