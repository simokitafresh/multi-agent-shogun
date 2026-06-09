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
---

<!-- script_refs_checked_at: 2026-06-10T08:35:40+09:00 -->

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
