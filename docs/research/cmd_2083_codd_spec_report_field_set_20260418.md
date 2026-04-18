# cmd_2083 CoDD Spec: `scripts/report_field_set.sh`

- cmd: `cmd_2083`
- worker: `hayate`
- target: `scripts/report_field_set.sh`
- date: `2026-04-18`

## Baseline

- fixture:
  - `queue/reports/hayate_report_cmd_2080.yaml` を `/tmp` に複製して計測
- commands:
  - `bash scripts/report_field_set.sh <report> status acknowledged`
  - `bash scripts/report_field_set.sh <report> result.summary test`
- before:
  - `status`: median `0.010s`
  - `result.summary`: median `0.010s`

## Hypothesis

- hot path は既に `_report_field_set_fast_scalar()` へ入っている
- `status` だけ体感的に重く見えたため、root-field awk 分岐の per-line regex 組立が候補

## Attempt

- root-field fast path のみ簡略化を試行
  - `regex_escape()` を外し、prefix match 中心へ変更
  - nested path / python fallback / validation は不変

## Comparison

- same fixture, same machine, same command, `HEAD` vs試行版
- result:
  - `HEAD status`: median `0.010s`, avg `0.014s`
  - `trial status`: median `0.010s`, avg `0.008s`
  - `HEAD result.summary`: median `0.010s`, avg `0.008s`
  - `trial result.summary`: median `0.010s`, avg `0.010s`

## Decision

- median は両経路とも不変
- `status` 平均のみ微改善、`result.summary` 平均は微悪化
- durable gain と言える差ではないため **PASS_NO_IMPROVEMENT**
- 変更は revert し、正本は維持

## Validation

- `bash -n scripts/report_field_set.sh`
- `bats tests/unit/test_report_field_set_validation.bats`
- `bats tests/unit/test_report_field_set_multiline.bats`
- `bats tests/unit/test_report_field_set_bc_validation.bats`
- `bats tests/test_gate_report_format.bats`
- `bats tests/unit/test_report_template_gate_compat.bats`
