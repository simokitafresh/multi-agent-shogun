# gate L6 awk偽陽性修正+BLOCK2件遡及解消
<!-- generated: 2026-06-19T23:00:00+09:00 by gunshi idle analysis -->

## 概要

gate_gunshi_cs_checklist.sh L999のawkルールが`gate_`キーワードでcontext索引cmd(cmd_3434)のobservations言及を偽検出し、L6-洗脳#2 BLOCKを誤発火。awkルールを`scripts/|ninja_monitor`に限定し偽陽性を排除。同時にbrainwash_check Quality Check三問を直近13件に遡及追記しBLOCKを解消。

## 根因分析

### L6偽陽性の因果連鎖

```
cmd_3434 report review observations:
  "事実3: gate_vercel_phase FAIL=L107参照切れ"
    ↓
gate L999 awk: obs ~ /gate_/ でマッチ
    ↓
context索引追記cmdがscripts変更cmdと誤分類
    ↓
L6 BLOCK(実動作確認なし)偽発火
```

### 修正

| 修正前 | 修正後 |
|--------|--------|
| `obs ~ /scripts\/\|gate_\|hook_\|monitor\|ninja_monitor/` | `obs ~ /scripts\/\|ninja_monitor/` |

理由: `scripts/`が`scripts/gates/`と`scripts/hooks/`を包含するため、`gate_`と`hook_`は冗長かつ偽陽性源。`monitor`も`ninja_monitor`に限定済み。

### brainwash_check三問遡及

| 対象 | 修正前 | 修正後 |
|------|--------|--------|
| 直近14件 | 13/14件にQ1/Q2/Q3未記入 | 0件未記入(全件記入) |

## 数値

- BLOCK: 2件 → 0件
- 総合判定: WARN → OK
- batsテスト: 28/28 PASS(回帰なし)
- 変更行数: 1行(gate awkルール)

## 因果リンク

- origin: `[[cmd_3434_L6偽陽性]] -> [[awkルールgate_キーワード過検出]] -> [[D0修正+28テストPASS]]`
- 関連教訓: LG039(無制限マッチの貪欲FP族)と同根。awkルールの検出範囲を有界化する一般原則
