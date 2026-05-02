---
name: cmd-complete
description: |
  【家老専用】cmd GATE CLEAR後の完了処理を1コマンドで実行するスキル。
  lesson review→cmd_complete_gate→品質記録→status completed→archive→dashboard→ntfyの全ステップを順序保証で実行。
  TRIGGER: /cmd-complete、GATE CLEAR後処理、cmd完了処理
  DO NOT TRIGGER: dashboard単独更新（→/dashboard-update）、lesson-sort（→将軍スキル）、cmd起票（→将軍）
---

# /cmd-complete — cmd完了処理スキル

GATE CLEAR後の5-7ステップを順序保証で1コマンド実行。ステップ抜け=ゼロ。

## 引数

`/cmd-complete <cmd_id>` — 完了処理するcmd IDを指定

## 実行フロー（順序厳守）

### Step 1: lesson review
```bash
bash scripts/lesson_review.sh
```
draft教訓があればconfirm/edit/delete。なければスキップ。

### Step 2: workaroundログ（該当時のみ）
cmd処理中にworkaround（忍者報告の手動修正等）があった場合:
```bash
bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> "<修正内容>" "<修正方法>"
```
なければスキップ。

### Step 3: cmd_complete_gate
```bash
bash scripts/gates/cmd_complete_gate.sh <cmd_id>
```
GATE CLEAR → Step 4へ。BLOCK → 停止。BLOCK理由を報告。

### Step 4: cmd品質記録
```bash
bash scripts/cmd_quality_log.sh <cmd_id> <gate_result> <karo_rework:yes/no> <supplementary_cmds:数値>
```

### Step 5: status → completed
```bash
bash scripts/lib/yaml_field_set.sh queue/shogun_to_karo.yaml "<cmd_id>" status completed
```

### Step 6: dashboard更新
`/dashboard-update` スキルを実行。

### Step 7: ntfy送信
```bash
bash scripts/ntfy_cmd.sh <cmd_id> "完了"
```

### Step 8: inbox archive
```bash
bash scripts/inbox_archive.sh karo
```

## BLOCK時の手順
- Step 3でBLOCK → BLOCK理由を確認し修正。修正後Step 3から再実行
- 新しいinbox nudgeが来ても上記Step 1-8を先に完了する（CTX膨張防止）

## 制約
- archive_completed.shはGATE CLEAR時に自動実行されるため手動不要
- 順序を崩すな（§8ルール）
