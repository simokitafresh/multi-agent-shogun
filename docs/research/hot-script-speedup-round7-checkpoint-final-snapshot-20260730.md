# ホットスクリプト集中高速化 第七弾 — final checkpoint snapshot

## 結論

第四世代final checkpointは **PASS**。固定SHA
`bee4d7ef4fd2ef3491b82356e89feb13865e0a1b` のclean detached worktreeで
unit全量を契約どおり1回だけ実行し、184/184 files・2,812/2,812 tests・
FAIL 0・SKIP 0・cache 0で完走した。同一4識別子のexact joinは
receipt 1 / per-file 184 / per-suite 1、選択集合との差はmissing 0 / extra 0。

第五弾wave-finalと同じ `scripts/run_tests.sh unit` のreceipt・per-file ledger・
per-suite ledger生成パイプラインによる同格比較で、suite wallは
742.250→717.390秒（-24.860秒、-3.35%）となった。

## 第四世代の実行境界とreceipt

| 項目 | 実測 |
|---|---|
| 実行境界 | `/tmp/hanzo-round7-gen4-YUF6cv`、clean detached worktree、実行前dirty 0 |
| 採用HEAD | `bee4d7ef4fd2ef3491b82356e89feb13865e0a1b` |
| command | `BATS_CACHE=0 bash scripts/run_tests.sh unit` |
| 実行回数 | 1 |
| receipt | `logs/test_receipts/run_tests_20260730T002238_243669.json` |
| receipt SHA-256 | `38aad56c84930fa94dbe2827be3f2caaf856d9c206fd9b0cc77ef8c62794ed1e` |
| artifact | `logs/test_receipts/run_tests_20260730T002238_243669.output` |
| artifact SHA-256 | `bce9b6806013515443fc1498a7f1e70191368b370daa5f945e59d31696c2ffa4` |
| TAP SHA-256 | `442afd2b558b40fdf6b319c57c7ea6278ce9b431728297de15e382ae4a118f9f` |
| run_id | `20260730T002238.243669.1143` |
| source_fingerprint | `3d21b6f581faf829e4e9ed2585756d1f1199ac29e946bac52ba03e5b452c95f3` |
| 結果 | rc=0、184/184 files、2,812/2,812 tests、FAIL 0、SKIP 0、cache 0 |
| receipt duration | 719,284ms |

生のterminal summary:

```text
PASS: 184 bats file(s) (184 run, 0 cached)
TEST_RECEIPT_PASS path=/tmp/hanzo-round7-gen4-YUF6cv/logs/test_receipts/run_tests_20260730T002238_243669.json rc=0 tests=2812/2812 skip=0 sha256=bce9b6806013515443fc1498a7f1e70191368b370daa5f945e59d31696c2ffa4 duration_ms=719284 files_selected=184 files_discovered=184 files_executed=184 complete=1 full_scope=1
```

## 4識別子exact join

| 識別子 | 値 |
|---|---|
| run_id | `20260730T002238.243669.1143` |
| commit_sha | `bee4d7ef4fd2ef3491b82356e89feb13865e0a1b` |
| source_fingerprint | `3d21b6f581faf829e4e9ed2585756d1f1199ac29e946bac52ba03e5b452c95f3` |
| output_sha256 | `bce9b6806013515443fc1498a7f1e70191368b370daa5f945e59d31696c2ffa4` |

| 媒体 | exact row_count | status | raw SHA-256 |
|---|---:|---|---|
| receipt JSON | 1 | PASS | `38aad56c84930fa94dbe2827be3f2caaf856d9c206fd9b0cc77ef8c62794ed1e` |
| `logs/test_timing_ledger.tsv` | 184 | pass 184/184、skip 0、cache 0 | `37c76561cc0a2c2ecc3b0a400426459e05d54320e126af4e3d902a69cced25d7` |
| `logs/test_suite_timing_ledger.tsv` | 1 | pass 1/1、file_count=184 | `24459a838613031b0723ff3d01d6cec0b3c92703016172c4b21b96513d68599a` |

receiptの選択184 fileとper-file ledgerの一意test_file集合は
missing 0 / extra 0。第三世代FAILのpending batchと異なり、成功runの両ledgerが
原子的にpublishされ、exact joinが成立した。

## wave-finalとの同格比較

beforeは第五弾wave-final run `20260729T172800.4154957.21942`、
afterは本checkpoint run `20260730T002238.243669.1143`。両者ともclean detached
fixed-SHA上で `BATS_CACHE=0 bash scripts/run_tests.sh unit` を1回実行し、
同runnerが生成したreceipt・per-file ledger・per-suite ledgerを同一4識別子で
exact joinした値である。

wave-finalのTOP10各fileを同名fileで比較した。

| test file | before_s | after_s | delta_s | change |
|---|---:|---:|---:|---:|
| `test_inbox_write.bats` | 68.219 | 81.478 | +13.259 | +19.44% |
| `test_deploy_task_ac_handling.bats` | 67.552 | 86.185 | +18.633 | +27.58% |
| `test_heavy_job_admission.bats` | 66.977 | 48.377 | -18.600 | -27.77% |
| `test_deploy_task.bats` | 58.697 | 70.939 | +12.242 | +20.86% |
| `test_cmd_complete_gate.bats` | 56.815 | 62.628 | +5.813 | +10.23% |
| `test_report_field_set_batch_throughput.bats` | 55.023 | 21.495 | -33.528 | -60.93% |
| `test_run_tests.bats` | 53.436 | 66.519 | +13.083 | +24.48% |
| `test_deploy_task_lifecycle.bats` | 47.256 | 64.316 | +17.060 | +36.10% |
| `test_campaign_lane_shard_item.bats` | 43.909 | 33.390 | -10.519 | -23.96% |
| `test_ninja_monitor_stall.bats` | 41.067 | 29.754 | -11.313 | -27.55% |
| **全量suite wall** | **742.250** | **717.390** | **-24.860** | **-3.35%** |

Σfile時間は並列実行のためsuite wallと加算比較しない。全量suite wallは短縮したが、
個別fileには実行時ノイズと追加testの影響を含むため、各弾の採否は既存のfocused
同条件計測を正本とし、本表は最終checkpoint snapshotとして扱う。

## 第四世代after TOP10

| 順位 | test file | wall_sec | test count |
|---:|---|---:|---:|
| 1 | `test_deploy_task_ac_handling.bats` | 86.185 | 49 |
| 2 | `test_inbox_write.bats` | 81.478 | 102 |
| 3 | `test_deploy_task.bats` | 70.939 | 54 |
| 4 | `test_run_tests.bats` | 66.519 | 54 |
| 5 | `test_deploy_task_lifecycle.bats` | 64.316 | 93 |
| 6 | `test_cmd_complete_gate.bats` | 62.628 | 162 |
| 7 | `test_context_freshness_check.bats` | 51.649 | 57 |
| 8 | `test_cmd_complete_wrapper.bats` | 51.377 | 25 |
| 9 | `test_heavy_job_admission.bats` | 48.377 | 86 |
| 10 | `test_semantic_index_update.bats` | 44.484 | 43 |

## 世代履歴

| 世代 | fixed SHA | duration | 結果 |
|---|---|---:|---|
| 第一世代 | `966b4fbe84d4ad9f244a2408ab2adfadac9e6d3a` | 353.669s | `test_deploy_task.bats` test 7 FAIL |
| 第二世代 | `b480b5b03e618c5fcd2794cb7ecdd7219f968acd` | 590.775s | 同test 7 FAIL |
| 第三世代 | `aed5dfb9b76cdd01c7fae2184bfb8063f32a9422` | 425.541s | deploy test 7 PASS、`test_lgtm_bundle_guard.bats` setup FAIL |
| 第四世代 | `bee4d7ef4fd2ef3491b82356e89feb13865e0a1b` | 719.284s | 184/184 files、2,812/2,812 tests、FAIL 0、SKIP 0 |

origin: `[[第三世代_lgtm_bundle_guard_setup_FAIL]] -> [[実行bit契約是正]] -> [[第四世代checkpoint_PASS]] -> [[第七弾総短縮効果確定]]`
