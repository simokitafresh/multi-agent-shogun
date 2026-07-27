# cmd_4185 外れ値型check発生条件

<!-- cmd: cmd_4185 | measured: 2026-07-27 | cohort: timestamp >= 2026-07-25T02:56:17+00:00 -->

## 結論

`logs/defense_overhead.jsonl` のcurrent cohortを全数再集計した。閾値超過率は共通して `wall_ms > 1000` と定義した。topNは設計判断に使えるようtop1/top5を併記する。

| check | N / 累積 | top1 / top5寄与率 | >1s率 | 発生条件（event実レコード×writer現物） |
|---|---:|---:|---:|---|
| `cmd_save:q11_semantic_search_overhead` | 173 / 672.941s | 19.8% / 74.8% | 18/173=10.4% | **特定**: `command:` が非空、`CMD_QUALITY_FAST_METADATA!=1`、かつセッションキャッシュ未命中時に `show_q11_semantic_search_matches` をbackground起動する。上位は `cmd_4170` 133.289s、`cmd_4169` 110.226s、`cmd_4181` 88.564s、`cmd_4185` 85.968s。 |
| `cmd_save:three_layer_memory_ruling_overhead` | 217 / 472.941s | 6.8% / 26.8% | 56/217=25.8% | **特定**: `CMD_QUALITY_FAST_METADATA!=1` かつquery単位session cache未命中時に三層検索を起動する。writerは `SEMANTIC_MEMORY_DB_TIMEOUT=2`、外側 `timeout -k 1 4`。上位は `cmd_4171` 32.189s/27.733s、`cmd_4178` 23.274s/22.467s/21.128s。同一cmd反復で別query/cache keyが生成される条件が残る。 |
| `git_pre_commit:instruction_sync` | 374 / 160.099s | 56.9% / 93.8% | 7/374=1.9% | **特定**: staged fileが正本 `instructions/*.md`（generated除外）を含む時だけ `build_instructions.sh` とgenerated diff/stageを実行する。`precommit-314006-instruction_sync` 91.040s、`precommit-823523-instruction_sync` 34.039s。他stepは同eventで概ねms級なので条件枝固有。 |
| `git_pre_commit:test_granularity` | 416 / 159.709s | 20.9% / 50.5% | 29/416=7.0% | **部分特定**: 常時呼ばれるが、追加testがある時だけ候補探索へ入り、globに加えて各script参照ごとに `grep -RIlF ... tests/unit` を走査する。最大 `precommit-1015501-test_granularity` 33.394s。同eventの`affected_tests`も443.599sでtest-heavy commitだったことは一致するが、台帳にstaged pathsがなく完全な条件照合は不能。 |
| `git_pre_commit:self_sync` | 416 / 221.997s | 7.3% / 29.4% | 37/416=8.9% | **部分特定**: live installed hook実行時、staged hook関連またはtracked/live hook不一致なら `sync_git_hooks.sh`、hash比較、必要時re-exec。最大 `precommit-494484-self_sync` 16.292sだが同eventには枝選択・staged paths・sync/re-exec有無が記録されず、DrvFS競合との分離は不能。 |

## 外れ値eventの生レコード

```jsonl
{"timestamp":"2026-07-25T04:05:23.279645+00:00","source":"cmd_save","check_id":"q11_semantic_search_overhead","wall_ms":133289,"verdict":"PASS","event_id":"cmd_4170-q11_semantic_search_overhead-931641-1784952323051715"}
{"timestamp":"2026-07-25T04:28:26.155986+00:00","source":"cmd_save","check_id":"three_layer_memory_ruling_overhead","wall_ms":32189,"verdict":"PASS","event_id":"cmd_4171-three_layer_memory_ruling_overhead-1093642-1784953706105911"}
{"timestamp":"2026-07-25T13:06:55.079170+00:00","source":"git_pre_commit","check_id":"instruction_sync","wall_ms":91040,"verdict":"PASS","event_id":"precommit-314006-instruction_sync"}
{"timestamp":"2026-07-25T13:36:08.961710+00:00","source":"git_pre_commit","check_id":"test_granularity","wall_ms":33394,"verdict":"PASS","event_id":"precommit-1015501-test_granularity"}
{"timestamp":"2026-07-27T11:55:09.474214+00:00","source":"git_pre_commit","check_id":"self_sync","wall_ms":16292,"verdict":"PASS","event_id":"precommit-494484-self_sync"}
```

Writer照合: `scripts/cmd_save.sh:4114,5321`、`scripts/hooks/git-pre-commit.sh:131-181,620-690,854,942-957`。

## 是正弾入力

| check | 方向性 | 対象・該当箇所 | 期待削減量の概算根拠 |
|---|---|---|---|
| q11 | キャッシュ＋発火抑止 | `scripts/cmd_save.sh:4095-4115`。command token正規化keyで既存成果物索引をsession共有し、同一token集合は再検索しない | top5だけで503.4s（累積の74.8%）。top5をcache hit化できればcurrent cohort約8.4分削減 |
| three_layer | キャッシュ | `scripts/cmd_save.sh` の `show_three_layer_memory_ruling_info`。title+purpose query正規化とnegative cacheをcmd保存間で共有 | >1s群56件。top5だけで126.8s、まず同一cmd反復のcache miss排除が下限 |
| instruction_sync | 条件の解消 | `scripts/hooks/git-pre-commit.sh:942-957` / `scripts/build_instructions.sh`。正本変更時のみは維持し、buildを入力hash差分生成へ | top2で125.1s、累積の78.1%。2外れ値の差分生成化が主標的 |
| test_granularity | キャッシュ | `scripts/hooks/git-pre-commit.sh:620-690`。staged testから得たscript_ref→既存test候補の逆引き索引を一度生成 | top5 80.7s（50.5%）。追加test枝の全tree反復grepを1索引参照へ置換 |
| self_sync | 追加観測後に条件解消 | `scripts/hooks/git-pre-commit.sh:131-181`。次回台帳へ `running_is_live_hook,staged_hook_related,cmp_equal,sync_called,reexec` を付与 | 現状は枝別寄与を識別不能。最大16.3sを推測で最適化せず、追加5項目でsync枝とfast pathを分離する |

## §3更新用の確定文

- §3-1は「未解決」から、q11=command非空+FAST無効+cache miss、three-layer=FAST無効+query cache miss、instruction_sync=instructions正本staged、test_granularity=追加test時の全tree候補探索（枝内詳細は要観測）へ更新できる。
- §3-2 self_syncは「live hook・staged hook関連/不一致時のsync枝まで部分特定。枝選択5項目の台帳追加後に最適化対象を決める」へ更新できる。
- 常時最適化対象ではなく、q11/three-layerはcache miss、instruction_sync/test_granularityは稀な重い枝だけを対象にする。

