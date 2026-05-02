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
deploy_task.shの重複ガードを回避するため、/tmp経由で配備:
```bash
# 1人目のタスクYAMLをベースにrecon2用に調整
cp queue/tasks/<ninja1>.yaml /tmp/recon2_<ninja2>.yaml
# cmd_idを変更（recon2サフィックス）
bash scripts/lib/yaml_field_set.sh /tmp/recon2_<ninja2>.yaml "task" "cmd_id" "<cmd_id>_recon2"
# 正式パスにコピー
cp /tmp/recon2_<ninja2>.yaml queue/tasks/<ninja2>.yaml
# inbox_writeで通知
bash scripts/inbox_write.sh <ninja2> "タスクYAMLを読んで作業開始せよ。" task_assigned karo
```

### Step 4: 陣形図確認
両忍者がin_progressになったことを確認。

## 制約
- 1人目=deploy_task.sh正規フロー、2人目=karo_direct方式。この順序を崩すな
- 2人目のcmd_idは `<cmd_id>_recon2` サフィックス
- 偵察結果の突合は家老が手動で実施（報告YAML受領後）
