# cmd_4181 計測境界再偵察

## 結論

固定スナップショット `logs/defense_overhead.jsonl` 39,070行、cutoff
`2026-07-27T11:03:55.717413+00:00` で再集計した。親子は加算せず、
selection / execution / queue_wait / lock_hold / wait を別母集団にした。
純オーバーヘッドの優先標的は累積時間順に
`git_pre_commit:self_sync` (1,699,622ms)、
`cmd_save:checks_main` (1,544,448ms)、
`git_pre_commit:test_granularity` (1,045,936ms) である。
本結果は高速化設計書v1.0
`docs/research/hot-script-speedup-asis-tobe-5w1h_20260727.md`
の覚醒更新入力であり、高速化実装そのものではない。

## 計測境界表（writer現物照合）

| source:check_id | writer現物 | 境界分類 | 加算可否 |
|---|---|---|---|
| `cmd_save:*` | `scripts/cmd_save.sh:131-164,3128` | 個別checkの純オーバーヘッド | check間のみ比較可 |
| `git_pre_commit:affected_tests` | `scripts/hooks/git-pre-commit.sh:273-330` | selection + `run_tests affected`実行本体 | 参考欄 |
| `git_pre_commit:self_sync,test_granularity,yaml_ast,instruction_sync,shell_syntax,sourced_dep,context_metadata,codd_context_freshness,semantic,task_scope,staged_snapshot` | `scripts/hooks/git-pre-commit.sh:19-65` | 個別防御の純オーバーヘッド | check間のみ比較可 |
| `deploy_task:deploy_total` | `scripts/deploy_task.sh:604` | 親total（全配備本体込み） | 子と非加算 |
| `deploy_task:check_yaml_freshness` | `scripts/deploy_task.sh:1690-1697` | 純オーバーヘッド | 比較可 |
| `gate_gunshi_report_precheck:full_precheck` | `scripts/gates/gate_gunshi_report_precheck.sh:13-22` | precheck実行本体込み親total | 子と非加算 |
| `gate_report_format:singleflight_hold` | `scripts/gates/gate_report_format.sh:77-103` | lock取得後からEXITまでのhold | waitではない |
| `heavy_job_admission:queue_wait` | `scripts/heavy_job_admission.sh:200-228` | admission queue wait | overhead標的外 |
| `heavy_job_admission:execution` | `scripts/heavy_job_admission.sh:230-263` | 子job終了までの実行本体 | overhead標的外 |
| `three_layer_health:refresh_window` | `scripts/memory_db_live_insert.py:519-539` | begin=0/end=窓長の混在marker | 集計禁止 |
| `three_layer_health:refresh_copy` | `scripts/memory_db_live_insert.py:394-410` | copy実行本体 | windowと非加算 |
| `three_layer_health:refresh_verify` | `scripts/memory_db_live_insert.py:394-410` | verify実行本体 | windowと非加算 |
| `three_layer_health:cache_rowid_gap` | `scripts/gates/gate_three_layer_health.sh:23-48` | 判定値（時間ではない） | 時間集計禁止 |
| `report_field_set:*` | `scripts/report_field_set.sh:299-317,353-378` | field/batch setter純オーバーヘッド | field単位比較可 |
| `shogun_rca:*`, `*_bench_*`, manual review | 各event_idに固定した診断・実験値 | 参考値/単発実験 | 本番標的母集団外 |

`report_field_set:*` は全check_idが同一writer境界（setter呼出しのwall）なので、
動的field名を個別に意味分類せず同一writer単位で分類した。

## 再集計コマンド

```python
import json, collections, statistics
cutoff = "2026-07-27T11:03:55.717413+00:00"
rows = []
for lineno, line in enumerate(open("logs/defense_overhead.jsonl"), 1):
    d = json.loads(line)
    if lineno <= 39070 and d.get("timestamp", "") <= cutoff:
        rows.append(d)
# source/check_idを上表の境界へ分類し、親total・実行本体・wait/holdを
# pure_overheadから除外。各pairは n/sum/median/p95/max を独立算出する。
```

## 出力生貼付（純オーバーヘッド標的序列）

```text
source|check_id|n|sum_ms|median_ms|p95_ms|max_ms
git_pre_commit|self_sync|819|1699622|758|9503|36639
cmd_save|checks_main|656|1544448|1642|5131|48937
git_pre_commit|test_granularity|819|1045936|2|1364|717213
report_field_set|commit_hash|1771|743930|350|1020|2350
git_pre_commit|yaml_ast|817|690573|303|3293|14860
cmd_save|q11_semantic_search_overhead|153|561177|1|15980|133289
report_field_set|status|538|489360|350|1710|16310
cmd_save|three_layer_memory_ruling_overhead|193|429861|1|13806|32189
git_pre_commit|instruction_sync|776|346329|1|1|91040
report_field_set|files_modified|327|263650|730|1560|3010
cmd_save|checks_pre_session|656|262802|194|1188|4339
cmd_save|memory_db_token_search_overhead|154|191671|83|4580|14256
git_pre_commit|shell_syntax|567|133993|3|1045|4701
deploy_task|check_yaml_freshness|135|88715|209|3128|13062
git_pre_commit|sourced_dep|319|62735|2|1029|2740
git_pre_commit|context_metadata|397|28607|2|305|3216
cmd_save|session_state|656|18164|10|171|508
git_pre_commit|semantic|772|10640|3|67|197
git_pre_commit|task_scope|819|5314|4|13|465
git_pre_commit|codd_context_freshness|776|1988|2|4|472
git_pre_commit|staged_snapshot|819|838|1|1|7
```

## 分離した参考母集団（非加算）

```text
category|n|sum_ms|median_ms|p95_ms|max_ms
queue_wait|749|3546000|0|11000|797000
lock_hold|3232|3259850|450|4410|20260
selection_plus_execution|319|28358709|23843|348427|1303072
execution_body|743|15913000|0|106000|867000
execution_child(copy/verify)|2392|23457266|10815.5|22105|62418
mixed_marker(refresh_window)|3164|52971871|0|83057|320043
parent_total|4093|31773590|1329|40694|314443
```

`refresh_window`の0ms beginとendを同一分布にせず、copy/verifyもwindowへ加算しない。
`affected_tests`は選別だけの計測ではないため純オーバーヘッド順位から外した。
`singleflight_hold`はlock待ちではなく保持時間、`queue_wait`は実行時間ではない。
