# cmd_4292 finalize mechanism reconstruction

## Measurement contract

- measured_at: 2026-08-11T07:20:08+09:00 (Asia/Tokyo)
- fixed_base: `1a948adf73a9fcc6f8e13005ea00bf09d824cf76`
- isolation: detached git worktree `.tmp/cmd_4292_fixture`; every Bats case created a fresh temporary fixture under `/tmp`; no production queue, DB, or external notification endpoint was used
- one_run_definition: one representative input executed once in an isolated fixture, with the command wall clock measured by GNU `time`; the review transaction additionally reports its internal `wall_ms`
- scope: review notification, completion gate, complete processing, and ntfy notification
- change policy: measurement only; no implementation or production-context change

## AC1 — representative execution and raw values

| mechanism | representative input | command | measured value | primary result |
|---|---|---|---:|---|
| review notification | one APPROVE review transaction with precheck, bundle, ledger, approval, and inbox notify stubs | `/usr/bin/time -f 'wall_sec=%e' python3 <fixture>/scripts/review_bundle.py --root <fixture> single --cmd cmd_one --verdict APPROVE --report queue/reports/worker_report_cmd_one.yaml --review-entry <fixture>/review-entry.yaml` | outer `0.42s`; internal `wall_ms=238` | PASS; calls `precheck → ledger → approval → notify → inbox` exactly once |
| completion gate | direct/non-numbered command with no task files, using isolated `GATE_METRICS_LOG` | `/usr/bin/time -f 'wall_sec=%e' env GATE_METRICS_LOG=<fixture>/isolated/gate_metrics.log bash <fixture>/scripts/cmd_complete_gate.sh cmd_nonexistent_benchmark` | `0.76s` | PASS; `CLEAR`, `no_task_benchmark_fast_path` |
| complete processing | SG7 consume through lesson review, gate, quality log, status, archive boundary, dashboard, ntfy, and inbox archive | `/usr/bin/time -f 'wall_sec=%e' env CMD_COMPLETE_SYNC_TAIL=1 CMD_COMPLETE_TEST_LOG=<fixture>/trace2.steps CMD_COMPLETE_ROOT_DIR=<fixture> CMD_COMPLETE_SCRIPT_DIR=<fixture>/scripts CMD_COMPLETE_CHECKPOINT_DIR=<fixture>/queue/gates/cmd_fixture_trace2 bash <fixture>/scripts/cmd_complete.sh cmd_fixture_trace2` | `1.17s` | PASS; checkpoint contains all 9 ordered steps |
| ntfy notification | synchronous ntfy dispatch with a fixture curl stub returning HTTP 200 | `bats -T -f 'sync mode executes exactly once' tests/unit/test_ntfy_async_dispatch.bats` | `192ms` fixture transaction | PASS; exactly one curl execution, no recursive worker |

Raw evidence excerpts:

```text
review_bundle: {"fail": 0, "p95_report_ms": 3, "skip": 0, "total": 1, "wall_ms": 238}
review calls: precheck / ledger / approval / notify / inbox

cmd_complete_gate:
GATE CLEAR: cmd完了許可
2026-08-11T07:18:20  cmd_nonexistent_benchmark  CLEAR  no_task_benchmark_fast_path

cmd_complete:
[cmd_complete] PASS sg7_consume wall_ms=27
[cmd_complete] PASS lesson_review wall_ms=8
[cmd_complete] PASS cmd_complete_gate wall_ms=7
[cmd_complete] PASS quality_log wall_ms=6
[cmd_complete] PASS archive_terminal wall_ms=3
[cmd_complete] PASS dashboard attempt=1/3 wall_ms=8
[cmd_complete] PASS ntfy attempt=1/3 wall_ms=87
[cmd_complete] PASS inbox_archive wall_ms=7
[cmd_complete] COMPLETE cmd_fixture_trace2
completion checkpoint: sg7_consume, lesson_review, cmd_complete_gate, quality_log,
status_completed, archive_terminal, dashboard, ntfy, inbox_archive

ntfy:
1..1
ok 1 sync mode executes exactly once without recursive dispatch in 192ms
```

Artifact existence was checked with `ls -l` and content with `head` after this file was written.

## AC2 — maximum wait decomposition

The maximum outer transaction was `cmd_complete.sh` at `1.17s`. Its direct phase trace identifies `ntfy=87ms` as the largest measured internal phase; the next largest phases were `sg7_consume=27ms`, `dashboard=8ms`, `lesson_review=8ms`, and `inbox_archive=7ms`. The dashboard single-flight wait was `4ms`. This confirms the dominant wait in this representative fixture is the notification phase inside complete processing, not the completion gate (`7ms` internally).

| candidate | before | after/candidate observation | quality impact |
|---|---:|---:|---|
| complete tail notification | synchronous trace: `ntfy=87ms`, complete outer `1.17s` | existing async-tail contract test with a 5-second dashboard stub returned the public caller in `818ms` and passed the `<5000ms` bound | none observed; ordered checkpoint contract remains asserted and this task made no code change |

The decomposition is reversible and observational only. No optimization was adopted in this task; the candidate is to keep notification/dashboard in the already-existing detached tail and preserve the nine-step checkpoint order.

## Verification boundary

- fixed-base identity: `git -C .tmp/cmd_4292_fixture rev-parse HEAD` matched the declared SHA
- AC1 evidence count: 4/4 mechanisms executed; PASS results: 4/4; SKIP: 0
- AC2 evidence: 1 maximum item decomposed into 8 measured internal phases plus dashboard wait
- no implementation files changed; the only deliverable is this reconstruction report

origin: `[[cmd_4292]] -> [[TrackD_隔離fixture機構計時]] -> [[finalize最大待ちの通知phase]]`
