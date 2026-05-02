---
name: report-write
argument-hint: "[report_path]"
description: |
  【忍者専用】報告YAML作成を標準化するスキル。report_field_set.sh経由で必須フィールドを記入し、
  Edit tool直接編集によるテンプレート破損・FILL_THIS残存・形式不備を防止する。
  全フィールドをreport_field_set.sh経由で書き込み、gate_report_format.shで事前検証する。
  TRIGGER: /report-write、報告YAML作成、報告記入、報告フィールド記入、FILL_THIS修正
  DO NOT TRIGGER: 報告YAMLの読み取り（→Read tool直接）、verdict判定（→/verdict-check）、commit（→/ninja-commit）
---

# /report-write — 報告YAML作成スキル

報告YAMLの全フィールドをreport_field_set.sh経由で記入する。Edit tool直接編集禁止。

## なぜこのスキルが必要か

- 報告YAML WA 24件/100件(24%) — 全WA最多カテゴリ
- 原因: Edit toolでテンプレートを上書き→必須フィールド巻き添え消去+FILL_THIS残存
- report_field_set.sh経由なら型検証+BLOCK付きで構造が壊れない

## 報告YAML記入手順

### Step 1: 報告パスを確認
```bash
# タスクYAMLから報告パスを取得
report_path="queue/reports/{ninja_name}_report_{cmd_id}.yaml"
```

### Step 2: 必須フィールドを記入（report_field_set.sh経由）

**記入順序を守れ。verdict は最後。**

```bash
REPORT="queue/reports/{ninja_name}_report_{cmd_id}.yaml"

# 1. 基本情報
bash scripts/report_field_set.sh "$REPORT" worker_id "{ninja_name}"
bash scripts/report_field_set.sh "$REPORT" task_id "{task_id}"
bash scripts/report_field_set.sh "$REPORT" parent_cmd "{cmd_id}"
bash scripts/report_field_set.sh "$REPORT" status "completed"
bash scripts/report_field_set.sh "$REPORT" timestamp "$(date -Iseconds)"

# 2. AC検証結果（AC1から順に）
bash scripts/report_field_set.sh "$REPORT" ac_version_read "{ac_hash}"
bash scripts/report_field_set.sh "$REPORT" result.AC1.status "PASS"
bash scripts/report_field_set.sh "$REPORT" result.AC1.evidence "検証方法と結果"

# 3. binary_checks（各ACごと）
bash scripts/report_field_set.sh "$REPORT" "binary_checks.AC1[0].check" "ACの条件"
bash scripts/report_field_set.sh "$REPORT" "binary_checks.AC1[0].result" "yes"

# 4. purpose_validation
bash scripts/report_field_set.sh "$REPORT" purpose_validation "目的に合致"

# 5. files_modified
bash scripts/report_field_set.sh "$REPORT" files_modified "[file1.py, file2.sh]"

# 6. result.summary
bash scripts/report_field_set.sh "$REPORT" result.summary "作業結果の1行要約"

# 7. assumption_invalidation
bash scripts/report_field_set.sh "$REPORT" assumption_invalidation "none"

# 8. lessons_useful（注入済み教訓のうち有用だったもの）
bash scripts/report_field_set.sh "$REPORT" "lessons_useful" "[{id: L123, useful: true, feedback: '具体的に何が役立ったか'}]"

# 9. lesson_candidate（新たな発見）
bash scripts/report_field_set.sh "$REPORT" "lesson_candidate" "{found: false, no_lesson_reason: '既知の手順で完了。新発見なし'}"
# または found: trueの場合:
# bash scripts/report_field_set.sh "$REPORT" "lesson_candidate" "{found: true, title: '発見タイトル', detail: '詳細'}"

# 10. skill_candidate（3回以上同じ手順を実行していたら）
bash scripts/report_field_set.sh "$REPORT" "skill_candidate" "{found: false}"

# 11. decision_candidate（判断が必要な事項）
bash scripts/report_field_set.sh "$REPORT" "decision_candidate" "{found: false}"

# 12. verdict は最後（/verdict-check で自動判定推奨）
bash scripts/report_field_set.sh "$REPORT" verdict "PASS"
```

### Step 3: 事前検証
```bash
bash scripts/gates/gate_report_format.sh "$REPORT"
```
PASS → 家老にinbox_writeで報告完了を通知。
FAIL → FAIL理由を修正してからStep 3を再実行。

## 禁止事項

- **Edit toolで報告YAMLを直接編集するな** — テンプレートフィールド巻き添え消去の原因
- **FILL_THISを残すな** — gate_report_format.shがBLOCKする
- **verdictをbinary_checksより先に書くな** — 不整合の原因(→/verdict-check)
- **lessons_usefulのidにUNKNOWN/null/FILL_THISを書くな** — BLOCK

## フィールド型ルール

| フィールド | 型 | 値 |
|-----------|-----|-----|
| verdict | string | PASS or FAIL のみ |
| binary_checks | list of dicts | [{check: "条件", result: "yes"}] |
| lessons_useful | list of dicts | [{id: "L123", useful: true, feedback: "..."}] |
| lesson_candidate | dict | {found: bool, title/detail or no_lesson_reason} |
| skill_candidate | dict | {found: bool, ...} |
| result.summary | string | 空文字禁止 |

## 注意ポイント


