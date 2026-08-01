# R04/R05 task-owner barrier matrix

Task: `cmd_karo_hotfix_hidden_infra_wave1b_r04_r05_barrier_20260801_normal`  
Inputs inspected at 2026-08-01T12:20+09:00: canonical manifest, foundation map, `scripts/deploy_task.sh`, `scripts/auto_deploy_next.sh`, and the accepted R03 eight-row matrix.

## Gate A — canonical consistency (stop before implementation)

| assertion | matches | mismatches | primary evidence | decision |
|---|---:|---:|---|---|
| R04 runtime classification is unique | 0 | 1 | manifest runtime probe says `SUPERSEDED_WITH_EVIDENCE`, while `findings[]` says `ACTIVE` | **BLOCK R04 implementation** until canonical reclassification is resolved |
| R04 has one foundation owner | 0 | 1 | foundation `excluded_superseded` contains R04 and `units[]` contains no R04 | no owner may implement an ACTIVE R04 from the stale row |
| R05 is open and active | 2 | 0 | manifest runtime probe=`OPEN_CONFIRMED`; finding status=`ACTIVE` | eligible after R03 |
| R04/R05/R03 share serialization domain | 3 | 0 | all three manifest finding rows use `serialization_key: task_owner` | one authority/lock/fence design |
| R05 depends on R03 | 1 | 0 | foundation unit R05 `depends_on: [R03]` | reuse R03 transaction; do not fork it |

Counts: 5 assertions, 6 matching observations, 2 mismatching observations. The wave-0 receipt's R04 positive and negative controls both pass, so its supersession is evidence, not a copy-only label. The later ACTIVE row is therefore stale until the canonical owner explicitly changes the classification and regenerates the foundation map.

## One authority decision

`task_owner/<subject_id>` in durable state is the sole authority for both units. R03's per-subject lock, monotonically increasing fence, payload hash, guarded YAML mutation, and terminal receipt are reused unchanged. R04 may only add a delivery outcome to that same receipt if Gate A reopens it; R05 may only reserve a candidate under that lock before selection becomes externally visible. TTL is recovery advice, never write authority. A stale caller may read, log, and return rc=4; it may not mutate task/report YAML, selector state, receipts, RR pointer, inbox, or delivery state.

## Complete shared barrier table

Every row is a side effect or durable state transition in the R04/R05 boundary. The stop point is immediately before the effect.

| row | unit | side effect | stop point immediately before | concurrent writers | authority / lock / fence / receipt | stale caller | rollback or reconcile | dependency |
|---:|---|---|---|---|---|---|---|---|
| 1 | R05 | read candidate task status and build eligible set | before snapshot read | deploy_task, karo direct deploy, monitor/task owner transition | task_owner lock; record observed task generation | deny selection if generation changes | discard snapshot and rescan | R03 terminal owner |
| 2 | R05 | choose a candidate only when its current task status is `pending` or `idle` | before candidate choice | parallel auto_deploy_next processes | same subject lock and fence | rejected rc=4 | retry selection under new fence | row 1 |
| 3 | R05 | reserve selected worker/subject | before durable `selector/prepared` mutation | deploy_task and another selector | R03 `begin`/`mutate`; receipt contains candidate, status, generation | mutation denied | reconciler expires only uncommitted reservation, then rescan | row 2 |
| 4 | R05 | advance RR pointer | before RR pointer publish | other selector completion | guarded effect keyed by selector receipt | no write | replay idempotently after terminal selection | row 3 |
| 5 | R03 shared | publish target as `owner_prepared` plus owner metadata | before target file publish | deploy_task task writer, another owner transfer | guarded publisher under task_owner fence; payload hash | bytes unchanged | R03 startup reconciler | row 3 |
| 6 | R03 shared | tombstone source and activate target | before each guarded YAML set | deploy_task/status writers, monitor | R03 guarded-yaml-set and owner pointer | rc=4; only convergent earlier fields remain | R03 eight-row reconciliation | row 5 |
| 7 | R04 | begin deploy delivery attempt | immediately before `deploy_task.sh` invocation | manual/karo deploy and retry | same task_owner fence; attempt id in receipt | invocation denied | retry with new attempt on current owner only | R03 terminal owner, row 6 |
| 8 | R04 | mutate task/report during deploy transaction | before `deploy_task_yaml_transaction_begin` and every YAML publish | deploy_task retry, task progress writer | task_owner fence must be revalidated before transaction; receipt phase=`delivery/prepared` | no YAML write | existing transaction rollback restores task/report | row 7 |
| 9 | R04 | persist inbox assignment notification | immediately before inbox_write persistence | other inbox writers | task_owner fence plus idempotency key in delivery receipt; inbox has its own canonical lock | no message | replay until exactly one correlated message | row 8 |
| 10 | R04 | wake target pane / mark deploy completed | immediately before wakeup and success marker | watcher, manual wake, deploy retry | terminal delivery receipt is prerequisite; effect count recorded | no wake/success | reconcile persisted inbox; never synthesize success from process exit alone | row 9 |
| 11 | R04 | rollback on any nonzero deployment rc | immediately before rollback publish | retry or new owner generation | rollback guarded by same fence and attempt id | stale rollback denied | current-generation reconciler restores snapshot or converges forward | rows 8-10 |
| 12 | shared | publish terminal task_owner receipt and release reservation | immediately before terminal mutation | startup reconciler and retry | CAS on current fence; receipt binds selector+owner+delivery outcome | cannot terminalize current generation | reconciler repeats idempotently | all prior applicable rows |

Coverage: 12/12 rows have an immediate stop point, concurrent writer, authority/fence/receipt, stale policy, reconcile rule, and dependency. Authority owners: `task_owner` 1; duplicate authority designs 0. R04 remains gated, so rows 7-12 are a contract, not authorization to implement the stale ACTIVE row.

## Fixture and implementation contract

| invariant | positive | negative | crash | retry | simultaneous writer | implementation owner | planned paths | serialization |
|---|---|---|---|---|---|---|---|---|
| R04 `failed_deploy_not_active` | rc=0 + correlated inbox + terminal receipt permits active/completed delivery | any nonzero rc leaves no terminal-active receipt and rolls back task/report | inject after task mutation and after inbox persistence; startup reconcile yields rollback or exactly-one terminal delivery | same attempt is idempotent; new attempt requires a new fence | old finisher paused before effect, new generation begins, old returns rc=4 with current bytes unchanged | **none while Gate A BLOCK**; if reclassified, extend R03 owner transaction in `scripts/deploy_task.sh` and its existing focused contract only | `scripts/deploy_task.sh`, `tests/unit/test_deploy_task.bats` (contract only if `test_necessity` is declared) | R03 → R04 under `task_owner` |
| R05 `only_pending_or_idle_selected` | pending and idle are each eligible | assigned, acknowledged, in_progress, done, failed, transferred, owner_prepared, unknown are rejected | inject after snapshot and after reservation; no candidate becomes visible without current receipt | rescan current generation; same reservation is idempotent | two selectors for one subject yield one reservation, loser rc=4, lost_update=0 | `unit_r05_deploy_selector`; reuse R03 helpers in `scripts/auto_deploy_next.sh` | `scripts/auto_deploy_next.sh`, `tests/unit/test_auto_deploy_next.bats` (contract only if `test_necessity` is declared) | R03 → R05 under `task_owner` |

Fixture cells: 2 invariants × 5 modes = 10/10 specified. Positive inputs=3 (R04 success, R05 pending, R05 idle); negative inputs=9 (R04 nonzero plus eight R05 denied states). Required assertions per concurrency run: `lost_update=0/N`, `false_success=0/N`, terminal receipts `<=1/subject`, executable owner `<=1`, SKIP=0. No implementation may start if an effect is absent from the 12-row table or if authority owner count differs from 1.

## Adoption order

1. Canonical owner resolves R04's contradictory status and regenerates the foundation map; unchanged supersession closes R04 with no code change.
2. Confirm the accepted R03 focused fixture remains PASS/SKIP0 at the implementation baseline.
3. Implement and fixture R05 through the existing R03 task_owner primitive.
4. Only if step 1 explicitly reopens R04, implement its receipt extension; otherwise retain the existing rollback and its wave-0 supersession evidence.
5. Run one final shared concurrency checkpoint, then publish the terminal manifest receipt.
