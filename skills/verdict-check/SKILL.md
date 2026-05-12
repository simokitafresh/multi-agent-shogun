---
name: verdict-check
argument-hint: "[report_path]"
quality_metric: "忍者系: verdict-check使用後のverdict不整合WA不発生率(対象報告のうちverdict_override/binary_checks矛盾なしの割合)"
description: |
  【忍者専用】binary_checksの結果からverdictを自動導出するスキル。
  verdict↔binary_checks矛盾（PASS判定だがbc:noあり等）を構造的に防止する。
  全bcがyesならPASS、1つでもnoならFAIL。手動verdict記入を排除。
  TRIGGER: /verdict-check、verdict判定、verdict自動判定、bc判定
  DO NOT TRIGGER: 報告YAML全体作成（→/report-write）、commit（→/ninja-commit）
---

# /verdict-check — verdict自動導出スキル

binary_checksの全結果を読み取り、verdictを自動決定する。手動verdict禁止。

## なぜこのスキルが必要か

- verdict_override WA 9件(全WA9%)
- 原因: verdict PASSだがbc:noが含まれる / bcがall yesなのにverdict FAIL
- 忍者が先にverdictを書いてからbcを記入→不整合

## verdict判定ルール

```
全binary_checks.result = "yes" → verdict = "PASS"
1つでも "no" があれば      → verdict = "FAIL"
1つでも 空/FILL_THIS       → verdict記入不可（先にbcを全て埋めよ）
```

**例外なし。** 条件付きPASS、実質PASS、ほぼPASSは全てFAIL。

## 手順


### 自動防止ステップ
- <!-- skill-auto-improve:2839a343b37d --> 自動防止: gate=gate_report_format のTop FAIL理由「binary_checks.commit[0].result: \"waive\" は不正。\"yes\" または \"no\" のみ」(count=1, last=2026-05-02T21:03:37+0900)を避けるため、該当Step完了直後に同条件を確認し、FAILなら次へ進まず修正する。
- <!-- skill-auto-improve:50757724ba13 --> 自動防止: gate=cmd_complete_gate のTop FAIL理由「kagemaru:binary_checks_fail」(count=1, last=2026-05-02T21:03:20+0900)を避けるため、該当Step完了直後に同条件を確認し、FAILなら次へ進まず修正する。
- <!-- skill-auto-improve:c338f44e9765 --> 自動防止: gate=gate_report_format のTop FAIL理由「verdict: \"None\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")」(count=1, last=2026-05-02T21:39:34+0900)を避けるため、該当Step完了直後に同条件を確認し、FAILなら次へ進まず修正する。

- <!-- skill-auto-improve:c9bc422a2822 --> 自動防止: gate=cmd_complete_gate のTop FAIL理由「hayate:binary_checks_fail」(count=1, last=2026-05-05T11:34:15+0900)を避ける。確認: 全 binary_checks の result が yes/no のみで、空欄・waive・PASS・FAIL を含まないことを確認する。修正: 各ACの result を yes/no に直し、1つでも no なら verdict を FAIL にする。
- <!-- skill-auto-improve:68b9c844f407 --> 自動防止: gate=cmd_complete_gate のTop FAIL理由「saizo:binary_checks_fail」(count=1, last=2026-05-03T11:04:05+0900)を避ける。確認: 全 binary_checks の result が yes/no のみで、空欄・waive・PASS・FAIL を含まないことを確認する。修正: 各ACの result を yes/no に直し、1つでも no なら verdict を FAIL にする。
### 矛盾防止の必須手順
- bc:no と verdict:PASS の矛盾防止: verdictを書き込む直前に全 `binary_checks.*[].result` を列挙する。1つでも `no` があれば verdict は必ず `FAIL`。`PASS` を書こうとしている状態で `no` を見つけたら、ACの実態を直すのではなく verdict を `FAIL` に変更する。
- verdict空欄防止: `binary_checks` に空欄、`FILL_THIS`、`waive`、`PASS`、`FAIL` が残っている場合は verdict を書かない。先に全resultを `yes/no` に正規化し、再度Step 1を実行してから `report_field_set.sh "$REPORT" verdict ...` を使う。
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

### Step 2: verdictを記入
```bash
# Step 1の結果に基づいて記入（手動判断禁止）
bash scripts/report_field_set.sh "$REPORT" verdict "PASS"  # or "FAIL"
```

### Step 3: 整合性最終確認
```bash
# report_field_set.shのGP-072c4が自動検証
# bc:no + verdict:PASS → BLOCK
# bc全empty + verdict記入 → BLOCK
```

## 禁止事項

- **verdictをbinary_checksより先に書くな** — 不整合の最大原因
- **条件付きPASSは存在しない** — bc:noが1つでもあればFAIL
- **verdict を Edit toolで直接書くな** — report_field_set.sh経由（GP-072c5: bc:no→verdict:PASS BLOCK）

## 注意ポイント

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
