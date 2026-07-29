# ホットスクリプト集中高速化 第五弾 — wave-final fixed-SHA snapshot

## 結論

第五弾は **CLOSED**。10/10弾GATE CLEAR（9採用・1 no-change）後、固定SHA `4717f7d1274bcb69206548bb701c570f351367a5` のclean detached worktreeでunit全量を1回だけ実行し、183/183 files・2,800/2,800 tests・FAIL 0・SKIP 0・cache 0でPASSした。本receiptを第七弾の序列SSOTとして兼用する。

## fixed-SHA境界とreceipt

| 項目 | 実測 |
|---|---|
| 実行境界 | clean detached worktree、dirty 0 |
| 採用HEAD | `4717f7d1274bcb69206548bb701c570f351367a5` |
| command | `BATS_CACHE=0 ... bash scripts/run_tests.sh unit` |
| receipt | `logs/test_receipts/run_tests_20260729T172759_4154957.json` |
| receipt SHA-256 | `202277bd525b7bad6f8a5ff1c5be331dc562fb203bdc37370cf47d290993eaed` |
| artifact | `logs/test_receipts/run_tests_20260729T172759_4154957.output` |
| TAP | `logs/test_receipts/run_tests_20260729T172759_4154957.tap`（3,016行、SHA-256 `8172ad271ac428bc550e113ccf55e977ff123080cbb0753f5fb9046916f8f521`） |
| 結果 | 183/183 files、2,800/2,800 tests、FAIL 0、SKIP 0、cache 0 |
| duration | 747,541ms |

## 4識別子一意結合

| 識別子 | 値 |
|---|---|
| run_id | `20260729T172800.4154957.21942` |
| commit_sha | `4717f7d1274bcb69206548bb701c570f351367a5` |
| source_fingerprint | `29f3fae90248da9d30589631a0d946d4fe29523517a360592b969f655b18b65a` |
| output_sha256 | `2bf681ddbeeedcfc04633658d3234fba2c3a50678b3194eb943a0829251a1303` |

同一4識別子の結合結果:

| 媒体 | row_count | status | exact boundary | raw SHA-256 |
|---|---:|---|---|---|
| receipt JSON | 1 | PASS | 1 identity / 1 receipt | `202277bd525b7bad6f8a5ff1c5be331dc562fb203bdc37370cf47d290993eaed` |
| `logs/test_timing_ledger.tsv` | 183 | pass 183/183 | `2026-07-29T17:40:24Z` inclusive | `4d7097250a308bc54e004d1cc3186e2b734fbbdea98e5af8d9be31103d43e20a` |
| `logs/test_suite_timing_ledger.tsv` | 1 | pass 1/1、file_count=183 | `2026-07-29T17:40:24Z` inclusive | `1441788246e07b2ec626e897f68a5c84a50aa085bd079e50b17aab0ef559643b` |

選択183 fileとper-file ledgerの集合差は missing 0 / extra 0、per-fileの一意test_file数は183。

## 第七弾 序列snapshot

同一4識別子で結合したper-file 183行の `wall_sec` 降順。Σfile時間は並列実行のためsuite wallと加算比較しない。

| 順位 | test file | wall_sec | test count | SKIP |
|---:|---|---:|---:|---:|
| 1 | `test_inbox_write.bats` | 68.219 | 102 | 0 |
| 2 | `test_deploy_task_ac_handling.bats` | 67.552 | 49 | 0 |
| 3 | `test_heavy_job_admission.bats` | 66.977 | 86 | 0 |
| 4 | `test_deploy_task.bats` | 58.697 | 53 | 0 |
| 5 | `test_cmd_complete_gate.bats` | 56.815 | 161 | 0 |
| 6 | `test_report_field_set_batch_throughput.bats` | 55.023 | 20 | 0 |
| 7 | `test_run_tests.bats` | 53.436 | 53 | 0 |
| 8 | `test_deploy_task_lifecycle.bats` | 47.256 | 92 | 0 |
| 9 | `test_campaign_lane_shard_item.bats` | 43.909 | 36 | 0 |
| 10 | `test_ninja_monitor_stall.bats` | 41.067 | 78 | 0 |
| 11 | `test_cmd_save_block_aggregation.bats` | 39.054 | 13 | 0 |
| 12 | `test_ninja_scope_commit.bats` | 38.814 | 68 | 0 |
| 13 | `test_deploy_task_nocode_commit_contract.bats` | 36.481 | 14 | 0 |
| 14 | `test_cmd_complete_wrapper.bats` | 33.305 | 24 | 0 |
| 15 | `test_three_layer_preflight.bats` | 31.377 | 51 | 0 |
| 16 | `test_yaml_field_set.bats` | 30.591 | 58 | 0 |
| 17 | `test_context_freshness_check.bats` | 28.392 | 57 | 0 |
| 18 | `test_deploy_task_yaml_injection.bats` | 27.806 | 63 | 0 |
| 19 | `test_report_commit_identity.bats` | 26.826 | 24 | 0 |
| 20 | `test_ninja_monitor_clear_guard.bats` | 24.155 | 70 | 0 |

## 第五弾 live採用値

各値の一次報告は `docs/research/hot-script-speedup-round5-asis-tobe-5w1h_20260729.md` §-2。wave-final PASSにより次を最終採用する。

| 弾 | 最終帰結 |
|---:|---|
| 1 | inbox_write_total: p50 2,555→1,382ms（-45.9%） |
| 2 | full_precheck制御境界: median 3,817→1,877ms（-50.8%） |
| 3 | publish_total: p95 1,110→305ms、max 4,150→319ms |
| 4 | yaml_ast: sum 13,321→6,639ms、p95 5,391→517ms |
| 5 | commit_hash: p50 160→80ms（負荷後40ms） |
| 6 | files_modified: p50 310→29ms（-90.6%） |
| 7 | sourced_dep: median 440→40ms（11倍） |
| 8 | task.commit_contract: no-change CLOSE |
| 9 | checks_main: semantic結果→causal再走査の入力増幅を明示query限定で除去 |
| 10 | shell_syntax: 15反復sum 415.7→373.7ms |

## scope_identity計器の既知false negative

receiptは `selected=183 / discovered=183 / executed=185 / full_scope=false`。実行漏れではない。artifactの外側STARTは選択183件を全て含み（missing 0）、`test_run_tests.bats` 内部のscheduler fixtureが出したnested START 3行（`test_normal_slow.bats`、`test_normal_short.bats`、`test_cmd_save.bats`）を外側parserが混入し、うち `test_cmd_save.bats` は外側選択と重複したためunique executedが183→185へ過大計上された。per-file ledgerは正しく183行・集合差0。wave-final結果と序列結合は有効だが、scope計器は別hotfixでnested境界を除外する。

origin: `[[第五弾10弾_GateClear]] -> [[fixed_SHA_wave_final_4717f7d12]] -> [[第五弾CLOSED]] -> [[第七弾序列SSOT]]`
