# cmd_2054 parity_check.sh CoDD spec

## Target

- `scripts/parity_check.sh`
- Registry entry to backfill: `docs/research/codd_refactor_registry.md` line for `scripts/parity_check.sh`

## Before

- current repro:
  - `python3 - <<'PY' ... subprocess.run(['bash','scripts/parity_check.sh','--help'])`
- observed:
  - `4.05ms`
  - `6.00ms`
  - `4.43ms`
  - median `4.43ms`
- existing registry baseline: `20ms → ~5ms` (`--help` path median)

## Bottleneck

- hot path is already `--help` / no-args fast path
- remaining fixed cost is shell startup + help判定の関数呼出し/引数走査

## Chosen change

1. `print_usage` を `printf` に統一し subshell余地を排除
2. `is_help_request()` を廃止し、builtin `case " $* "` 判定へ統合

## Guardrails

- `--help` / no-args の出力文言は維持
- `PARITY_CHECK_LIB_ONLY=1` の source test path は維持

## Validation

- `bash -n scripts/parity_check.sh`
- `bats tests/unit/test_parity_check.bats`
- same benchmark command as Before

## After

- replay measurement:
  - `8.11ms`, `6.12ms`, `5.94ms`, `10.25ms`, `16.48ms`, `11.51ms`, `10.72ms`
  - median `10.25ms`
- attempted micro-change:
  - help/no-args early return before helper definitions
- result:
  - replayed change regressed on the actual `--help` path
  - reverted immediately per `After>=Beforeなら即revert`
  - final code state remains unchanged
