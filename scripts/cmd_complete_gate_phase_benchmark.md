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

## cmd_4383: subphase default durability and self-grade fast path

計測日時: 2026-08-24 07:04–07:06 JST
対象: `cmd_complete_gate.sh` の同一 `cmd_4382` report commit
(`dd41c1a1b431a8a299538c9ec9fcf1b27f59c8be`) と、既存の実task subphase
ログ。検査条件は変更せず、self-grade の対象パス集合をアンカーcommitで先に照合した。

### AC1: サブフェーズ計装の既定化

`CMD_COMPLETE_GATE_SUBPHASE_LOG` 未指定時の出力先を
`logs/cmd_complete_gate_subphases.log` に固定し、粗粒度の
`CMD_COMPLETE_GATE_PHASE_LOG` を明示的に無効化しても独立して記録する構造へ変更した。
サブフェーズログは既存フェーズログと同じ5 MiB上限・初回flockローテーション規律を
維持する。既存の実task fixtureで、実行1回分の4列レコードとローテーションを確認した。

### AC2: self-grade の同条件短縮

変更前の `cmd_4382` 一次ログでは `self_grade_start=11.716s` だった。変更後に
同一report commitのアンカー差分を3回測定した結果は `0.32s / 0.27s / 0.22s`
（中央値 `0.27s`）。中央値比較で `11.716s → 0.27s`、`11.446s`短縮、短縮率
`97.7%`。アンカーcommitで全 `files_modified` を覆えない場合は、従来どおり
全履歴からcmd phase unionを収集するため、検査項目・対象範囲は削除していない。

### AC3: 判定不変性

サブ計装の明示無効化経路と既定有効経路を既存テストで比較し、gateの終了コード・出力を
不変とした。アンカーcommitで不足が出るfixtureは従来のphase unionへフォールバックする。

### AC4: 検証

- `bash -n scripts/cmd_complete_gate.sh`: PASS
- `bash scripts/run_tests.sh file tests/unit/test_cmd_complete_gate.bats`: `273/273 PASS`, `FAIL=0`, `SKIP=0`（receipt `run_tests_20260823T222251_4031591.json`、195.058s）

## cmd_4384: post-source/runtime内部分解・純処理短縮・CI WAIT化

計測日時: 2026-08-24 08:06–08:45 JST。既存本番実測`cmd_4383`を変更前基準とし、同一repo・同一cmd_idで変更後を再実測した。詳細計装は粗粒度`cmd_complete_gate_subphases.log`を変更せず、`CMD_COMPLETE_GATE_DETAIL_LOG`（既定=`logs/cmd_complete_gate_details.log`）へ`timestamp / cmd_id / class / label / seconds`を追記する。`class`は`pure_processing`または`external_wait`の二値である。

### AC1: 主要処理群

| 処理群 | class | 後追い方式 |
|---|---|---|
| `source_publication.push_task_repositories`、`runtime_publish.remote_source_push` / `remote_tip_lookup` / `remote_fetch` | `external_wait` | push実行自体はpublication契約、push-state確認とCI workflow確認はWAITとして後追い並行へ移行 |
| `runtime_publish.tracked_runtime_lock_wait` / `commit_lock_wait` / `index_lock_retry_wait` | `external_wait` | lock/indexの待機は詳細ログへ記録。push-state・CIの確認結果はGATE判定を止めない |
| `post_source_checks.cdp_production_check`、`post_source_checks.durable_writer_wait` | `external_wait` | 詳細ログへ記録し、CI/push結果確認系のGATE blockingから分離 |
| `post_source_checks.report_commit_main_ancestry` / `capture_durable_writer_snapshot` / `capture_rework_event` / `runtime_source_convergence.local_reconcile` / `runtime_publish.local_source_build` | `pure_processing` | 検査項目を削除せず短縮対象 |

CI workflowが非GREENでも`evaluate_ci_readiness_json`は`WAIT: ci_evaluation_external_pending=workflow_result_not_green`を返し、push-state確認欠損も`WAIT`台帳へ記録する。既存のtarget-side local failureは従来どおりBLOCKであり、CI結果の後追い化がローカル検査の削除へ波及しない。

### AC2: 同条件before/after

`discover_terminal_reports_for_cmd(cmd_4383)`の一次実測:

| 条件 | wall seconds | 結果 |
|---|---:|---|
| 変更前（全YAMLをglobして全件PyYAML parse） | `>30.00` | timeout 30秒、`rc=124` |
| 変更後（`rg -l --fixed-strings`候補抽出後、候補だけPyYAML parse） | `12.50` | `rc=0` |

保守的短縮値は`>17.50s`、`>58.3%`。候補外YAMLの意味判定を削除せず、`rg`不在・検索失敗時は従来の全globへfallbackする。変更前の本番基準は`post_source_checks=646.535s`、pregate `runtime_publish=109.662s`。CI/pushの外部確認はWAIT後追いへ移し、移せない理由の記録は殿裁定により不要とした。

### AC3/AC4: 判定不変性・検証

- `bash -n scripts/cmd_complete_gate.sh`: PASS。
- `BATS_CACHE=0 bash scripts/run_tests.sh file tests/unit/test_cmd_complete_gate.bats`: `275/275 PASS`、`FAIL=0`、`SKIP=0`。
- `BATS_CACHE=0 bash scripts/run_tests.sh file tests/unit/test_cmd_complete_gate_ci_readiness.bats`: workflow failure WAIT、push-state WAITの契約を確認。
- `BATS_CACHE=0 bash scripts/run_tests.sh file tests/unit/test_cmd_complete_gate_ci_result_type.bats`: workflow failure WAIT、target failure BLOCKの分離を確認。
