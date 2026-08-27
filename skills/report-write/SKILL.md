---
<!-- script_refs_checked_at: 2026-07-31T05:33:00+09:00 -->
<!-- 2026-07-31 cmd_karo_skill_ref_report_write_20260731検分: report_field_set.sh 2026-07-30差分3件(d878d5096/6e33bdbb2/4e17da006、最新=d878d5096)をgit showで確認。d878d5096はhook_failures.details.post_verification_resultのcanonical化ロジックを親mapping(hook_failures/hook_failures.details丸ごと書込み時)にも拡張する加算的修正。6e33bdbb2はpublish generation fingerprintをreview_approval.shの共有実装へ統一する内部計装。4e17da006はfiles_modified単一plain pathのfast-path(出力は従来と同一の`- path/change: modified`形式)。3件とも`bash scripts/report_field_set.sh --batch "$REPORT" < payload`契約・dot notation・stdin YAML・verdict自動導出・BLOCK条件は不変。本文Step 2/Step 3の書換え不要。 -->
<!-- script_refs_checked_at: 2026-07-18T03:18:00+09:00 -->
<!-- 2026-07-18 cmd_karo_hotfix_skill_refs_freshness_batch検分: report_field_set.sh 7c2a802e/cebb4ba2/4dafc13fは単一batch transaction、completed revision原子再公開、共通atomic serializerを追加。本文の--batch手順・verdict自動導出・fail-closed契約は現行scriptと一致。 -->
<!-- script_refs_checked_at: 2026-07-18T01:02:00+09:00 -->
<!-- 2026-07-18検分: report_field_set.sh 7c2a802e/cebb4ba2は--batch追加。1 flock+atomic replace、bc/terminal/commitをfail-closed検証。従来field CLI不変。 -->
<!-- script_refs_checked_at: 2026-07-17T09:45:00+09:00 -->
<!-- 2026-07-17 cmd_karo_hotfix_skill_refs_all検分: report_field_set.sh ab05776afは非terminal status書込み時の冗長status再読込を省略。terminal normalization、field CLI、型検証、verdict自動導出契約は不変。 -->
<!-- script_refs_checked_at: 2026-07-15T11:38:00+09:00 -->
<!-- 2026-07-15将軍検分: report_field_set.sh aa75598cf(lesson_candidate型チェック dict→(dict,list)緩和=内部バリデーション)。呼び出し契約不変。 -->
name: report-write
argument-hint: "[report_path]"
quality_metric: "忍者系: report-write使用後の報告YAML関連WA不発生率(対象報告のうちreport_yaml_format/report_field欠陥なしの割合)"
description: |
  【忍者専用】報告YAML作成を標準化するスキル。report_field_set.sh経由で必須フィールドを記入し、
  Edit tool直接編集によるテンプレート破損・FILL_THIS残存・形式不備を防止する。
  全フィールドをreport_field_set.sh経由で書き込み、gate_report_format.shで事前検証する。
  TRIGGER: /report-write、報告YAML作成、報告記入、報告フィールド記入、FILL_THIS修正
  DO NOT TRIGGER: 報告YAMLの読み取り（→Read tool直接）、verdict判定（→/verdict-check）、commit（→/ninja-commit）
allowed-tools:
  - Bash
  - Read
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

### Step 2: 全フィールドを単一batch transactionで記入

**約45フィールドを先に完全なYAML mappingへ集約し、setterは1回だけ呼ぶ。**
`commit_hash`、全`binary_checks`、`origin`、診断結果を含む必須値が揃う前に
`status: completed`を公開してはならない。`verdict`はpayloadへ書かず、batchが
binary checksから自動導出する。

```bash
REPORT="queue/reports/{ninja_name}_report_{cmd_id}.yaml"
PAYLOAD="$(mktemp)"
trap 'rm -f "$PAYLOAD"' EXIT

# apply_patch等でPAYLOADを作成するか、下記形のmappingを生成する。
# キーはreport_field_set.shのdot notation。構造値はYAMLのlist/dictで渡す。
printf '%s\n' \
  'worker_id: {ninja_name}' \
  'task_id: {task_id}' \
  'parent_cmd: {cmd_id}' \
  'timestamp: {ISO-8601 timestamp}' \
  'ac_version_read: {ac_hash}' \
  'commit_hash: {40-hex commit hash}' \
  'result.summary: {実測を含む要約}' \
  'purpose_validation.fit: true' \
  'files_modified: [{path: path/to/file, change: 変更内容}]' \
  'lessons_useful: [{id: L123, useful: true, reason: 使用理由}]' \
  'lesson_candidate: {found: false, no_lesson_reason: 新規教訓なしの具体理由}' \
  'lesson_candidate.origin: "[[cmd_xxx]] -> [[原因]] -> [[結果]]"' \
  'binary_checks.AC1[0].result: yes' \
  'skill_candidate: {found: false}' \
  'decision_candidate: {found: false}' \
  'status: completed' > "$PAYLOAD"

# 1 process・1 flock・1 YAML load/save・1 atomic replace。
bash scripts/report_field_set.sh --batch "$REPORT" < "$PAYLOAD"
rm -f "$PAYLOAD"
trap - EXIT
```

batchは全更新を検証してからatomic replaceする。必須値不足、不正なbinary result、
不正commit hashではbyte不変のままBLOCKする。単一フィールドCLIは非terminal報告の
診断的な局所補正に限り使用できるが、通常の完成フローでは使用しない。

`--batch` は旧版・別経路の報告に `operational_simulation` が欠落している場合、
`command`・`expected`・`actual`・`result` の空4枠だけを構造注入する。有効値は
自動補完しないため、実測値を記入しなければ `gate_report_format.sh` はFAILする。

completed報告を修正する場合も、`status: revision_requested`、修正値、全binary
checksを同じpayloadへ含めて`--batch`を1回だけ実行する。中間の
`revision_requested`は公開されず、検証成功時だけcompletedへ原子的に再公開される。

### Step 3: 事前検証
```bash
bash scripts/gates/gate_report_format.sh "$REPORT"
```

<!-- 2026-07-15 cmd_karo_hotfix_skill_refs_ops検分: report_field_set.sh 82d5cac4e/41415be7bをgit showで確認。commit identity共通化とqueue/logs-only no-code-change許可はcommit_hash専用契約で、全フィールド設定CLI・stdin YAML・binary_checks/verdict手順は不変。 -->
<!-- script_refs_checked_at: 2026-07-15T21:28:00+09:00 -->
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
- 2026-08-27: gate=gate_report_format result=FAIL executor=tobisaru reason=files_modified: 3件がパス形式でない(/ を含まない)。説明文ではなくファイルパスを記入せよ; commit_contract: files_modified path is outside planned scope: ./requirements.txt
- 2026-08-27: gate=gate_report_format result=FAIL executor=tobisaru reason=files_modified: 6件がパス形式でない(/ を含まない)。説明文ではなくファイルパスを記入せよ; commit_contract: files_modified path is outside planned scope: .gitignore; commit_contract: files_modified path is outsid...
- 2026-08-27: gate=gate_report_format result=FAIL executor=hanzo reason=final_checkpoint: ci_fix clean repro evidence post harness must start before push
- 2026-08-26: gate=gate_report_format result=FAIL executor=kotaro reason=files_modified: 1件がパス形式でない(/ を含まない)。説明文ではなくファイルパスを記入せよ; LG051: gate/hook/dispatcher変更には非test caller数の一次証跡が必須
- 2026-08-26: gate=gate_report_format result=FAIL executor=hayate reason=commit_contract: commit subject does not identify task_id/parent_cmd; commit_contract: files_modified path is outside planned scope: queue/reports/hayate_report_cmd_karo_hotfix_...
- 2026-08-26: gate=gate_report_format result=FAIL executor=kotaro reason=files_modified: 1件がパス形式でない(/ を含まない)。説明文ではなくファイルパスを記入せよ; commit_contract: commit/task history does not contain owned/planned path: .github/workflows/test.yml; commit_contract: co...
- 2026-08-26: gate=gate_report_format result=FAIL executor=hayate reason=LK-A14: 横展開/修正前パターンを扱う報告にはgrep/rg残存0件の一次証跡が必須
- 2026-08-26: gate=gate_report_format result=FAIL executor=kotaro reason=operational_simulation: MISSING (command,expected,actual,result; integration cmd requires command/expected/actual/result — LG055); LG051: gate/hook/dispatcher変更には非test caller数の一...
- 2026-08-26: gate=gate_report_format result=FAIL executor=saizo reason=cross_repo_commits: files_modified path lacks cross-repo ownership: scripts/archive_completed.sh; cross_repo_commits: FIX hint: cross_repo_commitsのpathsが実際のcommit内容と不一致。以下を実行して正...
- 2026-08-26: gate=gate_report_format result=FAIL executor=kagemaru reason=files_modified: 1件がパス形式でない(/ を含まない)。説明文ではなくファイルパスを記入せよ
- 2026-08-26: gate=gate_report_format result=FAIL executor=kagemaru reason=investigation_contract: outcome must be one of: found, zero_found, not_present, external_boundary, unknown_after_exhaustion; investigation_contract: method_completed must be tru...
- 2026-08-25: gate=gate_report_format result=FAIL executor=kagemaru reason=commit_contract: files_modified path is outside planned scope: context/senkyoku-log.md
- 2026-08-25: gate=gate_report_format result=FAIL executor=tobisaru reason=commit_contract: files_modified path is outside planned scope: tests/unit/test_run_tests.bats; LG051: gate/hook/dispatcher変更には非test caller数の一次証跡が必須
- 2026-08-25: gate=gate_report_format result=FAIL executor=kagemaru reason=LG051: gate/hook/dispatcher変更には非test caller数の一次証跡が必須; LK-A14: 横展開/修正前パターンを扱う報告にはgrep/rg残存0件の一次証跡が必須
- 2026-08-25: gate=gate_report_format result=FAIL executor=hanzo reason=investigation_contract: method_completed must be true; investigation_contract: primary_evidence requires at least 1 source+observation item(s); investigation_contract: remaining...
- 2026-08-25: gate=gate_report_format result=FAIL executor=kagemaru reason=investigation_contract: investigation_outcome mapping is missing; LG051: gate/hook/dispatcher変更には非test caller数の一次証跡が必須
- 2026-08-24: gate=gate_report_format result=FAIL executor=hanzo reason=commit_contract: files_modified path is outside planned scope: docs/research/cmd_4388_cmd_complete_gate_phase-union-ancestry.md (file does not exist — possible path typo in file...
- 2026-08-24: gate=cmd_complete_gate result=FAIL executor=sasuke reason=report_format:sasuke_report_cmd_karo_4380_full.yaml|ci_readiness:BLOCK: origin slug unresolvable from /tmp/cmd4380-full.TEckdE/project|ci_readiness:Traceback (most recent call l...
- 2026-08-24: gate=cmd_complete_gate result=FAIL executor=sasuke reason=report_format:sasuke_report_cmd_karo_4380_full.yaml|ci_push_state:BLOCK: report commit invalid or unresolvable
- 2026-08-23: gate=gate_report_format result=FAIL executor=saizo reason=operational_simulation.result: must be PASS or FAIL; LG051: gate/hook/dispatcher変更には非test caller数の一次証跡が必須

過去のgate FAIL頻出パターン要約(生ログはlogs/gate_fire_log.yaml等の台帳が正本。ここには要約のみ保持):

1. **commit_contract: files outside planned scope**(最頻出) — 実装がtarget_path外(特にtests/)へ拡大した時。テストファイルもplanned_paths/files_to_modifyへ事前宣言せよ(拡大時の正規更新=cmd_4161)
2. **LG051**: gate/hook/dispatcher変更の報告には非test caller数の一次証跡(rg結果)必須
3. **operational_simulation MISSING**: integration系はcommand/expected/actual/resultの4点を埋める(LG055)
4. **variation_checks未記入**: normal_pass/quoted_or_heredoc/linked_worktree/parallel_or_respawn/abnormal_exitは全てyes/noで埋める
5. **型エラー**: lessons_usefulはdictのlist(useful=true/false bool)・binary_checks resultは"yes"/"no"文字列・verdictはPASS/FAIL/PASS_NO_IMPROVEMENT・timestampはISO形式・FILL_THIS残存禁止
6. **commit_hash**: 40文字フルhash必須。commit subjectにtask_id/parent_cmdを含める。cross_repo_commitsは該当repoのcommitにpathが実在すること
7. **status遷移**: revision_requestedにverdict PASSを載せるな(completedへ更新してから)
8. **コード変更が無いcmdの正規表現(commit_hash: no-code-change)** — `permits_no_code_identity()`(scripts/lib/report_commit_identity.py)は次の**3条件のAND**でのみ受理する。1つでも欠けると `BLOCK: terminal readiness requires valid commit_hash` で終端できない(cmd_karo_impl_b28/b29_20260726で明文化):
   - `no_code_change_evidence`: `tree_unchanged: true` かつ `before_tree` = `after_tree`(40-hex。作業前後の `git rev-parse HEAD^{tree}` を記録)
   - `commit_contract.required: false`(理由を `reason` に書く。free-textマーカーではなくこのフィールドがSSOT)
   - `files_modified`: **非空**、かつ全pathが `queue/` または `logs/` 配下(またはgit-ignore済み `projects/`)
   **成果物が本報告YAMLだけの場合、`files_modified` に自分の報告YAML自身(`queue/reports/<自分の報告>.yaml`)を書くのが正規である。**`files_modified` を空にする経路は存在しない(空はfail-closed)。`change` には「本cmdの成果物は本報告のみ」+その根拠を書け。実データ例=`queue/archive/reports/saizo_report_cmd_karo_ci_fix_30161415740_phantom_unit_path_20260725_20260726.yaml`

Script refs verified: 2026-06-02T20:31:22+09:00 user infra-bug audit. `report_field_set.sh` の現行契約を再確認。lessons_useful空リスト、binary_checks空欄、status pending、summary空欄はgate_report_format.shでBLOCKされるため提出前に必ずgateを通す。
Script refs verified: 2026-06-08 9a1c5df09. `report_field_set.sh` のfiles_modified autofixがスペース区切り複数パス（拡張子or/を含む2+トークン）を検出し個別dict変換する。files_modifiedをスペース区切り文字列で渡しても正しくlist of dict化される。推奨形式（YAML list）への影響なし。
Script refs verified: 2026-06-09 06f5a0856. `report_field_set.sh` にlessons_useful全体上書きBLOCKガード追加。テンプレート注入済み件数より少ないリストで全体上書きすると拒否される。個別per-item書込み(`lessons_useful.0.useful true`等)を推奨。Step 2のコメントに制約注記済み。
<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->
Script refs verified: 2026-06-20 efb4b9c02. `report_field_set.sh` 直近変更はSC2221/SC2222/SC2154 shellcheck警告のdisableコメント追加のみ。report YAML各フィールド設定、stdin YAML、lessons_useful保護、binary_checks yes/no契約は変更なし。
Script refs verified: 2026-06-26 b12637002. `report_field_set.sh` 直近変更はstatus=completed済み報告へのcommit前フィールド書込みをBLOCKするガード追加。report-writeはstatus completedにする前に全フィールドを記入するため、通常フローでは影響なし。completedマーク後に修正が必要な場合はstatusをin_progressに戻してから再記入する。
<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->
<!-- 検分: 2026-07-12 shogun起動時gate WARN解消。report_field_set.shの差分=進行中hotfix(cmd_karo_hotfix_report_completed_immutability: completed/done後の報告書換えをfail-closedで封鎖、revision_requested遷移と冪等writeのみ許可)。通常タスク中の報告記入フロー・フィールド指定契約は不変 -->
<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->
