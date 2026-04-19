# cmd_2110 report-template gate compat setup profile

Date: 2026-04-19
Target: `tests/unit/test_report_template_gate_compat.bats`
Command: `bats tests/unit/test_report_template_gate_compat.bats --jobs 8`

## Before

- Raw runs (s): `8.45`, `10.77`, `13.39`, `11.18`, `8.59`
- Median: `10.77s`

## After

- Raw runs (s): `9.01`, `6.08`, `5.00`, `5.62`, `7.77`
- Median: `6.08s`

## Result

- Improvement: `-4.69s` (`-43.5%`)
- AC3 status: `PASS` (`30%` 以上削減を達成)

## Profiling Findings

- 支配項は `python3 -c` + `yaml.safe_load/yaml.dump` を使う fixture 変形の反復だった。
- `bats -T --jobs 8` でも、YAML 変形を含むケースが重く、template-state 判定のような軽量ケースは `20-80ms` に収まる。
- `GP-071` の template-state 判定は Python/YAML を使う必要がなく、シェル実装へ置換後は `20-80ms` 帯で安定した。

## Changes

- `setup_file()` で `BASE_EMPTY_REPORT` / `BASE_FILLED_REPORT` を一度だけ生成し、各 test は `cp` ベースの `_prepare_report()` を使う形へ変更。
- `GATE_SCRIPT` の都度生成をやめ、`gate_report_format_combined.py` / 既存 gate shell を直接参照する helper に集約。
- YAML fixture 変形は `python3 -c` ではなく `_replace_section()` で top-level section 単位に差し替える形へ変更。
- template-state 検出は Python/YAML 依存を外し、`awk` ベースへ変更。
- `setup()` は通常実行では高速な固定 workdir を使い、`--jobs` 実行時だけ `BATS_TEST_TMPDIR` へ退避する分岐を追加した。

## Verification

- `bats tests/unit/test_report_template_gate_compat.bats` → PASS (`51` tests)
- `bats tests/unit/test_report_template_gate_compat.bats --jobs 8 --timing` → PASS
