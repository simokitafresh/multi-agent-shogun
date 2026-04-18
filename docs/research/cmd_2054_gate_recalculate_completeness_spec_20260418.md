# cmd_2054 gate_recalculate_completeness.sh CoDD spec

## Target

- `scripts/gates/gate_recalculate_completeness.sh`
- Registry entry to backfill: `docs/research/codd_refactor_registry.md` line for `scripts/gates/gate_recalculate_completeness.sh`

## Before

- current repro:
  - `python3 - <<'PY' ... subprocess.run(['bash','scripts/gates/gate_recalculate_completeness.sh'])`
- observed:
  - `2317.64ms`
  - `1089.94ms`
  - `1117.07ms`
  - warm median `1117.07ms`
- target_date alignment:
  - production fullrecalculate reference date = `2026-04-15`
  - source: `docs/research/gunshi_phase4_improvement_plan_20260417.md`
- existing registry baseline: `1.76s → ~1.75s`

## Bottleneck

- main cost is remote PostgreSQL connect + SQL execution
- current SQL scans `signals`, `monthly_returns`, `fof_component_weights` globally via `SELECT DISTINCT portfolio_id`
- for this gate, truth source is only active portfolios. global distinct scans can over-read large tables

## Chosen change

1. rewrite completeness query to `EXISTS` probes per active portfolio
2. keep output shape and failure semantics unchanged
3. retain hostaddr cache path and current DB connection settings

## Guardrails

- PASS/FAIL text and exit codes unchanged
- FoF `component_weights` check remains only for `type='fof'`

## Validation

- `bash -n scripts/gates/gate_recalculate_completeness.sh`
- `bats tests/unit/test_gate_recalculate_completeness.bats`
- same benchmark command as Before

## After

- replay measurement:
  - `1080.98ms`, `2224.73ms`, `2223.07ms`, `1113.48ms`, `1149.97ms`, `1133.07ms`, `1051.16ms`, `2234.23ms`, `2219.17ms`, `1048.68ms`
  - stable cluster stayed around `1.1s`, but connection variance remained large
- attempted micro-change:
  - `EXISTS` probes per active portfolio
- result:
  - direct query cost improved, but end-to-end script median did not beat the current shipped version consistently
  - reverted immediately per `After>=Beforeなら即revert`
  - final code state remains unchanged
