---
name: verdict-check
argument-hint: "[report_path]"
quality_metric: "忍者系: verdict-check使用後のverdict不整合WA不発生率(対象報告のうちverdict_override/binary_checks矛盾なしの割合)"
description: |
  【忍者専用】binary_checksの結果確認と未記入検出を行うスキル。
  verdict↔binary_checks矛盾（PASS判定だがbc:noあり等）を構造的に防止する。
  verdictはgate_report_format.shが全bc yesならPASS、1つでもnoならFAILへ自動導出・上書きするため、手動verdict記入は不要。
  TRIGGER: /verdict-check、binary_checks確認、bc判定、bc未記入確認
  DO NOT TRIGGER: 報告YAML全体作成（→/report-write）、commit（→/ninja-commit）
allowed-tools:
  - Bash
  - Read
---

<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->

Script refs verified: 2026-07-13 将軍検分. `gate_report_format.sh` checked_at以降の変更(97170f617)をgit showで確認。dashboard reflux skipのCLEAR review fingerprint連携4行のみで、binary_checks検証・verdict自動導出の判定契約不変。手順書き換え不要。

Script refs verified: 2026-07-11 shogun起動時gate WARN解消。checked_at以降の変更(review two-phase race fix系/inbox gate trigger detach/report discovery偽BLOCK根治/rg grepフォールバック/memory DB cache atomic recovery)をgit logで確認。いずれも内部強化であり呼び出し契約・出口文言・本文手順に変更なし。
<!-- 検分: gate_report_format.sh bc8c87bc5 非重複post-commit dirty hunk許容(FAIL条件緩和)。binary_checksからのverdict自動導出(全yes→PASS/1つでもno→FAIL/空・FILL_THIS→BLOCK)と呼び出し契約は不変 -->
<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->
<!-- 検分: gate_report_format.sh 460db6e2b session_state-only task diff除外。binary_checksからのverdict自動導出、未記入/FILL_THIS BLOCK、呼び出し契約は不変 -->
<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->

Script refs verified: 2026-07-04 cmd_training_skill_refs_verdict_check_202607042005. checked_at 2026-07-03T02:15:00+09:00 以降の `gate_report_format.sh` 差分は 83fc58fd (`cmd_karo_hotfix_commit_missing_structural_202607032250`) のみ。bc:commit=yes時の未commit検査対象を`target_path`だけでなく報告YAMLの`files_modified`申告ファイルにも拡張する変更で、`binary_checks`からのverdict自動導出（全yes→PASS/1つでもno→FAIL/空・FILL_THIS→BLOCK）ロジックは`gate_report_format_combined.py`側にあり無変更。verdict-checkの手順・判定ルールへの影響なし。

Script refs verified: 2026-07-02 cmd_karo_hotfix_skill_script_refs_202607021234. 対象scriptの2026-07-02T01:12以降差分をgit log/showで確認。直近変更は速度改善・内部検査強化・テンプレート修復・files_modified path guardで、各SKILL本文の呼び出し契約は維持。

Script refs verified: 2026-06-26 cmd_3550. `gate_report_format.sh` 直近変更後も `bash scripts/gates/gate_report_format.sh <report_yaml_path>` の呼び出し契約、binary_checksからのverdict自動導出、未記入/FILL_THIS/不正値BLOCKの契約は変更なし。

<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->

Script refs verified: 2026-06-11. `gate_report_format.sh` の契約は `bash scripts/gates/gate_report_format.sh <report_yaml_path>` のまま。binary_checksが全てyes/noならverdictをPASS/FAILへ自動導出し、空/FILL_THIS/不正値はBLOCKする仕様に変更なし。

# /verdict-check — binary_checks確認スキル

binary_checksの全結果を読み取り、未記入や不正値がないか確認する。verdictはgate_report_format.shが自動決定・上書きするため、忍者の手動verdict記入は不要。

## なぜこのスキルが必要か

- verdict_override WA 9件(全WA9%)
- 原因: verdict PASSだがbc:noが含まれる / bcがall yesなのにverdict FAIL
- 忍者が先にverdictを書いてからbcを記入→不整合
- cmd_2871以降、gate_report_format.shがbinary_checksからverdictを計算し、忍者記入値を上書きする

## verdict判定ルール

```
全binary_checks.result = "yes" → gate_report_format.shがverdict = "PASS"へ上書き
1つでも "no" があれば      → gate_report_format.shがverdict = "FAIL"へ上書き
1つでも 空/FILL_THIS       → gate_report_format.shがBLOCK（先にbcを全て埋めよ）
```

**例外なし。** 条件付きPASS、実質PASS、ほぼPASSは全てFAIL。

## 手順


### 自動防止ステップ
- <!-- skill-auto-improve:2839a343b37d --> 自動防止: gate=gate_report_format のTop FAIL理由「binary_checks.commit[0].result: \"waive\" は不正。\"yes\" または \"no\" のみ」(count=1, last=2026-05-02T21:03:37+0900)を避けるため、該当Step完了直後に同条件を確認し、FAILなら次へ進まず修正する。
- <!-- skill-auto-improve:50757724ba13 --> 自動防止: gate=cmd_complete_gate のTop FAIL理由「kagemaru:binary_checks_fail」(count=1, last=2026-05-02T21:03:20+0900)を避けるため、該当Step完了直後に同条件を確認し、FAILなら次へ進まず修正する。
- <!-- skill-auto-improve:c338f44e9765 --> 自動防止: gate=gate_report_format のTop FAIL理由「verdict: \"None\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")」(count=1, last=2026-05-02T21:39:34+0900)を避けるため、該当Step完了直後に同条件を確認し、FAILなら次へ進まず修正する。

- <!-- skill-auto-improve:c9bc422a2822 --> 自動防止: gate=cmd_complete_gate のTop FAIL理由「hayate:binary_checks_fail」(count=1, last=2026-05-05T11:34:15+0900)を避ける。確認: 全 binary_checks の result が yes/no のみで、空欄・waive・PASS・FAIL を含まないことを確認する。修正: 各ACの result を yes/no に直し、1つでも no なら verdict を FAIL にする。
- <!-- skill-auto-improve:68b9c844f407 --> 自動防止: gate=cmd_complete_gate のTop FAIL理由「saizo:binary_checks_fail」(count=1, last=2026-05-03T11:04:05+0900)を避ける。確認: 全 binary_checks の result が yes/no のみで、空欄・waive・PASS・FAIL を含まないことを確認する。修正: 各ACの result を yes/no に直し、1つでも no なら verdict を FAIL にする。
- <!-- skill-auto-improve:c58dbdce16a1 --> 自動防止: gate=cmd_complete_gate のTop FAIL理由「<ninja>:binary_checks_fail」(count=3, last=2026-05-05T11:34:15+0900)を避ける。確認: 全 binary_checks の result が yes/no のみで、空欄・waive・PASS・FAIL を含まないことを確認する。修正: 各ACの result を yes/no に直し、1つでも no なら verdict を FAIL にする。
### 矛盾防止の必須手順
- bc:no と verdict:PASS の矛盾防止: 忍者はverdictを書かない。全 `binary_checks.*[].result` を列挙し、空欄・不正値がないことだけ確認する。
- verdict空欄防止: `binary_checks` に空欄、`FILL_THIS`、`waive`、`PASS`、`FAIL` が残っている場合はgate_report_format.shがBLOCKする。先に全resultを `yes/no` に正規化せよ。
- Script refs verified: 2026-06-07 cmd_3206. `gate_report_format.sh` はhot path高速化後も、`binary_checks` が全てyes/noで埋まっている場合に既存verdict値をPASS/FAILへ自動導出・上書きする。未記入/FILL_THIS/不正値はBLOCK、PASS cacheと`GATE_NO_LOG`契約も維持。
- Script refs verified: 2026-05-22 cmd_2959. `gate_report_format.sh` は `binary_checks` が全てyes/noで埋まっている場合、既存verdict値をPASS/FAILへ自動導出・上書きする。PASS cache、`GATE_FAST_EXIT`/`GATE_NO_LOG`、中間状態FAILログ抑止、task_clarity未記入WARN、skill_execution_log.sh非同期実行を持つ。`SKILL_LOG_SYNC=1` でテスト時は同期実行する。
### Step 1: binary_checksを全て記入済みか確認
```bash
# 報告YAMLからbinary_checksの全resultを抽出
python3 -c "
import yaml, sys
with open('$REPORT') as f:
    data = yaml.safe_load(f)
bcs = data.get('binary_checks', {})
results = []
for ac_key, checks in bcs.items():
    if isinstance(checks, list):
        for c in checks:
            r = c.get('result', '')
            results.append((ac_key, c.get('check',''), r))
            if not r or r in ('FILL_THIS', 'null'):
                print(f'INCOMPLETE: {ac_key} - {c.get(\"check\",\"\")}')
all_yes = all(r == 'yes' for _, _, r in results)
any_empty = any(not r or r in ('FILL_THIS','null') for _, _, r in results)
if any_empty:
    print('BLOCK: binary_checksに未記入あり。全て記入してからverdictを決定せよ')
elif all_yes:
    print('VERDICT: PASS')
else:
    fails = [(ac, c, r) for ac, c, r in results if r != 'yes']
    for ac, c, r in fails:
        print(f'FAIL: {ac} - {c} = {r}')
    print('VERDICT: FAIL')
"
```

### Step 2: gate_report_format.shでverdict自動導出を確認
```bash
# Step 1で未記入がないことを確認してから実行。verdictは自動上書きされる
bash scripts/gates/gate_report_format.sh "$REPORT"
```

`self_gate_check`を直す必要がある場合、`report_field_set.sh "$REPORT" self_gate_check PASS` はBLOCKされる。dict構造を壊さないよう、`self_gate_check.lesson_ref PASS` のように各keyを個別更新する。

### Step 3: 整合性最終確認
```bash
# gate_report_format.shが自動検証
# bc:no + verdict:PASS → verdict:FAILへ上書き
# bc全empty/未記入 → BLOCK
```

## 禁止事項

- **verdictを手動記入するな** — gate_report_format.shがbinary_checksから導出して上書きする
- **条件付きPASSは存在しない** — bc:noが1つでもあればFAIL
- **verdict を Edit toolで直接書くな** — 独立フィールドとして扱うほど矛盾の温床になる

## 注意ポイント
- 2026-07-15: gate=gate_report_format result=FAIL executor=hayate reason=status: \"revision_requested\" cannot carry terminal verdict PASS (set status to completed after revisions); LK-A14: 横展開/修正前パターンを扱う報告にはgrep/rg残存0件の一次証跡が必須

- 2026-07-14: gate=gate_report_format result=FAIL executor=hanzo reason=variation_checks: required cells unfilled: normal_pass, quoted_or_heredoc, linked_worktree, parallel_or_respawn, abnormal_exit; memory_references[2].reason: empty (参照した理由を具体的に書け...
- 2026-07-14: gate=gate_report_format result=FAIL executor=kagemaru reason=variation_checks: required cells unfilled: normal_pass, quoted_or_heredoc, linked_worktree, parallel_or_respawn, abnormal_exit; binary_checks.AC1[0].result: 空文字。\"yes\" または \"no...

- 2026-07-14: gate=gate_report_format result=FAIL executor=kotaro reason=status: \"revision_requested\" cannot carry terminal verdict PASS (set status to completed after revisions)
- 2026-07-14: gate=gate_report_format result=FAIL executor=hayate reason=variation_checks: required cells unfilled: normal_pass, quoted_or_heredoc, linked_worktree, parallel_or_respawn, abnormal_exit; memory_references[1].reason: empty (参照した理由を具体的に書け...

- 2026-07-14: gate=gate_report_format result=FAIL executor=kagemaru reason=variation_checks: required cells unfilled: normal_pass, quoted_or_heredoc, linked_worktree, parallel_or_respawn, abnormal_exit; binary_checks.AC2[0].result: 空文字。\"yes\" または \"no...
- 2026-07-14: gate=gate_report_format result=FAIL executor=hanzo reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC1[1].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文字。\"yes\" または \"no\" を記入せよ; ...

- 2026-07-14: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.AC3[1].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC5[1].result: 空文字。\"yes\" または \"no\" を記入せよ; verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or ...
- 2026-07-14: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.AC3[1].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC5[1].result: 空文字。\"yes\" または \"no\" を記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ; ve...

- 2026-07-14: gate=gate_report_format result=FAIL executor=kagemaru reason=commit_hash: 欠落または40文字フルhashでない(binary_checks.commitがyes) — review_approvalの後段BLOCK(review_report_fingerprint契約)をここで前段検出。git rev-parse HEADの40文字フルhashを記入せよ; LK-A14: 横展開/修正前パターンを...
- 2026-07-14: gate=gate_report_format result=FAIL executor=kotaro reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ; verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or \"...

- 2026-07-14: gate=gate_report_format result=FAIL executor=saizo reason=binary_checks.AC3[1].result: 空文字。\"yes\" または \"no\" を記入せよ; verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")
- 2026-07-13: gate=gate_report_format result=FAIL executor=hanzo reason=commit_hash: 欠落または40文字フルhashでない(binary_checks.commitがyes) — review_approvalの後段BLOCK(review_report_fingerprint契約)をここで前段検出。git rev-parse HEADの40文字フルhashを記入せよ

- 2026-07-13: gate=gate_report_format result=FAIL executor=hayate reason=binary_checks.AC3[1].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ;...
- 2026-07-12: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.AC2[1].result: 空文字。\"yes\" または \"no\" を記入せよ; verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")

- 2026-07-12: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC1[1].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC1[2].result: 空文字。\"yes\" または \"no\" を記入せよ; ...
- 2026-07-12: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.AC10[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ...

- 2026-07-12: gate=gate_report_format result=FAIL executor=kotaro reason=binary_checks.AC4[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC4[1].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せ...
- 2026-07-10: gate=cmd_complete_gate result=FAIL executor=tobisaru reason=tobisaru:binary_checks_fail|tobisaru:post_deploy_evidence_missing:deploy_live_at,evidence_run_start_at,evidence_run_completed_at,run_completed

- 2026-07-10: gate=gate_report_format result=FAIL executor=tobisaru reason=binary_checks.AC2[1].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC3[1].result: 空文字。\"yes\" または \"no\" を記入せよ; verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or ...
- 2026-07-08: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.AC2[2].result: 空文字。\"yes\" または \"no\" を記入せよ; verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")

- 2026-07-08: gate=gate_report_format result=FAIL executor=hayate reason=binary_checks: item count 3/14 (<50% of task template)
- 2026-07-08: gate=gate_report_format result=FAIL executor=hayate reason=binary_checks.AC4[1].result: 空文字。\"yes\" または \"no\" を記入せよ; verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")

- 2026-07-08: gate=gate_report_format result=FAIL executor=tobisaru reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文字。\"yes\" または \"no\" を記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ; ve...
- 2026-07-08: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.AC1[1].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[1].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC3[1].result: 空文字。\"yes\" または \"no\" を記入せよ; ...

- 2026-07-08: gate=gate_report_format result=FAIL executor=hayate reason=binary_checks.AC1[1].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC1[2].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[1].result: 空文字。\"yes\" または \"no\" を記入せよ; ...
- 2026-07-04: gate=gate_report_format result=FAIL executor=tobisaru reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ;...

- 2026-07-03: gate=gate_report_format result=FAIL executor=kotaro reason=binary_checks: item count 6/14 (<50% of task template)
- 2026-07-02: gate=cmd_complete_gate result=FAIL executor=kagemaru reason=kagemaru:purpose_validation_fit_false

- 2026-07-02: gate=gate_report_format result=FAIL executor=saizo reason=binary_checks.AC5[0].result: 空文字。\"yes\" または \"no\" を記入せよ; verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")
- 2026-07-01: gate=gate_report_format result=FAIL executor=hanzo reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せ...

- 2026-07-01: gate=gate_report_format result=FAIL executor=kotaro reason=binary_checks: AC self-verification missing (0/2 ACs). 全ACの二値チェックを記入せよ
- 2026-06-30: gate=gate_report_format result=FAIL executor=tobisaru reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks: AC self-verification missing (0/4 ACs). 全ACの二値チェックを記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"compl...

- 2026-06-29: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.AC6[0].result: 空文字。\"yes\" または \"no\" を記入せよ; verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")
- 2026-06-26: gate=gate_report_format result=FAIL executor=saizo reason=binary_checks: AC self-verification missing (0/4 ACs). 全ACの二値チェックを記入せよ

- 2026-06-19: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks: null (must be dict with AC entries); verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\"); knowledge_candidate: found=true but item...
- 2026-06-17: gate=cmd_complete_gate result=FAIL executor=tobisaru reason=tobisaru:binary_checks_fail|command_files_modified_mismatch

- 2026-06-17: gate=cmd_complete_gate result=FAIL executor=saizo reason=saizo:binary_checks_fail|command_files_modified_mismatch
- 2026-06-13: gate=gate_report_format result=FAIL executor=hanzo reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文字。\"yes\" または \"no\" を記入せよ; verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or ...

- 2026-06-13: gate=gate_report_format result=FAIL executor=kagemaru reason=AUTO-FIXED: verdict binary_checks導出→PASS
- 2026-06-13: gate=cmd_complete_gate result=FAIL executor=kotaro reason=kotaro:binary_checks_fail

- 2026-06-12: gate=gate_report_format result=FAIL executor=hanzo reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks: AC self-verification missing (0/4 ACs). 全ACの二値チェックを記入せよ; verdict: \"\" is not valid (must be \"PASS\...
- 2026-06-11: gate=cmd_complete_gate result=FAIL executor=hanzo reason=hanzo:binary_checks_fail|hanzo:purpose_validation_fit_false

- 2026-06-11: gate=gate_report_format result=FAIL executor=saizo reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ; verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or...
- 2026-06-10: gate=gate_report_format result=FAIL executor=saizo reason=binary_checks.AC1: is dict (must be list of check items); binary_checks.AC2: is dict (must be list of check items)

- 2026-06-08: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\"); knowledge_candidate: found=tru...
- 2026-06-07: gate=gate_report_format result=FAIL executor=tobisaru reason=binary_checks.AC1[1].result: 空文字。\"yes\" または \"no\" を記入せよ; verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")

- 2026-06-03: gate=gate_report_format result=FAIL executor=hanzo reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks: AC self-verification missing (0/5 ACs). 全ACの二値チェックを記入せよ; status: \"pending\" はテンプレート初期値。完了後に \"compl...
- 2026-06-02: gate=cmd_complete_gate result=FAIL executor=tobisaru reason=tobisaru:binary_checks_fail

- 2026-06-02: gate=gate_report_format result=FAIL executor=hanzo reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC3[0].result: 空文字。\"yes\" または \"no\" を記入せよ; ...
- 2026-06-02: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks: MISSING; verdict: \"None\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")

- 2026-05-21: gate=gate_report_format result=FAIL executor=kagemaru reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")
- 2026-05-19: gate=cmd_complete_gate result=FAIL executor=hanzo reason=hanzo:binary_checks_fail

- 2026-05-17: gate=cmd_complete_gate result=FAIL executor=saizo reason=saizo:binary_checks_fail|saizo:purpose_validation_fit_false
- 2026-05-16: gate=cmd_complete_gate result=FAIL executor=kagemaru reason=kagemaru:binary_checks_fail|kagemaru:purpose_validation_fit_false

- 2026-05-10: gate=gate_report_format result=FAIL executor=unknown reason=binary_checks: AC self-verification missing (0/1 ACs). 全ACの二値チェックを記入せよ
- 2026-05-10: gate=gate_report_format result=FAIL executor=unknown reason=binary_checks.description[0].check: \"|-\" が短すぎる(確認内容を具体的に書け)

- 2026-05-10: gate=cmd_complete_gate result=FAIL executor=unknown reason=hayate:binary_checks_fail|hayate:purpose_validation_fit_false
- 2026-05-09: gate=gate_report_format result=FAIL executor=unknown reason=binary_checks: AC self-verification missing (0/3 ACs). 全ACの二値チェックを記入せよ

- 2026-05-05: gate=cmd_complete_gate result=FAIL executor=unknown reason=hayate:binary_checks_fail
- 2026-05-04: gate=gate_report_format result=FAIL executor=unknown reason=binary_checks.commit[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks: AC self-verification missing (0/3 ACs). 全ACの二値チェックを記入せよ; verdict: \"\" is not valid (must be \"PASS\...

- 2026-05-03: gate=gate_report_format result=FAIL executor=unknown reason=verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")
- 2026-05-02: gate=gate_report_format result=FAIL executor=unknown reason=verdict: \"None\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")

- 2026-05-02: gate=gate_report_format result=FAIL executor=unknown reason=binary_checks.commit[0].result: \"waive\" は不正。\"yes\" または \"no\" のみ
- 2026-05-02: gate=cmd_complete_gate result=FAIL executor=unknown reason=kagemaru:binary_checks_fail

Script refs verified: 2026-06-02T20:31:22+09:00 user infra-bug audit. `gate_report_format.sh` の現行契約を再確認。binary_checks未記入または欠落時はverdict自動導出できずBLOCKするため、verdict編集ではなくbinary_checksを修正する。
Script refs verified: 2026-06-10 6bf403d2c. `gate_report_format.sh` はauto-commit contamination check(cmd_3264)を追加。bc:commit=yes時にtarget_path配下の未commit変更・auto-commit巻込みをWARN検出する。verdict自動導出(binary_checks→PASS/FAIL上書き)の契約は変更なし。verdict-checkの手順変更は不要。

Script refs verified: 2026-06-20 48204a464. `gate_report_format.sh` 直近変更は操作的オントロジー/targetフィルタ/スキル強制の内部検査強化。binary_checksからverdictを自動導出する契約と、未記入/FILL_THIS/不正値BLOCKは変更なし。

<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->

<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->

<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->
Script refs verified: 2026-07-08 将軍検分. 前回checked_at以降の gate_report_format.sh 差分は c1f2b38d8 のみ(gate_loop_health集計向けログパス正規化=内部ログ記録のみの変更。報告YAMLパス引数・PASS/FAIL判定・verdict自動導出の契約は不変)。

<!-- 検分: 2026-07-12 shogun起動時gate WARN解消。checked_at以降の差分をgit logで確認 — gate_report_format.sh 8c576d849(AC3 hunk provenance判定=内部判定強化)/memory_db_query.sh 8ce7c5c26(ext4キャッシュ経由=内部速度)/deploy_task.sh 2ecaf21ba+0cc6175e6+5dc9e8423(chunk境界regex誤検知根治+lesson注入絞込+atomic mv=内部)/ninja_scope_commit.sh 42d06b1d5+13f46a918(fail-closed patch commit mode追加+CI fixture=内部)/ninja_monitor.sh b40e13d2c系(dedupe通知+stall FP抑制=内部)。いずれも呼び出し契約・手順・出口文言に変更なし -->
<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->
