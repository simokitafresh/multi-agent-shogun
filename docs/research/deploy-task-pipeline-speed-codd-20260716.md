# deploy_task 配備パイプライン速度改善 CoDD 設計書

## 対象と不変契約

- 対象: `scripts/deploy_task.sh` のtask mutation終端からreport template/parent contract生成まで。
- 不変: task YAML、report template、lesson/semantic注入、inbox通知の値・順序・BLOCK条件。
- 手法: 同一task YAMLの重複読取だけを `field_get_multi` へ統合する。injector、公開、通知は変更しない。

## Before設計と実測

計測入口: `queue/tasks/hayate.yaml` を入力に、各候補を15回実行。単位ms。p95は昇順15件の第14値。

| 巡 | 区間 | Before p50 | Before p95 | 支配要因 |
|---|---|---:|---:|---|
| 1 | canonical training判定 | 48 | 61 | `parent_cmd` と `task_type` を別々に走査 |
| 2 | report metadata終端読取 | 54 | 61 | 4項目一括後に `report_filename` を再走査 |

## 実装

- 巡1: `parent_cmd task_type` を1回の `field_get_multi` で取得。
- 巡2: 既存の `task_id _ac_task_id parent_cmd project` 一括取得へ `report_filename` を追加。
- `generate_report_template`、`inject_parent_contract`、lesson/semantic injector、`safe_inbox_write` の呼出順序は不変。

## After設計と実測

| 巡 | 区間 | After p50 | After p95 | p50短縮 | p95短縮 |
|---|---|---:|---:|---:|---:|
| 1 | canonical training判定 | 31 | 42 | 17ms (35.4%) | 19ms (31.1%) |
| 2 | report metadata終端読取 | 48 | 52 | 6ms (11.1%) | 9ms (14.8%) |

関連回帰: `test_deploy_task.bats` 1/1 PASS、`test_deploy_task_template_generation.bats` 1/1 PASS。FAIL=0、SKIP=0。`bash -n scripts/deploy_task.sh` PASS。

## 再劣化基準

- 巡1区間: p50 > 48ms または p95 > 61ms で回帰。
- 巡2区間: p50 > 54ms または p95 > 61ms で回帰。
- 静的契約: 終端読取が単独 `field_get` に戻った場合は `deploy mutation final reads batch canonical and report metadata fields` がFAILする。
- 機能契約: L4 post-mutation fixtureがFAIL/SKIP、または生成task/report差分が生じた変更は不採用。

## 因果

`[[deploy-task-pipeline]] -> [[duplicate-yaml-scan]] -> [[field-get-multi-batch]]`

