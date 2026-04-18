# cmd_2084 CoDD Spec: `scripts/report_merge.sh`

## Goal

`report_merge.sh` の ready path を正規 CoDD で再計測し、実利のある軽量改善だけを retained する。

## Before

隔離 fixture (`/mnt/c/tools/multi-agent-shogun/tmp_report_merge_finalbench.*`) で、6件の recon task がすべて `done` の ready path を `HEAD` 版で実行。

- Median (5 runs): `0.11s`
- Raw runs: `0.11, 0.13, 0.12, 0.08, 0.06`

## Bottleneck

既存ロジック自体は `cmd_1956`/`cmd_2044` で十分に削られており、残差は YAML 走査器の起動コストだった。

- `gawk` parser only microbench: `~0.02s`
- `mawk` parser only microbench: `~0.01s`
- 差分は WSL2 `/mnt/c` の短命プロセス実行で効く

## Decision

ロジック変更は retained しない。計数や出力順はそのまま維持し、YAML 走査器だけを `mawk` 優先 `awk` fallback に切り替える。

理由:

- 一時的に試した 1-pass 集計版は実利が安定せず、回帰リスクが相対的に高い
- `mawk` 優先は変更面積が小さく、fallback で移植性も落とさない

## After

同一 fixture・同一条件で作業中版を実行。

- Median (5 runs): `0.08s`
- Raw runs: `0.10, 0.08, 0.08, 0.10, 0.08`
- Improvement: `-27.3%` (`0.11s -> 0.08s`)

## Verification

- `bash -n scripts/report_merge.sh`
- `bats tests/unit/test_report_merge.bats`
- `bats tests/unit/test_cmd_complete_gate_subsystems.bats`
- `bats tests/unit`

## Retained Change

- `scripts/report_merge.sh`
  - `AWK_BIN="mawk"` if available, else `awk`
  - 既存の gawk 依存構文は使っていないため互換性維持
