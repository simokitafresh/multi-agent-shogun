# cmd_2062 post-write-edit-combined.sh CoDD spec

## Target

- `.claude/hooks/post-write-edit-combined.sh`

## Before

- profiling SSOT: `docs/research/codd_infra_script_profiling.md` row 32 = `34ms`
- replay payload:
  - `{"tool_name":"Write","tool_input":{"file_path":"/tmp/nonexistent_codex_hook_bench.txt"}}`
- observed:
  - `11.35ms`
  - `9.85ms`
  - `10.95ms`
  - `9.93ms`
  - `10.62ms`
  - median `10.62ms`

## Bottleneck hypothesis

- hot path for non-report/non-shell/non-instruction files should exit early, but still pays:
  - full stdin slurp
  - string scan for `"Write"` / `"Edit"`
  - `jq` extraction for file path
- Python branches are already lazy, so remaining fixed bash/jq overhead is the target

## Planned change

1. tighten fast-path before expensive branch checks
2. avoid extra shell work on paths that match none of report/shell/instruction guards
3. preserve all emitted context messages and `|| true` crash-tolerance behavior

## Validation

- `bash -n .claude/hooks/post-write-edit-combined.sh`
- replay payload benchmark (same as Before)
- `bats tests/unit/test_write_edit_combined_hooks.bats`

## After

- replay measurement:
  - `7.39ms`, `7.05ms`, `6.82ms`, `6.06ms`, `5.83ms`, `7.43ms`, `5.99ms`
  - median `6.82ms`
- implemented:
  - stdin slurpを `$(</dev/stdin)` に変更
  - whitespace/tool fast-path を `case` 化
  - jq後に file_path ベースの dispatch `case` を追加し、非対象パスを report/shell/instruction 判定前に即 return
