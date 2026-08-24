# cmd_4390 ASYNC_VERIFY failure classification

- cmd: `cmd_4390`
- measured_at: `2026-08-24T21:47:21+09:00`
- source: `logs/inbox_codex_delivery_verify/`, `archive/inbox/*_20260824.yaml`, `queue/inbox/*.yaml`, `queue/tasks/*.yaml`, `scripts/inbox_write.sh`, `scripts/inbox_watcher.sh`

## AC1 — classification

The live corpus contains 49 verification logs for 2026-08-24; 27 end in
`ASYNC_VERIFY FAILURE` (`27/49 = 55.1%`). All 27 failure message IDs were
found in the durable inbox/archive records and have `read: true`. Therefore
the observed failures are verifier false negatives, not message loss:

| category | count | evidence | delay evidence |
|---|---:|---|---:|
| false negative: delivered/read later | 27 | 27/27 failure IDs found and read=true | 4 representative task records: 44, 45, 57, 72 s from message timestamp to acknowledged_at |
| confirmed actual non-delivery | 0 | no failure ID lacked a durable read record | no permanent loss observed |

Representative primary-record joins (message timestamp → task
`acknowledged_at`; the verifier failure itself ended before the latter):

| target | message ID | message ts | failure ts | acknowledged/read ts | delay |
|---|---|---|---|---|---:|
| hayate | `msg_20260824_143924_874724_6ab6663a` | 14:39:24 | 14:39:30 | 14:40:36 | 72 s |
| hanzo | `msg_20260824_195315_1003300_15477d38` | 19:53:15 | 19:53:24 | 19:54:00 | 45 s |
| saizo | `msg_20260824_213808_347437_0ac5597b` | 21:38:08 | 21:38:13 | 21:39:05 | 57 s |
| kotaro | `msg_20260824_214026_381727_289c4fb4` | 21:40:26 | 21:40:31 | 21:41:10 | 44 s |

## Root cause

`scripts/inbox_write.sh` requires the post-send pane evidence to contain the
exact `delivery_msg=<message id>` (`codex_pane_has_delivery_evidence`). When an
active watcher owns delivery, `inbox_write.sh` delegates retries to the
watcher. Before this change, `scripts/inbox_watcher.sh` pasted only `inboxN`
and the task-read instruction; it did not carry the durable message ID.
Consequently the message could be persisted, nudged, and later read while the
async verifier could never satisfy its identity predicate.

## AC2/AC3 decision

The correction is verification-side evidence completion, not a retry-policy
relaxation: when exactly one unread `task_assigned` message exists, the watcher
adds its ID as `delivery_msg=<id>`. Multiple pending task assignments fail
closed and omit the identity. This preserves stale-pane protection and avoids
attributing one prompt to the wrong message. The singleflight watcher path
continues to own the nudge, so direct retry duplication is not reintroduced.

Controlled same-condition result:

| condition | success | failure | rate |
|---|---:|---:|---:|
| before: pane transition without exact message identity | 0/1 | 1/1 | 0% success |
| after: watcher-generated nudge carries the unique identity | 1/1 | 0/1 | 100% success |

The after row is covered by the watcher identity fixture; the unchanged
verifier identity contract remains covered by the existing three-case suite
(stale evidence failure, wrong identity failure, exact identity success).

## AC3 duplicate baseline

The failure logs show retries delegated to the active watcher (`2/2`), while
each failure message ID occurs once in the durable corpus. The fix does not
append or resend inbox records; it only adds identity to the one watcher
nudge. Across the retained 2026-08-24 archive/current inbox corpus, the 27
failure IDs are `27` unique IDs with `0` repeated IDs. Existing same-payload
history has `97` extra records in `36` groups, but those are read historical
task/recovery messages and cannot be attributed to verifier retry. Duplicate
inbox creation is `0` in the controlled verification fixture and is not used
as a delivery-success signal.

