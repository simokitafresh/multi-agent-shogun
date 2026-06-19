# SSOT Audit Round 2: DM-Signal

metadata:
- task: cmd_3459_normal
- auditor: hayate
- audited_at: 2026-06-20
- repo: `/mnt/c/Python_app/DM-signal`
- scope: SSOT references, absolute path embedding, duplicated config/default values, hard-coded constants
- note: existing uncommitted changes were present before this audit and were not touched.

| Area | Evidence | SSOT / Current Source | Duplication Or Risk | Fix Target Candidate |
|---|---|---|---|---|
| DB URL | `CLAUDE.md:64-68`, `backend/scripts/*`, `scripts/oneshot/*` use `DATABASE_URL`; `cmd_3430_corr_threshold_analysis.py:13` embeds a production URL | Environment variable is the stated SSOT | One analysis script contains a literal production connection string; many scripts correctly read env | Replace literal DB URL in one-off analysis scripts with env loading or shared helper |
| API base URL | `scripts/register_shin_v2.py:20`, multiple `scripts/oneshot/cmd_*.py` hard-code `https://dm-signal-backend.onrender.com`; `scripts/registration/hide_alm_shijin_global_visibility.py:27` uses `os.getenv("BASE_URL", ...)` | No single shared runtime helper found in bounded scan | Endpoint default repeats across registration/oneshot scripts | Introduce or reuse one URL resolver for admin/registration scripts |
| Absolute repo paths | `scripts/check_pf_config.py:10-26`, `scripts/registration/test_lookback_accuracy.py:11,18`, `scripts/register_shin_v2.py:339,468,624-639` | Repo root should be derived from file location or cwd | `/mnt/c/Python_app/DM-signal` appears in executable scripts and output paths | Move path derivation to `Path(__file__).resolve()` based helpers |
| Frontend/backend constants | `backend/app/constants.py`, `frontend/lib/constants.ts`, `frontend/lib/__tests__/constants.test.ts:21-23` | Backend constant appears intended SSOT; frontend test asserts parity manually | `MAX_PORTFOLIOS` is duplicated across backend/frontend with test-only parity | Generate frontend constant or add an explicit sync source |
| Trade return SSOT | `backend/app/services/return_calculator.py:278-321`, `backend/app/services/trades_impl.py:491,544,569`, `backend/tests/test_trade_period_return.py` | `calculate_trade_period_return` / monthly returns are documented SSOT | Good SSOT pattern; tests encode expected route | Preserve as positive pattern for later cross-project ontology |
| Business day SSOT | `backend/app/utils/business_day_utils.py:19`, `backend/tests/test_business_day_utils.py:18` | Comment points to `rebalance.py` `get_last_rebalance_month_end_business()` | Utility/test comments enforce single function but scan did not confirm all callers | Candidate for caller graph check in implementation phase |
| Visibility settings | `scripts/registration/hide_alm_shijin_global_visibility.py:57-109`, `scripts/oneshot/cmd_3389_register_weighted_yotsume_okugi.py:153-173` | DB tables `global_visibility_settings` / `tier_visibility_settings` | Update logic exists in multiple one-off scripts | Centralize hide/publish operations if these scripts remain active |
| Localhost defaults | `backend/start_local.py:45,61`, `backend/scripts/check_timing_history.py:33`, tests use `sqlite:///:memory:` | Local/dev execution uses explicit local defaults | Mostly acceptable for dev/test; risk if copied to production scripts | Keep bounded to dev/test scripts; gate production scripts against localhost defaults |

Counts from bounded search:
- High-risk literal production DB URL: 1 file observed.
- Repeated production base URL pattern: multiple registration/oneshot scripts observed.
- Absolute `/mnt/c/Python_app/DM-signal` executable path pattern: multiple scripts observed.
- Positive SSOT anchors observed: trade return, annual return from monthly return, business day function comments.

Blind spots:
- Search was bounded to `backend`, `frontend`, and `scripts` plus top-level docs; full repository search was stopped after high output volume.
- Secrets in `.env*` were not opened.
- No production DB/API execution was performed.
