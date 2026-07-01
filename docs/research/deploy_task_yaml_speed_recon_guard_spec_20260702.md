# deploy_task --yaml 高速化 + 偵察重複ガード修正 CoDD Spec

## 問題

`scripts/deploy_task.sh --yaml` は direct YAML を上書きした後も、通常配備と同じ heavy injection を毎回実行している。既に `related_lessons` / `semantic_concepts` / `memory_db_context` 等が注入済みの YAML を再配備する場合、品質を増やさずに数十秒を消費する。

同時に、複数偵察で同一 parent_cmd を別忍者に配る場合、duplicate guard が parent_cmd 一致だけで BLOCK するケースがある。

## 定量プロファイル

実測ソース: `logs/deploy_task.log` 2026-07-02 01:25-01:34。

| 対象 | 開始 | 完了付近 | 総時間 | 主な遅延 |
|---|---:|---:|---:|---|
| hanzo `--yaml` | 01:25:21 | 01:28:33 | 192s | freshness 124s + injection 49s |
| kotaro `--yaml` | 01:29:14 | 01:32:13 | 179s | freshness 111s + injection 53s |
| kagemaru `--yaml` | 01:33:37 | 01:34:47 | 70s | lesson/semantic/memory injection 56s |

Phase 0依存確認: `codd, version 2.19.0`、`bats`、`parallel` すべて存在。

## リファクタリング対象

R1: direct YAML が既注入済みかを構造判定する。

条件: `related_lessons`、`semantic_concepts`、`standard_skills`、`memory_db_context`、`context_hints`、`report_filename` が存在すること。これらが欠ける初回 direct YAML は通常通り注入する。

R2: 既注入済み direct YAML では heavy injection を短絡する。

短絡対象: `inject_task_modifiers`、lesson/semantic/memory/context 系注入、ninja weak points、context freshness 等。維持対象: stale reset、direct YAML syntax repair、parent_cmd/status/task_id 設定、report template生成、inbox通知、deployed_at、preflight gate、draft review。

R3: recon/scout の別忍者並列配備を許可する。

同一忍者 in_progress、pending own report、completed peer report、同一 task_id の二重配備は BLOCK を維持する。

## 制約

- `yaml.dump` / `yaml.safe_dump` で運用YAMLを書き戻さない。
- direct YAML が未注入なら品質低下を避けるため短絡しない。
- report template生成、inbox通知、stale reset は維持する。
- `bash -n scripts/deploy_task.sh` と関連 bats は SKIP=0 PASS を完了条件にする。

## After 設計

実装後の構造:

- `deploy_task_direct_yaml_is_preinjected`: direct YAML の `task` に `related_lessons`、`semantic_concepts`、`standard_skills`、`memory_db_context`、`context_hints`、`report_filename` がある場合だけ既注入済みと判定する。
- `deploy_task_apply_task_mutations`: 既注入済み direct YAML では metadata clear と heavy injection を短絡し、既存注入内容を保持する。
- 維持される処理: stale reset、YAML syntax repair、parent_cmd/status/task_id 設定、report template生成、inbox通知、deployed_at、preflight gate、draft review。
- duplicate guard: `task_type`/`scope_mode` が `recon` または `scout` で peer task_id が異なる場合、active peer を許可する。同一 task_id、同一忍者、pending own report、completed peer report は従来通り BLOCK。
- `check_yaml_freshness`: script pathごとの逐次 `git log` 2回呼出しを廃止し、対象script群に対する1回のbatch `git log` で保守的WARNを出す。

After計測:

| 段階 | 条件 | 時間 |
|---|---|---:|
| Before | kagemaru direct `--yaml` 実ログ | 70s |
| Before | hanzo/kotaro direct `--yaml` 実ログ | 192s / 179s |
| Before | `check_yaml_freshness` 単体 | 59.76s |
| After | `check_yaml_freshness` 単体 | 1s |
| After | preinjected同等fixture全体 | 0.63s |

関連テスト:

- `bash -n scripts/deploy_task.sh`
- `bats tests/unit/test_deploy_task_yaml_injection.bats` → 15/15 PASS, SKIP=0
- `bats tests/unit/test_deploy_task_ac_version.bats tests/unit/test_deploy_task_template_generation.bats` → 65/65 PASS, SKIP=0
