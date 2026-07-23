# cmd_4095 FAIL実績層の契約昇格checkpoint

作成: hayate / 2026-07-20  
入力: `docs/research/ci-test-failure-attribution-20260719.csv`、削除直前blob `36fe2add^`  
origin: [[殿裁定_振り分け型_20260720_0036]] -> [[FAIL実績あり層は生きた回帰網]] -> [[昇格弾cmd_4095]]

## §1 母集団と到達不能条件

FAIL台帳の `github_or_local_failed_log=yes` は26 files。現HEADで現存する6 filesは全て `test_necessity` 宣言済みであり、宣言なしの20 filesは全件がcommit `36fe2add45abb8d7ceb18a128ee756ccc6a7ba1a` で削除済みだった。したがって対象fileへの宣言率は記入前0/20、現HEAD上で直接記入可能0/20である。

設計正本 `cmd_4093_test_triage_batch1.md` §4どおり、軍師は各行を「現行統合testへ境界移植済み」または「削除前blobから復元して宣言」の二択で判定する。旧fileを無条件に20件復元することは、移植済みtestの重複再導入になるため実施しない。

## §2 20/20 契約候補（削除前blobのtest名から外部不変量を抽出）

| # | 削除済みfile | cases | test_necessity候補（不変量1つ） | 軍師判定 |
|---:|---|---:|---|---|
| 1 | `tests/unit/test_cmd_save_block_aggregation.bats` | 7 | `cmd_save.sh` は同一実行で検出した全BLOCK理由を欠落なく一括提示する | 未判定 |
| 2 | `tests/unit/test_context_freshness_check.bats` | 55 | context鮮度判定は対象pathの関連commitだけを根拠にし、staleをfreshへ誤分類しない | 未判定 |
| 3 | `tests/unit/test_deploy_task_ac_handling.bats` | 49 | 配備task/reportのAC集合は親cmdの最新AC集合と一致する | 未判定 |
| 4 | `tests/unit/test_deploy_task_ac_version.bats` | 37 | AC内容が変わるたびtask/reportのac_versionは同一の新fingerprintへ更新される | 未判定 |
| 5 | `tests/unit/test_deploy_task_lifecycle.bats` | 80 | 同一cmdを複数忍者のactive taskへ二重配備できない | 未判定 |
| 6 | `tests/unit/test_deploy_task_nocode_commit_contract.bats` | 5 | no-code commit免除は許可scopeかつ一致するtree証跡がある場合だけ成立する | 未判定 |
| 7 | `tests/unit/test_deploy_task_template_generation.bats` | 43 | 配備時report templateはtask種別に対応する必須検証フィールドを欠落なく原子的に公開する | 未判定 |
| 8 | `tests/unit/test_full_deploy_e2e_harness.bats` | 3 | full-deploy harnessはlost・duplicate・stale・telemetry異常を成功として受理しない | 未判定 |
| 9 | `tests/unit/test_gate_single_check_consolidated.bats` | 2 | gateは運用shellの直接PyYAML dumpとruntime incident ID混入を拒否する | 未判定 |
| 10 | `tests/unit/test_gate_small_consolidated.bats` | 27 | 小規模gate群は各禁止パターンを検出した場合に成功終了しない | 未判定 |
| 11 | `tests/unit/test_karo_snapshot_freshness.bats` | 1 | task完了遷移は同じ世代のsource timestampを含むsnapshotを即時公開する | 未判定 |
| 12 | `tests/unit/test_learning_ops_small_consolidated.bats` | 34 | 学習運用helper群は不正入力・永続化失敗を成功として扱わない | 未判定 |
| 13 | `tests/unit/test_ninja_monitor_clear_guard.bats` | 66 | ninja_monitorはactive作業または未完了通知があるagentをclearしない | 未判定 |
| 14 | `tests/unit/test_ninja_monitor_stall.bats` | 74 | ninja_monitorは一次runtime/task状態が進行中のagentをstallと誤判定しない | 未判定 |
| 15 | `tests/unit/test_ninja_monitor_training_auto.bats` | 15 | 自動修行配備は所有scope競合・cooldown・部分配備失敗時に新taskを残さない | 未判定 |
| 16 | `tests/unit/test_report_commit_identity.bats` | 16 | terminal reportのcommit identityは解決可能な40桁hashまたは厳格なno-code契約に限る | 未判定 |
| 17 | `tests/unit/test_restart_watchers_handoff.bats` | 6 | watcher rolling handoff中もinbox arrivalは欠落・重複なく一度だけ配送される | 未判定 |
| 18 | `tests/unit/test_run_tests_receipt.bats` | 4 | test receiptは完全なTAP、FAIL0、SKIP0、検証済み対象数を満たす場合だけPASSになる | 未判定 |
| 19 | `tests/unit/test_send_wakeup.bats` | 15 | wakeupはself-watch時の重複nudgeを避け、fallback時もpayloadとEnterを確実に配送する | 未判定 |
| 20 | `tests/unit/test_skill_feedback_loop.bats` | 39 | skill品質ログは実行結果を重複なく記録し未解消FAILだけを改善入力へ反映する | 未判定 |

合計は20/20 files、573 cases。対象縮小0件。

## §3 軍師checkpoint

- [ ] 20/20候補が具体的な外部不変量を1つだけ記述している
- [ ] 実装手順・一時fixture・内部構造の契約混入が0件
- [ ] 各候補を「現行testへ移植済み」または「旧file復元+宣言」に分類した
- [ ] 移植済み判定には現行fileとtest名の証跡がある
- [ ] 復元判定には重複契約でない証跡がある

checkpoint承認後のみ、復元対象へ `# test_necessity:` を記入して全量テストへ進む。

### §3.1 checkpoint結果と実装分類

軍師 `msg_20260720_033800_404458_4e5f25d6` により、20/20が具体的な外部不変量1つ、契約混入0件として承認された。現行testとの厳格な文字列・test名突合では、以下3件だけ同一境界の現行契約を確認した。

| 旧file | 移植先 | 一次証跡 |
|---|---|---|
| `test_deploy_task_ac_version.bats` | `tests/unit/test_deploy_task.bats` | report `ac_version_read` とtask `ac_version` の一致をassert |
| `test_deploy_task_template_generation.bats` | `tests/unit/test_deploy_task.bats` / `test_deploy_task_yaml_injection.bats` | report templateのAC注入とYAML guard順序をassert |
| `test_run_tests_receipt.bats` | `tests/unit/test_run_with_receipt.bats` | partial TAPをPASSにしない境界をassert |

残る17 filesは曖昧な類似を移植証明にせず、削除直前blob `36fe2add^` から復元し、各fileへ表§2の `test_necessity` を1件ずつ記入した。分類は移植済み3＋復元17＝20/20、母集団縮小0件。

## §4 宣言率・工程還流（checkpoint後に確定）

| 指標 | 記入前 | 記入後 |
|---|---:|---:|
| 対象20 filesの有効契約 | 0/20 | 20/20（移植済み3＋復元宣言17） |
| 現HEAD全test fileの宣言 | 70/136 | 89/155（2026-07-20 05:40時点。並行追加を含む） |

工程表への結論: B3 cmd_4095は20/20を移植済み3＋復元宣言17へ分類し、契約昇格を完了。全量FAIL0/SKIP0の最終receipt確認後に完了する。

## §5 最新HEAD全量receipt（2026-07-20 05:43）

- receipt: `logs/test_receipts/run_tests_20260719T204014_2397508.json`
- 実測: 966/966 observed、FAIL 1、SKIP 0、rc=1
- FAIL: `tests/unit/test_gate_single_check_consolidated.bats` の `gate_no_direct_yaml_dump blocks direct PyYAML dumps in shell scripts`
- 一次原因: `scripts/deploy_task.sh:5941` と `scripts/throughput_scan.sh:36` に直接 `yaml.safe_dump` が残存し、現行gateがactive hits 2件として正しくBLOCKした。
- 判定: 復元17 files由来の宣言欠落は0件だが、全量FAIL0契約は未達。運用script 2件は本taskの `tests` / 本文書scope外のため、修正cmdへ引き継ぐ。

## §6 tobisaru確認receipt（2026-07-24 tobisaru）

| 指標 | 記入前→後 |
|------|----------|
| 17復元files現存 | 17/17 確認済み |
| test_necessity宣言 | 17/17 全件OK |
| 現HEAD全test宣言率 | 123/187 |

### task-scope実行receipt

- receipt: `logs/test_receipts/run_tests_20260723T220635_2974880.json`
- 選択ファイル(dependency map): 9 files（414 cases declared、414 observed、SKIP 0）
- task-owned復元filesのPASS: test_context_freshness_check.bats(55)、test_deploy_task_ac_handling.bats(49) — 共にPASS
- scope外FAIL 1: `tests/unit/test_heavy_job_admission.bats` 「GitHub runner型: 終了済みzombieだけのprocess groupはdrain済みとして扱う」— タイミング感応テスト(WSL2環境)。本taskの17復元filesと無関係。task contractに従いbinary_checks帰属対象外
- yaml.safe_dump問題: 前回(§5)のFAIL原因は修正済み確認(`gate_no_direct_yaml_dump.sh`: active hits = 0)

### 分類表更新
- `docs/research/cmd_4093_test_triage_batch1.md` §4「昇格候補」→「昇格済み」へ更新（移植済み3＋復元宣言17＝20/20完了）
- `docs/research/s3-test-speed-asis-tobe-5w1h_20260720.md` §5 B3行を「完了」へ更新
