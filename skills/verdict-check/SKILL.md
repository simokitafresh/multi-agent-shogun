---
<!-- script_refs_checked_at: 2026-07-18T14:08:00+09:00 -->
<!-- 2026-07-18 cmd_karo_hotfix_skill_refs_batch_a検分: gate_report_format.sh e7ab41112はPASS report fingerprintをfast/no-log exit前にflock下で保存する内部耐久化。binary_checks全yes/noからのverdict自動導出、未記入BLOCK、report path引数・失敗exit契約は不変。既存未commit注意ポイント2件を保持。 -->
<!-- script_refs_checked_at: 2026-07-18T01:02:00+09:00 -->
<!-- 2026-07-18検分: gate_report_format.sh 7c2a802eはfingerprint reuse追加。不一致full gate、verdict/未記入BLOCK契約不変。 -->
<!-- script_refs_checked_at: 2026-07-17T09:45:00+09:00 -->
<!-- 2026-07-17 cmd_karo_hotfix_skill_refs_all検分: gate_report_format.sh 7526e7a51はroot解決subshell回避のhot-path内部最適化。binary_checks全yes/noからのverdict自動導出・未記入BLOCK・report path引数契約は不変。 -->
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
<!-- script_refs_checked_at: 2026-08-01T19:15:00+09:00 -->
<!-- cmd_karo_hotfix_skill_refs_reflux_b_20260801検分: gate_report_format.sh c15becc99は共有logs/gunshi_review_log.yamlの未commit汚染判定をsemantic ownership SSOTへ委譲し、fail-closed時は従来判定へ戻す。binary_checks yes/no、verdict自動導出、report引数、PASS/FAIL出口契約は不変。 -->
<!-- commit_scope_verified: cmd_karo_hotfix_skill_refs_reflux_b_20260801 shared-WIP非重複hunk -->

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

<!-- 2026-07-15 cmd_karo_hotfix_skill_refs_ops検分: gate_report_format.sh 4ecef7670をgit showで確認。複数task所有commitのhunkをdirty判定へ含める内部誤検知修正で、binary_checks全yes/noからのverdict自動導出・未記入BLOCK・report path引数契約は不変。 -->
<!-- script_refs_checked_at: 2026-07-15T21:28:00+09:00 -->

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
- 2026-08-25: gate=gate_report_format result=FAIL executor=hanzo reason=commit_contract: commit subject does not identify task_id/parent_cmd; status: \"revision_requested\" cannot carry terminal verdict PASS (set status to completed after revisions)
- 2026-08-25: gate=gate_report_format result=FAIL executor=hanzo reason=investigation_contract: method_completed must be true; investigation_contract: primary_evidence requires at least 1 source+observation item(s); investigation_contract: remaining...
- 2026-08-24: gate=gate_report_format result=FAIL executor=hayate reason=LG051: gate/hook/dispatcher変更には非test caller数の一次証跡が必須; status: \"revision_requested\" cannot carry terminal verdict PASS (set status to completed after revisions)
- 2026-08-18: gate=gate_report_format result=FAIL executor=kotaro reason=commit_contract: commit/task history does not contain owned/planned path: tests/unit/test_inbox_watcher_codex_busy_claim.bats; status: \"revision_requested\" cannot carry termin...
- 2026-08-17: gate=gate_report_format result=FAIL executor=kagemaru reason=commit_contract: required commit_hash is missing or invalid; binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文字。\"yes\" または \"no\" を記入せよ...
- 2026-08-17: gate=gate_report_format result=FAIL executor=saizo reason=investigation_contract: investigation_outcome mapping is missing; status: \"revision_requested\" cannot carry terminal verdict PASS (set status to completed after revisions)
- 2026-08-17: gate=gate_report_format result=FAIL executor=hayate reason=binary_checks.AC1[0]: missing \"check\" field; binary_checks.AC1[1]: missing \"check\" field; binary_checks.AC1[2]: missing \"check\" field; binary_checks.AC1[3]: missing \"chec...
- 2026-08-15: gate=gate_report_format result=FAIL executor=hayate reason=commit_contract: required commit_hash is missing or invalid; commit_hash: 欠落または40文字フルhashでない(binary_checks.commitがyes) — review_approvalの後段BLOCK(review_report_fingerprint契約)をここで...
- 2026-08-11: gate=gate_report_format result=FAIL executor=hayate reason=operational_simulation: MISSING (command,expected,actual,result; integration cmd requires command/expected/actual/result — LG055); status: \"revision_requested\" cannot carry te...
- 2026-08-11: gate=gate_report_format result=FAIL executor=kotaro reason=commit_contract: required commit_hash is missing or invalid; binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC1[1].result: 空文字。\"yes\" または \"no\" を記入せよ...
- 2026-08-10: gate=gate_report_format result=FAIL executor=kotaro reason=commit_contract: commit subject does not identify task_id/parent_cmd; binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC1[1].result: 空文字。\"yes\" または \"n...
- 2026-08-10: gate=gate_report_format result=FAIL executor=kagemaru reason=commit_contract: required commit_hash is missing or invalid; cross_repo_commits: cross_repo_commits[0].commit_hash is not a resolvable 40-hex commit; binary_checks.AC1[0].result...
- 2026-08-10: gate=gate_report_format result=FAIL executor=hanzo reason=investigation_contract: investigation_outcome mapping is missing; commit_contract: required commit_hash is missing or invalid; binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\...
- 2026-08-10: gate=gate_report_format result=FAIL executor=hanzo reason=commit_contract: commit identity evidence hash differs from report commit_hash; status: \"revision_requested\" cannot carry terminal verdict PASS (set status to completed after ...
- 2026-08-10: gate=gate_report_format result=FAIL executor=hanzo reason=investigation_contract: outcome must be one of: found, zero_found, not_present, external_boundary, unknown_after_exhaustion; investigation_contract: method_completed must be tru...
- 2026-08-09: gate=gate_report_format result=FAIL executor=kagemaru reason=commit_contract: required commit_hash is missing or invalid; variation_checks: required cells unfilled: normal_pass, quoted_or_heredoc, linked_worktree, parallel_or_respawn, abn...
- 2026-08-08: gate=gate_report_format result=FAIL executor=kagemaru reason=status: \"revision_requested\" cannot carry terminal verdict PASS (set status to completed after revisions); knowledge_candidate: found=true but items is empty; self_gate_check....
- 2026-08-07: gate=gate_report_format result=FAIL executor=kagemaru reason=commit_contract: task/report commit_contract required mismatch; binary_checks.AC1[1].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC1[2].result: 空文字。\"yes\" または \"no\" を記...
- 2026-08-07: gate=gate_report_format result=FAIL executor=saizo reason=operational_simulation: MISSING (command,expected,actual,result; integration cmd requires command/expected/actual/result — LG055); status: \"failed\" cannot carry terminal verdi...
- 2026-08-05: gate=gate_report_format result=FAIL executor=kotaro reason=binary_checks.AC1[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[0].result: 空文字。\"yes\" または \"no\" を記入せよ; binary_checks.AC2[1].result: 空文字。\"yes\" または \"no\" を記入せよ; ...

Script refs verified: 2026-06-02T20:31:22+09:00 user infra-bug audit. `gate_report_format.sh` の現行契約を再確認。binary_checks未記入または欠落時はverdict自動導出できずBLOCKするため、verdict編集ではなくbinary_checksを修正する。
Script refs verified: 2026-06-10 6bf403d2c. `gate_report_format.sh` はauto-commit contamination check(cmd_3264)を追加。bc:commit=yes時にtarget_path配下の未commit変更・auto-commit巻込みをWARN検出する。verdict自動導出(binary_checks→PASS/FAIL上書き)の契約は変更なし。verdict-checkの手順変更は不要。

Script refs verified: 2026-06-20 48204a464. `gate_report_format.sh` 直近変更は操作的オントロジー/targetフィルタ/スキル強制の内部検査強化。binary_checksからverdictを自動導出する契約と、未記入/FILL_THIS/不正値BLOCKは変更なし。

<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->

<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->

<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->
Script refs verified: 2026-07-08 将軍検分. 前回checked_at以降の gate_report_format.sh 差分は c1f2b38d8 のみ(gate_loop_health集計向けログパス正規化=内部ログ記録のみの変更。報告YAMLパス引数・PASS/FAIL判定・verdict自動導出の契約は不変)。

<!-- 検分: 2026-07-12 shogun起動時gate WARN解消。checked_at以降の差分をgit logで確認 — gate_report_format.sh 8c576d849(AC3 hunk provenance判定=内部判定強化)/memory_db_query.sh 8ce7c5c26(ext4キャッシュ経由=内部速度)/deploy_task.sh 2ecaf21ba+0cc6175e6+5dc9e8423(chunk境界regex誤検知根治+lesson注入絞込+atomic mv=内部)/ninja_scope_commit.sh 42d06b1d5+13f46a918(fail-closed patch commit mode追加+CI fixture=内部)/ninja_monitor.sh b40e13d2c系(dedupe通知+stall FP抑制=内部)。いずれも呼び出し契約・手順・出口文言に変更なし -->
<!-- script_refs_checked_at: 2026-07-13T07:50:00+09:00 -->
