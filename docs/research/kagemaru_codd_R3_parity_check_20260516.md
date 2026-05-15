# cmd_training_codd_r3_kagemaru: parity_check.sh CoDD Spec

date: 2026-05-16
worker: kagemaru
target: `scripts/parity_check.sh`
pipeline: spec -> elicit/lexicon -> generate -> validate -> measure

## 1. Spec

### Purpose

`scripts/parity_check.sh` is a DM-Signal parity spot-check wrapper. It receives
portfolio names, UUIDs, or `--all`, reads production `DATABASE_URL` from the
DM-Signal backend `.env`, connects to production PostgreSQL and local
`analysis_runs/experiments.db`, then compares monthly return rows and monthly
holding-signal approximations for matched portfolios.

The practical requirement is "quickly detect obvious production-vs-experiments
drift for selected portfolios." It is not, by itself, the full Lord-defined
parity gate for all-period holding position plus all-period monthly return.

### Scope

- Accept portfolio name, UUID, multiple arguments, or `--all`.
- Provide `-h` / `--help` and no-argument fast paths before DB work.
- Resolve configurable paths via `DM_SIGNAL_PATH`, `ENV_PATH`, and `EXPERIMENTS_DB`.
- Load `DATABASE_URL` from `.env` while stripping CRLF.
- Fail early when `.env`, `DATABASE_URL`, or `experiments.db` is missing.
- Connect to production PostgreSQL via `psycopg2`.
- Resolve portfolios by exact UUID/name first, then partial name match.
- Compare `monthly_returns.return_open` and `return_close` for common months with
  tolerance `1e-10`.
- For non-FoF portfolios, compare production `signals.holding_signal` with the
  max-weight ticker extracted from experiments `monthly_returns.signal` JSON.
- Emit per-portfolio PASS/FAIL/SKIP and an overall exit code.
- Support `PARITY_CHECK_LIB_ONLY=1` for unit tests to source helper functions.

### Non-scope

- It does not run fullrecalculate or create before/after snapshots.
- It does not compare `monthly_return_open`, which is the stricter Open-series field
  called out in later DM-Signal parity audits.
- It does not fully validate FoF component holdings; FoF signal check is skipped.
- It does not compare all-period holding-position objects for multi-asset allocations.
- It does not guarantee Lord-defined full parity; existing audit classifies it as a
  supplementary spot-check tool.

## 2. Elicit / Lexicon Findings

`codd elicit --format md --path .` failed before target analysis because the configured
`shogun_core` lexicon manifest was not found. The findings below combine code reading,
unit-test evidence, existing CoDD specs, and the DM-Signal parity audit.

| ID | Hole / Coverage Axis | Evidence | Impact |
| --- | --- | --- | --- |
| GAP-1 | Tool name implies stronger parity than it provides | `dmsignal_parity_verification_audit.md` says `parity_check.sh` is not enough for Lord-defined parity | Callers can over-trust PASS as full production safety |
| GAP-2 | Monthly return field contract is ambiguous | Script compares `return_open` / `return_close`; audit says stricter path needs `monthly_return_open` | Open-series regressions can be missed |
| GAP-3 | FoF signal parity is skipped | Script prints `Signals: N/A (FoF)` for `pf_type == "fof"` | FoF registration can appear partially checked while holding parity is unverified |
| GAP-4 | Signal comparison reduces experiments weights to one max ticker | JSON `signal` dict is collapsed with `max(weights, key=weights.get)` | Multi-asset holdings and weight-level drift are invisible |
| GAP-5 | SKIP handling is operationally risky | Missing experiments rows or common months return SKIP; overall fails only if all checks skip | Partial SKIP can coexist with overall PASS, conflicting with global "SKIP = FAIL" reporting expectations |
| GAP-6 | Unit coverage is mostly fast-path and argument plumbing | Existing bats has 4 tests: help, no args, CRLF, space-containing names | DB query semantics, mismatch formatting, SKIP aggregation, FoF behavior are not unit-fixtured |
| GAP-7 | Partial name match can widen scope silently | Multiple matches are warned and all are checked | A caller intending one PF may trigger broad checks without an explicit confirmation mode |
| GAP-8 | External dependency preflight is not separated from comparison | Path/env/DB connection checks happen inside the same command | Training and gate users cannot easily distinguish environment failure from parity failure |

Recommended lexicon axes:

- `parity_spot_check_not_full_gate`
- `monthly_return_field_contract`
- `holding_signal_exactness_level`
- `fof_signal_parity_gap`
- `skip_is_fail_semantics`
- `parity_external_preflight`
- `portfolio_resolution_scope_control`
- `parity_fixture_coverage`

## 3. Generate / Design Sketch

The design should be represented by a CoDD node set like:

- Requirement: "CLI PASS must state whether it means spot-check parity or full parity."
- Requirement: "The compared monthly-return fields must be named and linked to the DM-Signal model."
- Constraint: "SKIP counts must not be reported in a way that looks like completed verification."
- Constraint: "FoF signal parity must be either fully implemented or explicitly excluded from PASS claims."
- Constraint: "Portfolio resolution must distinguish exact, partial-single, and partial-multiple matches."
- Test fixture: help and no-args fast path never touch missing default paths.
- Test fixture: `.env` CRLF `DATABASE_URL` is normalized.
- Test fixture: name with spaces is passed as one portfolio argument.
- Test fixture: return mismatch over tolerance emits FAIL and nonzero exit.
- Test fixture: missing experiments data produces SKIP and, when any requested check is skipped, a non-complete verification status.
- Test fixture: FoF portfolio reports signal parity as intentionally excluded.

## 4. Validate / Measure Evidence

Commands run from `/mnt/c/tools/multi-agent-shogun`:

| Command | Result |
| --- | --- |
| `bash -n scripts/parity_check.sh` | PASS |
| `bats tests/unit/test_parity_check.bats` | PASS: 4/4 |
| `codd validate --path .` | PASS: 16 Markdown files validated |
| `codd measure --path . --json` | PASS: health_score=95, validation_errors=0, validation_warnings=0, total_nodes=16, total_edges=12, orphan_nodes=4, coverage_ratio=0.0 |
| `codd coverage report --path . --format md` | FAIL: Unknown lexicon `shogun_core` |
| `codd elicit --format md --path .` | FAIL: lexicon manifest not found: `shogun_core` |
| `codd dag verify --path . --format json` | PASS: all checks passed; `depends_on_consistency` skipped because propagation output was not found; `runtime:db_seed:users` unreachable but amber/pass |

Actual production parity was not run in this training task because it would connect to
DM-Signal production DB. The task asks for CoDD analysis, not live PF validation.

## 5. Design Score

Score: 6 / 10.

Rationale:

- Good operational ergonomics: fast help path, configurable paths, CRLF-safe `.env` parsing,
  and unit-test source mode exist.
- Good spot-check value: selected PFs can quickly compare production and experiments rows.
- Existing CoDD/performance history is present, including the fast-path fix.
- Weak semantic naming: "parity" can be mistaken for full Lord-defined parity.
- Weak FoF and holding exactness: FoF signals are skipped and experiments signal JSON is collapsed
  to one max-weight ticker.
- Weak source/lexicon coverage: CoDD measure reports 0 tracked source files and lexicon commands fail.
- Test coverage is shallow for a DB comparison tool: mismatch, skip aggregation, partial-match scope,
  and FoF behavior are not fixture-tested.

## 6. Improvement Candidates

1. Rename output language or add an explicit banner: "SPOT CHECK, not full Lord-defined parity"
   unless the command is upgraded to full-period `monthly_return_open` + holding-position comparison.
2. Add a strict mode, for example `--strict-full`, that compares `monthly_return_open` and exact
   monthly holding position using the golden-data comparator path recommended in the audit.
3. Treat any SKIP as incomplete verification in report-oriented mode, or emit a machine-readable
   status that distinguishes PASS_WITH_SKIPS from PASS.
4. Add unit fixtures with stubbed psycopg2/sqlite data for return mismatch, signal mismatch,
   no common months, experiments missing, FoF signal exclusion, and multiple partial matches.
5. Split preflight from comparison (`--preflight`) so environment failures are not conflated with
   parity failures.
6. Fix CoDD `shogun_core` lexicon configuration so `coverage report` and `elicit` can run during
   training without environmental failure.

## 7. Binary Checks

| AC | Check | Result |
| --- | --- | --- |
| AC1 | `parity_check.sh` was read and a spec-like purpose, constraints, and scope were recorded in this file | yes |
| AC2 | Elicit/lexicon-style requirement holes and coverage axes were listed despite the current lexicon command failure | yes |
| AC3 | `validate`, `measure`, unit tests, and related CoDD checks were run; design quality was scored and at least three improvements were identified | yes |
