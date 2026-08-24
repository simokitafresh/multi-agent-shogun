# cmd_4391 report completion → review request gap

## Scope and baseline

- Source distribution: `logs/completion_gap_metrics_cmd_4389.md` records 6/6 complete rows; `report_done_to_review_request_sec` was median **618.000s**, mean **1237.667s**, max **3579.000s**.
- The largest raw example is `cmd_4387`: the correlator selected `report_done=2026-08-24T09:12:00Z` from `queue/reports/tobisaru_report_cmd_4387.yaml` and `review_request=2026-08-24T10:11:39Z` from `queue/inbox/gunshi.yaml`, yielding **3579s**.
- Primary-cause check: the report's `timestamp` is the authoring/deployment timestamp; terminal reports had no completion timestamp (`completed_at`/`done_at` were absent). Therefore the measured gap mixed report authoring/revision time with the actual publication-to-review edge.

## Stage-by-stage trace

| Stage | Evidence | Before/after contract |
|---|---|---|
| Terminal report bytes | `scripts/report_field_set.sh:212-218` computes terminal status and now records UTC `completed_at` before the atomic replace. | New timestamp is added; report status and identity remain unchanged. |
| `report_received` detection and send | `scripts/report_field_set.sh:414-465` invokes `inbox_write.sh` synchronously after the terminal replace. | Same target `karo`, same completion type, same parent/task identity. |
| Review child persistence | `scripts/inbox_write.sh:3022-3030` persists one fingerprint-bound `report_review` child for Gunshi; `:3033-3039` repairs a missing child asynchronously on retry. | Review target, report identity, and exactly-once fingerprint dedupe remain unchanged. |
| Gap attribution | `scripts/completion_gap_metrics.sh:121-133` now uses `completed_at`, then legacy `done_at`, then legacy `timestamp`. | Old reports remain readable; new reports measure terminal publication rather than authoring time. |

The former 618-second stage was therefore a timestamp-boundary defect in the gap recorder, not a missing review route. The route already had synchronous report completion → inbox write → review-child persistence; the recorder used the wrong left-hand edge.

## Correction measurement

- Before: baseline median **618.000s** (6 complete records), with false inflation up to **3579.000s**.
- After: the affected correlator fixture with an old authoring timestamp (`00:00:00+09:00`), terminal `completed_at` (`10:00:05+09:00`), and review request (`10:00:10+09:00`) reports `report_done_to_review_request_sec=5.0s`. This is **613.000s below** the before median and proves the corrected edge selection through the real `completion_gap_metrics.sh` entrypoint.
- Terminal publication performance remained bounded: `tests/unit/test_report_field_set_batch_throughput.bats` measured 20 isolated terminal publishes at **p50=0.282s**, **p95=0.312s**, with no review-child loss or duplicate.

## Verification

- `bash scripts/run_tests.sh file tests/unit/test_inbox_write.bats`: **118/118 PASS, SKIP=0**.
- `bash scripts/run_tests.sh file tests/unit/test_report_field_set_batch_throughput.bats`: **21/21 PASS, SKIP=0**.
- `bash scripts/run_tests.sh file tests/unit/test_cmd_complete_gate.bats`: **281/281 PASS, SKIP=0**; the new `completed_at` preference case reports **5.0s**.
- Duplicate/omission coverage remains green through the existing fingerprint tests in `test_inbox_write.bats` (including 20 parallel lifecycle writers and retry repair), and no review target or dedupe key was changed.

## Files and compatibility

- `scripts/report_field_set.sh`: terminal publication timestamp.
- `scripts/completion_gap_metrics.sh`: timestamp precedence with legacy fallback.
- `scripts/deploy_task.sh`: report template field.
- Tests cover timestamp precedence and terminal publication; existing report schemas remain backward compatible because reports without `completed_at` still use `done_at`/`timestamp`.

