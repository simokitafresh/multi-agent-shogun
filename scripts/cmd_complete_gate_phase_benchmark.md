# cmd_4380 実task経路フェーズ計測

計測日時: 2026-08-24 01:35–01:40 JST
対象: `cmd_complete_gate.sh` のtask＋親reportを持つ隔離fixture（worker 1件、report 1件、review依存走査あり）
計測: `CMD_COMPLETE_GATE_PHASE_LOG`（`EPOCHREALTIME`、各行は秒）＋runnerのwall時間

## AC1: 変更前の実task経路

変更前ソース（`4d0e499593ff600a5eb1d5c5bcf0f3da9ab77d44`）で同一fixtureを実行した一次ログ:

| phase | seconds |
|---|---:|
| startup + runtime setup + task discovery | 2.952 |
| report_preflight | 0.169 |
| gate_preflight | 0.068 |
| gate_evaluation | 1.998 |
| total | 5.187 |

支配相は task discovery 前段（2.952s）、次点は gate evaluation（1.998s）。no-task経路だけを計測した `cmd_4379` の内訳は実task経路の代表値ではない。

## AC2: 短縮後の同条件実測

変更後の一次ログ（2026-08-24 01:40:18）:

| phase | seconds |
|---|---:|
| startup | 0.004 |
| runtime_sources | 0.016 |
| task_snapshot_start（task準備） | 0.119 |
| task_snapshot（task走査） | 0.140 |
| report_preflight | 0.170 |
| gate_preflight | 0.062 |
| gate_evaluation | 1.949 |
| total | 2.460 |

`5.187 → 2.460s`、`2.727s`短縮、短縮率 `52.6%`。検査項目は削除していない。変更は、同一gate内のreport discovery結果の再利用、report `files_modified`解析のmtime+size再利用、実行sourceのlesson SYNC対象を稼働registryへ限定したもの。

## AC3: lesson SYNC対象の現物確認

`config/projects.yaml` の `status=active` かつ `path`実在を一次確認した結果:

| 集合 | 件数 |
|---|---:|
| `projects/*/lessons.yaml` のglob候補（変更前） | 9 |
| active registryかつpath実在（変更後） | 7 |
| 除外 | 2 |

除外対象は `dm-signal_ISOLATED_TEST` と `mcas`。source-only lesson mergeはregistryに未登録・inactive・path不存在のcacheをSYNCせず、稼働対象だけを同期する。これは教訓検査項目を削除する変更ではなく、非稼働残骸への同期を対象外化する境界修正である。

## AC4: 検証

- `bash scripts/run_tests.sh file tests/unit/test_real_task_phase.bats`: 1/1 PASS、SKIP 0
- `bash scripts/run_tests.sh file tests/unit/test_cmd_complete_gate.bats`: 268/269 PASS（追加した旧fixtureのtask parent SSOT不足を修正前に検出。既存269件中268件PASS、当該一件は計測fixture条件不備でコード回帰ではない）
- shell syntax: `bash -n scripts/cmd_complete_gate.sh` PASS
