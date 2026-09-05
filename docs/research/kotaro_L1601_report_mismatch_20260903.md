# L1601 lessons_useful 補足指示と旧report前提の不一致 (2026-09-03)

## 受領した補足指示
- msg_id: msg_20260903_212443_3670416_21e0312f (家老→小太郎, type: task_supplement, action: fix_old_report)
- 内容: 旧report `queue/reports/kotaro_report_cmd_karo_recon_root_dirty_writer_routes_202609032048.yaml` の related_lessons L1601 について実際の有用性を確認し lessons_useful へ id/useful/reason を記入せよ。gate_report_format PASS 後、旧 parent_cmd の report 再提出を家老へ通知せよ。コード変更なし・現task status変更なし。

## 確認した一次情報
- 旧report `task_contract_snapshot.lesson_set` は `{ids: [], mode: subset}`。つまりこのreportが作られた時点(deploy時)の契約では、related_lessonsは**注入されていない(0件)**。
- `report_field_set.sh` はこの `lesson_set.ids` を正本として `lessons_useful` の許容集合を検証する(subsetモード)。L1601をlessons_usefulへ追加すると `MISMATCH mode=subset missing=none extra=L1601` でBLOCKされ、`status: completed` へ戻せない。
- 一方 `gate_report_format_main.py` の `lessons_useful: empty list` FAILチェック(L1510付近)は、**旧reportの再検証時に現在の `queue/tasks/kotaro.yaml`(＝今のcmd_karo_hotfix_x_url_disclaimer_compose_202609032032用に上書き済みのtask YAML、related_lessons: [L1725])を参照**しており、旧cmd当時のtask実体ではない。そのため「lessons_useful空はNG」という判定が出るが、これは**task YAMLがcmdごとに使い回されて上書きされる構造**由来の誤検出であり、旧reportの実際の契約(lesson_set.ids: [])とは矛盾する。
- L1601自体は infra 教訓としては `ninja_monitor.sh`/`daemon_supervisor.sh` の bounded lock rollover(dead owner/old inode rollback)に関する教訓であり、旧taskの purpose(root常時dirtyの共有writerをfile/function/caller単位で特定しledger route/U1bへの移設境界を確定する)とは対象subsystemが異なる。

## 実施内容
- `lessons_useful` へ L1601 (useful:false, reason記入)を一度追加→`report_field_set.sh` がMISMATCHでBLOCK(status completedへ戻せない)を実測確認。
- 旧reportの正本契約(`task_contract_snapshot.lesson_set.ids: []`)と矛盾するため、**旧reportを元の状態(status: completed, lessons_useful: [])へ復元**した。コード変更・現task(cmd_karo_hotfix_x_url_disclaimer_compose_202609032032)のstatusは無変更。

## 家老への確認依頼
1. L1601が旧cmdへ本当に related_lessons として注入されていたか(deploy_task.shのinjectionログ等の一次証跡)を確認されたい。snapshotが `ids: []` である以上、注入されていなかった可能性が高い。
2. `gate_report_format_main.py` の `lessons_useful` 空リストFAILチェックが、cmdごとに使い回される `queue/tasks/{name}.yaml` の**現在の**related_lessonsを参照してしまう構造(旧reportの再検証時に無関係な最新task内容と衝突する)は、gate側の恒久バグの可能性がある。decision_candidate/lesson_candidateとしての切り出しを提案する。
