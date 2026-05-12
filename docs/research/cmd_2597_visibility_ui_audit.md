# cmd_2597 Visibility UI Audit

## 1. Scope

- Date: 2026-05-07 JST
- Frontend: `https://dm-signal-frontend.onrender.com`
- Data as of: `2026-05-06`
- CDP: isolated debug Chrome/Edge profile on port `9222`
- Auth: Admin UI login confirmed; screenshots and DOM text were captured from rendered production pages, not from grep.
- Raw artifact: `outputs/cdp/cmd_2597/audit_raw.json`
- Screenshots: `outputs/cdp/cmd_2597/*.png` (`28` PNG files: 14 pages x standard/FoF)

Portfolios used:

| Variant | Portfolio | ID | Current signal shown by `/api/signals` |
|---|---|---|---|
| Standard | `DM2` | `f8d70415-24f2-4b1a-a603-d0e86155255a` | `XLU` |
| FoF | `Ave-X` | `a78887bf-25ae-4525-81af-cd4c630b3d36` | `XLU 66.7%, TECL 16.7%, TMV 16.7%` |

## 2. Binary Classification

Definitions used in this audit:

- Holding signal information: current or historical signal/position/holding text such as `Signal for 2026/5`, `Position`, `Signal Date`, or per-month holdings.
- Component ticker information: ticker symbols or weighted ticker/component composition visible to users, including ticker columns and FoF weighted holdings.

| Page | Route | Key visible UI elements | Holding signal info | Component ticker info | FoF difference |
|---|---|---:|---:|---|
| Dashboard | `/dashboard` | PF selector, `Signal for 2026/5`, ticker/weight block, Total Return chart, MTD chart/table | yes | yes | FoF shows weighted components (`XLU 66.7%, TECL 16.7%, TMV 16.7%`); standard shows single ticker (`XLU 100.0%`). |
| Compare | `/compare` | multi-PF selector, benchmark selector, From selector, Comparison chart, period buttons | no | no | Selected PF query did not materially change visible content in this capture; page showed comparison set such as `DM-safe`, `DM-safe-2`, `SPY`. |
| Compare Summary | `/compare-summary` | folder chips, global portfolio table, metrics columns `CAGR` through `p̅` | no | yes | Same global table for both variants. Some portfolio names expose ticker-like components/params, e.g. `L0-Qj_TECL_XLU...`. |
| Summary | `/summary` | selected PF selector, Performance Summary table | no | no | Metrics switch from `DM2` to `Ave-X`; no current signal or component weights shown. |
| Annual Returns | `/annual-returns` | annual return chart, annual table, ticker return columns | no | yes | FoF table exposes a wider ticker set (`GLD/LQD/SPXL/SPY/TECL/TMF/TMV/TQQQ/XLU/^VIX`) than standard. |
| Monthly Returns | `/monthly-returns` | monthly table with pagination, ticker return columns | no | yes | FoF table exposes the same wider ticker-return column set; standard shows smaller ticker set. |
| Monthly Trade | `/monthly-trade` | `Signal Date`, `Signal`, `Position`, `Return Period`, `Price Movement` table | yes | yes | FoF rows expose weighted monthly positions and per-component price moves; standard rows show single-position trades. |
| Rolling Returns | `/rolling-returns` | Summary Statistics table, rolling CAGR chart, period buttons | no | no | Metrics switch from `DM2` to `Ave-X`; no signal/component composition shown. |
| Drawdowns | `/drawdowns` | drawdown chart, PF drawdown table, SPY drawdown table | no | no | Metrics switch from `DM2` to `Ave-X`; no signal/component composition shown. |
| Metrics | `/metrics` | Risk and Return Metrics, Up vs Down Market Performance table | no | no | Metrics switch from `DM2` to `Ave-X`; no signal/component composition shown. |
| Deterioration | `/deterioration` | folder chips, deterioration count chips, portfolio table with `G1/G2/P/p̅/P₆/P₁₂/P₂₄` | no | yes | Same global table for both variants. Portfolio names include ticker-like encoded names such as `L0-..._TMV...`. |
| Trades | `/trades` | blocked-page message (`この街道は現在封鎖中にございます`) | no | no | No PF-specific visible data. |
| Docs | `/docs` | collapsed sections: Methodology, Terms and Definitions, Notes and Disclosures, Deterioration Monitor | no | no | No PF-specific visible data. |
| FAQ | `/faq` | language toggle, collapsed FAQ groups, strategy guide links | no | no | No PF-specific visible data. |

## 3. Page Notes

### Dashboard

- Standard screenshot: `outputs/cdp/cmd_2597/standard_dashboard.png`
- FoF screenshot: `outputs/cdp/cmd_2597/fof_dashboard.png`
- Visible standard elements include `Signal for 2026/5`, `XLU`, `XLU 100.0%`, `Total Return (DM2)`, `MTD Performance`, and `MTD Daily Returns`.
- Visible FoF elements include `Signal for 2026/5`, `XLU 66.7%, TECL 16.7%, TMV 16.7%`, repeated component rows, `Total Return (Ave-X)`, and MTD charts/tables.
- Mask implication: vis_L3 must hide the current signal block; vis_L4 must hide FoF component ticker/weight rows while preserving non-sensitive backtest charts if intended.

### Compare

- Screenshots: `standard_compare.png`, `fof_compare.png`
- Visible elements include `Select Portfolios (max 7)`, `Bench: SPY`, `From: ALL`, period buttons, and chart legend values.
- No selected-current-signal text was visible. The selected `portfolio` URL parameter did not drive the visible comparison set in this capture.

### Compare Summary

- Screenshots: `standard_compare-summary.png`, `fof_compare-summary.png`
- Main columns: `Portfolio`, `CAGR`, `Sharpe`, `Sortino`, `MDD`, `Stdev`, `Max Run-up`, `Tail Contrib`, `Left Jumps`, `New High %`, `Up Cap`, `Down Cap`, `U/D Spread`, `U/D Ratio`, `U/D Vector`, `Calmar`, `UWP (MaxDD)`, `Avg UWP`, `PTU(%)`, `G1`, `G2`, `P`, `p̅`.
- No holding signal is shown, but ticker-bearing portfolio names are visible in the table.
- Mask implication: if ticker-coded PF names are considered component leakage, vis_L4 needs a PF-name masking policy on global tables.

### Summary / Rolling / Drawdowns / Metrics

- Screenshots: `standard_summary.png`, `fof_summary.png`, `standard_rolling-returns.png`, `fof_rolling-returns.png`, `standard_drawdowns.png`, `fof_drawdowns.png`, `standard_metrics.png`, `fof_metrics.png`
- These pages show selected-PF performance/risk/drawdown metrics and charts.
- No current signal, historical position, or component-weight block was visible in the captured viewport/DOM text.

### Annual Returns / Monthly Returns

- Screenshots: `standard_annual-returns.png`, `fof_annual-returns.png`, `standard_monthly-returns.png`, `fof_monthly-returns.png`
- Both pages show ticker return columns under `Tickers`.
- FoF exposes more ticker columns than standard. Example FoF columns: `GLD`, `LQD`, `SPXL`, `SPY`, `TECL`, `TMF`, `TMV`, `TQQQ`, `XLU`, `^VIX`.
- Mask implication: these pages are not holding-signal pages, but they are component/ticker-exposure pages.

### Monthly Trade

- Screenshots: `standard_monthly-trade.png`, `fof_monthly-trade.png`
- Main columns: `Month`, `Signal Date`, `Signal`, `Position Start`, `Position`, `Return Period`, `Return`, `Cumulative`, `Price Movement`.
- Standard rows show single-position holdings such as `XLU(100%)` and `TECL(100%)`.
- FoF rows show weighted component holdings such as `XLU(67%) /TECL(17%) /TMV(17%)` plus per-component price moves.
- Mask implication: this is the highest-risk page for both vis_L3 and vis_L4.

### Deterioration

- Screenshots: `standard_deterioration.png`, `fof_deterioration.png`
- Main columns: `Portfolio`, `G1`, `G2`, `P`, `p̅`, `Label`, `P₆`, `P₁₂`, `P₂₄`, `p̅`, `Trend`, `G1`, `G2`.
- No current holding signal is shown.
- Component ticker concern is indirect through encoded portfolio names, not through signal/position columns.

### Trades / Docs / FAQ

- Screenshots: `standard_trades.png`, `fof_trades.png`, `standard_docs.png`, `fof_docs.png`, `standard_faq.png`, `fof_faq.png`
- `/trades` is blocked and shows only a closed-road message.
- `/docs` and `/faq` are static/collapsed content pages in the captured state.
- No PF-specific signal or component composition was visible.

## 4. Candidate Mask Targets

| Priority | Page | Element | Reason |
|---|---|---|---|
| high | Dashboard | `Signal for YYYY/M` and adjacent ticker/weight rows | Direct current holding signal; FoF includes component weights. |
| high | Monthly Trade | `Signal`, `Position`, `Price Movement` rows | Historical and current holdings, weighted FoF positions, and component price movement are directly visible. |
| medium | Annual Returns | ticker return columns | No holding signal, but component ticker universe is visible. |
| medium | Monthly Returns | ticker return columns | No holding signal, but component ticker universe is visible. |
| medium | Compare Summary | ticker-coded portfolio names | Global table can leak ticker-like strategy/component names through PF names. |
| medium | Deterioration | ticker-coded portfolio names | Same indirect leak pattern as Compare Summary. |
| low | Summary/Rolling/Drawdowns/Metrics | selected PF name only | Backtest metrics are visible, but no current signal/component composition was found. |
| none | Trades/Docs/FAQ | blocked/static content | No PF-specific signal/component composition found in captured state. |

## 5. Verification Status

- AC1: CDP screenshots captured for all requested routes in both standard and FoF states.
- AC2: Visible headings, controls, table columns, chart labels, and body text were extracted from production DOM.
- AC3: Each page was classified for holding-signal and component-ticker exposure.
- AC4: FoF (`Ave-X`) was compared against standard (`DM2`) on every route.
- AC5: This audit is saved at `docs/research/cmd_2597_visibility_ui_audit.md`.
