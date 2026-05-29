---
name: recon-dual
argument-hint: "[cmd_id] [target_scope]"
description: |
  【家老専用】偵察2名配備(recon Pattern 1)を標準化するスキル。
  1人目をdeploy_task.sh、2人目をkaro_direct方式で配備し、重複ガード問題を回避。
  TRIGGER: /recon-dual、偵察2名配備、recon2配備、2名偵察
  DO NOT TRIGGER: 偵察1名配備（→deploy_task.sh直接）、karo_direct単独（→/karo-direct）
quality_metric: "当該スキルで配備した偵察2名タスクのgate通過率（完了時cmd_complete_gate.sh CLEAR割合）"
---

<!-- script_refs_checked_at: 2026-05-29T20:07:36+09:00 -->

# /recon-dual — 偵察2名配備スキル

偵察cmd(type=scout)を2名の忍者に配備。毎回の手順バラつきをゼロに。

## 引数

`/recon-dual <cmd_id> <ninja1> <ninja2>`

## 実行フロー

### Step 1: idle忍者2名確認
```bash
grep "idle" queue/karo_snapshot.txt
```
指定2名がともにidleでなければ停止。

### Step 2: 1人目配備（deploy_task.sh）
```bash
bash scripts/deploy_task.sh <cmd_id> <ninja1> scout
```
deploy_task.shが正規のタスクYAML生成+教訓注入+inbox_writeを実行。

### Step 3: 2人目配備（karo_direct方式）
deploy_task.shの重複ガードを回避するため、/tmp YAMLを作って `--yaml` 経由で配備:
```bash
# 1人目のタスクYAMLをベースにrecon2用に調整（正式task YAMLへ直接cpしない）
cp queue/tasks/<ninja1>.yaml /tmp/recon2_<ninja2>.yaml
bash scripts/lib/yaml_field_set.sh /tmp/recon2_<ninja2>.yaml "task" "parent_cmd" "<cmd_id>_recon2"
bash scripts/lib/yaml_field_set.sh /tmp/recon2_<ninja2>.yaml "task" "cmd_id" "<cmd_id>_recon2"
bash scripts/deploy_task.sh --yaml /tmp/recon2_<ninja2>.yaml <ninja2>
```
`deploy_task.sh --yaml` が stale field reset、注入チェーン、report template生成、safe_inbox_write通知を実行する。手動 `cp` で `queue/tasks/<ninja2>.yaml` を上書きしたり、手動 `inbox_write` で通知したりしない。
`deploy_task.sh` が配備前にpending own report / completed peer reportを検出してBLOCKした場合、報告YAML消失防止が優先である。cmd_complete_gate完了または別idle忍者選定まで、2人目を配備済み扱いにしない。

### Step 4: 陣形図確認
両忍者がin_progressになったことを確認。

## 制約
- 1人目=deploy_task.sh正規フロー、2人目=`deploy_task.sh --yaml` のkaro_direct方式。この順序を崩すな
- 2人目のcmd_idは `<cmd_id>_recon2` サフィックス
- 偵察結果の突合は家老が手動で実施（報告YAML受領後）
- Script refs verified: 2026-05-29 cmd_3091. `deploy_task.sh` はreport templateのbinary_checks注入ログでAC数をawk集計する。ログ精度の変更であり、偵察2名配備の手順変更は不要。2026-05-27 cmd_3062: `deploy_task.sh` は `target_path` / `files_modified` と教訓 `target_files` が一致した場合に `TARGET_PATH_MATCH_BOOST` で関連教訓の注入順位を上げる。注入精度の変更であり、偵察2名配備の手順変更は不要。`deploy_task.sh` は旧task由来の `scope`、`context_hints`、`context` をreset_stale_fieldsで清掃する。cmd_3019のq11_not_already_done再確認WARNとcmd_3020のuniversal lessons target_path関連フィルタは共通配備経路の自動処理で、偵察2名配備の手順変更は不要。`inbox_write.sh` は `from=shogun type=task_new` をBLOCKするため、将軍直送の作業指示経路をこのスキルへ追加しない。cmd_2899: deploy_task.sh target_path存在チェックのproject_path 2段解決追加+yaml_field_set.sh WSL2最適化。cmd_2939: report filename生成でparent_cmd未設定時にcmd_idをフォールバックとして使用。cmd_2944: `_compute_ac_hash` は `description:` なしACでも `check:` / `checks[].check` をフォールバックに使い、偵察/直接配備テンプレート由来ACのハッシュを空にしない。cmd_2951: 配備前pending own report / completed peer reportをBLOCKし、報告YAML消失を防止。cmd_2956: cmd_training_* のparent_cmd nullishをcmd_idから修復。cmd_2957: trainingテンプレートは関連ファイルへの直接[[ファイル名]]リンクとリンク先特定行引用を要求。cmd_2953: training target_pathは `markdown_link_counts.sh --select-file` 優先、未取得時のみ `semantic_alias_quality.sh` へフォールバックする。cmd_2968: report templateのverdictは空値のみを出力し、gate_report_format.shがbinary_checksから自動導出する。
