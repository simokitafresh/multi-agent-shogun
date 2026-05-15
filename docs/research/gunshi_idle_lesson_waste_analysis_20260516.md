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

## ★ 後続検証(cmd_2794/2795)による前提修正 — 2026-05-16T08:30

### 根因分析の訂正

上記「根因」セクションは**不正確**だった。

- cmd_2794(fallbackパス除外拡張)を起票→**軍師レビューで前提否定**。L3705のfallbackはscoredに入り、L3740のeffectiveness除外を通る構造
- cmd_2795(偵察)で才蔵がstderrログ分析→**still-injected 10件は現行では大半が既に除外済み**

### 真因: 分析時点差

本分析(00:30)時点のlesson_impact.tsvスナップショットと、現行(07:15以降)のstderrログで状態が異なる:
- L502/L501/L511: 現行ではuniversal effectiveness exclusionで除外済み
- L087/L577/L324/L171/L415/L114: 現行ではtask_specific effectiveness exclusionで除外済み
- L171/L415/L114: TSV上feedback total=4(MIN_SAMPLES未満)→時間経過でフィードバック蓄積により解消予定
- L112: 過去注入7件の蓄積だが、feedback 5件到達後は除外済み

### 教訓: 動的データの静的スナップショットに有効期限を付けよ

feedback蓄積で状態が変わるデータを一時点で分析し、その結果を固定的にcmd前提とした。
殿の「過去データ不変の暗黙前提禁止」と同根。分析結果には計測時点を明記し、
動的データ(feedback/useful_rate)に依存する結論には有効期限の概念を持て。
