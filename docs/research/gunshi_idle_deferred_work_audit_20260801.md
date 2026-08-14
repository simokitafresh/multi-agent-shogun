# Deferred Work Audit
<!-- generated: 2026-08-01T03:25:00+09:00 by gunshi idle analysis -->

## Result

One genuinely abandoned operational state was found. Four current tasks were active in their panes, inbox and bulletin unread counts were zero, and Karo reduced pending decisions from 24 to 12 during this audit.

## Measurements

| Surface | Result | Classification |
|---|---:|---|
| Gunshi inbox unread | 0 | clear |
| Bulletin unconfirmed | 0 | clear |
| Active tasks | 4/4 panes working | not abandoned |
| Pending decisions | 24 -> 12 during audit | active remediation |
| Historical unsynced reviews inspected | 5 | superseded/revision paths without a terminal GATE; do not fabricate sync |
| Tobisaru stale dependency BLOCK | 24 events, 02:11:06-03:14:01 | abandoned state |

## Root cause

`queue/tasks/tobisaru.yaml` is `status=failed` with `wait_reason=dependency`, but `wait_connected_cmd` and `continuation_task_id` are absent. `scripts/ninja_monitor.sh` therefore enters `_handle_dependency_continuation`, logs `durable_fields=invalid`, and returns without either retiring the malformed state or deduplicating the alert. The same result was emitted 24 times in 63 minutes.

## Action

Karo and Shogun were asked to repair or terminally retire the stale task state immediately. A structural follow-up is required: the continuation consumer must emit one durable action item per malformed registration rather than append the same BLOCK every monitor cycle, while preserving fail-closed behavior.

Origin: `[[cmd_karo_hotfix_archive_review_canonical_allowlist_20260801]] -> [[dependency_registration_missing]] -> [[repeated_BLOCK_without_state_transition]]`
