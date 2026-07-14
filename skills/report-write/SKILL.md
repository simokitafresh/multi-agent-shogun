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

<!-- script_refs_checked_at: 2026-07-15T03:25:00+09:00 -->
<!-- cmd_3948検分: report_field_set.sh直近差分はsummary placeholder入口BLOCK。field-set CLI・型契約不変。 -->
<!-- 検分: report_field_set.sh cd0411247dはresult.summaryの空値/FILL_THISを入口でfail-closed BLOCK。既存のCLI引数、stdin YAML、binary_checks→verdict自動導出、呼出順序は不変 -->

Script refs verified: 2026-07-13 将軍検分. `report_field_set.sh` checked_at以降の変更(08f9440fb/69ace96dc/5dfec6b28)をgit showで確認。completed/done報告の内容変更fail-closed BLOCK+normalize_report異常終了時のbyte不変中断=内部堅牢化。`bash scripts/report_field_set.sh "$REPORT" <field> <value>`契約・stdin YAML・verdict自動導出は不変。手順書き換え不要。
<!-- 検分: report_field_set.sh b86ddd6f5。active report欠落かつ同basenameのarchive存在時は残骸YAML再生成をBLOCKする契約へ変更。通常はtask YAMLの現行report_pathを使い、archive済み報告を更新する場合だけcanonical archive pathを明示する -->

Script refs verified: 2026-07-08 cmd_karo_hotfix_skill_refs_202607081021. `report_field_set.sh` checked_at以降の変更(edb26ea1)をgit showで確認。`verified_existing_dependency`フィールド(list of {path, reason, checked_not_modified: true}、既存依存を参照のみで確認しLG037照合から除外する宣言)に型/必須値BLOCKバリデーションを新規追加。書込み例: `echo '- {path: scripts/foo.sh, reason: "既存依存として参照のみ", checked_not_modified: true}' | bash scripts/report_field_set.sh "$REPORT" verified_existing_dependency -`。既存の`bash scripts/report_field_set.sh "$REPORT" <field> <value>`契約、stdin YAML、lessons_useful保護、binary_checks yes/no、verdict自動導出前提には影響なし。Step 2の必須フィールド手順自体の書き換えは不要(このフィールドは該当時のみ任意記入)。

Script refs verified: 2026-07-07 cmd_3743. `report_field_set.sh` checked_at以降の変更はgit log上なし、mtimeのみ22:12:18へ更新されていることを確認。現行契約 `bash scripts/report_field_set.sh "$REPORT" <field> <value>`、stdin YAML、lessons_useful保護、binary_checks yes/no、verdict自動導出前提は変更なし。報告YAML記入手順は現行仕様と一致。

Script refs verified: 2026-07-02 cmd_karo_hotfix_skill_script_refs_202607021234. 対象scriptの2026-07-02T01:12以降差分をgit log/showで確認。直近変更は速度改善・内部検査強化・テンプレート修復・files_modified path guardで、各SKILL本文の呼び出し契約は維持。

Script refs verified: 2026-07-02 cmd_karo_hotfix_shogun_startup_memory_skill_refs_20260702010546. `report_field_set.sh` 直近変更(281349be)はresult系書込み高速化で、`bash scripts/report_field_set.sh "$REPORT" <field> <value>`、stdin YAML、verdict自動導出前提の契約は変更なし。報告YAML記入手順は現行と矛盾なし。

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

- <!-- skill-auto-improve:8976e9afe4a5 --> 自動防止: gate=gate_report_format のTop FAIL理由「verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")」(count=4, last=2026-05-02T18:54:01+0900)を避ける。確認: binary_checks 全resultが yes/no で埋まっていることを確認する。修正: binary_checks を修正して `gate_report_format.sh` を再実行し、verdict を自動導出させる。
- <!-- skill-auto-improve:648694597565 --> 自動防止: gate=gate_report_format のTop FAIL理由「lesson_candidate: no_lesson_reason=\"FILL_THIS\" is placeholder (write a real reason); binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文...」(count=2, last=2026-05-02T22:22:28+0900)を避ける。確認: 提出前に対象YAML/本文へ `rg -n 'FILL_THIS'` を実行する / binary_checks 全resultが yes/no で埋まっていることを確認する。修正: 残存箇所を実値または具体的な no_* reason に置換する / binary_checks を修正して `gate_report_format.sh` を再実行し、verdict を自動導出させる。
- <!-- skill-auto-improve:734212e8bbbd --> 自動防止: gate=gate_report_format のTop FAIL理由「ac_version_read: MISSING; binary_checks: MISSING; files_modified: MISSING; lesson_candidate: MISSING; lessons_useful: MISSING; purpose_validation: MISSING; result.summary: MISSI...」(count=1, last=2026-05-06T00:24:24+0900)を避ける。確認: 全 binary_checks の result が yes/no のみで、空欄・waive・PASS・FAIL を含まないことを確認する。修正: 各ACの result を yes/no に直し、`gate_report_format.sh` で verdict を自動導出させる。
- <!-- skill-auto-improve:bb1bffc5e476 --> 自動防止: gate=gate_report_format のTop FAIL理由「assumption_invalidation: is str (must be dict)」(count=1, last=2026-05-02T18:38:56+0900)を避ける。確認: assumption_invalidation に detail と affected_cmds があることを確認する。修正: `report_field_set.sh <report> assumption_invalidation found false` で dict 形式を保証する。
- <!-- skill-auto-improve:a693dd5bd951 --> 自動防止: gate=cmd_complete_gate のTop FAIL理由「missing_gate:lesson|<ninja>:lesson_done_missing」(count=2, last=2026-05-05T01:02:40+0900)を避ける。確認: FAIL理由に出たフィールド名を報告YAML上で `rg -n '<field>' <report>` で検索する。修正: 欠落フィールドを `report_field_set.sh` 経由で追加する。
### 必須事前検査
- verdict自動導出: 忍者は verdict を手動記入禁止。`binary_checks` 全resultを `yes` または `no` で埋め、`gate_report_format.sh` に verdict を自動導出させる。空欄、`None`、`null`、`FILL_THIS` が1つでもあれば該当ACを `report_field_set.sh` で修正する。
- FILL_THIS残存防止: 家老通知前に `rg -n "FILL_THIS" "$REPORT"` を実行する。1件でも出たら通知禁止。`lesson_candidate.no_lesson_reason`、`lessons_useful.reason`、`files_modified`、`result.summary` などを実値へ置換してから `gate_report_format.sh` を再実行する。
- フィールド未記入pre-flight: `gate_report_format.sh` 前に下記を実行し、`MISSING` または `BAD_BC` が1件でも出たら通知禁止。該当フィールドを `report_field_set.sh` で埋めてから再実行する。

```bash
python3 - "$REPORT" <<'PY'
import sys, yaml
path = sys.argv[1]
data = yaml.safe_load(open(path)) or {}
required = [
    ('worker_id', data.get('worker_id')),
    ('parent_cmd', data.get('parent_cmd')),
    ('ac_version_read', data.get('ac_version_read')),
    ('result.summary', (data.get('result') or {}).get('summary') if isinstance(data.get('result'), dict) else None),
    ('purpose_validation', data.get('purpose_validation')),
    ('files_modified', data.get('files_modified')),
    ('lesson_candidate.found', (data.get('lesson_candidate') or {}).get('found') if isinstance(data.get('lesson_candidate'), dict) else None),
    ('lessons_useful', data.get('lessons_useful')),
]
for name, value in required:
    if value in (None, '', [], {}):
        print(f'MISSING {name}')
for ac, checks in (data.get('binary_checks') or {}).items():
    if not isinstance(checks, list):
        print(f'MISSING binary_checks.{ac}')
        continue
    for i, item in enumerate(checks):
        result = str((item or {}).get('result', '')).strip()
        if result not in ('yes', 'no'):
            print(f'BAD_BC binary_checks.{ac}[{i}].result={result!r}')
PY
```
- Script refs verified: 2026-05-19 cmd_2883. `report_field_set.sh` は空文字値をYAML空文字として許可し、構造体/複数行/stdin YAMLはPython fallbackを使う。`lessons_useful`、`binary_checks`、`self_gate_check`、`assumption_invalidation`、`knowledge_candidate` は書込み前に型/値をBLOCK検証する。`report_field_set.sh <report> origin [value]` は `lesson_candidate.origin` へ書き、value省略時はworker task/reportのcmdからoriginを自動継承する。`verdict` は `gate_report_format.sh` が自動導出するため手動記入禁止。
### Step 1: 報告パスを確認
```bash
# タスクYAMLから報告パスを取得
report_path="queue/reports/{ninja_name}_report_{cmd_id}.yaml"
```

### Step 2: 必須フィールドを記入（report_field_set.sh経由）

**記入順序を守れ。verdict は手動記入禁止。**

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
# ★テンプレート初期値FILL_THISは規約トークン。実測を含む実値へ手動置換必須。自動補完禁止。
bash scripts/report_field_set.sh "$REPORT" result.summary "作業結果の1行要約"

# 7. assumption_invalidation
bash scripts/report_field_set.sh "$REPORT" assumption_invalidation "none"

# 8. lessons_useful（注入済み教訓のうち有用だったもの）
# ★ 全体上書きは既存件数より少ない場合BLOCKされる(06f5a0856)。
#    テンプレート注入済み教訓が消えるため。個別書込みを推奨:
#    bash scripts/report_field_set.sh "$REPORT" "lessons_useful.0.useful" "true"
#    bash scripts/report_field_set.sh "$REPORT" "lessons_useful.0.feedback" "具体的に何が役立ったか"
# 全体書込みする場合はテンプレート注入済み件数以上のリストを渡すこと。
bash scripts/report_field_set.sh "$REPORT" "lessons_useful" "[{id: L123, useful: true, feedback: '具体的に何が役立ったか'}]"

# 9. lesson_candidate（新たな発見）
bash scripts/report_field_set.sh "$REPORT" "lesson_candidate" "{found: false, no_lesson_reason: '既知の手順で完了。新発見なし'}"
# または found: trueの場合:
# bash scripts/report_field_set.sh "$REPORT" "lesson_candidate" "{found: true, title: '発見タイトル', detail: '詳細'}"
# originだけ追記/自動継承する場合:
bash scripts/report_field_set.sh "$REPORT" origin

# 10. skill_candidate（3回以上同じ手順を実行していたら）
bash scripts/report_field_set.sh "$REPORT" "skill_candidate" "{found: false}"

# 11. decision_candidate（判断が必要な事項）
bash scripts/report_field_set.sh "$REPORT" "decision_candidate" "{found: false}"

# 12. verdict は gate_report_format.sh が自動導出する。忍者は手動記入禁止。
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
- **verdictを手動記入するな** — `gate_report_format.sh` が binary_checks から自動導出する
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

- 2026-07-12: gate=gate_report_format result=FAIL executor=hayate reason=timestamp: completed/revision_requested report requires a parseable ISO timestamp
- 2026-07-12: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC1[1].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC1[2].result: 空文字。\"yes\" または \"no\" を記入せよ; ...

- 2026-07-12: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.AC1[0].check: \"AC1\" が短すぎる(確認内容を具体的に書け); binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].check: \"AC2\" が短すぎる(確認内容を具体的に書け); binary...
- 2026-07-12: gate=gate_report_format result=FAIL executor=saizo reason=binary_checks.AC3[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC3[1].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せ...

- 2026-07-11: gate=gate_report_format result=FAIL executor=hayate reason=binary_checks: empty dict (must have at least one AC entry); status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ; result.summary: MISSING or empty; verdict: \"\" is not vali...
- 2026-07-10: gate=gate_report_format result=FAIL executor=tobisaru reason=LK-A14: 横展開/修正前パターンを扱う報告にはgrep/rg残存0件の一次証跡が必須

- 2026-07-10: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[1].result: 空文字。\"yes\" または \"no\" を記入せよ; ...
- 2026-07-10: gate=gate_report_format result=FAIL executor=kotaro reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC1[1].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文字。\"yes\" または \"no\" を記入せよ; ...

- 2026-07-03: gate=gate_report_format result=FAIL executor=kotaro reason=binary_checks: MISSING; files_modified: MISSING; lesson_candidate: MISSING; lessons_useful: MISSING; purpose_validation: MISSING; result.summary: MISSING or empty; verdict: \"No...
- 2026-07-03: gate=cmd_complete_gate result=FAIL executor=hayate reason=report_format:kotaro_report_cmd_3680_recon2.yaml

- 2026-07-03: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:hayate_report_cmd_3677_recon2.yaml
- 2026-07-02: gate=cmd_complete_gate result=FAIL executor=kagemaru reason=report_format:kagemaru_report_cmd_training_speed_cmd_complete_gate_202607020409_kagemaru.yaml|kagemaru:binary_checks_fail

- 2026-07-02: gate=gate_report_format result=FAIL executor=saizo reason=stale_report: filename has cmd_bench_test2 but parent_cmd=cmd_bench_test (cmd_id mismatch)
- 2026-07-02: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:kotaro_report_cmd_training_speed_gate_shogun_startup_202607020211_kotaro.yaml|kotaro:binary_checks_fail

- 2026-07-02: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:kotaro_report_cmd_3634_recon3.yaml
- 2026-07-02: gate=gate_report_format result=FAIL executor=kotaro reason=binary_checks.AC3[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ;...

- 2026-07-01: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:kotaro_report_cmd_3629_kotaro.yaml
- 2026-07-01: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:hanzo_report_cmd_3629_hanzo.yaml|report_format:kagemaru_report_cmd_3629.yaml|report_format:kotaro_report_cmd_3629_kotaro.yaml|report_format:saizo_report_cmd_3629_s...

- 2026-07-01: gate=gate_report_format result=FAIL executor=kotaro reason=test
- 2026-07-01: gate=gate_report_format result=FAIL executor=kotaro reason=binary_checks: AC self-verification missing (0/3 ACs). 全ACの二値チェックを記入せよ; result.summary: MISSING or empty

- 2026-07-01: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:kotaro_report_cmd_3628_kotaro.yaml|report_format:saizo_report_cmd_3628_saizo.yaml|report_format:tobisaru_report_cmd_3628_tobisaru.yaml|hanzo:binary_checks_fail|kot...
- 2026-07-01: gate=gate_report_format result=FAIL executor=kotaro reason=binary_checks: AC self-verification missing (0/2 ACs). 全ACの二値チェックを記入せよ; result.summary: MISSING or empty

- 2026-07-01: gate=gate_report_format result=FAIL executor=kotaro reason=files_modified: 1件がパス形式でない(/ を含まない)。説明文ではなくファイルパスを記入せよ
- 2026-07-01: gate=cmd_complete_gate result=FAIL executor=kotaro reason=report_format:kotaro_report_cmd_3621_kotaro_ab.yaml|report_format:tobisaru_report_cmd_3621.yaml

- 2026-06-30: gate=cmd_complete_gate result=FAIL executor=saizo reason=report_format:saizo_report_cmd_karo_ci_fix_diagnosis_trigger_map_202606301658.yaml
- 2026-06-30: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:saizo_report_cmd_3609_recon2.yaml|saizo:binary_checks_fail

- 2026-06-30: gate=gate_report_format result=FAIL executor=saizo reason=binary_checks: AC self-verification missing (0/4 ACs). 全ACの二値チェックを記入せよ; result.summary: MISSING or empty
- 2026-06-28: gate=gate_report_format result=FAIL executor=kagemaru reason=files_modified: 2件がパス形式でない(/ を含まない)。説明文ではなくファイルパスを記入せよ

- 2026-06-28: gate=gate_report_format result=FAIL executor=kagemaru reason=files_modified: 9件がパス形式でない(/ を含まない)。説明文ではなくファイルパスを記入せよ
- 2026-06-24: gate=gate_report_format result=FAIL executor=hanzo reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks: AC self-verification missing (0/3 ACs). 全ACの二値チェックを記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"compl...

- 2026-06-24: gate=gate_report_format result=FAIL executor=kagemaru reason=lessons_useful[0]: id=\"L_SCOPE\" is invalid (must match L+number, e.g. L074)
- 2026-06-24: gate=gate_report_format result=FAIL executor=hanzo reason=Traceback: AttributeError: 'str' object has no attribute 'get'

- 2026-06-23: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:tobisaru_report_cmd_3518.yaml
- 2026-06-23: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:kotaro_report_cmd_3518.yaml|report_format:tobisaru_report_cmd_3518.yaml

- 2026-06-23: gate=gate_report_format result=FAIL executor=unknown reason=worker_id: MISSING; parent_cmd: MISSING; ac_version_read: MISSING; lessons_useful[0]: missing \"id\" field (must have lesson ID like L074); lessons_useful[1]: missing \"id\" fie...
- 2026-06-23: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:hanzo_report_cmd_3515_l1_kasoku_ratio.yaml|report_format:tobisaru_report_cmd_3515_l1_kasoku_diff.yaml|hanzo:binary_checks_fail|tobisaru:binary_checks_fail|command_...

- 2026-06-23: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:hanzo_report_cmd_3515_l1_kasoku_ratio.yaml|report_format:kotaro_report_cmd_3515_l1_nukimi.yaml|report_format:tobisaru_report_cmd_3515_l1_kasoku_diff.yaml|hanzo:bin...
- 2026-06-23: gate=gate_report_format result=FAIL executor=hanzo reason=binary_checks: AC self-verification missing (0/1 ACs). 全ACの二値チェックを記入せよ; result.summary: MISSING or empty

- 2026-06-23: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:hanzo_report_cmd_3515.yaml|report_format:kagemaru_report_cmd_3515.yaml
- 2026-06-23: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:hanzo_report_cmd_3515.yaml|report_format:hayate_report_cmd_3515.yaml|report_format:kagemaru_report_cmd_3515.yaml|report_format:kotaro_report_cmd_3515.yaml|command_...

- 2026-06-23: gate=gate_report_format result=FAIL executor=kagemaru reason=stale_report: filename has ga118_lesson_health but parent_cmd=GA-118 (cmd_id mismatch)
- 2026-06-23: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:saizo_report_cmd_3514_nukimi.yaml|saizo:empty_lessons_useful:related=['L565','L086','L633']|saizo:ac_version_mismatch:task=2cc8762f:report=pending

- 2026-06-23: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks: MISSING; files_modified: MISSING; lessons_useful: MISSING; purpose_validation: MISSING; verdict: \"None\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_I...
- 2026-06-23: gate=gate_report_format result=FAIL executor=hanzo reason=lesson_candidate: missing \"found\" field; lesson_candidate: found=false but no no_lesson_reason; lessons_useful[0]: missing \"reason\" field; lessons_useful[1]: missing \"reaso...

- 2026-06-23: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:hanzo_report_cmd_3513.yaml|report_format:kotaro_report_cmd_3513.yaml|report_format:saizo_report_cmd_3513.yaml|report_format:tobisaru_report_cmd_3513.yaml|hanzo:emp...
- 2026-06-23: gate=gate_report_format result=FAIL executor=unknown reason=worker_id: MISSING; ac_version_read: MISSING; binary_checks: MISSING; files_modified: MISSING; lessons_useful: MISSING; lesson_candidate: missing \"found\" field; lesson_candida...

- 2026-06-21: gate=gate_report_format result=FAIL executor=kagemaru reason=YAML parse error: while parsing a block mapping
- 2026-06-21: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:hanzo_report_cmd_3475.yaml|hanzo:binary_checks_fail

- 2026-06-21: gate=gate_report_format result=FAIL executor=hanzo reason=lessons_useful: empty list (テンプレートには教訓が注入済み。空リストで上書きするな); assumption_invalidation: missing \"affected_cmds\" field; assumption_invalidation: missing \"detail\" field
- 2026-06-20: gate=cmd_complete_gate result=FAIL executor=tobisaru reason=tobisaru:empty_lessons_useful:related=['AC1','AC2']

- 2026-06-20: gate=gate_report_format result=FAIL executor=unknown reason=worker_id: MISSING; parent_cmd: MISSING; ac_version_read: MISSING; files_modified: MISSING; lesson_candidate: MISSING; lessons_useful: MISSING; purpose_validation: MISSING; assu...
- 2026-06-20: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:saizo_report_cmd_3463.yaml|report_format:tobisaru_report_cmd_3463.yaml

- 2026-06-20: gate=gate_report_format result=FAIL executor=tobisaru reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC4[0].result: 空文字。\"yes\" または \"no\" を記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ;...
- 2026-06-20: gate=gate_report_format result=FAIL executor=saizo reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC5[0].result: 空文字。\"yes\" または \"no\" を記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ;...

- 2026-06-20: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:kotaro_report_cmd_3458_kotaro.yaml|report_format:saizo_report_cmd_3458_saizo.yaml|report_format:tobisaru_report_cmd_3458_tobisaru.yaml
- 2026-06-20: gate=gate_report_format result=FAIL executor=hanzo reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks: AC self-verification missing (0/5 ACs). 全ACの二値チェックを記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"compl...

- 2026-06-19: gate=cmd_complete_gate result=FAIL executor=kotaro reason=report_format:kotaro_report_cmd_3449.yaml
- 2026-06-19: gate=gate_report_format result=FAIL executor=kotaro reason=lessons_useful[0]: id=\"none_injected\" is invalid (must match L+number, e.g. L074)

- 2026-06-19: gate=cmd_complete_gate result=FAIL executor=kagemaru reason=report_format:kagemaru_report_cmd_3447_kagemaru.yaml
- 2026-06-19: gate=gate_report_format result=FAIL executor=hanzo reason=lessons_useful[0]: id=\"none\" is invalid (must match L+number, e.g. L074)

- 2026-06-19: gate=cmd_complete_gate result=FAIL executor=hanzo reason=hanzo:empty_lessons_useful:related=[cmd_3447_hanzo_normal,]
- 2026-06-19: gate=cmd_complete_gate result=FAIL executor=kagemaru reason=kagemaru:empty_lessons_useful:related=[cmd_3447_kagemaru_normal,]

- 2026-06-19: gate=cmd_complete_gate result=FAIL executor=hayate reason=report_format:saizo_report_cmd_3445_saizo.yaml|saizo:invalid_lessons_useful_format
- 2026-06-19: gate=gate_report_format result=FAIL executor=saizo reason=lessons_useful[0]: useful=NOT_USEFUL is str (must be true or false); lessons_useful[1]: useful=NOT_USEFUL is str (must be true or false)

- 2026-06-19: gate=cmd_complete_gate result=FAIL executor=hayate reason=saizo:invalid_lessons_useful_format
- 2026-06-19: gate=gate_report_format result=FAIL executor=unknown reason=worker_id: MISSING; parent_cmd: MISSING; ac_version_read: MISSING; files_modified: MISSING; lessons_useful[0]: missing \"id\" field (must have lesson ID like L074); lessons_usef...

- 2026-06-19: gate=cmd_complete_gate result=FAIL executor=hayate reason=report_format:saizo_report_cmd_3445_saizo.yaml|saizo:empty_lessons_useful:related=['L219','L211',cmd_3445_saizo_normal,,MISSING;parent_cmd:MISSING;ac_version_read:MISSING;binary...
- 2026-06-19: gate=cmd_complete_gate result=FAIL executor=hayate reason=report_format:saizo_report_cmd_3445_saizo.yaml

- 2026-06-19: gate=gate_report_format result=FAIL executor=saizo reason=binary_checks: null (must be dict with AC entries); status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ; result.summary: MISSING or empty; verdict: \"\" is not valid (must b...
- 2026-06-15: gate=cmd_complete_gate result=FAIL executor=kagemaru reason=kagemaru:empty_lessons_useful:related=['L634','L633','L621','L620','L619','L618','L617','L616','L615','L614']

- 2026-06-13: gate=gate_report_format result=FAIL executor=unknown reason=worker_id: MISSING; parent_cmd: MISSING; ac_version_read: MISSING; lessons_useful[0]: missing \"id\" field (must have lesson ID like L074); lessons_useful[0]: missing \"useful\"...
- 2026-06-13: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks: item count 1/5 (<50% of task template); status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ; res...

- 2026-06-12: gate=gate_report_format result=FAIL executor=unknown reason=worker_id: MISSING; parent_cmd: MISSING; ac_version_read: MISSING; lesson_candidate: MISSING; lessons_useful[0]: missing \"id\" field (must have lesson ID like L074); lessons_us...
- 2026-06-11: gate=gate_report_format result=FAIL executor=kagemaru reason=YAML parse error: while scanning a simple key

- 2026-06-10: gate=gate_report_format result=FAIL executor=saizo reason=lessons_useful: MISSING; lesson_candidate: found=true but no title
- 2026-06-10: gate=gate_report_format result=FAIL executor=saizo reason=lessons_useful: MISSING; binary_checks.AC1: is dict (must be list of check items); binary_checks.AC2: is dict (must be list of check items); assumption_invalidation: MISSING

- 2026-06-10: gate=gate_report_format result=FAIL executor=hanzo reason=lesson_candidate: found=false but no no_lesson_reason; lessons_useful: empty list (テンプレートには教訓が注入済み。空リストで上書きするな); binary_checks: AC self-verification missing (0/5 ACs). 全ACの二値チェッ...
- 2026-06-10: gate=gate_report_format result=FAIL executor=kotaro reason=files_modified: MISSING; lesson_candidate: MISSING; lessons_useful: MISSING; binary_checks.ac1_done: is str (must be list of check items); binary_checks.ac2_done: is bool (must ...

- 2026-06-10: gate=gate_report_format result=FAIL executor=unknown reason=worker_id: MISSING; parent_cmd: MISSING; ac_version_read: MISSING; files_modified: MISSING; lessons_useful: MISSING; lesson_candidate: found=false but no no_lesson_reason; purpo...
- 2026-06-08: gate=gate_report_format result=FAIL executor=unknown reason=worker_id: MISSING; ac_version_read: MISSING; lesson_candidate: missing \"found\" field; lesson_candidate: found=false but no no_lesson_reason; purpose_validation: MISSING; assu...

- 2026-06-08: gate=gate_report_format result=FAIL executor=unknown reason=worker_id: MISSING; ac_version_read: MISSING; purpose_validation: MISSING; assumption_invalidation: MISSING
- 2026-06-08: gate=cmd_complete_gate result=FAIL executor=kagemaru reason=report_format:kagemaru_report_cmd_3228.yaml|command_files_modified_mismatch

- 2026-06-08: gate=gate_report_format result=FAIL executor=kagemaru reason=result: not a dict
- 2026-06-08: gate=gate_report_format result=FAIL executor=kagemaru reason=knowledge_candidate: found=true but items is empty

- 2026-06-07: gate=gate_report_format result=FAIL executor=saizo reason=ac_version_read: MISSING; binary_checks: MISSING; files_modified: MISSING; lessons_useful: MISSING; parent_cmd: MISSING (empty value); lesson_candidate: found=false but no no_le...
- 2026-06-07: gate=gate_report_format result=FAIL executor=kotaro reason=stale_report: filename has cmd_training_speed_sync_pane_vars_20260607 but parent_cmd=cmd_training_speed_sync_pane_vars_20260607201900_normal (cmd_id mismatch)

- 2026-06-07: gate=gate_report_format result=FAIL executor=kagemaru reason=lesson_candidate: found=true but no detail or summary
- 2026-06-07: gate=gate_report_format result=FAIL executor=tobisaru reason=ac_version_read: MISSING; lesson_candidate: MISSING; stale_report: filename has cmd_training_speed_search_log_write_20260607 but parent_cmd=cmd_training_speed_search_log_write_2...

- 2026-06-07: gate=gate_report_format result=FAIL executor=kagemaru reason=ac_version_read: MISSING; binary_checks.commit[0].result: \"pending\" は不正。\"yes\" または \"no\" のみ; purpose_validation: MISSING; verdict: \"None\" is not valid (must be \"PASS\", \...
- 2026-06-07: gate=gate_report_format result=FAIL executor=kagemaru reason=YAML parse error: mapping values are not allowed here

- 2026-06-07: gate=gate_report_format result=FAIL executor=kagemaru reason=assumption_invalidation: is str (must be dict)
- 2026-06-07: gate=gate_report_format result=FAIL executor=tobisaru reason=result.summary: MISSING or empty

- 2026-06-07: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks: item count 1/14 (<50% of task template); result.summary: MISSING or empty
- 2026-06-07: gate=gate_report_format result=FAIL executor=unknown reason=worker_id: MISSING; parent_cmd: MISSING; ac_version_read: MISSING; assumption_invalidation: MISSING

- 2026-06-05: gate=gate_report_format result=FAIL executor=hanzo reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks: AC self-verification missing (0/4 ACs). 全ACの二値チェックを記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"compl...
- 2026-06-05: gate=gate_report_format result=FAIL executor=kagemaru reason=lesson_candidate: missing \"found\" field; lesson_candidate: found=false but no no_lesson_reason; lessons_useful[0]: id=\"growth_loop_defense\" is invalid (must match L+number, ...

- 2026-06-04: gate=gate_report_format result=FAIL executor=unknown reason=worker_id: MISSING; parent_cmd: MISSING; ac_version_read: MISSING; lessons_useful: MISSING
- 2026-06-04: gate=gate_report_format result=FAIL executor=unknown reason=worker_id: MISSING; parent_cmd: MISSING; ac_version_read: MISSING; lessons_useful[0]: is NoneType (must be dict); lessons_useful[1]: missing \"id\" field (must have lesson ID li...

- 2026-06-04: gate=gate_report_format result=FAIL executor=hayate reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks: item count 1/14 (<50% of task template); status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ; re...
- 2026-06-02: gate=gate_report_format result=FAIL executor=hayate reason=lessons_useful: empty list (テンプレートには教訓が注入済み。空リストで上書きするな); binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文字。\"yes\" または \"no\" を記入せよ; b...

- 2026-05-22: gate=gate_report_format result=FAIL executor=saizo reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks: item count 1/13 (<50% of task template); status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ; re...
- 2026-05-22: gate=gate_report_format result=FAIL executor=kagemaru reason=parent_cmd: MISSING (empty value); binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ; result.summary: MISSING...

- 2026-05-21: gate=gate_report_format result=FAIL executor=saizo reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks: item count 1/11 (<50% of task template); status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ; re...
- 2026-05-21: gate=cmd_complete_gate result=FAIL executor=hayate reason=report_format:hayate_report_cmd_training_L7_v3_hayate_6_20260521205341.yaml

- 2026-05-21: gate=gate_report_format result=FAIL executor=hanzo reason=lessons_useful[1]: missing \"id\" field (must have lesson ID like L074); lessons_useful[2]: missing \"id\" field (must have lesson ID like L074); lessons_useful[3]: missing \"id...
- 2026-05-21: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せ...

- 2026-05-21: gate=gate_report_format result=FAIL executor=hanzo reason=lesson_candidate: no_lesson_reason=\"FILL_THIS\" is placeholder (write a real reason); binary_checks.AC1[0].result: \"FILL_THIS\" は不正。\"yes\" または \"no\" のみ; binary_checks.AC2[0]...
- 2026-05-19: gate=gate_report_format result=FAIL executor=kotaro reason=lesson_candidate: found=true but no title; assumption_invalidation: found=true but affected_cmds is empty (影響cmdを列挙せよ)

- 2026-05-19: gate=gate_report_format result=FAIL executor=kotaro reason=ac_version_read: MISSING; lessons_useful: MISSING; parent_cmd: MISSING (empty value); lesson_candidate: found=true but no detail or summary; verdict: PASS but binary_checks cont...
- 2026-05-19: gate=cmd_complete_gate result=FAIL executor=hanzo reason=report_format:kotaro_report_cmd_2896.yaml

- 2026-05-19: gate=gate_report_format result=FAIL executor=kotaro reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ;...
- 2026-05-19: gate=cmd_complete_gate result=FAIL executor=hayate reason=hayate:lesson_candidate_fields_empty:detail

- 2026-05-19: gate=gate_report_format result=FAIL executor=hayate reason=lesson_candidate: found=true but no title
- 2026-05-19: gate=gate_report_format result=FAIL executor=hanzo reason=ac_version_read: MISSING; lessons_useful: MISSING

- 2026-05-18: gate=gate_report_format result=FAIL executor=tobisaru reason=files_modified: MISSING; purpose_validation: MISSING
- 2026-05-18: gate=gate_report_format result=FAIL executor=kotaro reason=lessons_useful[0]: missing \"reason\" field; lessons_useful[1]: missing \"reason\" field; lessons_useful[2]: missing \"reason\" field; lessons_useful[3]: missing \"reason\" fiel...

- 2026-05-18: gate=gate_report_format result=FAIL executor=kagemaru reason=self_gate_check: missing required key \"lesson_ref\" (required: lesson_ref, lesson_candidate, status_valid, purpose_fit); self_gate_check: missing required key \"lesson_candidat...
- 2026-05-17: gate=cmd_complete_gate result=FAIL executor=saizo reason=report_format:saizo_report_cmd_2825.yaml|saizo:binary_checks_fail

- 2026-05-16: gate=gate_report_format result=FAIL executor=hayate reason=files_modified: is dict (must be string or list of file paths); lessons_useful[0]: useful=yes is str (must be true or false); lessons_useful[1]: useful=yes is str (must be true ...
- 2026-05-16: gate=gate_report_format result=FAIL executor=hayate reason=files_modified: MISSING; lesson_candidate: MISSING; lessons_useful: MISSING; purpose_validation: MISSING; assumption_invalidation: MISSING

- 2026-05-16: gate=gate_report_format result=FAIL executor=hayate reason=assumption_invalidation: MISSING; self_gate_check: is str (must be dict)
- 2026-05-15: gate=cmd_complete_gate result=FAIL executor=kagemaru reason=kagemaru:empty_lessons_useful:related=['L512','L511','L510','L509','L508','L507','L506','L505','L504','L503']

- 2026-05-15: gate=gate_report_format result=FAIL executor=kotaro reason=files_modified: MISSING; lesson_candidate: MISSING; lessons_useful: MISSING; binary_checks.AC1: is dict (must be list of check items); binary_checks.AC2: is dict (must be list o...
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

Script refs verified: 2026-06-02T20:31:22+09:00 user infra-bug audit. `report_field_set.sh` の現行契約を再確認。lessons_useful空リスト、binary_checks空欄、status pending、summary空欄はgate_report_format.shでBLOCKされるため提出前に必ずgateを通す。
Script refs verified: 2026-06-08 9a1c5df09. `report_field_set.sh` のfiles_modified autofixがスペース区切り複数パス（拡張子or/を含む2+トークン）を検出し個別dict変換する。files_modifiedをスペース区切り文字列で渡しても正しくlist of dict化される。推奨形式（YAML list）への影響なし。
Script refs verified: 2026-06-09 06f5a0856. `report_field_set.sh` にlessons_useful全体上書きBLOCKガード追加。テンプレート注入済み件数より少ないリストで全体上書きすると拒否される。個別per-item書込み(`lessons_useful.0.useful true`等)を推奨。Step 2のコメントに制約注記済み。
<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->

Script refs verified: 2026-06-20 efb4b9c02. `report_field_set.sh` 直近変更はSC2221/SC2222/SC2154 shellcheck警告のdisableコメント追加のみ。report YAML各フィールド設定、stdin YAML、lessons_useful保護、binary_checks yes/no契約は変更なし。

Script refs verified: 2026-06-26 b12637002. `report_field_set.sh` 直近変更はstatus=completed済み報告へのcommit前フィールド書込みをBLOCKするガード追加。report-writeはstatus completedにする前に全フィールドを記入するため、通常フローでは影響なし。completedマーク後に修正が必要な場合はstatusをin_progressに戻してから再記入する。

<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->

<!-- 検分: 2026-07-12 shogun起動時gate WARN解消。report_field_set.shの差分=進行中hotfix(cmd_karo_hotfix_report_completed_immutability: completed/done後の報告書換えをfail-closedで封鎖、revision_requested遷移と冪等writeのみ許可)。通常タスク中の報告記入フロー・フィールド指定契約は不変 -->
<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->
