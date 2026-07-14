# context source commit set test speed

- 対象: [[test_context_source_commit_set.bats]]
- 被テスト: [[context_source_commit_set.sh]]
- 変更前: 5 tests / 1.706秒 / FAIL 0 / SKIP 0（`logs/test_timing_ledger.tsv`）。
- 支配項: 全testのsetupが同一Git repositoryを`init/config/add/commit`していた。
- 改善: committed repository fixtureを`setup_file`で1回だけ生成し、各testは隔離copyから開始する。期待値・対象数は不変。
