# cmd_2062 pre-write-edit-combined.sh CoDD spec

## Target

- `.claude/hooks/pre-write-edit-combined.sh`

## Before

- profiling SSOT: `docs/research/codd_infra_script_profiling.md` row 33 = `32ms`
- replay payload:
  - `{"tool_name":"Write","tool_input":{"file_path":"/tmp/nonexistent_codex_hook_bench.txt"}}`
- observed:
  - `10.08ms`
  - `9.63ms`
  - `11.96ms`
  - `13.57ms`
  - `10.41ms`
  - median `10.41ms`

## Bottleneck hypothesis

- script still pays:
  - full stdin slurp
  - string scan for `"Write"` / `"Edit"`
  - one `jq` process for TSV extraction
  - multiple bash guards after parse
- lesson `L494` applies: grep/rg単独改善より、block parsing 自体の shell cost が支配する可能性

## Planned change

1. collapse payload string scans into parsed `tool_name` trust path
2. reduce repeated case/regex checks after `jq` extraction
3. keep deny messages and protected path logic byte-for-byte where possible

## Validation

- `bash -n .claude/hooks/pre-write-edit-combined.sh`
- replay payload benchmark (same as Before)
- `bats tests/unit/test_write_edit_combined_hooks.bats`

## After

- replay measurement:
  - `6.28ms`, `6.75ms`, `6.75ms`, `6.40ms`, `7.32ms`, `8.79ms`, `7.90ms`
  - median `6.75ms`
- implemented:
  - stdin slurpを `$(</dev/stdin)` に変更
  - whitespace/tool fast-path を parameter expansion から `case` に変更
  - basename変数を廃し、hot path の変数展開を削減
