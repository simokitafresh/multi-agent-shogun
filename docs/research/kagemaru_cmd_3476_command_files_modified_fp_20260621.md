# cmd_3476 command_files_modified_mismatch FP classification

Date: 2026-06-21
Scope: `logs/gate_metrics.log` entries after cmd_3408 fix with `command_files_modified_mismatch`.

## Summary

対象は7ユニークcmd、18 BLOCK記録。taskの例にあるcmd_3457を加えて挙動確認した。

| cmd | block_count | classification | pattern | evidence |
| --- | ---: | --- | --- | --- |
| cmd_3426 | 5 | FP | research cmd with no code change; `cmd_3425` was recorded as `verified_existing_dependency` in `files_modified` | archive cmd/report; commit only docs/research |
| cmd_3428 | 1 | FP | research cmd with no code change; `cmd_3427` was recorded as `verified_existing_dependency` in `files_modified` | archive cmd/report; commit only docs/research |
| cmd_3435 | 4 | FP | readonly design inputs were present but encoded in report `files_modified` as dependency markers instead of top-level `verified_existing_dependency` | report wrote docs/research outputs; command refs were investigation targets |
| cmd_3437 | 3 | FP | design doc was a verified existing dependency encoded inside `files_modified` | report modified `scripts/semantic_index_update.sh`; design doc was reference |
| cmd_3439 | 2 | FP | `docs/semantic-index/index.md` was a verified dependency encoded inside `files_modified`; actual changed files were reported | report modified `scripts/semantic_causal_traverse.sh` and `scripts/cmd_complete_gate.sh` |
| cmd_3442 | 2 | mixed, actionable FP pattern | `scripts/lesson_write.sh` was execution/reference dependency encoded inside `files_modified`; tests not modified because AC3 already satisfied by prior work per report | report states AC2 only remained; dependency marker was not consumed by gate |
| cmd_3451 | 1 | TP / unrelated to this fix | command required `prompt_state_inject.sh`; report modified `log_terminal_response.sh`, tests, and `.codex/hooks.json` only | missing command target should remain BLOCK |
| cmd_3457 | 0 in gate_metrics after archive, but cited example | FP now covered | `CLAUDE.md` was checked and not changed; report used both `files_modified change: verified_existing_dependency` and top-level `verified_existing_dependency` | archive report |

## Root Cause

`cmd_complete_gate.sh` already supports top-level `verified_existing_dependency:` and task `readonly_ref:`, but several real reports expressed the same judgment inside `files_modified` with `change: verified_existing_dependency`. That encoding was not consumed by `collect_report_verified_existing_deps`, so command refs that the ninja had explicitly checked as not modified still became missing files.

There was also no explicit `checked_not_modified:` section for the exact semantic case "the command mentioned this file, I checked it, and no edit was needed."

## Fix Target

Implemented in `scripts/cmd_complete_gate.sh`:

- collect `files_modified` entries whose `change`, `status`, `category`, or `reason` contains `verified_existing_dependency`, `checked_not_modified`, `not_modified`, `変更不要`, `参照のみ`, `既存依存`, `実行のみ`, `read-only`, or `no-change`.
- collect top-level `checked_not_modified:` entries using the same path parsing as `verified_existing_dependency:`.

This preserves true positives because only refs explicitly marked as dependency/not-modified are removed; unreported command targets still block.
