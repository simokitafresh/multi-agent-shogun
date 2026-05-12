# cmd_2553 saizo scout: DM-Signal polysemy crosscheck

date: 2026-05-04
worker: saizo
scope: multi-agent-shogun knowledge files + DM-Signal backend/app + frontend/app
target_input: `queue/cmd_2553_mcp_polysemy_extract.txt`

## Summary

The MCP extract is confirmed and the code layer adds two high-risk collision groups:

1. `L0/L1/L2/L3/L4` is not one taxonomy. It names PF research hierarchy, SSOT return hierarchy, sync job hierarchy, and visibility/masking hierarchy.
2. `signal` is not one data concept. It names product/page data, raw computed signal, holding signal, signal table rows, FE context state, and visibility mask flags.
3. `component` is not one object. It names FoF child portfolios, final ticker components, UI component modules, and masked component data.
4. `weight` is not one quantity. It names lookback blend weight, final ticker allocation, FoF component target/actual weight, Ward cluster key, Kalman weights, and UI display percentages.

Count scan over the scoped files found: `L0` 89, `L1` 71, `L2` 98, `L3` 81, `L4` 40, `signal` 656, `holding_signal` 207, `component` 88, `weight` 202, `layer` 60, `mode` 114, `type` 423, `tier` 92, `block` 249, `pipeline` 281, `config` 457, `momentum` 152, `monthly_return` 115, `source` 700.

## Collision Inventory

| Term | Meanings Found | Evidence | Collision Degree |
|---|---|---|---|
| `L0/L1/L2/L3` | PF/research hierarchy: `L0=四神`, `L1=忍法`, `L2=奥義` | `context/dm-signal-core.md:12-16` | High: same project docs |
| `L0/L1/L2/L3` | SSOT/return hierarchy: `L0=Price/trade-rule`, `L1=return functions`, `L2=MonthlyReturn cache`, `L3=UI` | `context/dm-signal-core.md:70-79` | High: same file as PF hierarchy |
| `L0/L1/L2/L3` | Sync job hierarchy: L0 prices, L1 tickers, L2 standard, L3 FoF | `/mnt/c/Python_app/DM-signal/backend/app/api/etl_trigger.py:508-541`, `:602-682`, `:768-829` | High: BE API and admin UI |
| `L1/L1.5/L2/L3/L4` | Visibility hierarchy: L1 pages, L1.5 folders, L2 hide PF, L3 mask signal, L4 mask components | `/mnt/c/Python_app/DM-signal/backend/app/db/models.py:471-489`, `/mnt/c/Python_app/DM-signal/frontend/app/admin/visibility/page.tsx:78`, `:529-596` | High: collides with sync/PF layer labels |
| `signal` | Raw computed signal in `signals.signal` | `/mnt/c/Python_app/DM-signal/backend/app/db/models.py:87-96` | High: same table as holding signal |
| `holding_signal` | Rebalance-aware held position | `/mnt/c/Python_app/DM-signal/backend/app/db/models.py:94-95`, `/mnt/c/Python_app/DM-signal/backend/app/jobs/generators/monthly_returns.py:367-431` | High: frequent source of rule mistakes |
| `signals` | FE fetched app state/context | `/mnt/c/Python_app/DM-signal/frontend/app/dashboard/page.tsx:220`, `:564-616` | Medium: plural means API payload, not DB rows |
| `hide_signal` | Visibility flag for masking, not trading signal | `/mnt/c/Python_app/DM-signal/backend/app/services/masking_service.py:4-12`, `:90-103` | High: same token with unrelated semantics |
| `component` | FoF child portfolio ID | `/mnt/c/Python_app/DM-signal/backend/app/jobs/shared.py:68-82`, `/mnt/c/Python_app/DM-signal/backend/app/jobs/recalculate_fof.py:493-555` | High: overlaps UI and ticker expansion |
| `component` | Masked component/ticker data in visibility | `/mnt/c/Python_app/DM-signal/backend/app/services/masking_service.py:95-113`, `:149-157` | Medium: same user-facing label as FoF component |
| `component` | React component module/import | `/mnt/c/Python_app/DM-signal/frontend/app/admin/fof/components/FoFEditor.tsx`, `/mnt/c/Python_app/DM-signal/frontend/app/admin/visibility/components/ManageTiersModal.tsx` | Low: code-structure context usually clear |
| `weight` | LookbackPeriod blend weight | `/mnt/c/Python_app/DM-signal/backend/app/schemas/models.py:25-28`, `:80-83` | High: same field name as allocation |
| `weight` | Ticker allocation/final portfolio weight | `/mnt/c/Python_app/DM-signal/backend/app/services/pipeline/engine.py:179-194`, `/mnt/c/Python_app/DM-signal/backend/app/jobs/generators/trade_performance.py:516-611` | High |
| `target_weight` | FoF component target allocation/debug table | `/mnt/c/Python_app/DM-signal/backend/app/db/models.py:538-558`, `/mnt/c/Python_app/DM-signal/frontend/app/admin/fof/components/WeightBreakdown.tsx:12-18`, `:108-188` | High: can be mistaken for lookback weight |
| `type` | Portfolio DB type `standard/fof` | `/mnt/c/Python_app/DM-signal/backend/app/db/models.py:70` | Medium |
| `type` | Pipeline/block/discriminated union and UI event type | `/mnt/c/Python_app/DM-signal/backend/app/schemas/pipeline.py:23-49`, `/mnt/c/Python_app/DM-signal/backend/app/schemas/models.py:251-256` | Medium |
| `tier` | Viewer access tier | `/mnt/c/Python_app/DM-signal/backend/app/db/models.py:464-489`, `/mnt/c/Python_app/DM-signal/frontend/app/admin/visibility/page.tsx:50-64` | Medium: MCP extract notes `tier` is unsafe as replacement for L* |
| `mode` | PF mode `激攻/鉄壁/常勝` | `projects/dm-signal.yaml:45-51` | Medium |
| `mode` | Pydantic/model dump or UI/admin state mode | `/mnt/c/Python_app/DM-signal/backend/app/jobs/etl/calculator.py:151`, FE admin components | Medium |

## MECE Naming Proposal

| Current Term | Use New Term For | Example New Name |
|---|---|---|
| `L0/L1/L2` for 四神/忍法/奥義 | PF product hierarchy | `pf_stage_shijin`, `pf_stage_ninpo`, `pf_stage_ougi` |
| `L0/L1/L2/L3` for sync | ETL dependency stages | `sync_stage_price`, `sync_stage_ticker`, `sync_stage_standard_pf`, `sync_stage_fof` |
| `L0/L1/L2/L3` for SSOT | calculation/data lineage | `calc_lineage_price`, `calc_lineage_return_fn`, `calc_lineage_monthly_cache`, `calc_lineage_ui` |
| `L1/L2/L3/L4` for visibility | visibility policy levels | `visibility_page`, `visibility_hide_pf`, `visibility_mask_signal`, `visibility_mask_components` |
| `signal` raw | computed signal before rebalance hold logic | `raw_signal` or `computed_signal` |
| `holding_signal` | rebalance-aware held position | keep `holding_signal` |
| FE `signals` context | API portfolio signal payload | `portfolio_signal_state` |
| `hide_signal` | visibility mask flag | `mask_signal_enabled` |
| `component_portfolios` | FoF child PF IDs | `fof_child_portfolio_ids` |
| `component` for ticker expansion | expanded ticker constituent | `expanded_ticker_component` |
| `weight` in lookback | blend coefficient | `lookback_weight` |
| `weights` in positions | allocation map | `position_weights` |
| `target_weight` in FoF table | target component allocation | `fof_target_weight` |
| `tier` | viewer access segment | `viewer_tier` |
| `type` | portfolio category | `portfolio_type` |
| `type` | block discriminator | `block_type` |
| `mode` | PF risk mode | `pf_risk_mode` |

## Implementation Plan

1. Add a glossary section to `context/dm-signal-core.md` before existing `§0` that declares forbidden ambiguous shorthand and the preferred names above.
2. Keep historical docs unchanged except for front-matter warnings; do not bulk replace old cmd records because their original wording is evidence.
3. For new commands/tasks, gate on ambiguous standalone `L0/L1/L2/L3/L4` unless paired with an approved prefix: `pf_stage`, `sync_stage`, `calc_lineage`, or `visibility`.
4. Code rename order should be docs/comments first, FE labels second, BE schemas/DB fields last. DB column renames are not needed for the first pass; add aliases and descriptions instead.

## Scope Notes

- `backend/app` and `frontend/app` were included after the 2026-05-04 17:20 inbox supplement.
- The scan intentionally excluded generated coverage, `package-lock.json`, outputs, and broad `analysis_runs` artifacts because they are not current implementation or active knowledge surfaces.
