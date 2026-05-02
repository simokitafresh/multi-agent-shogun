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
BULLETIN_NOTIFY=shogun bash scripts/bulletin_write.sh gunshi "<summary>→docs/research/gunshi_idle_<topic>_<date>.md"
```

### Step 4: review_log記録
```bash
bash scripts/lib/yaml_field_set.sh logs/gunshi_review_log.yaml "idle_<topic>_<date>" type "idle_analysis"
bash scripts/lib/yaml_field_set.sh logs/gunshi_review_log.yaml "idle_<topic>_<date>" output "docs/research/gunshi_idle_<topic>_<date>.md"
```

## 制約
- ファイル名は `gunshi_idle_` プレフィックス固定（検索性担保）
- 日付はYYYYMMDD形式（ISO 8601のdate部分）
- 掲示板通知先はデフォルトshogunのみ（全員共有不要な場合）
