# 任務テスト帰属 After設計書（2026-07-21）

## 問題と根因

共有worktreeで `run_tests.sh affected` を引数なし実行すると、全agentの未commit差分を `git diff` から取得する。cmd_4108では任務固有fixture 6/6 PASSにもかかわらず、scope外 `test_inbox_write.bats` を含む690件へ拡大し、無関係FAIL 1件が任務verdictをFAILへ反転した。

## 現在の構造

- 任務反復・報告直前: `bash scripts/run_tests.sh task queue/tasks/<worker>.yaml`
- scope SSOT: taskの `target_path` / `test_path` / `files_to_modify` / `owned_paths(_json)` と、reportの `files_modified`
- selector: 上記scopeを明示引数として既存 `test_select.sh` へ渡す。共有worktree全体の `git diff` は使わない
- scope空・解決不能・repo外path: 全量fallbackせずrc=2
- 全量 `all` / `unit`: fixed-SHA統合checkpointの独立判定。結果は任務固有binary checkへ混入させない

## 二値証跡

| 項目 | 修正前 | 修正後 |
|---|---:|---:|
| cmd_4108選択 | 690 tests | 所有4 paths → 4 test files |
| 任務判定 | FAIL 1 / SKIP 0 | 109/109 PASS / FAIL 0 / SKIP 0 |
| scope外 `test_inbox_write.bats` 混入 | 1 | 0 |
| runner contract tests | — | 24/24 PASS / SKIP 0 |

証跡: `logs/test_receipts/run_tests_20260721T043544_1744738.json`。

## 不変量

任務の成否は任務所有pathから到達するテストだけで判定する。全体健全性は失敗を隠さずfixed-SHA統合checkpointで別途回収する。

origin: `[[cmd_4108]] -> [[shared_worktree_global_diff_contamination]] -> [[task_test_attribution]]`
