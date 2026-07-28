# ホットスクリプト集中高速化 第五弾 — fixed-window snapshot v4.0

- 実施日: 2026-07-29
- source HEAD: `f8831da8ee9ceff2d76e08902f957249e8a207bc`
- snapshot下限: `2026-07-28T11:25:10+00:00`（v3.0上限を継承、inclusive）
- snapshot上限: `2026-07-28T18:24:39.872864+00:00`（第四弾fixed-SHA checkpoint receipt確定時刻、inclusive）
- 固定窓の台帳全行: 8,237行
- 固定窓raw-line SHA-256: `db3fed9cc21495fb6d2a1f4584481c8c75b636af3a57dbc80e9218d443c8c9ed`
- hash定義: timestampが上下限内の行を元台帳順・末尾改行込みで連結したbyte列のSHA-256
- 欠損: 下表の全標的で `wall_ms` 欠損0
- checkpoint: CI run `30385588247` success、local receipt `logs/test_receipts/run_tests_20260728T181204_396464.json`
- checkpoint生値: `rc=0 tests=2745/2745 skip=0 duration_ms=753818`

## 集計契約

集計対象は `logs/defense_overhead.jsonl` の固定窓8,237行。source/check_idごとに `n / sum / median / nearest-rank p95 / max` を算出する。親totalと子区分は加算せず、子は診断専用とする。

```python
lo = "2026-07-28T11:25:10+00:00"
hi = "2026-07-28T18:24:39.872864+00:00"
rows = [json.loads(line) for line in open("logs/defense_overhead.jsonl")
        if lo <= json.loads(line).get("timestamp", "") <= hi]
# source/check_id別にwall_msを全数集計。
# p95 = sorted(values)[ceil(0.95 * n) - 1]
```

v3.0窓を同じ集計コードで再計算し、主要5標的の `n/sum/median/p95/max` がv3.0正本と5/5完全一致した。

## v4.0 累積時間序列 — 第五弾候補10標的

| 順 | source:check_id | n | 累積 | median | p95 | max | writer / 並列制約 |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | `inbox_write:inbox_write_total` | 560 | 967,783ms | 298ms | 6,264ms | 12,357ms | `scripts/inbox_write.sh` |
| 2 | `gate_gunshi_report_precheck:full_precheck` | 131 | 507,206ms | 1,077ms | 13,402ms | 21,531ms | `scripts/gates/gate_gunshi_report_precheck.sh` |
| 3 | `report_publish:publish_total` | 261 | 110,160ms | 320ms | 600ms | 12,520ms | `scripts/report_field_set.sh` |
| 4 | `git_pre_commit:yaml_ast` | 66 | 98,789ms | 1ms | 6,460ms | 13,907ms | `scripts/hooks/git-pre-commit.sh` |
| 5 | `report_field_set:commit_hash` | 324 | 84,260ms | 245ms | 490ms | 1,110ms | `scripts/report_field_set.sh`、#3後に直列 |
| 6 | `report_field_set:files_modified` | 54 | 29,180ms | 520ms | 1,040ms | 1,560ms | `scripts/report_field_set.sh`、#5後に直列 |
| 7 | `git_pre_commit:sourced_dep` | 66 | 20,856ms | 2ms | 1,973ms | 4,161ms | `scripts/hooks/git-pre-commit.sh`、#4後に直列 |
| 8 | `report_field_set:task.commit_contract` | 59 | 17,870ms | 250ms | 650ms | 1,050ms | `scripts/report_field_set.sh`、#6後に直列 |
| 9 | `cmd_save:checks_main` | 14 | 15,911ms | 1,095ms | 2,233ms | 2,233ms | `scripts/cmd_save.sh` |
| 10 | `git_pre_commit:shell_syntax` | 66 | 11,480ms | 2ms | 859ms | 2,415ms | `scripts/hooks/git-pre-commit.sh`、#7後に直列 |

## 非加算・別母集団

| category | source:check_id | n | 累積 | 理由 |
|---|---|---:|---:|---|
| mixed marker | `three_layer_health:refresh_window` | 578 | 7,560,079ms | begin=0/end=窓長の混在。集計禁止 |
| selection+execution | `git_pre_commit:affected_tests` | 66 | 4,719,749ms | テスト実行本体込み |
| execution child | `three_layer_health:refresh_copy` | 290 | 3,811,625ms | background保守lane、windowと非加算 |
| execution child | `three_layer_health:refresh_verify` | 288 | 3,347,143ms | background保守lane、windowと非加算 |
| execution body | `heavy_job_admission:execution` | 239 | 2,510,000ms | 子job実行本体 |
| queue wait | `heavy_job_admission:queue_wait` | 240 | 2,416,000ms | 実行時間と別母集団 |
| parent total | `deploy_task:deploy_total` | 110 | 1,260,368ms | 配備本体込み。子と非加算、既存deployレーンへ帰属 |
| lock hold | `gate_report_format:singleflight_hold` | 227 | 123,560ms | lock待ちではなく保持時間 |

## 第五弾10レーンへの入力

- 殿裁定の対象数は10標的で固定し、途中追加しない。
- 上位10標的は5 writerに属する。最大同時並列は5 writer、同一writer内は表の順で直列とする。別ファイルは即並列配備する。
- 第四弾で扱った標的も依然上位なら再試行する方針を継承する。ただし各弾AC1でv4.0の混合窓を鵜呑みにせず、現行commitの枝別beforeを再計測する。
- `inbox_write_total` / `full_precheck` / `publish_total` は第四弾是正後も累積上位だが、窓内にbefore/afterが混在する。第五弾では最初に現行枝の寄与を識別子で分離し、改善余地なしならno-change CLOSEとする。
- 個別弾は選択テストのみ。全量unitは10標的全クローズ後のfixed-SHA checkpointでwave共有1回とする。

origin: `[[第四弾v3.0_snapshot]] -> [[第四弾fixed_SHA_checkpoint_f8831da8]] -> [[第五弾v4.0_snapshot]] -> [[第五弾10標的序列]]`
