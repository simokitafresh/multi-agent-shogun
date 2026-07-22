# cmd_karo_recon2_dm_style_axis_b — B2/B3 color audit

検証日: 2026-07-22。対象: `/mnt/c/Python_app/DM-signal/frontend/components/**/*.tsx` のうち `__tests__` を除く67/67件。CDP不使用、実装変更0。○=1件以上、×=0件。括弧内はgrep occurrence数。fileはすべて `frontend/components/` 相対。

## §6.1 コンポーネント×属性カバレッジ

| component | inline hex | `bg-*` | `border-*` |
|---|---:|---:|---:|
| `ErrorBoundary.tsx` | × (0) | ○ (2) | ○ (2) |
| `GlobalErrorBanner.tsx` | × (0) | ○ (3) | ○ (1) |
| `RecalculateStatus.tsx` | × (0) | ○ (2) | ○ (1) |
| `annual-returns-chart.tsx` | ○ (2) | ○ (5) | ○ (1) |
| `annual-returns-table.tsx` | × (0) | ○ (7) | ○ (26) |
| `auth-status.tsx` | × (0) | ○ (8) | ○ (7) |
| `chart/ChartAxes.tsx` | × (0) | × (0) | × (0) |
| `chart/ChartControls.tsx` | × (0) | × (0) | × (0) |
| `chart/ChartLegend.tsx` | × (0) | × (0) | × (0) |
| `chart/ChartTooltip.tsx` | × (0) | ○ (1) | ○ (1) |
| `chart/FromYearSelector.tsx` | × (0) | × (0) | × (0) |
| `chart/PeriodModeToggle.tsx` | × (0) | ○ (5) | × (0) |
| `chart/ScaleToggle.tsx` | × (0) | ○ (3) | ○ (2) |
| `chart/TimingToggle.tsx` | × (0) | ○ (3) | ○ (2) |
| `chart/YearRangeSelector.tsx` | × (0) | ○ (3) | ○ (2) |
| `compare-returns-table.tsx` | × (0) | ○ (9) | ○ (20) |
| `compare-summary-table.tsx` | × (0) | ○ (7) | ○ (22) |
| `comparison-chart.tsx` | × (0) | × (0) | × (0) |
| `docs/deterioration-monitor-content.tsx` | × (0) | ○ (1) | ○ (5) |
| `docs/disclosures-content.tsx` | × (0) | ○ (1) | ○ (1) |
| `docs/methodology-content.tsx` | × (0) | ○ (1) | ○ (6) |
| `docs/terms-content.tsx` | × (0) | ○ (4) | × (0) |
| `drawdowns-chart.tsx` | × (0) | × (0) | × (0) |
| `drawdowns-table.tsx` | × (0) | ○ (1) | ○ (5) |
| `install-prompt.tsx` | × (0) | ○ (1) | ○ (1) |
| `language-toggle.tsx` | × (0) | ○ (6) | × (0) |
| `metrics-table.tsx` | × (0) | ○ (1) | ○ (2) |
| `mobile-menu.tsx` | × (0) | × (0) | × (0) |
| `model-trades-table.tsx` | × (0) | ○ (8) | ○ (8) |
| `momentum-chart.tsx` | × (0) | × (0) | × (0) |
| `monthly-returns-table.tsx` | × (0) | ○ (8) | ○ (29) |
| `monthly-trade-table.tsx` | × (0) | ○ (18) | ○ (11) |
| `mtd-chart.tsx` | × (0) | × (0) | × (0) |
| `mtd-daily-table.tsx` | × (0) | ○ (7) | ○ (9) |
| `page-navigation.tsx` | × (0) | ○ (1) | × (0) |
| `page-shell.tsx` | × (0) | ○ (3) | × (0) |
| `page-view-tracker.tsx` | × (0) | × (0) | × (0) |
| `period-notes.tsx` | × (0) | × (0) | ○ (2) |
| `portfolio-details.tsx` | × (0) | ○ (2) | ○ (4) |
| `portfolio-nav-selector.tsx` | × (0) | ○ (2) | × (0) |
| `portfolio-select-items.tsx` | × (0) | × (0) | × (0) |
| `portfolio-selector.tsx` | × (0) | ○ (2) | ○ (4) |
| `risk-management-table.tsx` | × (0) | ○ (2) | ○ (34) |
| `rolling-return-chart.tsx` | × (0) | ○ (7) | ○ (1) |
| `rolling-returns-distribution-table.tsx` | × (0) | × (0) | ○ (4) |
| `rolling-returns-summary-table.tsx` | × (0) | ○ (1) | ○ (18) |
| `sidebar.tsx` | × (0) | ○ (4) | ○ (5) |
| `signal-pie-chart.tsx` | ○ (8) | ○ (1) | ○ (1) |
| `summary-table.tsx` | × (0) | ○ (4) | ○ (2) |
| `sw-register.tsx` | × (0) | ○ (3) | ○ (1) |
| `theme-provider.tsx` | × (0) | × (0) | × (0) |
| `theme-toggle.tsx` | × (0) | ○ (5) | × (0) |
| `total-return-chart.tsx` | × (0) | × (0) | × (0) |
| `ui/accordion.tsx` | × (0) | × (0) | ○ (2) |
| `ui/button.tsx` | × (0) | ○ (10) | ○ (3) |
| `ui/dropdown-menu.tsx` | × (0) | ○ (4) | ○ (3) |
| `ui/folder-filter-chip.tsx` | × (0) | ○ (1) | ○ (3) |
| `ui/glass-card.tsx` | × (0) | × (0) | × (0) |
| `ui/input.tsx` | × (0) | ○ (2) | ○ (2) |
| `ui/latex.tsx` | × (0) | × (0) | × (0) |
| `ui/loading.tsx` | × (0) | × (0) | × (0) |
| `ui/message-banner.tsx` | × (0) | ○ (3) | ○ (3) |
| `ui/page-header.tsx` | × (0) | × (0) | × (0) |
| `ui/select.tsx` | × (0) | ○ (7) | ○ (3) |
| `ui/skeleton.tsx` | × (0) | ○ (2) | × (0) |
| `up-down-market-chart.tsx` | ○ (3) | ○ (6) | ○ (11) |
| `viewer-auth-modal.tsx` | × (0) | ○ (2) | ○ (7) |

全数集計: component 67、未確認0。inline-hex grep 13 occurrence/3 files（うち `up-down-market-chart.tsx:71` のIssue `#146`は色ではない偽陽性、実色12）。`bg-*` 189 occurrence/47 files、`border-*` 277 occurrence/42 files。0件componentも表から除外していない。

## B2 inline hex — 全file:line

- `frontend/components/annual-returns-chart.tsx:23-24` — `#3B82F6`, `#2DD4BF`
- `frontend/components/up-down-market-chart.tsx:54-55` — `#3B82F6`, `#2DD4BF`; `:71` はIssue番号`#146`（色ではない）
- `frontend/components/signal-pie-chart.tsx:32-37,124` — palette 6色、dark/light stroke 2色（同一行2 occurrence）

再現コマンド: `rg -n '#[0-9A-Fa-f]{3}([0-9A-Fa-f]{3})?\\b' frontend/components -g '*.tsx' -g '!**/__tests__/**'`。B3の全file:lineは `rg -n '\\b(bg|border)-[[:alnum:]_:/.-]+' frontend/components -g '*.tsx' -g '!**/__tests__/**'` で取得し、上表の各component occurrence数と照合した。

## 統一基準・SSOT再利用判定

| 対象 | 統一基準 | 既存SSOT候補 | 現物判定 |
|---|---|---|---|
| chart semantic color | inline hex禁止、意味色はCSS var経由 | `frontend/lib/colors.ts` の `CHART_COLORS` / `PORTFOLIO_COLORS` | 再利用可。既に25 componentが`@/lib/colors`をimport。annual/up-down/pieの実色12件が移行候補 |
| status/value text | positive/negative/warning/neutralを直書きしない | 同 `STATUS_TEXT_CLASSES`, `getValueColorClass` | 再利用可。表・status・bannerで現用 |
| background/border | Tailwind palette直書きをsemantic tokenへ寄せ、同一stateのborder/bg組を一組として定義 | `STATUS_TEXT_CLASSES`拡張または新規semantic surface map | 部分再利用可。text SSOTのみではbg/borderを表せないため、`colors.ts`内の追加map候補 |
| page heading | title色/typographyを個別定義しない | `frontend/components/ui/page-header.tsx` の `PAGE_TITLE_CLASS` / `PageHeader` | 色B軸への直接再利用は不可（header typography用）。page側統一には再利用可 |

整数結論: 漏れ0 component、inline色直書き12実色（raw grep 13）、既存SSOT再利用候補2資産（`colors.ts`, `page-header.tsx`）、うちB軸へ直接再利用可1・部分/隣接再利用1。実装変更0、CDP 0回。
