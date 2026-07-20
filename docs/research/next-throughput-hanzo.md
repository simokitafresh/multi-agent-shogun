# Publication 経路スループット実測

日時: 2026-07-20  
対象: `scripts/report_field_set.sh --batch` の terminal publication 経路  
実行: `bats --filter 'batch applies many fields|persisted terminal report survives pre-delivery failpoint|twenty isolated terminal publishes' tests/unit/test_report_field_set_batch_throughput.bats` を3反復

## 実測結果

| phase | run 1 | run 2 | run 3 | 未計測 | 欠落/誤配送 |
|---|---:|---:|---:|---:|---:|
| 50-field atomic persist | 327 ms | 157 ms | 204 ms | 0 | 0 |
| failpoint durable persist | 453 ms | 242 ms | 257 ms | 0 | 0 |
| terminal publication, n=20 p50 | 161 ms | 181 ms | 166 ms | 0 | 0 |
| terminal publication, n=20 p95 | 221 ms | 208 ms | 212 ms | 0 | 0 |

全9 phase-runがPASS、SKIP 0。terminal publicationは各run 20/20件が永続化され、合計60/60件。各イベントは canonical `worker_id=hanzo`、`parent_cmd=cmd_test`、`report=report.yaml` を保持し、テストの `fp=0 fn=0` からidentity誤り0・欠落0を確認した。failpoint 3/3ではreportのterminal bytesが配送前に残り、delivery 0でもmonitor repair可能だった。

## 最速候補

現行の「batch 1 process + flock 1回 + atomic replace 1回でpersistし、その確定bytesから`setsid -f`でdeliveryを切り離す」経路を維持するのが最速候補。観測p95最大221 msで、persist/identity/欠落0の全条件を同時に満たした。同期inbox配送をterminal writerの成功境界へ戻す案は、永続化済みoutboxという復旧点を失いwriter latencyも増やすため採用候補外。

## 二値判定

- AC1: PASS — 3 phaseを各3回計測、9/9 PASS、未計測0、SKIP 0。
- AC2: PASS — persist 60/60、identity誤り0、欠落0を維持する現行deferred publicationを最速候補として確定。
