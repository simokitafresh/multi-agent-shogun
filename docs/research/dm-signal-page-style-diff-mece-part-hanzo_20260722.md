# DM-Signal page style MECE fragment — rolling-returns / drawdowns / monthly-trade

Verified: 2026-07-22. Scope is implementation evidence only; no browser inference. Paths below are relative to `/mnt/c/Python_app/DM-signal` unless prefixed `infra:`.

## Dependency graph (AC1)

- `frontend/app/rolling-returns/page.tsx:4-10` → `PageShell`, `RollingReturnChart`, `RollingReturnsDistributionTable`, `RollingReturnsSummaryTable`, `GlassCard`, `Loading`, `MessageBanner`.
  - `RollingReturnChart` → `ChartAxes`, `ChartLegend`, `ChartTooltip` (`frontend/components/rolling-return-chart.tsx:4-6`).
  - Both rolling tables have no child UI-component import (`frontend/components/rolling-returns-distribution-table.tsx:3-4`; `frontend/components/rolling-returns-summary-table.tsx:3-5`).
- `frontend/app/drawdowns/page.tsx:9-14` → `GlassCard`, `MessageBanner`, `Loading`, `DrawdownsTable`, `DrawdownsChart`, `PageShell`.
  - `DrawdownsChart` → `ChartAxes`, `ChartLegend`, `ChartTooltip` (`frontend/components/drawdowns-chart.tsx:6-8`); `DrawdownsTable` has no child UI-component import (`frontend/components/drawdowns-table.tsx:3-4`).
- `frontend/app/monthly-trade/page.tsx:4-7` → `MonthlyTradeTable`, `PageShell`, `Loading`, `MessageBanner`; `MonthlyTradeTable` has no child UI-component import (`frontend/components/monthly-trade-table.tsx:3-6`).
- Shared recursive branch: `PageShell` → `PortfolioNavSelector`, `MobileMenu`, `TimingToggle`, `PageNavigation`, `HomeButton` (`frontend/components/page-shell.tsx:6-9`). `Loading` → Lucide `Loader2` (`frontend/components/ui/loading.tsx:1`); `MessageBanner` → Lucide status icons (`frontend/components/ui/message-banner.tsx:1-2`); `GlassCard` is a leaf wrapper around `.glass-card` (`frontend/components/ui/glass-card.tsx:1-10`).

This enumerates every imported React/UI component reachable from the three page roots; hooks, contexts, types and data libraries are intentionally not classified as visual components.

## Axis definitions

A shell/width; B vertical grouping; C container/card; D section heading; E typography/alignment; F semantic color; G primary visualization/data surface; H controls/actions; I loading/error/empty states; J responsive/accessibility. Each implementation fact belongs to exactly one axis.

## 30-cell evidence matrix (AC2)

| Axis | rolling-returns | drawdowns | monthly-trade |
|---|---|---|---|
| A shell/width | `PageShell` props at `page.tsx:86`; shared `max-w-6xl`, `px-4 md:px-8` at `page-shell.tsx:25,47,56`. | Same shell at `page.tsx:80`; identical shared width evidence. | Same shell at `page.tsx:165`; identical shared width evidence. |
| B vertical grouping | Content stack `space-y-6 md:space-y-8` (`page.tsx:113`). | Inner stack `space-y-6 md:space-y-8` (`page.tsx:105`). | No page stack; single table under `min-h-[300px]` (`page.tsx:187-205`), hence N/A for multi-section spacing by code. |
| C container/card | Three `GlassCard className="p-4 md:p-6"` (`page.tsx:136,149,163`); loading cards same (`116,124`). | Two/three `GlassCard className="p-6"` (`page.tsx:107,120,132`). | No `GlassCard` import or JSX (`page.tsx:4-18,194-203`); table root is `w-full overflow-x-auto` (`monthly-trade-table.tsx:120`). |
| D section heading | Repeated plain `h2 text-lg font-semibold text-foreground mb-4` (`page.tsx:117-119,137-139,150-152,164-166`). | `h2 text-lg font-semibold mb-6 flex ... gap-2` plus decorative bar (`page.tsx:108-111,121-124,133-136`). | Table owns one `h2 text-lg font-semibold text-foreground` (`monthly-trade-table.tsx:123-130`); no page-owned heading. |
| E typography/alignment | Table desktop mixes left labels and centered/right numeric cells (`distribution-table.tsx:75,80,92`; `summary-table.tsx:102-140`). | Table labels left and drawdown right (`drawdowns-table.tsx:36-43`); note is centered italic (`page.tsx:144-146`). | Dense labels `text-xs/text-sm`, numeric `text-right font-mono` (`monthly-trade-table.tsx:123-130,736-741`). |
| F semantic color | Chart distribution uses cyan vs slate and negative red (`rolling-return-chart.tsx:588-614,548`); tables use primary for portfolio and muted for benchmark (`summary-table.tsx:108-115`). | Primary bar for portfolio, muted bar for benchmark (`page.tsx:109,134`); negative values red (`drawdowns-table.tsx:64`). | Sky denotes active mode, primary denotes actions/data, amber denotes warning (`monthly-trade-table.tsx:143-160,350-392`). |
| G data surface | Summary table + distribution table + interactive SVG chart (`page.tsx:140-173`; chart canvas `rolling-return-chart.tsx:363-370`). | Interactive chart then portfolio/optional benchmark tables (`page.tsx:112-140`; chart canvas `drawdowns-chart.tsx:186-193`). | One wide trade table (`monthly-trade-table.tsx:239-287`) with detail rows through `:816`; no chart by imports/JSX. |
| H controls/actions | Chart period selector uses flex-wrap pills (`rolling-return-chart.tsx:325-356`); no page-level primary action. | No button/control in page or its two direct data components (imports and JSX: `page.tsx:9-14,104-140`; `drawdowns-table.tsx:32-65`; `drawdowns-chart.tsx:183-193`), thus N/A. | View toggles, load-all, show-all, pagination buttons (`monthly-trade-table.tsx:136-216`), styled as small rounded text controls. |
| I states | Page load min-height 350; data skeletons 200/350; shared banners (`page.tsx:88-109,114-131`). | Page/data load min-height 300; shared banners (`page.tsx:81-103`). | Page/data load min-height 300; shared banners (`page.tsx:166-191`). |
| J responsive/a11y | Padding responds at `md`; desktop/mobile table branches (`page.tsx:116-174`; `distribution-table.tsx:71,136`; `summary-table.tsx:97,309`). Shared Loading has `role=status`, `aria-label`, hidden icon (`ui/loading.tsx:10-12`). | Desktop columns hidden via `hidden md:table-cell` (`drawdowns-table.tsx:39-42,52-61`); chart is width responsive (`drawdowns-chart.tsx:186-193`); shared Loading evidence applies. | Toolbar changes `flex-col`→`sm:flex-row`; columns hide at md/lg (`monthly-trade-table.tsx:122,278-287`); shared Loading evidence applies. |

## Axis differences, guide deviations, unification candidates (AC3)

- A is unified by `PageShell`; preserve it. B/C/D diverge together: rolling uses responsive card padding/plain headings, drawdowns fixed padding/decorative bars, monthly no card. Candidate: one `DataSection` contract with explicit `surface=card|bare`, but default spacing and heading treatment shared.
- D/F drawdowns' colored heading bars are decorative and encode portfolio/benchmark partly by color. This conflicts with “keep patterns consistent”, “remove unnecessary styles”, and “do not rely on color alone” (`infra:context/ui-design-guide.md §1, §6`). Candidate: remove bars or pair meaning with a textual badge/icon.
- H monthly controls are `px-2 py-1` / `px-3 py-1.5`, below the guide's 48pt touch floor (`monthly-trade-table.tsx:143-216`; guide §3/§7). Candidate: common button primitives with minimum hit area and filled/outline/underlined hierarchy. Rolling chart pills need the same audit; drawdowns has no local action.
- E monthly's dense `text-xs` metadata and colored text require measured 4.5:1 contrast; implementation classes alone cannot prove contrast. Candidate: token-level contrast test. This is an unresolved verification condition, not a claim of failure.
- I differs at 350px vs 300px and rolling nests card skeletons while the others use bare loaders. Candidate: shared page/data-state component with one reserved-height token and optional surface matching final content.
- J responsive behavior exists on all three, but rolling duplicates whole mobile tables, drawdowns hides columns, monthly hides columns and retains horizontal overflow. Candidate: document a single table-responsive policy per information criticality, not per page.

## CE / ME binary verification (AC4)

- CE pages: 3/3; axes: 10/10; cells: 30/30. N/A cells: 2/30 (monthly B, drawdowns H), both carry negative code/import evidence.
- Dependency roots: 3/3; direct visual imports: rolling 7/7, drawdowns 6/6, monthly 4/4; recursive shared/chart branches recorded above.
- ME finding attribution: 6 candidates across disjoint axes B/C/D, D/F, H, E, I, J. Candidate count 6; true-positive code-supported 6; false-positive 0; duplicate finding pairs 0.
- Result: PASS. Missing cells 0, duplicate findings 0, unresolved conditions 0. The contrast item is explicitly a future measurement candidate and does not assert an unverified implementation defect.
