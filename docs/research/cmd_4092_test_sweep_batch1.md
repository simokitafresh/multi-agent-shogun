# cmd_4092 テスト在庫sweep 第1弾 — 軍師確認checkpoint

作成: hayate / 2026-07-20
更新: kotaro / 2026-07-24 (cmd_4092再配備による再計測)
対象: `tests/` 全在庫
origin: [[殿裁定_S3二本立て開始_20260720_0005]] -> [[sweep第1弾cmd_4092]] -> [[軍師必須確認checkpoint]]

## §1 二値結論

削除候補は **0件**。削除は未実施。厳格な積集合 `30日FAIL実績なし AND test_necessity等の契約宣言なし AND 他テストとの重複被覆を一次証明` を満たす対象が0件だったため、未知を安全側へ倒した。

軍師確認前に削除しないというAC1の停止条件に従い、本書確定時点で作業を停止する。

## §2 機械抽出 (2026-07-24 再計測)

在庫の変化: B1' (cmd_4093) が1 file削除、B3 (cmd_4095) が20 filesへtest_necessity宣言を追加したため、元の365 files → 159 files(非test_helper)、4,922 cases → 2,418 casesに減少。

一次入力:

| 入力 | 件数 |
|---|---|
| `find tests/ -name "*.bats" -not -path "*/test_helper/*"` | 159 files |
| `find tests/unit/ -name "*.bats"` | 144 files (unit) |
| 総test cases (grep '^@test') | 2,418 cases (unit: 2,329 + その他: 89) |
| `grep -rL "test_necessity" tests/unit/*.bats` | 23 files (契約宣言なし) |
| `grep -rl "test_necessity" tests/unit/*.bats` | 121 files (契約宣言あり) |
| 30日FAIL実績あり (test_timing_ledger.tsv, 2026-06-24以降) | 11 files |
| 30日FAIL実績なし | 505 files (ledger確認分) |
| 契約宣言なし ∩ 30日FAIL実績なし | 23 files |

抽出段階:

| 段階 | 件数 | 判定 |
|---|---:|---|
| 全在庫 (unit .bats) | 144 files | 全件対象。縮小なし |
| 30日FAIL実績あり (timing ledger) | 11 files | 削除候補から除外 |
| 30日FAIL実績なし | 133 files | 条件1: PASS |
| test_necessity等の契約宣言なし | 23 files | 条件1+2の積集合 = **23 files** |
| `@test` 名の跨file一致 (必要条件ファイルとの比較) | 0組 | 名称重複なし |
| production pathを契約testと共有 | 全23 files | scripts/cmd_complete_gate.sh等は共有。ただし script共有 ≠ 同一被覆(下記敵対比較) |
| 他テストとの重複被覆を一次証明 | **0 files** | 全23 fileで同一invariantの重複証明不可 |
| 三条件の厳格積集合 | **0 files / 0 cases** | 削除候補0 |

### 条件2: test_necessity宣言なし 23 files 一覧

| file | tests | 参照主スクリプト | 備考 |
|---|---:|---|---|
| test_cmd_complete_gate_auto_lesson_write.bats | 9 | cmd_complete_gate.sh, lesson_write.sh | auto_lesson_write機能固有 |
| test_cmd_complete_gate_context_freshness_block.bats | 15 | cmd_complete_gate.sh, context_freshness_check.sh | GA-238-242固有 |
| test_cmd_complete_gate_gunshi_verdict_precheck.bats | 14 | cmd_complete_gate.sh | gunshi verdict precheck Python固有 |
| test_cmd_complete_gate_small_consolidated.bats | 4 | (embedded) | DELETED originals含む(sole coverage) |
| test_cmd_complete_gate_subsystems.bats | 30 | cmd_complete_gate.sh | DELETED 3 originals含む(sole coverage) |
| test_cmd_complete_gate_task_idle.bats | 9 | cmd_complete_gate.sh | set_matching_tasks_idle()固有 |
| test_cmd_complete_gate_warning_levels.bats | 34 | cmd_complete_gate.sh | warning level判定ロジック固有 |
| test_cmd_complete_insight_consumption.bats | 5 | cmd_complete_gate.sh, insight_resolve.sh | auto_resolve_cmd_related_insights固有 |
| test_gate_report_format_cmd_3630_env_info.bats | 3 | gate_report_format.sh | cmd_3630 ENV INFO機能固有 |
| test_gate_report_format_lu_warn.bats | 4 | gate_report_format.sh | LU-COMBO WARN機能固有 |
| test_gate_report_format_pass_no_improvement.bats | 15 | gate_report_format_cmd_2072.sh | PASS_NO_IMPROVEMENT機能固有 |
| test_inbox_drain.bats | 3 | inbox_drain.sh | inbox_drain.sh唯一のtester |
| test_ninja_monitor_destructive.bats | 2 | ninja_monitor.sh | check_destructive_commands固有(main testにはなし) |
| test_parity_check.bats | 4 | parity_check.sh | parity_check.sh唯一のtester |
| test_pre_bash_destructive_approval.bats | 4 | pre-bash-combined.sh | D010 git push approval固有(pre_bash_combined.batsは別invariant) |
| test_report_field_set_archive_guard.bats | 4 | report_field_set.sh | archive guard固有 |
| test_report_field_set_bc_validation.bats | 15 | report_field_set.sh | binary_checks型15境界固有 |
| test_report_field_set_completed_immutability.bats | 15 | report_field_set.sh | completed状態不変性固有 |
| test_report_field_set_multiline.bats | 7 | report_field_set.sh | multiline handling固有 |
| test_report_field_set_normalize_hook.bats | 11 | report_field_set.sh | normalize hook固有 |
| test_report_field_set_terminal_readiness.bats | 1 | report_field_set.sh | terminal readiness固有 |
| test_report_field_set_validation.bats | 44 | report_field_set.sh | lessons_useful型バリデーション固有 |
| test_report_field_set_verdict_status.bats | 7 | report_field_set.sh | verdict/status相関固有 |

## §3 候補別 deletion_justification / 被覆根拠

確定候補が0件のため、削除対象別 `deletion_justification` は0/0件、fixture/helper削除も0件。

### 近似候補の敵対比較結果 (全23 files)

| file | 近似被覆 | 敵対比較結論 |
|---|---|---|
| test_cmd_complete_gate_* (7 files) | test_cmd_complete_gate.bats (necessity, 142 tests)と同スクリプト | 各fileは固有feature(auto_lesson_write/GA-238-242/gunshi_precheck/set_matching_tasks_idle/warning_levels等)を対象。main testの142 testsは別invariant群で@test名重複=0件。同一被覆なし |
| test_cmd_complete_gate_small_consolidated.bats | (重複先なし) | 元の test_cmd_complete_gate_auto_failure_lesson / test_cmd_complete_gate_lockingは削除済み。このファイルが唯一の証拠 |
| test_cmd_complete_gate_subsystems.bats | (重複先なし) | 元の 3 filesは削除済み。このファイルが唯一の証拠 |
| test_gate_report_format_* (3 files) | gate_report_format.sh共有 | 各fileは固有機能(ENV INFO/LU-COMBO WARN/PASS_NO_IMPROVEMENT)。main test_gate_report_format.batsは存在しない。被覆は非重複 |
| test_report_field_set_* (8 files) | report_field_set.sh共有、test_report_field_set_batch_throughput.bats(necessity)も同スクリプト | batch_throughputは原子publish/terminal遷移が対象。残8 filesは各々入力型/状態不変性/multiline/normalize等の別invariant。@test名重複=0件。被覆非重複 |
| test_inbox_drain.bats | inbox_mark_read.sh共有 | inbox_drain.shは別スクリプト。drain(全未読一括取得)/mark_read(個別既読化)は異なる操作。被覆非重複 |
| test_ninja_monitor_destructive.bats | ninja_monitor.sh共有 | check_destructive_commandsはmain test_ninja_monitor.bats(necessity, 0 matches for "destructive")に存在しない。被覆非重複 |
| test_parity_check.bats | (重複先なし) | parity_check.sh唯一のtester |
| test_pre_bash_destructive_approval.bats | pre-bash-combined.sh共有 | test_pre_bash_combined.bats(necessity)はbats直実行BLOCK/CDP等を対象。D010 git push approval flowは0 matches。被覆非重複 |
| test_cmd_complete_insight_consumption.bats | insight_resolve.sh/cmd_complete_gate.sh共有 | test_insight_write.bats(necessity)はinsight書込みを対象。auto_resolve_cmd_related_insights(cmd_complete_gate内)の自動消費ロジックは別invariant |

## §4 軍師確認依頼の二値項目

- [x] 在庫全体 (144 unit files / 2,418 cases) を縮小せず全件対象とした
- [x] 30日FAIL実績の判定を timing ledger の status='fail' エントリから直接読んだ(absenceをFAIL0へ誤変換していない)
- [x] 契約宣言付きtest (121 files) を削除候補へ混入していない
- [x] production path共有を意味的重複と誤認していない (@test名重複=0、invariant比較で非重複を確認)
- [x] 候補0件につき削除実走・fixture参照検査・全量after計測へ進まず、本書確定時点で作業を停止する

## §5 次の状態

軍師が候補0件を承認した場合、AC2の削除実走は対象0件のため開始不能。軍師が具体的な重複被覆を一次証拠付きで指摘した場合のみ、確認済みリストを正本へ追記して削除実走へ進む。

なお、S3 §5 B1設計正本は「三条件AND → 候補0 = 誠実FAIL」を想定済み。後続のB1'(cmd_4093、二条件=30日FAIL実績なし∧宣言なし)が1 file削除・1551/1551 PASSで完了しており、三条件B1の結果は設計の意図通り。
