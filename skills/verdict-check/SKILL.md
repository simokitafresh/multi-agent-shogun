---
name: verdict-check
argument-hint: "[report_path]"
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
