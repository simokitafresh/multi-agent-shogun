# shutsujin_departure.sh CoDD Spec + After Report (2026-04-16)

- cmd: cmd_1953
- 実施者: hayate
- CoDD Phase到達: Phase 5(before/after計測+実装+検証)。specは事後作成(2026-04-16)

## Summary

- Target: `scripts/shutsujin_departure.sh`
- Goal: startup fast path for already-healthy `shogun:agents`
- Result: `1.84-3.25s -> 0.15-0.20s` in `--dry-run` measurement on the current tmux session

## Before

- Reproduction command:
  - `/usr/bin/time -f "%e" bash scripts/shutsujin_departure.sh --dry-run`
- Observed samples:
  - `3.25s`
  - `2.20s`
  - `1.84s`
- Bottleneck:
  - `shutsujin_departure.sh` always invoked `bash scripts/reset_layout.sh --dry-run`
  - `reset_layout.sh --dry-run` alone cost about `1.59-1.67s`
  - Current session was already normalized, so the full layout diagnosis was redundant on the hot path

## Implementation

- Added `layout_is_normalized()` to `scripts/shutsujin_departure.sh`
- The check uses one batched `tmux list-panes` query plus `pane-base-index` to verify:
  - pane count/order matches `get_all_agents`
  - no dead panes
  - `@agent_id`, `@model_name`, `@agent_group`, `@agent_cli` are populated
- Only when the layout check fails does the script fall back to `bash scripts/reset_layout.sh`

## After

- Reproduction command:
  - `/usr/bin/time -f "%e" bash scripts/shutsujin_departure.sh --dry-run`
- Observed samples:
  - `0.16s`
  - `0.17s`
  - `0.15s`
  - `0.18s`
  - `0.20s`
- Dry-run output now shows:
  - `[shutsujin] layout: reset_layout.sh skipped (already normalized)`

## Validation

- `bash -n scripts/shutsujin_departure.sh`
- `bats tests/unit/test_switch_cli.bats`
- `bats tests/unit/test_cli_adapter.bats`
- `bash scripts/shutsujin_departure.sh --dry-run`
