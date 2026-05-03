# cmd_2526 CoDD Batch Optimization

Date: 2026-05-03
Worker: saizo

## Scope

Target selection followed cmd_2526's mechanical definition: high-frequency `registry=no` scripts from `hayate_cmd_2493_scripts_profile.tsv`, excluding cmd_2521-2525 targets. The eighth target is `scripts/decision_write.sh`; `scripts/ntfy_listener.sh` was excluded because it is a long-running daemon and normal execution has side effects.

| Target | Measurement Command | Before Median | After Median | Result |
|--------|---------------------|---------------|--------------|--------|
| `scripts/decision_write.sh` | no args | 9ms | 12ms | PASS_NO_IMPROVEMENT |
| `scripts/pending_decision_write.sh` | no args | 9ms | 8ms | PASS_NO_IMPROVEMENT |
| `scripts/lesson_write_shogun.sh` | no args | 11ms | 8ms | PASS_NO_IMPROVEMENT |
| `scripts/switch_cli_mode.sh` | `--help` | 11ms | 8ms | PASS_NO_IMPROVEMENT |
| `scripts/bulletin_write.sh` | `--help` with isolated `BULLETIN_ROOT_OVERRIDE` | 79ms | 8ms | PASS |
| `scripts/sync_pane_vars.sh` | `--help` | 11ms | 10ms | PASS_NO_IMPROVEMENT |
| `scripts/usage_monitor.sh` | `PROVIDER=codex --status` | 159ms | 106ms | PASS |
| `scripts/lesson_deprecation_scan.sh` | `--help` | 9ms | 8ms | PASS_NO_IMPROVEMENT |

## Changes

- Added explicit help/argument fast paths to prevent expensive setup or unintended writes on help paths.
- Made `usage_monitor.sh PROVIDER=codex --status` use one SQLite query instead of two and lazy-load `mcas_common.sh` only for Claude provider paths.
- Left `switch_cli_mode.sh` unchanged because its help path was already fast enough.

## Verification

- `bash -n scripts/decision_write.sh scripts/pending_decision_write.sh scripts/lesson_write_shogun.sh scripts/switch_cli_mode.sh scripts/bulletin_write.sh scripts/sync_pane_vars.sh scripts/usage_monitor.sh scripts/lesson_deprecation_scan.sh`
- `bats tests/unit/test_pending_decision_write.bats tests/unit/test_lesson_write_shogun.bats tests/unit/test_bulletin_board.bats`

