# cmd_2110 report-template gate compat setup profile

Date: 2026-04-19
Target: `tests/unit/test_report_template_gate_compat.bats`
Command: `bats tests/unit/test_report_template_gate_compat.bats`

## Before

- Raw runs (s): `11.50`, `10.94`, `11.44`, `9.27`, `8.58`
- Median: `10.94s`

## After

- Raw runs (s): `6.01`, `7.30`, `6.77`, `7.33`, `7.42`
- Median: `7.30s`

## Result

- Improvement: `-3.64s` (`-33.3%`)
- AC3 status: `PASS` (`30%` 以上削減を達成)

## Profiling Findings

- 支配項は `python3 -c` + `yaml.safe_load/yaml.dump` を使う fixture 変形の反復だった。
- `bats -T` では、YAML 変形を含むケースが概ね `100-240ms`、単純 gate 実行のみのケースが概ね `80-120ms` だった。
- `GP-071` の template-state 判定は Python/YAML を使う必要がなく、シェル実装へ置換後は `15-27ms` に収まった。

## Changes

- `setup_file()` で `BASE_EMPTY_REPORT` / `BASE_FILLED_REPORT` を一度だけ生成し、各 test は `cp` ベースの `_prepare_report()` を使う形へ変更。
- `GATE_SCRIPT` の都度生成をやめ、`gate_report_format_combined.py` / 既存 gate shell を直接参照する helper に集約。
- YAML fixture 変形は `python3 -c` ではなく `_replace_section()` で top-level section 単位に差し替える形へ変更。
- template-state 検出は Python/YAML 依存を外し、`awk` ベースへ変更。

## Verification

- `bats tests/unit/test_report_template_gate_compat.bats` → PASS (`51` tests)
- `bats -T tests/unit/test_report_template_gate_compat.bats` → PASS
