---
name: report-write
argument-hint: "[report_path]"
quality_metric: "忍者系: report-write使用後の報告YAML関連WA不発生率(対象報告のうちreport_yaml_format/report_field欠陥なしの割合)"
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


### 自動防止ステップ
- <!-- skill-auto-improve:4915d84e940c --> 自動防止: gate=gate_report_format のTop FAIL理由「assumption_invalidation: missing \"affected_cmds\" field; assumption_invalidation: missing \"detail\" field」(count=1, last=2026-05-02T22:27:16+0900)を避けるため、該当Step完了直後に同条件を確認し、FAILなら次へ進まず修正する。
- <!-- skill-auto-improve:47a7cd7f4343 --> 自動防止: gate=cmd_complete_gate のTop FAIL理由「draft_lessons:1」(count=1, last=2026-05-02T23:59:28+0900)を避けるため、該当Step完了直後に同条件を確認し、FAILなら次へ進まず修正する。
- <!-- skill-auto-improve:8b0229f09993 --> 自動防止: gate=cmd_complete_gate のTop FAIL理由「draft_lessons:2」(count=1, last=2026-05-02T21:57:04+0900)を避けるため、該当Step完了直後に同条件を確認し、FAILなら次へ進まず修正する。

- <!-- skill-auto-improve:8976e9afe4a5 --> 自動防止: gate=gate_report_format のTop FAIL理由「verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")」(count=4, last=2026-05-02T18:54:01+0900)を避ける。確認: verdict が空/None/不正値でないこと、かつ binary_checks 記入後に決めていることを確認する。修正: `/verdict-check` または `report_field_set.sh ... verdict PASS|FAIL` で再導出する。
- <!-- skill-auto-improve:648694597565 --> 自動防止: gate=gate_report_format のTop FAIL理由「lesson_candidate: no_lesson_reason=\"FILL_THIS\" is placeholder (write a real reason); binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文...」(count=2, last=2026-05-02T22:22:28+0900)を避ける。確認: 提出前に対象YAML/本文へ `rg -n 'FILL_THIS'` を実行する / verdict が空/None/不正値でないこと、かつ binary_checks 記入後に決めていることを確認する。修正: 残存箇所を実値または具体的な no_* reason に置換する / `/verdict-check` または `report_field_set.sh ... verdict PASS|FAIL` で再導出する。
- <!-- skill-auto-improve:734212e8bbbd --> 自動防止: gate=gate_report_format のTop FAIL理由「ac_version_read: MISSING; binary_checks: MISSING; files_modified: MISSING; lesson_candidate: MISSING; lessons_useful: MISSING; purpose_validation: MISSING; result.summary: MISSI...」(count=1, last=2026-05-06T00:24:24+0900)を避ける。確認: verdict が空/None/不正値でないこと、かつ binary_checks 記入後に決めていることを確認する / 全 binary_checks の result が yes/no のみで、空欄・waive・PASS・FAIL を含まないことを確認する。修正: `/verdict-check` または `report_field_set.sh ... verdict PASS|FAIL` で再導出する / 各ACの result を yes/no に直し、1つでも no なら verdict を FAIL にする。
- <!-- skill-auto-improve:bb1bffc5e476 --> 自動防止: gate=gate_report_format のTop FAIL理由「assumption_invalidation: is str (must be dict)」(count=1, last=2026-05-02T18:38:56+0900)を避ける。確認: assumption_invalidation に detail と affected_cmds があることを確認する。修正: `report_field_set.sh <report> assumption_invalidation found false` で dict 形式を保証する。
### 必須事前検査
- verdict空文字防止: verdictを書き込む直前に `binary_checks` 全resultが `yes` または `no` で埋まっていることを確認する。空欄、`None`、`null`、`FILL_THIS` が1つでもあれば verdict を書かず、該当ACを `report_field_set.sh` で修正する。
- FILL_THIS残存防止: 家老通知前に `rg -n "FILL_THIS" "$REPORT"` を実行する。1件でも出たら通知禁止。`lesson_candidate.no_lesson_reason`、`lessons_useful.reason`、`files_modified`、`result.summary` などを実値へ置換してから `gate_report_format.sh` を再実行する。
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
- 2026-05-14: gate=gate_report_format result=FAIL executor=kotaro reason=files_modified: MISSING; lessons_useful: MISSING; assumption_invalidation: missing \"affected_cmds\" field; assumption_invalidation: missing \"detail\" field

- 2026-05-12: gate=gate_report_format result=FAIL executor=unknown reason=worker_id: MISSING; parent_cmd: MISSING; ac_version_read: MISSING; binary_checks: MISSING; files_modified: MISSING; lesson_candidate: MISSING; lessons_useful: MISSING; purpose_v...
- 2026-05-11: gate=cmd_complete_gate result=FAIL executor=hayate reason=report_format:kagemaru_report_cmd_2680.yaml

- 2026-05-11: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文字。\"yes\" または \"no\" を記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ; re...
- 2026-05-11: gate=cmd_complete_gate result=FAIL executor=kagemaru reason=report_format:kagemaru_report_cmd_2679.yaml

- 2026-05-11: gate=cmd_complete_gate result=FAIL executor=hayate reason=report_format:kagemaru_report_cmd_2678.yaml
- 2026-05-11: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC3[0].result: 空文字。\"yes\" または \"no\" を記入せよ; ...

- 2026-05-11: gate=gate_report_format result=FAIL executor=unknown reason=purpose_validation: MISSING
- 2026-05-10: gate=gate_report_format result=FAIL executor=unknown reason=binary_checks.result empty

- 2026-05-10: gate=cmd_complete_gate result=FAIL executor=unknown reason=report_format:kagemaru_report_cmd_2656.yaml
- 2026-05-10: gate=gate_report_format result=FAIL executor=unknown reason=lesson_candidate: MISSING; lessons_useful: MISSING; verdict: \"None\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\"); assumption_invalidation: is str (mus...

- 2026-05-10: gate=cmd_complete_gate result=FAIL executor=unknown reason=report_format:kotaro_report_cmd_2637.yaml|report_format:tobisaru_report_cmd_2637.yaml
- 2026-05-10: gate=gate_report_format result=FAIL executor=unknown reason=lesson_candidate: found=false but no no_lesson_reason; binary_checks.description[0].check: \"|-\" が短すぎる(確認内容を具体的に書け); binary_checks.description[0].result: 空文字。\"yes\" または \"no\"...

- 2026-05-10: gate=gate_report_format result=FAIL executor=unknown reason=lesson_candidate: MISSING; lessons_useful: MISSING; verdict: \"None\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\"); assumption_invalidation: MISSING
- 2026-05-10: gate=gate_report_format result=FAIL executor=unknown reason=worker_id: MISSING; parent_cmd: MISSING; ac_version_read: MISSING; files_modified: MISSING; lessons_useful: MISSING; lesson_candidate: is string (must be dict with found/title/d...

- 2026-05-10: gate=gate_report_format result=FAIL executor=unknown reason=lessons_useful[0]: missing \"reason\" field; lessons_useful[1]: missing \"reason\" field; lessons_useful[2]: missing \"reason\" field; verdict: \"None\" is not valid (must be \"...
- 2026-05-10: gate=gate_report_format result=FAIL executor=unknown reason=lesson_candidate: found=false but no no_lesson_reason; binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ; res...

- 2026-05-10: gate=gate_report_format result=FAIL executor=unknown reason=lessons_useful[0]: missing \"reason\" field; verdict: \"None\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\"); assumption_invalidation: is str (must be dict)
- 2026-05-09: gate=gate_report_format result=FAIL executor=unknown reason=assumption_invalidation: missing \"found\" field; assumption_invalidation: missing \"affected_cmds\" field; assumption_invalidation: missing \"detail\" field

- 2026-05-09: gate=gate_report_format result=FAIL executor=unknown reason=assumption_invalidation: MISSING
- 2026-05-09: gate=gate_report_format result=FAIL executor=unknown reason=worker_id: MISSING; parent_cmd: MISSING; ac_version_read: MISSING; binary_checks: MISSING; files_modified: MISSING; lessons_useful: MISSING; lesson_candidate: found=false but no...

- 2026-05-09: gate=gate_report_format result=FAIL executor=unknown reason=lessons_useful: MISSING; lesson_candidate: found=false but no no_lesson_reason; verdict: \"None\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")
- 2026-05-09: gate=gate_report_format result=FAIL executor=unknown reason=lessons_useful: MISSING; assumption_invalidation: missing \"affected_cmds\" field; assumption_invalidation: missing \"detail\" field

- 2026-05-09: gate=gate_report_format result=FAIL executor=unknown reason=self_gate_check: is str (must be dict)
- 2026-05-09: gate=gate_report_format result=FAIL executor=unknown reason=verdict: \"None\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\"); assumption_invalidation: found=true but affected_cmds is empty (影響cmdを列挙せよ); self_gate_c...

- 2026-05-06: gate=gate_report_format result=FAIL executor=unknown reason=ac_version_read: MISSING; binary_checks: MISSING; files_modified: MISSING; lesson_candidate: MISSING; lessons_useful: MISSING; purpose_validation: MISSING; result.summary: MISSI...
- 2026-05-04: gate=cmd_complete_gate result=FAIL executor=unknown reason=missing_gate:lesson|missing_gate:report_merge|hayate:lesson_done_missing

- 2026-05-04: gate=cmd_complete_gate result=FAIL executor=unknown reason=hayate:empty_lessons_useful:related=['L636','L635','L634','L633','L632','L626','L625','L624','L623','L622']
- 2026-05-04: gate=cmd_complete_gate result=FAIL executor=unknown reason=missing_gate:lesson|hayate:lesson_done_missing|draft_lessons:1

- 2026-05-04: gate=cmd_complete_gate result=FAIL executor=unknown reason=hayate:empty_lessons_useful:related=['L636','L635','L634','L633','L632','L626','L625','L624','L623','L622',AC1]
- 2026-05-04: gate=gate_report_format result=FAIL executor=unknown reason=verdict: \"None\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\"); assumption_invalidation: MISSING

- 2026-05-04: gate=cmd_complete_gate result=FAIL executor=unknown reason=missing_gate:lesson|report_format:hayate_report_cmd_2554.yaml|saizo:lesson_done_missing
- 2026-05-04: gate=gate_report_format result=FAIL executor=unknown reason=lessons_useful: MISSING

- 2026-05-04: gate=cmd_complete_gate result=FAIL executor=unknown reason=missing_gate:lesson|saizo:lesson_done_missing
- 2026-05-03: gate=cmd_complete_gate result=FAIL executor=unknown reason=missing_gate:lesson|report_format:tobisaru_report_cmd_2526.yaml|draft_lessons:2

- 2026-05-03: gate=cmd_complete_gate result=FAIL executor=unknown reason=report_format:saizo_report_cmd_2528.yaml|draft_lessons:2
- 2026-05-03: gate=gate_report_format result=FAIL executor=unknown reason=lesson_candidate: no_lesson_reason=\"FILL_THIS\" is placeholder (write a real reason); binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks: AC self-verif...

- 2026-05-02: gate=cmd_complete_gate result=FAIL executor=unknown reason=draft_lessons:1
- 2026-05-02: gate=cmd_complete_gate result=FAIL executor=unknown reason=saizo:empty_lessons_useful:related=['L512','L511','L510','L509','L508','L507','L506','L505','L504','L503']|draft_lessons:2

- 2026-05-02: gate=cmd_complete_gate result=FAIL executor=unknown reason=report_format:saizo_report_cmd_2483.yaml|saizo:empty_lessons_useful:related=['L512','L511','L510','L509','L508','L507','L506','L505','L504','L503']|draft_lessons:1
- 2026-05-02: gate=gate_report_format result=FAIL executor=unknown reason=assumption_invalidation: missing \"affected_cmds\" field; assumption_invalidation: missing \"detail\" field

- 2026-05-02: gate=gate_report_format result=FAIL executor=unknown reason=lesson_candidate: no_lesson_reason=\"FILL_THIS\" is placeholder (write a real reason); binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文...
- 2026-05-02: gate=gate_report_format result=FAIL executor=unknown reason=verdict: \"None\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\"); assumption_invalidation: missing \"affected_cmds\" field

- 2026-05-02: gate=cmd_complete_gate result=FAIL executor=unknown reason=draft_lessons:2
- 2026-05-02: gate=gate_report_format result=FAIL executor=unknown reason=lessons_useful[0]: missing \"reason\" field; lessons_useful[1]: missing \"reason\" field; verdict: \"None\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")...

- 2026-05-02: gate=cmd_complete_gate result=FAIL executor=unknown reason=report_format:saizo_report_cmd_2481.yaml|report_format:tobisaru_report_cmd_2481.yaml|tobisaru:empty_lessons_useful:related=['L512','L511','L510','L509','L508','L507','L506','L50...
- 2026-05-02: gate=gate_report_format result=FAIL executor=unknown reason=files_modified: MISSING; lesson_candidate: MISSING; lessons_useful: MISSING; purpose_validation: MISSING; verdict: \"None\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_N...

- 2026-05-02: gate=gate_report_format result=FAIL executor=unknown reason=lesson_candidate: found=false but no no_lesson_reason; binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; purpose_validation: MISSING; status: \"pending\" はテンプレート初期値。完了後...
- 2026-05-02: gate=gate_report_format result=FAIL executor=unknown reason=files_modified: MISSING; lessons_useful: MISSING; purpose_validation: MISSING; assumption_invalidation: MISSING
