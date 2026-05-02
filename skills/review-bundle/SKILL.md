---
name: review-bundle
argument-hint: "[cmd_id] [verdict:APPROVE|FAIL] [fail_reason]"
user-invocable: false
description: |
  【軍師専用】レビュー完了後のSG7バンドル生成→review_log記録→inbox送信を1コマンドで実行。
  precheck結果→報告YAML→判定→バンドルYAML構成→review_log追記→inbox_writeの4ステップ連鎖を自動化。
  TRIGGER: /review-bundle、レビュー完了後処理、SG7バンドル、レビュー記録
  DO NOT TRIGGER: レビュー判定そのもの（→手動）、gate_sync（→/gate-sync）、idle分析永続化（→/idle-persist）
---

# /review-bundle — レビュー完了後処理スキル

レビュー判定後の4ステップ連鎖を1コマンドで実行。フォーマットブレ・転記忘れをゼロにする。

## 引数

`/review-bundle <cmd_id> <verdict: APPROVE|FAIL> [fail_reason]`

## 実行フロー

### Step 1: SG7バンドル生成

レビュー結果をバンドルYAML形式で構成:
```yaml
review:
  cmd_id: <cmd_id>
  verdict: <APPROVE|FAIL>
  reviewer: gunshi
  reviewed_at: <ISO 8601>
  sg_checklist:
    SG1_ac_coverage: <PASS|FAIL>
    SG2_test_pass: <PASS|FAIL>
    SG3_parity: <PASS|FAIL|N/A>
    SG4_no_regression: <PASS|FAIL>
    SG5_lesson_candidate: <PASS|FAIL>
    SG6_code_quality: <PASS|FAIL>
    SG7_gate_prediction: <PASS|FAIL>
  fail_reason: <該当時のみ>
  gate_prediction: <CLEAR|BLOCK>
```

### Step 2: review_log追記
```bash
# gunshi_review_log.yamlに追記
bash scripts/lib/yaml_field_set.sh logs/gunshi_review_log.yaml "<cmd_id>" verdict "<verdict>"
bash scripts/lib/yaml_field_set.sh logs/gunshi_review_log.yaml "<cmd_id>" gate_prediction "<prediction>"
bash scripts/lib/yaml_field_set.sh logs/gunshi_review_log.yaml "<cmd_id>" reviewed_at "<timestamp>"
```

### Step 3: 家老inbox送信
```bash
bash scripts/inbox_write.sh karo "cmd_<cmd_id>レビュー完了。verdict=<verdict>。" review_feedback gunshi
```

### Step 4: 掲示板投稿（FAIL時のみ）
FAIL時は将軍にも共有:
```bash
BULLETIN_NOTIFY=shogun,karo bash scripts/bulletin_write.sh gunshi "cmd_<cmd_id> FAIL — <fail_reason>"
```

## 制約
- verdict判定は軍師の手動判断。このスキルは判定後の記録・送信のみ
- SG7チェックリストの各項目は事前に判定済みであること
- review_logのEdit直接編集禁止（yaml_field_set.sh経由）
