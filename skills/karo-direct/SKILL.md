---
name: karo-direct
argument-hint: "[task_id] [ninja_name] [reason]"
description: |
  【家老専用】将軍cmd不要の家老自立配備(karo_direct)を標準化するスキル。
  CI修正・修行・偵察2人目など、将軍cmdなしで家老が直接忍者に配備する場合に使用。
  deploy_task.shの重複ガード回避を安全に処理する。
  TRIGGER: /karo-direct、karo_direct配備、家老自立配備、CI修正配備
  DO NOT TRIGGER: 将軍cmdの通常配備（→deploy_task.sh直接）、偵察1名配備（→通常配備）
quality_metric: "当該スキルで配備したkaro_directタスクのgate通過率（完了時cmd_complete_gate.sh CLEAR割合）"
---

# /karo-direct — 家老自立配備スキル

将軍cmd不要の配備を安全に実行。重複ガード回避の手順を標準化。

## 引数

`/karo-direct <task_type> <ninja_name> <purpose>`
- task_type: ci_fix | training | recon2 | hotfix
- ninja_name: idle忍者名
- purpose: タスクの目的（1行）

内部で使う `deploy_task.sh` は次の2系統:
- `bash scripts/deploy_task.sh --yaml <yaml_file> <ninja_name>`: ci_fix/recon2/hotfix用。YAML内の `parent_cmd:` を `CMD_ID` として自動取得する。
- `bash scripts/deploy_task.sh --direct <ninja_name> <cmd_id>`: training用。`cmd_id` は `cmd_training_...` 形式にする。

## 実行フロー

### Step 1: idle忍者確認
```bash
# karo_snapshot.txtからidle忍者を確認
grep "idle" queue/karo_snapshot.txt
```
指定忍者がidleでなければ停止。

### Step 2: タスクYAML作成（ci_fix/recon2/hotfix）
```bash
# /tmp に一時YAML作成（deploy_task.shの重複ガード回避）
cat > /tmp/karo_direct_task.yaml << 'YAML'
task:
  parent_cmd: cmd_karo_<task_type>_<timestamp>
  task_type: <task_type>
  project: <project>
  purpose: <purpose>
  acceptance_criteria:
    AC1:
      description: "<AC内容>"
  status: assigned
YAML
```

### Step 3: タスク配備
```bash
# /tmp から deploy_task.sh --yaml 経由で配備する。
# --yaml は <yaml_file> <ninja_name> の順。parent_cmdはYAMLから自動取得される。
# deploy_task.sh は共通経路で reset_stale_fields を実行し、旧task YAMLの残留フィールドを清掃する。
bash scripts/deploy_task.sh --yaml /tmp/karo_direct_task.yaml <ninja_name>

# deploy_task.sh は direct_mode として resolve_cmd_to_task をスキップし、
# parent_cmd/task_id/status を設定してから inbox_write を自動送信する。
# 手動 inbox_write は不要。
```
Script refs verified: 2026-05-16 cmd_2799.

### Step 4: 陣形図更新
karo_snapshot.txtの該当忍者行を更新（ninja_monitorが自動検知）。

## task_type別テンプレート

### ci_fix
```yaml
purpose: "CI RED修正 — <テスト名/エラー内容>"
acceptance_criteria:
  AC1: {description: "該当テストがPASS"}
  AC2: {description: "既存テストにリグレッションなし"}
```

### recon2
```yaml
purpose: "偵察補完 — <1人目の偵察結果を受けた追加調査>"
acceptance_criteria:
  AC1: {description: "1人目の偵察結果と突合し差異を明記"}
  AC2: {description: "修正対象ファイル・行番号・波及先を明記"}
```

### training（必ず deploy_task.sh --direct を使え）
```bash
# ★ training だけは /tmp 手動YAML禁止。deploy_task.sh --direct が修行テンプレート(purpose/AC)を自動注入する。
# cmd_id は cmd_training_L4_r<round>_<ninja_name> 形式など、cmd_training_ で始める。
bash scripts/deploy_task.sh --direct <ninja_name> cmd_training_L4_r<round>_<ninja_name>
# --direct は parent_cmd/task_id/status を自動設定し、cmd_training_* なら inject_direct_training_template が
# purpose/ACを自動注入する。inbox_write は deploy_task.sh 内部で自動送信されるため不要。
```
手動でpurpose/ACを書いてはならない。inject_direct_training_template が自動注入する。

## 制約
- training タイプは deploy_task.sh --direct を使え。/tmp 手動YAML方式は AC 未注入を引き起こす（cmd_training_L4_r16 事故実証済み）
- ci_fix/recon2/hotfix タイプは `/tmp` に一時YAMLを作り、必ず `bash scripts/deploy_task.sh --yaml /tmp/karo_direct_task.yaml <ninja_name>` で配備する。直接 `cp` 禁止（stale field reset、parent_cmd/task_id/status設定、inbox通知を迂回するため）
- `/tmp` YAMLには `parent_cmd: cmd_karo_<task_type>_<簡潔な説明>` を入れる。`--yaml` はこの値を配備cmdとして読む。
- 家老自立配備は殿裁定済み（CI RED即修正等は将軍cmd不要）
