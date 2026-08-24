# cmd_4386 durable-writer wait measurement

created: 2026-08-24T10:14:52+09:00
source: `scripts/cmd_complete_gate.sh`, `logs/cmd_complete_gate_details.log`

## Before

Production detail telemetry recorded `post_source_checks.durable_writer_wait`
at **209.504 s** for cmd_4384. The function waited for its generation-bound
pending/result markers and then executed a bare shell `wait`, which waited for
all unrelated background jobs in the gate shell as well.

## After

The generation-bound marker/result checks and path-manifest validation remain;
the process-wide `wait` was removed. A same-condition fixture launched a
0.10 s durable worker plus an unrelated 0.80 s background job:

| implementation | elapsed | result |
|---|---:|---|
| baseline (`git show HEAD`) | 836 ms | PASS |
| cmd_4386 | 210 ms | PASS |

The unrelated job remained outside the measured completion interval. This is
an 626 ms reduction (74.9%) for the controlled wait contract; no inspection,
generation binding, timeout, or path-manifest check was removed.

## Push lane

The prior production detail log recorded `source_publication.push_task_repositories`
at **422.135 s** and `runtime_publish.remote_source_push` at **316.124 s**.
Both are now queued by the post-CLEAR follow-up worker; report ancestry records
an unpushed source as `WAIT`, and the existing unpushed detector remains the
failure/retry lane. The follow-up emits separate detail rows, outside the
`gate_evaluation` wall interval.
