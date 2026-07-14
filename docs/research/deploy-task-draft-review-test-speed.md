# deploy_task draft-review test speed

- 対象: [[test_deploy_task_draft_review.bats]]
- 共有fixture: [[deploy_task_scaffold.bash]]
- 変更前: 20 tests / 15.982秒 / FAIL 0 / SKIP 0（`logs/test_timing_ledger.tsv`）
- 支配項: `setup` で読込済みの10k行deploy libraryを、共通helperが各呼出しで再度`bash -lc + source`していた。
- 改善: Batsの`run` subshellから既に読込済みの関数を直接呼ぶ。期待値・対象数は不変。
