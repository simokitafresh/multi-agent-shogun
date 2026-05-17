---
name: idle-persist
argument-hint: "[topic] [summary]"
user-invocable: false
description: |
  【軍師専用】idle自走分析結果をdocs/researchに保存→掲示板投稿→review_log記録の永続化フローを1コマンドで実行。
  ファイル命名規則(gunshi_idle_{topic}_{date}.md)を自動適用し、ブレをゼロにする。
  TRIGGER: /idle-persist、idle分析永続化、分析結果保存、自走分析記録
  DO NOT TRIGGER: レビュー完了処理（→/review-bundle）、gate同期（→/gate-sync）
quality_metric: "当該スキル利用後の軍師review精度（logs/gunshi_review_log.yamlで当該分析由来レビューのgate_prediction==gate_resultとなった割合）"
---

# /idle-persist — idle分析永続化スキル

idle自走分析の結果を標準フローで永続化。命名・投稿・記録のブレをゼロに。

## 引数

`/idle-persist <topic> <summary>`
- topic: 分析トピック（英語snake_case）
- summary: 掲示板投稿用1行サマリ

## 実行フロー

### Step 1: ファイル名生成
```
docs/research/gunshi_idle_<topic>_<YYYYMMDD>.md
```
日付は当日。同名ファイルが存在する場合は末尾に`_2`を付与。

### Step 2: 分析結果をファイルに書出し
分析結果テキストをWrite toolで保存。ヘッダ:
```markdown
# <Topic Title>
<!-- generated: YYYY-MM-DDTHH:MM:SS+09:00 by gunshi idle analysis -->
```

### Step 3: 掲示板投稿
```bash
BULLETIN_NOTIFY=shogun bash scripts/bulletin_write.sh gunshi "<summary>→docs/research/gunshi_idle_<topic>_<date>.md" false info
```
`bulletin_write.sh` の現在仕様:
- 推奨形式は `bash scripts/bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]`。
- `requires_confirmation` は `true|false` または確認必須エージェントのCSV。`BULLETIN_NOTIFY` もCSV指定可能。
- `action_type` は `info` または `action_required`。idle分析の永続化報告は通常 `info`。
- 同一 `posted_by` + 同一 `content` は重複投稿せずDEDUPする。
- 投稿後のinbox通知は掲示板本文全文を含む。`inbox_write` 失敗やwatcher未起動はWARN表示される。

### Step 4: review_log記録
```bash
bash scripts/lib/yaml_field_set.sh logs/gunshi_review_log.yaml "idle_<topic>_<date>" type "idle_analysis"
bash scripts/lib/yaml_field_set.sh logs/gunshi_review_log.yaml "idle_<topic>_<date>" output "docs/research/gunshi_idle_<topic>_<date>.md"
```

### Step 5: 利他還流判断（LG030 gate化）
分析結果が他者(忍者/家老)のlessonsに追加すべき知見を含むか判断する。

判断基準: 「この知見を忍者/家老が知っていれば、将来のWA/BLOCK/再cmdを防げるか？」
- **YES** → `bash scripts/inbox_write.sh karo "{知見1行要約}" gunshi_lesson_candidate gunshi` を送信
- **NO** → review_logエントリの `altruism_check: not_needed` に理由を1行記載

★ このStepを省略するな。利他還流の判断自体が記録される(YES=送信/NO=理由)ことで、LG030「行動完了≠還流完了」を構造的に解消する。

## 制約
- ファイル名は `gunshi_idle_` プレフィックス固定（検索性担保）
- 日付はYYYYMMDD形式（ISO 8601のdate部分）
- 掲示板通知先はデフォルトshogunのみ（全員共有不要な場合）
