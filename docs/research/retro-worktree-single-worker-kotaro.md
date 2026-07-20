# Retro: checkout.workers single-worker verification — kotaro

- Date: 2026-07-20
- Fixed HEAD: `78878d4c6`
- Isolation: bare shared clone and all linked worktrees under `.kotaro-retro-worktree-exp-202607202108/` on the same `/mnt/c` 9p filesystem.
- Scope: no production code, shared worktree, gate, hook, or operational YAML was modified by the experiment.
- Definitions: false completion = `git worktree add` returns success while immediate status is dirty; convergence = parent exit to completed status/absence checks; duplicate = same path appears as both staged delete and untracked.

## Results

| workers | run | rc | add ms | path | exit dirty | convergence ms | index.lock | missing | duplicate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| true | 1 | 128 | 2663 | no | N/A | N/A | 0 | N/A | N/A |
| true | 2 | 128 | 2508 | no | N/A | N/A | 0 | N/A | N/A |
| true | 3 | 128 | 2587 | no | N/A | N/A | 0 | N/A | N/A |
| true | 4 | 128 | 2283 | no | N/A | N/A | 0 | N/A | N/A |
| true | 5 | 128 | 2066 | no | N/A | N/A | 0 | N/A | N/A |
| true | 6 | 128 | 2054 | no | N/A | N/A | 0 | N/A | N/A |
| true | 7 | 128 | 1982 | no | N/A | N/A | 0 | N/A | N/A |
| true | 8 | 128 | 2101 | no | N/A | N/A | 0 | N/A | N/A |
| true | 9 | 128 | 2249 | no | N/A | N/A | 0 | N/A | N/A |
| true | 10 | 128 | 1425 | no | N/A | N/A | 0 | N/A | N/A |
| 1 | 1 | 0 | 35807 | yes | 0 | 7067 | 0 | 0 | 0 |
| 1 | 2 | 0 | 31223 | yes | 0 | 6691 | 0 | 0 | 0 |
| 1 | 3 | 0 | 47323 | yes | 0 | 4637 | 0 | 0 | 0 |
| 1 | 4 | 0 | 35118 | yes | 0 | 5054 | 0 | 0 | 0 |
| 1 | 5 | 0 | 127377 | yes | 0 | 22899 | 0 | 0 | 0 |
| 1 | 6 | 0 | 108728 | yes | 0 | 16628 | 0 | 0 | 0 |
| 1 | 7 | 0 | 83862 | yes | 0 | 18399 | 0 | 0 | 0 |
| 1 | 8 | 0 | 97530 | yes | 0 | 10066 | 0 | 0 | 0 |
| 1 | 9 | 0 | 105298 | yes | 0 | 14546 | 0 | 0 | 0 |
| 1 | 10 | 0 | 140901 | yes | 0 | 20250 | 0 | 0 | 0 |

## Aggregate

| workers | success | explicit failure | false completion | add median/range ms | convergence median/range ms | index.lock | missing | duplicate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| true | 0/10 | 10/10 | 0 | 2060 / 1425–2663 | N/A | 0 | N/A | N/A |
| 1 | 10/10 | 0/10 | 0/10 | 90696 / 31223–140901 | 12306 / 4637–22899 | 0/10 | 0/10 | 0/10 |

## Finding and application boundary

`checkout.workers=true` is not an asynchronous-completion mode. Git requires a numeric value and consistently returned rc 128 with `fatal: bad numeric config value 'true' for 'checkout.workers': invalid unit`. The earlier apparent dirty worktree was therefore not evidence of a successful parent returning before workers; it was an explicit checkout failure whose rc was not preserved by the caller.

The fastest eligible candidate maintaining false completion zero is `checkout.workers=1`, because it is the only successful candidate. Apply it as a local `git -c checkout.workers=1 worktree add ...` override (or correct the invalid repository setting) for full linked-worktree creation on `/mnt/c`. Do not describe it as a speed optimization: median creation was 90.696 seconds and full immediate verification added 12.306 seconds. Callers must preserve and check the `git worktree add` rc before inspecting status; failed creation is not a convergence state.

## Contract and policy notes

- 20/20 required repetitions were executed; the first four harness rows produced before rc validation were discarded and are not included above.
- Documentation/data-only reconnaissance: no implementation test was created or persisted.
- The result narrows the suspected root cause from background parallel checkout to invalid boolean configuration plus lost rc evidence.
