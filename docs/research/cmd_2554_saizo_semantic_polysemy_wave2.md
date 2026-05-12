# cmd_2554 saizo scout: DM-Signal semantic polysemy wave 2

date: 2026-05-04
worker: saizo
scope: first-wave docs + DM-Signal `docs/rule/trade-rule.md`, `backend/app/jobs`, `backend/app/api`, frontend visible/i18n-adjacent strings

## Input Read

- First wave 1: `docs/research/cmd_2553_dm_signal_term_collision_mece.md`
- First wave 2: `docs/research/cmd_2553_saizo_dm_signal_polysemy_code_crosscheck.md`
- Target prompt: `queue/tasks/saizo.yaml` purpose = trade-rule/jobs/api/i18n uncovered semantic search
- Supplement: gunshi approved cmd_2554 draft; uncovered areas confirmed.

## Summary

The first wave already covers the largest term families: `L0-L4`, `signal`, `component`, `weight`, `type`, `tier`, `mode`, `family`, `monthly_return`, `FoF`, `top_n`, `DB/CSV/source`, and `block`.

Wave 2 adds 9 collision groups from job orchestration, API contracts, and user-visible labels:

| # | Term | Additional meanings found | Risk |
|---|---|---|---|
| 1 | `status` | HTTP status, ApiResponse success/error, recalc running state, Stock API fetch job state, backfill progress state | HIGH |
| 2 | `progress` | Layer L2/L3 portfolio progress, backfill percent progress, UI loading progress/status | MEDIUM |
| 3 | `job` / `task` | asyncio background task, Stock API fetch job, ETL/recalculate job, shogun task YAML | HIGH |
| 4 | `history` | price/history data retrieval, `/api/history` signal chart, timing history, full historical recalculation | MEDIUM |
| 5 | `performance` | `/api/performance` cumulative-return chart, old `performance` table, `[PERF]` log category, model-trade performance | HIGH |
| 6 | `metrics` | summary metrics page/API, cached portfolio_metrics, robustness/GS objective metrics | MEDIUM |
| 7 | `return` | function return value, Python `return`, monthly/trade/benchmark/total return, API response return | MEDIUM |
| 8 | `date` | `signal_date`, `position_start_date`, `as_of_date`, `start_date/end_date`, `year_month`, displayed month date | HIGH |
| 9 | `latest` / `current` | DB latest row, current running layer/status, current selected portfolio, current/latest signal | MEDIUM |

## Collision Inventory

### 1. `status`

| Meaning | Evidence | Collision |
|---|---|---|
| HTTP error status code | `/mnt/c/Python_app/DM-signal/backend/app/api/etl_trigger.py:377-379`, `viewer_tiers.py` uses `status_code` for HTTP failures | Same word as business process state |
| Recalculate running status payload | `/mnt/c/Python_app/DM-signal/backend/app/api/etl_trigger.py:88-103` documents `running`, `started_at`, `current_layer`, `mode`; frontend mirrors this as `RecalculateStatusResponse` in `frontend/lib/api-client.ts:145-151` | `status` endpoint returns several state fields, not one status enum |
| Accepted background-start state | `/mnt/c/Python_app/DM-signal/backend/app/api/etl_trigger.py:384-391` and `:804-808` return `data.status = accepted` | Can be mistaken for completed success |
| Stock API fetch job state | `/mnt/c/Python_app/DM-signal/backend/app/jobs/maintenance.py:75-90`, `:168-185` polls `completed`, `failed`, `cancelled`, `completed_with_errors` | External job lifecycle enum |
| Backfill progress state | `/mnt/c/Python_app/DM-signal/backend/app/api/backfill.py:56-70`, `:117` writes progress file `status` values such as `running` / `completed` | File state, not API wrapper success |

Recommended names: `http_status_code`, `api_success_flag`, `recalc_running_state`, `background_request_state`, `stock_fetch_job_state`, `backfill_progress_state`.

### 2. `progress`

| Meaning | Evidence | Collision |
|---|---|---|
| Recalculate L2/L3 portfolio progress | `/mnt/c/Python_app/DM-signal/backend/app/api/etl_trigger.py:516-527`, `:811-833` stores `current/total/name` only for L2/L3 locks | Layer-local operational progress |
| Backfill percentage phase progress | `/mnt/c/Python_app/DM-signal/backend/app/api/backfill.py:53-70`, `:142-148` writes `phase`, numeric percent, message to JSON | File-based percent progress |
| Frontend loading/error state | `/mnt/c/Python_app/DM-signal/frontend/app/summary/page.tsx:80-136`, `:148-185` uses loading/error UI state rather than job progress | UI request state |

Recommended names: `layer_portfolio_progress`, `backfill_percent_progress`, `ui_request_loading_state`.

### 3. `job` / `task`

| Meaning | Evidence | Collision |
|---|---|---|
| asyncio background task reference | `/mnt/c/Python_app/DM-signal/backend/app/api/etl_trigger.py:33-46` stores `_background_tasks` to prevent GC | Python task object |
| Stock API fetch job | `/mnt/c/Python_app/DM-signal/backend/app/jobs/maintenance.py:61-73`, `:75-90`, `:168-185` creates/polls external fetch jobs | External data-fetch job |
| ETL/recalculate job | `/mnt/c/Python_app/DM-signal/backend/app/api/etl_trigger.py:49-85`, `:336-350`, `sync_layers.py:1-10` use job as operational unit | Internal processing job |
| Shogun task YAML | Current assignment is `queue/tasks/saizo.yaml`; first-wave doc already notes `task_type` collision | Multi-agent assignment |

Recommended names: `asyncio_task_ref`, `stock_fetch_job`, `etl_operation`, `agent_task_yaml`.

### 4. `history`

| Meaning | Evidence | Collision |
|---|---|---|
| `/api/history/{portfolio_id}` signal chart history | `/mnt/c/Python_app/DM-signal/backend/app/api/history.py:27-119` returns `history` rows with `raw_signal` | Signal/momentum chart series |
| Long-term data history/backfill | `/mnt/c/Python_app/DM-signal/backend/app/api/backfill.py:20-30`, `:124-153` fetches historical price and DTB3 data | Source data history |
| Full historical recalculation | `etl_trigger.py:354-367` validates prices then recalculates history from a start date | Derived recomputation |
| Timing history | `docs/skills/api-reference.md:201-203`, `:472` lists `/admin/timing-history` | Operational timing records |

Recommended names: `signal_chart_history`, `price_source_history`, `recalc_full_history`, `timing_run_history`.

### 5. `performance`

| Meaning | Evidence | Collision |
|---|---|---|
| Total-return chart API | `/mnt/c/Python_app/DM-signal/backend/app/api/performance.py:41-159` returns `total_return` series from `monthly_returns` | User-facing chart data |
| Deprecated/removed DB table | `docs/rule/trade-rule.md:1193` says the daily `performance` table is abolished | Historical table name |
| PERF log category | `/mnt/c/Python_app/DM-signal/backend/app/api/performance.py:145-149`, docs logging guide uses `[PERF]` for API timings | Operational logging |
| Trade/model performance | `docs/rule/trade-rule.md:757-777` separates Model Trades return/performance semantics | Trade-period result |

Recommended names: `total_return_chart`, `legacy_performance_table`, `api_perf_log`, `trade_period_performance`.

### 6. `metrics`

| Meaning | Evidence | Collision |
|---|---|---|
| Summary/Metrics page data | `/mnt/c/Python_app/DM-signal/frontend/app/summary/page.tsx:72-77`, `:102-180` fetches `api.getMetrics(..., 0)` for full-history summary | FE summary data |
| Portfolio metrics cache | `frontend/lib/api-client.ts:99-104` lists `portfolio_metrics` in precomputed counts | DB/cache table concept |
| GS/robustness objective metrics | First-wave docs mention GS objectives and metric families; `docs/rule/trade-rule.md:956-959` defines return metrics | Research/objective metric space |

Recommended names: `summary_metrics_payload`, `portfolio_metrics_cache`, `gs_objective_metrics`.

### 7. `return`

| Meaning | Evidence | Collision |
|---|---|---|
| Financial return | `docs/rule/trade-rule.md:705-708`, `:819-820`, `:856-863` define monthly/open/close/benchmark returns | Domain quantity |
| Python/API function return | `backend/app/jobs/sync_layers.py:109-119`, `:164-173`, `:380-390` returns SyncResult dicts | Programming control/data return |
| API response wrapper return | `backend/app/schemas/response.py:7-12` defines `ApiResponse{success,data,error,message}` | Transport wrapper |

Recommended names: `financial_return`, `function_result`, `api_response_payload`.

### 8. `date`

| Meaning | Evidence | Collision |
|---|---|---|
| Signal fix date | `docs/rule/trade-rule.md:690-693`, `:796-798` distinguishes `signal_date`, `position_start_date`, `position_end_date` | Trade-rule timing |
| API as-of/current date | `docs/rule/trade-rule.md:720-722`, `performance.py:211-230` uses today/month_start for MTD | Display/calculation boundary |
| Query range start/end | `etl_trigger.py:51-53`, `backfill.py:16-27`, `maintenance.py:94-103` use start/end ranges for jobs | Operational range |
| Monthly label date | `performance.py:115-120` converts `year_month` to first day of month for frontend ISO expectations | Display surrogate date |

Recommended names: `signal_fix_date`, `position_start_date`, `position_end_date`, `api_as_of_date`, `job_range_start_date`, `month_label_date`.

### 9. `latest` / `current`

| Meaning | Evidence | Collision |
|---|---|---|
| Latest DB row/date | `sync_layers.py:99-117` computes `latest_date`; `api-client.ts:61-78` has latest signal/price fields | Data freshness |
| Current running layer/status | `etl_trigger.py:95-100` returns `current_layer` for recalc status | Operation state |
| Current selected portfolio/UI state | `frontend/app/summary/page.tsx:80-90` uses `selectedPortfolio` / selected ID, while offline page says latest signals | UI state |

Recommended names: `latest_data_date`, `current_recalc_layer`, `selected_portfolio_state`, `latest_signal_snapshot`.

## i18n / Visible Text Finding

There is no active message-catalog i18n system under `frontend/app`, `frontend/lib`, or `backend/app`; search found only `frontend/components/language-toggle.tsx` with hard-coded `EN` / `JP`, and many hard-coded English page messages such as `frontend/app/offline/page.tsx:51-53` and `frontend/app/summary/page.tsx:142-180`.

Therefore `language`, `locale`, and `message` are future collision risks, not current code-layer dictionaries:

| Term | Current usage | Risk if i18n is added |
|---|---|---|
| `message` | ApiResponse message, backfill progress message, UI banner message | Must split `api_response_message`, `job_progress_message`, `ui_notice_text`, `i18n_message_key` |
| `language` | Toggle value `en/jp` only | Split `ui_language_code` from natural-language labels |
| `locale` | Not active outside dependencies | Reserve `ui_locale` for formatting; do not use for viewer tier or region |

## MECE Dictionary Additions

| Concept ID | Recommended term | Avoid using alone | Definition |
|---|---|---|---|
| HTTP_STATUS | `http_status_code` | `status` | HTTP error/status code |
| API_SUCCESS | `api_success_flag` | `status`, `success` without namespace | Transport-level request success |
| RECALC_STATE | `recalc_running_state` | `status` | Recalculation lifecycle state |
| STOCK_FETCH_STATE | `stock_fetch_job_state` | `job status` | External Stock API fetch lifecycle |
| BACKFILL_STATE | `backfill_progress_state` | `status` | JSON progress file lifecycle |
| LAYER_PROGRESS | `layer_portfolio_progress` | `progress` | Sync L2/L3 current/total/name |
| BACKFILL_PROGRESS | `backfill_percent_progress` | `progress` | Backfill phase percent |
| ASYNC_TASK | `asyncio_task_ref` | `task` | Python background task object |
| AGENT_TASK | `agent_task_yaml` | `task` | Multi-agent assignment file |
| SIGNAL_HISTORY | `signal_chart_history` | `history` | `/api/history` chart series |
| PRICE_HISTORY | `price_source_history` | `history` | Historical source price range |
| PERF_CHART | `total_return_chart` | `performance` | `/api/performance` chart payload |
| PERF_LOG | `api_perf_log` | `performance` | Timing log category |
| METRICS_PAYLOAD | `summary_metrics_payload` | `metrics` | FE summary/metrics page response |
| RETURN_DOMAIN | `financial_return` | `return` | Investment return value |
| RETURN_PROGRAM | `function_result` | `return` | Function result object |
| MESSAGE_API | `api_response_message` | `message` | ApiResponse message |
| MESSAGE_PROGRESS | `job_progress_message` | `message` | Job/backfill progress message |
| MESSAGE_UI | `ui_notice_text` | `message` | UI banner/user-facing text |

## Implementation Notes

1. Do not bulk-rename existing API fields. `status`, `message`, `data`, `success`, and `error` are public API contract terms.
2. New docs and cmd text should require namespace qualifiers for `status`, `progress`, `job`, `history`, `performance`, `metrics`, `return`, and `date`.
3. If a glossary gate is added, apply WARN only to docs/queue text first. Code and API schemas need compatibility aliases before any enforcement.
4. Existing first-wave P0 rules remain higher priority; this wave is a second layer for orchestration/API ambiguity.

## Scout Five Requirements

| Requirement | Result |
|---|---|
| Change target files/lines | Glossary additions: `context/dm-signal-core.md` and possibly `projects/dm-signal.yaml`; gate candidates in shogun cmd/task wording. No direct code rename recommended. |
| Ripple targets | API docs (`docs/skills/api-reference.md`), `trade-rule.md`, `context/dm-signal-ops.md`, FE page text docs if i18n introduced. |
| Related tests | Documentation-only: no unit test. Gate candidate: `rg -n '\b(status|progress|job|history|performance|metrics|return|date|message)\b' queue/shogun_to_karo.yaml queue/tasks/*.yaml` with namespace whitelist. |
| Edge cases | Public API fields (`ApiResponse.status-like success/message/data/error`) must not be renamed without compatibility layer. Historical docs preserve original wording. |
| Dependency/order | First-wave glossary prefixes first; then add wave-2 namespace guidance; then WARN-only gate; then optional API doc annotations. |
