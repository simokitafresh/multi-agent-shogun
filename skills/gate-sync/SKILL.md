---
name: gate-sync
description: |
  【軍師専用】gate CLEAR/BLOCK通知受信時にreview_logのgate_result更新+accuracy即時計算を実行。
  inbox受信→review_log該当エントリ更新→accuracy計算の3ステップを自動化。
  TRIGGER: /gate-sync、gate結果同期、review_log更新、accuracy計算
  DO NOT TRIGGER: レビュー完了処理（→/review-bundle）、idle分析（→/idle-persist）
---

# /gate-sync — gate結果同期スキル

gate CLEAR/BLOCK通知をreview_logに同期し、軍師のgate予測精度を即時計算。

## 引数

`/gate-sync <cmd_id> <gate_result: CLEAR|BLOCK>`

## 実行フロー

### Step 1: review_log更新
```bash
bash scripts/lib/yaml_field_set.sh logs/gunshi_review_log.yaml "<cmd_id>" gate_result "<gate_result>"
bash scripts/lib/yaml_field_set.sh logs/gunshi_review_log.yaml "<cmd_id>" gate_synced_at "<ISO 8601>"
```

### Step 2: accuracy計算
```bash
# review_logの全エントリでgate_prediction vs gate_resultを突合
python3 -c "
import yaml
with open('logs/gunshi_review_log.yaml') as f:
    data = yaml.safe_load(f)
entries = [e for e in data.get('reviews', []) if e.get('gate_prediction') and e.get('gate_result')]
correct = sum(1 for e in entries if e['gate_prediction'] == e['gate_result'])
total = len(entries)
print(f'Accuracy: {correct}/{total} ({correct*100//total if total else 0}%)')
# 直近10件
recent = entries[-10:]
rc = sum(1 for e in recent if e['gate_prediction'] == e['gate_result'])
print(f'Recent 10: {rc}/{len(recent)} ({rc*100//len(recent) if recent else 0}%)')
"
```

### Step 3: 掲示板投稿（精度低下時のみ）
直近10件のaccuracyが70%未満の場合:
```bash
BULLETIN_NOTIFY=shogun bash scripts/bulletin_write.sh gunshi "gate予測精度低下: <accuracy>%。要因分析必要"
```

## 制約
- review_logのEdit直接編集禁止（yaml_field_set.sh経由）
- accuracy計算はreview_logのgate_prediction+gate_result両方存在するエントリのみ
- gate_sync.shが一括処理する場合と競合しない（yaml_field_set.shのflock排他）
