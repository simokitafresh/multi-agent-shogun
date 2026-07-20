# Git index contention retro (hanzo, 2026-07-20)

## 結論

隔離fixtureで4候補×3状態×3反復、各回2 worker（計72 worker）を実走した。最速かつ全状態で成功したのはlinked worktreeで、平均72.0–90.7ms、18/18成功、scope混入0、複数親0。適用境界は「workerごとに独立branchを許容できる並列作業」。同一HEADへ直列公開する必要がある通常の忍者commitでは、private `GIT_INDEX_FILE` + common-dir単位lockが安全（90.3–111.3ms、18/18成功）。

## 一次結果

| 候補 | 状態 | 平均wall_ms | 成功 | scope混入 | 複数親 |
|---|---:|---:|---:|---:|---:|
| shared guard | 通常 | 96.3 | 6/6 | 0 | 0 |
| shared guard | REVERT_HEAD | 48.7 | 0/6 | 0 | 0 |
| shared guard | index.lock | 49.0 | 0/6 | 0 | 0 |
| private index + ref lock | 通常 | 90.3 | 6/6 | 0 | 0 |
| private index + ref lock | REVERT_HEAD | 95.0 | 6/6 | 0 | 0 |
| private index + ref lock | index.lock | 111.3 | 6/6 | 0 | 0 |
| wait/retry shared | 通常 | 96.0 | 6/6 | 0 | 0 |
| wait/retry shared | REVERT_HEAD | 215.7 | 0/6 | 0 | 0 |
| wait/retry shared | index.lock | 152.3 | 6/6 | 0 | 0 |
| linked worktree | 通常 | 72.0 | 6/6 | 0 | 0 |
| linked worktree | REVERT_HEAD | 87.0 | 6/6 | 0 | 0 |
| linked worktree | index.lock | 90.7 | 6/6 | 0 | 0 |

有効測定のraw receipt: `/tmp/hanzo-retro-valid.EDUC4p/results.tsv`。初回は安全hookが通常commit直書きをBLOCK、2回目はfixture identity欠落で全条件無効、3回目にidentity明示後、全72 workerを完走した。

## 判断

- index.lockはbounded retryで回復できるが、REVERT_HEADは待機では解消しない。両者を同一の「少し待てば直る競合」と扱わない。
- linked worktreeはbranch分離できる偵察・独立実験に限定する。同一branchへ順序付き公開する成果には使わない。
- 通常成果の最小案は、現行 `scripts/ninja_scope_commit.sh` が採るprivate index、common-dir lock、単一親CAS更新を維持すること。共有indexや進行中operation stateをcommit sourceへ継承しない。
- 本番worktreeのindex、index.lock、REVERT_HEADは変更していない。履歴破壊操作も0件。

