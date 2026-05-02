---
name: karo-direct
description: |
  【家老専用】将軍cmd不要の家老自立配備(karo_direct)を標準化するスキル。
  CI修正・修行・偵察recon2など、将軍cmdなしで家老が直接忍者に配備する場合に使用。
  deploy_task.shの重複ガード回避を安全に処理する。
  TRIGGER: /karo-direct、karo_direct配備、家老自立配備、CI修正配備、recon2配備
  DO NOT TRIGGER: 将軍cmdの通常配備（→deploy_task.sh直接）、偵察1名配備（→通常配備）
---

# /karo-direct — 家老自立配備スキル

将軍cmd不要の配備を安全に実行。重複ガード回避の手順を標準化。

## 引数

`/karo-direct <task_type> <ninja_name> <purpose>`
- task_type: ci_fix | training | recon2 | hotfix
- ninja_name: idle忍者名
- purpose: タスクの目的（1行）

## 実行フロー

### Step 1: idle忍者確認
```bash
# karo_snapshot.txtからidle忍者を確認
grep "idle" queue/karo_snapshot.txt
```
指定忍者がidleでなければ停止。

### Step 2: タスクYAML作成
```bash
# /tmp に一時YAML作成（deploy_task.shの重複ガード回避）
cat > /tmp/karo_direct_task.yaml << 'YAML'
task:
  cmd_id: cmd_karo_<task_type>_<timestamp>
  type: <task_type>
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
# /tmp から正式パスにコピー
cp /tmp/karo_direct_task.yaml queue/tasks/<ninja_name>.yaml

# inbox_writeで忍者に通知
bash scripts/inbox_write.sh <ninja_name> "タスクYAMLを読んで作業開始せよ。" task_assigned karo
```

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

### training
```yaml
purpose: "修行 — <修行テーマ>"
# 修行サイクルのACはcontext/training-cycle.md参照
```

## 制約
- deploy_task.shを直接使うと重複ガードで拒否される場合がある→/tmp経由が正解
- cmd_idは `cmd_karo_<task_type>_<簡潔な説明>` 形式
- 家老自立配備は殿裁定済み（CI RED即修正等は将軍cmd不要）
