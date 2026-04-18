# cmd_2062 pre-write-read-tracker.sh CoDD spec

## Target

- `.claude/hooks/pre-write-read-tracker.sh`

## Before

- profiling SSOT: `docs/research/codd_infra_script_profiling.md` row 34 = `20ms`
- replay payload:
  - `{"tool_name":"Read","tool_input":{"file_path":"/tmp/read_tracker_bench.txt"}}`
- observed:
  - `18.16ms`
  - `17.55ms`
  - `19.54ms`
  - `15.42ms`
  - `14.27ms`
  - median `17.55ms`
- existing unit coverage:
  - `tests/unit/test_read_tracker_hook.bats`

## Bottleneck hypothesis

- no-op/read path still pays:
  - stdin slurp
  - string scan for 3 tool kinds
  - `jq` process
  - `tmux display-message` on every invocation
  - append via shell redirection

## Planned change

1. reduce pre-parse string scanning
2. special-case `Read` path after parse to minimize checks before log append
3. preserve task/report deny semantics and unknown-agent fallback

## Validation

- `bash -n .claude/hooks/pre-write-read-tracker.sh`
- `bats tests/unit/test_read_tracker_hook.bats`
- replay payload benchmark (same as Before)

## After

- replay measurement:
  - `7.64ms`, `6.76ms`, `7.01ms`, `7.55ms`, `6.66ms`, `6.05ms`, `6.71ms`
  - median `6.76ms`
- implemented:
  - stdin slurpを `$(</dev/stdin)` に変更
  - whitespace/tool fast-path を `case` 化
  - `MOCK_AGENT_ID` / `AGENT_ID` 優先で agent 解決し、hot path の tmux 呼出しを回避
