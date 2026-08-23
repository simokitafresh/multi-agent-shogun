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

## cmd_4382: gate_evaluation subphase measurement and reduction

計測日時: 2026-08-24 06:05–06:19 JST
対象: `cmd_complete_gate.sh` の親report-only completion path。判定が完了するまでの
`gate_evaluation` 内部を `CMD_COMPLETE_GATE_SUBPHASE_LOG` で記録した。

### AC1: 実task経路のsubphase内訳

変更前の一次ログ（06:05:46–06:07:54、`gate_evaluation=119.710s`）:

| subphase | seconds |
|---|---:|
| final_checks | 36.308 |
| report_checks | 25.952 |
| self_grade_start | 23.791 |
| review_quality_end | 20.530 |
| gate_checks | 12.117 |

`report_checks` 内の単一 `gate_report_format.sh` 実測は `28.45s`。既存の
`<report>.validated_fingerprints` による同一内容再利用は `0.18s`（PASS）だった。

### AC2: 検査を削らない短縮

fingerprint reuse導入直前の同条件再計測（06:10:20–06:13:14、
`gate_evaluation=157.889s`）では `report_checks=39.651s` だった。変更後の一次ログ
（06:16:40–06:19:18、`gate_evaluation=146.239s`）では、同一reportのfingerprint
再利用により:

| subphase | before | after | delta |
|---|---:|---:|---:|
| report_checks | 39.651 | 0.163 | -39.488s |

単一validatorの同条件比較は `28.45s → 0.18s`、`28.27s`短縮、短縮率
`99.4%`。`gate_report_format.sh` は、現在のreport SHA-256がvalidated cacheに
一致する場合だけreuseし、不一致時は従来の完全検査を実行する。実際のgate判定は
reuse時も `PASS`、変更後はsource publication/runtime publishへ到達し、旧BLOCKの
report_format原因は消失した。後続のpublication failureは未commit変更による別条件で、
gate_evaluation内の検査短縮とは分離される。

### AC3: 判定不変性

`bash scripts/run_tests.sh file tests/unit/test_cmd_complete_gate.bats` は
`273/273 PASS`、`FAIL=0`、`SKIP=0`。ログ有効/無効の既存比較、report format、
実task subphase形状、ローテーションを含む。fingerprint不一致時の完全検査は
コード分岐で維持する。
