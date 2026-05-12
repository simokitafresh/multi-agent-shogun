# cmd_2554 hayate scout: DM-Signal semantic ambiguity map

date: 2026-05-04
worker: hayate
parent_cmd: cmd_2554
scope: wave-1 outputs + wave-2 uncovered areas: trade-rule.md, backend/app/jobs, backend/app/api, frontend labels, knowledge-base, context/dm-signal-research.md

## Input Read

- `docs/research/cmd_2553_dm_signal_term_collision_mece.md`
- `docs/research/cmd_2553_saizo_dm_signal_polysemy_code_crosscheck.md`
- `queue/archive/reports/hanzo_report_cmd_2553_scout_3_20260504.yaml`
- `docs/research/cmd_2554_saizo_semantic_polysemy_wave2.md`
- `queue/cmd_2553_mcp_polysemy_extract.txt`
- `/mnt/c/Python_app/DM-signal/docs/rule/trade-rule.md`
- `/mnt/c/Python_app/DM-signal/backend/app/jobs/`
- `/mnt/c/Python_app/DM-signal/backend/app/api/`
- `/mnt/c/Python_app/DM-signal/frontend/app`, `/frontend/components`, `/frontend/lib`
- `/mnt/c/Python_app/DM-signal/docs/research/knowledge-base/`
- `context/dm-signal-research.md`

Note: `queue/tasks/hanzo.yaml` for cmd_2554 was still `assigned` and no `queue/reports/hanzo_report_cmd_2554.yaml` content existed at hayate investigation time. Therefore this map integrates the available three prior cmd_2553 scouts plus saizo's cmd_2554 wave-2 output and hayate's independent cmd_2554 findings.

## Summary

Wave 1 identified 13 high-risk ambiguous term families. Saizo wave 2 added 9 API/job/UI contract families. Hayate wave 2 adds 5 semantic families that grep-only scans tend to miss because the same concept is expressed through domain synonyms rather than identical tokens.

`ambiguity_map` should be treated as a namespace proposal, not as a bulk rename plan. Public API keys, DB columns, and historical docs should keep compatibility; new cmd text, new docs, and glossary gates should require prefixed names.

## Ambiguity Map

| Priority | Family | Ambiguous forms | Namespaced meanings | Recommended names |
|---|---|---|---|---|
| P0 | L0/L1/L2/L3/L4 | L*, Level, Layer | PF product hierarchy, SSOT calculation hierarchy, sync/recalculate hierarchy, UI visibility hierarchy, research defense layers, FLAIR Level series | `pf_stage_*`, `calc_lineage_*`, `sync_layer_*`, `visibility_level_*`, `research_defense_layer`, `flair_level_series` |
| P0 | signal | signal, signals, current signal, hide_signal | raw pipeline signal, rebalance holding signal, FE payload state, visibility mask flag, product name | `raw_pipeline_signal`, `rebalance_holding_signal`, `portfolio_signal_state`, `mask_signal_enabled`, `dm_signal_product` |
| P0 | return | monthly_return, return, total return, function return | close monthly return, open monthly return, financial return, function result, API response payload | `monthly_return_close`, `monthly_return_open`, `financial_return`, `function_result`, `api_response_payload` |
| P0 | date/current/latest | date, as_of, current, latest, signal_date | signal fix date, position start/end date, API as-of date, latest data date, selected UI state | `signal_fix_date`, `position_start_date`, `position_end_date`, `api_as_of_date`, `latest_data_date`, `selected_portfolio_state` |
| P1 | FoF/component | FoF, component, child, constituents | DB portfolio type, FoF child PF, ticker expansion component, UI component, masking component | `portfolio_type_fof`, `fof_child_portfolio`, `expanded_ticker_component`, `react_component`, `ui_mask_component` |
| P1 | weight/allocation/position | weight, weights, allocation, position | lookback blend coefficient, final ticker allocation, FoF target/actual allocation, UI displayed position | `lookback_weight`, `pipeline_final_weights`, `fof_target_weight`, `fof_actual_weight`, `display_position_weights` |
| P1 | status/progress/job | status, progress, job, task | HTTP status, API success flag, recalc lifecycle, Stock API job, backfill progress, asyncio task, agent task | `http_status_code`, `api_success_flag`, `recalc_running_state`, `stock_fetch_job_state`, `backfill_progress_state`, `asyncio_task_ref`, `agent_task_yaml` |
| P1 | phase/stage | Phase, stage, layer | recalculate execution phase, research roadmap phase, backfill phase, UI SWR phase, sync stage | `recalc_phase`, `research_phase`, `backfill_phase`, `swr_request_phase`, `sync_stage` |
| P1 | method/model/strategy | method, model, strategy, system | momentum method config, HTTP method, ML/statistical model, PF strategy, CSS/system theme | `momentum_method`, `http_method`, `statistical_model`, `portfolio_strategy`, `ui_theme_system` |
| P1 | source/input/provenance/cache | source, input, CSV, DB, cache, artifact | production PostgreSQL, SQLite mirror, GS CSV, analysis output, precomputed cache, API input | `prod_postgres`, `dm_signal_sqlite_mirror`, `gs_csv_artifact`, `analysis_output_artifact`, `precomputed_cache`, `api_request_input` |
| P2 | universe/basket/assets | universe, basket, relative_assets, offensive/defensive/canary | DM portfolio relative asset set, safe-haven gate asset, VAA/BAA offensive/defensive/canary universe, fixed backtest universe | `dm_relative_asset_set`, `absolute_gate_asset`, `safe_haven_asset`, `baa_offensive_universe`, `baa_defensive_universe`, `baa_canary_universe`, `backtest_fixed_universe` |
| P2 | metrics/objective/score | metrics, objective, score | UI summary metrics, cached portfolio metrics, GS objective metrics, ALM objective score, test/model score | `summary_metrics_payload`, `portfolio_metrics_cache`, `gs_objective_metrics`, `alm_objective_score`, `model_validation_score` |
| P2 | performance/history | performance, history | total-return chart, removed legacy performance table, API perf log, signal chart history, price source history, timing history | `total_return_chart`, `legacy_performance_table`, `api_perf_log`, `signal_chart_history`, `price_source_history`, `timing_run_history` |
| P3 | type/mode/tier/family/block | type, mode, tier, family, block | portfolio type, block type, task type, PF risk mode, execution mode, viewer tier, DM family, pipeline block, gate BLOCK | `portfolio_type`, `pipeline_block_type`, `agent_task_type`, `pf_risk_mode`, `execution_mode`, `viewer_access_tier`, `dm_family`, `pipeline_block`, `gate_block_status` |

## Hayate Wave-2 Additions

### 1. `universe` / `basket` / asset-set

This family is not captured by searching only `relative_assets` or `family`.

| Meaning | Evidence | Collision |
|---|---|---|
| DM-Signal configured candidate assets | `backend/app/jobs/recalculate_fast.py:518`, `backend/app/api/portfolios.py:113-135`, `frontend/app/admin/components/PortfolioEditor.tsx:194-245` | Implementation calls this `relative_assets`, not universe |
| Absolute/safe-haven gate assets | `trade-rule.md:241-243`, `recalculate_fast.py:532-551`, `maintenance.py:26-30` | Gate assets are not the same population as relative selection candidates |
| Knowledge-base research universe | `knowledge-base/methods/vigilant-bold-asset-allocation.md:76-88`, `:116`, `:143-144`, `:240-253`; `knowledge-base/methods/hierarchical-momentum.md:203` | VAA/BAA `offensive/defensive/canary universe` is a strategy design concept |
| Fixed validation universe | `knowledge-base/validation/optimal-trading-without-backtesting.md:132`, `knowledge-base/methods/momentum-transformer.md:204` | Validation universe is a backtest control, not a production config field |

Recommended additions: `dm_relative_asset_set`, `absolute_gate_asset`, `safe_haven_asset`, `baa_offensive_universe`, `baa_defensive_universe`, `baa_canary_universe`, `backtest_fixed_universe`.

### 2. `phase` / `stage` / `layer`

Wave 1 covered `L0-L4`, but the synonym family also appears without `L` tokens.

| Meaning | Evidence | Collision |
|---|---|---|
| Recalculate internal phases | `backend/app/jobs/recalculate_fast.py:1467-1680`, `:1845-1859`, `:2531-2554`; `recalculate_fof.py:839`, `:1119`, `:1161` | Operational execution phase |
| Sync layers | `backend/app/jobs/sync_layers.py:1-7`, `:59-399` | Layer 0-3 means ETL dependency order |
| Trade-rule data levels | `docs/rule/trade-rule.md:188-190`, `:232-237`, `:783`, `:826-830` | Level numbers are reused for data lineage and UI page integration |
| Research knowledge-base layers/phases | `knowledge-base/index.md` method table Layer/Phase columns; `dm-signal/meta-structure.md:74-96`; `dms-tvp-layer-selection-design.md:135-141` | Layer means research defense architecture or rollout phase |
| Frontend SWR/request phase | `frontend/lib/swr-phase-guard.ts`, `frontend/app/monthly-returns/page.tsx` | UI request lifecycle |

Recommended additions: `recalc_phase`, `sync_layer`, `calc_lineage_level`, `research_defense_layer`, `research_rollout_phase`, `swr_request_phase`.

### 3. `method` / `model` / `strategy`

This family crosses FE config, API transport, ML methods, and portfolio strategy wording.

| Meaning | Evidence | Collision |
|---|---|---|
| Portfolio momentum method | `frontend/app/admin/components/PortfolioEditor.tsx:88-114`, `frontend/lib/types/portfolio.ts` | User-facing PF config |
| HTTP request method | `frontend/lib/api-client.ts:415`, `:434`, `:603`, `:1084`, `:1120` | Transport method |
| Pipeline block method | `frontend/app/admin/fof/components/SelectionPipelineSection.tsx:595-634`, `backend/app/jobs/recalculate_fast.py:1231-1245` | Block-local algorithm selector |
| Statistical/ML model | `knowledge-base/methods/hidden-markov-model.md:81-93`, `regime-switching.md:185-190`, `momentum-transformer.md:83-147` | Research model object/architecture |
| Portfolio strategy | `frontend/app/admin/fof/page.tsx:247`, `knowledge-base/methods/re-evaluating-trend-factors.md:9`, `overfitting-causes-solutions.md:58` | Investment strategy or selected GS candidate |

Recommended additions: `momentum_method`, `http_method`, `pipeline_block_method`, `statistical_model`, `portfolio_strategy`.

### 4. `source` / `input` / `cache` / `artifact`

Wave 1 covered DB/CSV/source, but the implicit synonym group extends into provenance, cache, and output artifacts.

| Meaning | Evidence | Collision |
|---|---|---|
| Trade-rule Price/MonthlyReturn SSOT | `trade-rule.md:183`, `:232-237`, `:705-708`, `:936-962` | Production data source |
| Recalculate caches | `recalculate_fast.py:476-498`, `:1648-1680`, `:2179-2246`; `recalculate_fof.py:374-416`, `:1254-1257` | Runtime performance cache |
| Knowledge-base provenance | `knowledge-base/dm-signal/production-invariants.md:62-63`, `:103`, `:153` | Evidence/provenance rule |
| External source citations | many `knowledge-base/**` files use `source:` metadata | Citation source, not runtime input |
| Analysis artifacts | `context/dm-signal-research.md:346`, `knowledge-base/dm-signal/flair-interpretation.md:89` | Output files may be unverified unless provenance is declared |

Recommended additions: `prod_data_source`, `runtime_precomputed_cache`, `evidence_source`, `citation_source`, `analysis_output_artifact`, `provenance_chain`.

### 5. `allocation` / `position` / `exposure`

This family is semantically close to weight but is often written as user-facing text rather than code fields.

| Meaning | Evidence | Collision |
|---|---|---|
| Monthly Trade displayed position | `trade-rule.md:690-708`, `:736-850` | Expanded ticker x weight, not raw signal |
| Model Trades allocation | `trade-rule.md:748-756`, `:850` | Historical trade-period holdings |
| FoF editor allocation text | `frontend/app/admin/fof/components/FoFEditor.tsx:203`, `frontend/app/admin/fof/page.tsx:247` | Composite PF allocation |
| Deep/ML position sizing | `knowledge-base/methods/deep-unified-momentum.md:28-59`, `momentum-transformer.md:83` | Model output exposure/position, not DM production weight table |

Recommended additions: `display_position_weights`, `trade_period_allocation`, `fof_composite_allocation`, `model_position_sizing`.

## MECE Dictionary Additions

| Concept ID | Recommended term | Avoid using alone | Definition |
|---|---|---|---|
| DM_RELATIVE_ASSETS | `dm_relative_asset_set` | universe, basket | Candidate assets in a DM standard portfolio config |
| ABSOLUTE_GATE_ASSET | `absolute_gate_asset` | gate asset, absolute | Asset used by absolute momentum gate |
| BAA_CANARY_UNIVERSE | `baa_canary_universe` | universe, canary | Protective universe for BAA regime switch |
| BACKTEST_UNIVERSE | `backtest_fixed_universe` | universe | Validation/test population fixed before selection |
| RECALC_PHASE | `recalc_phase` | phase | Internal recalculate execution phase |
| RESEARCH_PHASE | `research_rollout_phase` | phase | Research roadmap / implementation plan phase |
| SWR_PHASE | `swr_request_phase` | phase | Frontend request lifecycle guard |
| MOMENTUM_METHOD | `momentum_method` | method | Portfolio config momentum calculation method |
| HTTP_METHOD | `http_method` | method | GET/POST/DELETE transport method |
| PIPELINE_METHOD | `pipeline_block_method` | method | Algorithm selector inside a pipeline block |
| STAT_MODEL | `statistical_model` | model | ML/statistical model object or architecture |
| PF_STRATEGY | `portfolio_strategy` | strategy | Investable portfolio rule set |
| DATA_SOURCE | `prod_data_source` | source, input | Production data source such as Price/MonthlyReturn/PostgreSQL |
| PROVENANCE_CHAIN | `provenance_chain` | source | Evidence chain for analysis or parity data |
| RUNTIME_CACHE | `runtime_precomputed_cache` | cache | In-memory or precomputed cache used during jobs |
| OUTPUT_ARTIFACT | `analysis_output_artifact` | artifact, CSV | Generated analysis file requiring provenance check |
| DISPLAY_POSITION | `display_position_weights` | position, allocation | User-facing expanded ticker allocation |
| TRADE_ALLOCATION | `trade_period_allocation` | allocation | Historical Model Trades holding allocation |

## Implementation Readiness

| Requirement | Result |
|---|---|
| Files to modify | `context/dm-signal-core.md` glossary section; `projects/dm-signal.yaml` naming notes; optional gate docs for cmd/task wording. Do not rename public API/DB fields in first pass. |
| Affected files | `context/dm-signal-ops.md`, `context/dm-signal-research.md`, `docs/rule/trade-rule.md`, `docs/research/knowledge-base/index.md`, task/report templates if a wording gate is added. |
| Related tests | Documentation only: no unit test. Gate candidate: WARN-only `rg` over new cmd/task text for standalone `L[0-4]`, `status`, `phase`, `method`, `source`, `universe`, `position`, `allocation`, `return`, `date` unless an approved namespace prefix is present. |
| Edge cases | Historical docs preserve original wording. Public API keys (`status`, `message`, `data`, `type`, `method`) and DB columns (`monthly_return`, `type`) must not be renamed without compatibility aliases. |
| Dependency constraints | First add glossary/namespace guidance, then WARN-only gate for new queue text, then optional docs annotations, then any code/schema aliases. Bulk replacement is unsafe. |

## Conclusion

The complete ambiguity set is now larger than wave 1: 13 first-wave families + 9 saizo wave-2 API/job/UI families + 5 hayate wave-2 semantic synonym families. The highest-risk next action is not code rename; it is a passive glossary plus WARN-only wording gate for new cmd/task text.
