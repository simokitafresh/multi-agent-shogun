# ホットスクリプト集中高速化 第七弾 — final checkpoint snapshot

## 結論

第七弾final checkpointは **FAIL**。固定SHA `966b4fbe84d4ad9f244a2408ab2adfadac9e6d3a` のclean detached worktreeでunit全量を契約どおり1回だけ実行したが、`test_deploy_task.bats` のtest 7が失敗した。成功runだけを序列SSOTにする契約によりper-file/per-suite ledgerはpublishされず、wave-finalとのTOP10比較は確定不能である。

## 実行境界とreceipt

| 項目 | 実測 |
|---|---|
| 実行境界 | clean detached worktree、実行前dirty 0 |
| 採用HEAD | `966b4fbe84d4ad9f244a2408ab2adfadac9e6d3a` |
| command | `BATS_CACHE=0 bash scripts/run_tests.sh unit` |
| 実行回数 | 1 |
| receipt | `/tmp/tobisaru-round7-checkpoint-uTjdZ5/logs/test_receipts/run_tests_20260729T211955_2436357.json` |
| receipt SHA-256 | `607a4e6644c6cced831d81fe68707188674f341812918adb71857ea2fd523416` |
| artifact | `/tmp/tobisaru-round7-checkpoint-uTjdZ5/logs/test_receipts/run_tests_20260729T211955_2436357.output` |
| artifact SHA-256 | `6805d80ffe3c3af728aa63ff2ef4265f530785dcc4abdf5654217722a7749795` |
| run_id | `20260729T211955.2436357.29678` |
| source_fingerprint | `31949ebc4831dc8b73daca43ba1ef027772d7a93f631737026ea286c3998fed1` |
| 結果 | rc=1、FAIL file 1、SKIP 0、cache 0 |
| duration | 353,669ms |

## 失敗の一次結果

receiptのscope identityは selected 183 / started 47 / executed 47 / failed 1。失敗対象は `tests/unit/test_deploy_task.bats` のtest 7:

```text
not ok 7 report commit contract inherits explicit task value and falls back only when absent
# (in test file tests/unit/test_deploy_task.bats, line 161)
#   `wait "$pid"' failed
```

同ファイルは53 tests中52 PASS・1 FAIL。全runのobserved test countは2,858、skip_countは0。

## 4識別子結合と比較判定

失敗runはreceiptのみpublishされ、`logs/test_timing_ledger.tsv` と `logs/test_suite_timing_ledger.tsv` は生成されなかった。したがって同一4識別子の結合件数は receipt 1 / per-file 0 / per-suite 0 で、要求値 receipt 1 / per-file 183 / per-suite 1 を満たさない。

| 比較対象 | before: wave-final | after: final checkpoint | 判定 |
|---|---:|---:|---|
| 全量suite wall | 747.541s | 353.669s（失敗時点） | 比較不可 |
| TOP10各file wall | 10件あり | success ledgerなし | 比較不可 |

afterは183 files完走値ではないため、短縮率を算出・採用してはならない。第七弾の総短縮効果は未確定のまま、失敗原因の是正後に新たなfixed-SHA checkpointが必要である。

origin: `[[全10レーンCLEAR]] -> [[fixed_SHA_checkpoint_966b4fbe]] -> [[test_deploy_task_test7_FAIL]] -> [[第七弾総短縮効果未確定]]`
