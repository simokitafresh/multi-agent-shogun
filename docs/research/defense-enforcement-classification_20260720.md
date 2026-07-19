# 防御強制方式・独立防御台帳 — 2026-07-20

## 結論

BLOCK。正規ログID25件は全量分類できたが、ログID未接続77ファイルの内部に複数の「発火条件×作用」が存在する。1ファイル1暫定IDでは対象縮小になるため、独立防御総数102は下限値であり全量値として採用しない。

## 正規ログID母集団

| 集計元 | ID数 | 表示型 | 構造型 | 未分類 |
|---|---:|---:|---:|---:|
| `logs/defense_overhead.jsonl` `(source,check_id)` | 13 | 2 | 11 | 0 |
| `logs/gate_fire_log.yaml` `gate`（check_id相当） | 12 | 3 | 9 | 0 |
| 正規ID合計 | 25 | 5 | 20 | 0 |
| ID未接続ファイルの暫定下限 | 77 | 0 | 0 | 77 |
| 下限合計 | 102 | 5 | 20 | 77 |

正規ID一覧と発火回数:

| check_id | source path:line | 型 | 発火数 | 人手秒/未計測理由 | 作用・二値基準 |
|---|---|---|---:|---|---|
| `deploy_task/deploy_total` | `scripts/deploy_task.sh:4` | 構造型 | 179 | 0（自動） | task配備。event_id一意かつ1 run 1件 |
| `gate_gunshi_report_precheck/full_precheck` | `scripts/gates/gate_gunshi_report_precheck.sh:33` | 構造型 | 790 | 0（自動） | precheck実行・verdict記録 |
| `gate_skill_script_refs/interface_unchanged_manual_review` | `scripts/gates/gate_skill_script_refs.sh:15` | 表示型 | 12 | 0（自動記録、判断時間未計測） | manual review要求→自動差分検証候補 |
| `git_pre_commit/codd_context_freshness` | `scripts/hooks/git-pre-commit.sh:18` | 構造型 | 202 | 0（自動） | commit前強制 |
| `git_pre_commit/instruction_sync` | `scripts/hooks/git-pre-commit.sh:18` | 構造型 | 202 | 0（自動） | commit前強制 |
| `git_pre_commit/self_sync` | `scripts/hooks/git-pre-commit.sh:18` | 構造型 | 202 | 0（自動） | commit前強制 |
| `git_pre_commit/semantic` | `scripts/hooks/git-pre-commit.sh:18` | 構造型 | 198 | 0（自動） | commit前強制 |
| `git_pre_commit/staged_snapshot` | `scripts/hooks/git-pre-commit.sh:18` | 構造型 | 202 | 0（自動） | commit前強制 |
| `git_pre_commit/task_scope` | `scripts/hooks/git-pre-commit.sh:18` | 構造型 | 202 | 0（自動） | commit前強制 |
| `git_pre_commit/test_granularity` | `scripts/hooks/git-pre-commit.sh:18` | 構造型 | 202 | 0（自動） | commit前強制 |
| `git_pre_commit/yaml_ast` | `scripts/hooks/git-pre-commit.sh:18` | 構造型 | 202 | 0（自動） | commit前強制 |
| `karo_startup/skill_refs_roundtrip` | `scripts/gates/gate_karo_startup.sh:25` | 表示型 | 1 | 0（自動記録、判断時間未計測） | ALERT→自動修復候補 |
| `throughput_growth_loop/durable_trigger_missing` | `scripts/ninja_monitor.sh:163` | 構造型 | 1 | 0（自動） | durable trigger欠落をBLOCK |
| `gate:cmd_complete_gate` | `scripts/cmd_complete_gate.sh:16` | 構造型 | 363 | wall_msなし | 後続停止/記録 |
| `gate:cmd_save` | `scripts/cmd_save.sh:14` | 構造型 | 6818 | wall_msなし | 後続停止/記録 |
| `gate:daemon_watchdog_heartbeat` | `logs/gate_fire_log.yaml:1` | 構造型 | 172 | wall_msなし | heartbeat記録 |
| `gate:gate_report_autofix` | `scripts/gates/gate_report_autofix.sh:3` | 構造型 | 533 | wall_msなし | 自動修復 |
| `gate:gate_report_format` | `scripts/gates/gate_report_format.sh:15` | 構造型 | 8053 | wall_msなし | 不正報告を停止 |
| `gate:gunshi_cs_checklist` | `logs/gate_fire_log.yaml:1` | 構造型 | 196 | wall_msなし | checklist強制 |
| `gate:inject_target_path_check` | `logs/gate_fire_log.yaml:1` | 表示型 | 40 | 人手秒未計測 | WARN→存在確認自動化候補 |
| `gate:karo_idle_cycle_fp` | `logs/gate_fire_log.yaml:1` | 構造型 | 1 | wall_msなし | FP契約記録 |
| `gate:memory_db_backup_rotation` | `logs/gate_fire_log.yaml:1` | 構造型 | 63 | wall_msなし | rotation結果記録 |
| `gate:script_speed_record_real` | `logs/gate_fire_log.yaml:1` | 構造型 | 84 | wall_msなし | speed結果記録 |
| `gate:scripts_same_day_history` | `logs/gate_fire_log.yaml:1` | 表示型 | 180 | 人手秒未計測 | WARN→履歴自動統合候補 |
| `gate:skill_script_refs` | `logs/gate_fire_log.yaml:1` | 表示型 | 1793 | 人手秒未計測 | WARN→自動refs更新候補 |

## E1 / E4一次ログquery

| ID | query | 実測 |
|---|---|---|
| E1 | `ci_red_structural_autodeploy` in `gate_fire_log.yaml` | auto_deploy=0、duplicate=0、BLOCK=0。実装sourceは `scripts/ninja_monitor.sh:66,131,169,173`。専用ログ未発火 |
| E4 | `retro|terminal|auto-done|duplicate` in `defense_overhead.jsonl` | retro=6、terminal/auto-done=0、duplicate=0。retro配備計測あり、終端自動記録の専用check_idなし |

## 未解消条件

- `scripts/gates` + `scripts/hooks` は83ファイル。正規IDへ対応した6ファイルを除く77ファイルに暫定ID候補がある。
- 暫定IDをファイル単位にすると、同一ファイル内の複数発火条件・作用を束ねて対象縮小するためAC1不成立。
- 表示型3件に発火数はあるが人手秒は一次ログにないためAC2不成立。
- E1/E4の指定queryは0件を含む実測値を得たが、E4終端記録を示す専用check_idがなく同一ログquery一致を証明できない。

## 品質計測

- false_positive: 正規ID重複0件。
- detector_fp_rate: `0/25 = 0%`（正規ログID母集団のみ。全防御母集団率ではない）。
- 同一query再集計: 正規ID25、表示5、構造20、未分類0で2回一致。
- コード差分0。本台帳のみ更新。

origin: `[[殿裁定_並列全実行_20260720]] -> [[check_id母集団固定]] -> [[未接続防御粒度BLOCK]]`
