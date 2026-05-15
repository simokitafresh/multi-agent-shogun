# 教訓注入CTX浪費分析 — 利他改善
<!-- generated: 2026-05-16T00:30:00+09:00 by gunshi idle analysis -->

## 問題

忍者に注入される教訓の70%がuseful: false。1教訓≈180tok。10件注入で7件無駄=1,260tok/タスク。
6忍者×複数タスク=累積18,000tok浪費(lesson_impact.tsv 2,011行分析)。

## 計測結果

| 分類 | 件数 | 条件 |
|------|------|------|
| feedback付き教訓 | 182件 | lesson_impact.tsvでfeedback行あり |
| never-useful | 27件 | fb≥3 AND useful=0 |
| should-exclude | 13件 | fb≥5 AND useful=0 (MIN_SAMPLES=5超) |
| still-injected | 10件 | should-excludeだが2026-05-15以降も注入 |
| rarely-useful | 10件 | fb≥5 AND useful_rate≤20% |

## 根因

effectiveness除外(cmd_2700)は**universal教訓のみ対象**(deploy_task.sh L3724)。
タグ付き教訓(recon/shinobi等)は除外されない。still-injected 10件は全てタグ付き。

```
L3724: if useful_rates and universal_lessons:
           ↑ universal_lessonsのみフィルタ
           tag_candidatesは対象外
```

## still-injected 10件の内訳(2026-05-15以降)

| 教訓 | 注入回数 | fb | useful | タグ |
|------|---------|-----|--------|------|
| L112 | 7 | 5 | 0 | recon |
| L502 | 6 | 6 | 0 | tagged |
| L087 | 5 | 5 | 0 | tagged |
| L501 | 5 | 5 | 0 | tagged |
| L577 | 5 | 5 | 0 | tagged |
| L324 | 5 | 5 | 0 | tagged |
| L171 | 4 | 5 | 0 | tagged |
| L415 | 4 | 5 | 0 | tagged |
| L114 | 4 | 5 | 0 | tagged |
| L511 | 1 | 6 | 0 | tagged |

## 行動提案

1. **deploy_task.sh L3724**: tag_candidatesにもeffectiveness_score除外を適用(cmd起票要)
2. 推定効果: 10件×平均5注入=50注入削減。50×180tok=9,000tok削減
3. 閾値0.40は維持。MIN_SAMPLES=5は維持。対象範囲のみ拡張

## 因果鎖

universal教訓のみ除外→タグ付き教訓は常に注入→useful=0でも止まらない→忍者CTX浪費→利他改善で解消可能
