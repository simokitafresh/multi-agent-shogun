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

### Step 4: 陣形図確認
両忍者がin_progressになったことを確認。

## 制約
- 1人目=deploy_task.sh正規フロー、2人目=`deploy_task.sh --yaml` のkaro_direct方式。この順序を崩すな
- 2人目のcmd_idは `<cmd_id>_recon2` サフィックス
- 偵察結果の突合は家老が手動で実施（報告YAML受領後）
- Script refs verified: 2026-05-19 cmd_2883. `deploy_task.sh` は旧task由来の `scope`、`context_hints`、`context` をreset_stale_fieldsで清掃する。`inbox_write.sh` は `from=shogun type=task_new` をBLOCKするため、将軍直送の作業指示経路をこのスキルへ追加しない。
