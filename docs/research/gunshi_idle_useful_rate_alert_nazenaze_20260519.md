# 教訓useful率ALERT なぜなぜ分析 — 2026-05-19

## 現象
- gate_lesson_health.sh ALERT: useful率13.6%(32/236)
- 直近30cmdで注入101件→useful判定32件のみ

## なぜなぜ

1. **なぜuseful率が低い？** → 注入教訓の多くがタスク内容と無関係(topic_mismatch)
2. **なぜ無関係教訓が注入される？** → effectiveness_score未計算の教訓が除外対象外
3. **なぜscore未計算？** → USEFUL_RATE_MIN_SAMPLES=5だがfb最大4件。閾値未達
4. **なぜfb蓄積が遅い？** → 教訓注入はtask内容依存でランダム。特定教訓のfb蓄積は報告数に比例
5. **なぜ閾値5？** → cmd_2700で設定。統計的根拠は明記されていない

## データ

| 教訓 | fb | useful | rate | topic |
|------|----|----|------|-------|
| L512 | 4 | 0 | 0% | insight dedup |
| L500 | 2 | 0 | 0% | bats skip |
| L548 | 2 | 1 | 50% | yaml.dump禁止 |
| L511 | 2 | 0 | 0% | tac末尾読み |
| L509 | 2 | 0 | 0% | cold計測 |

fb >= 5の教訓: **0件**(effectiveness_scoreが一度も発動していない)

## 提案

USEFUL_RATE_MIN_SAMPLES = 5 → 3 に下げる。

効果: L512(fb=4, score=0.0→除外)等が即淘汰。fb=3でuseful=0は実質的に無用。
リスク: 偶然useful=0の有用教訓の早期除外(fb=3は統計的に弱い)。
代替案: fb閾値を動的にする(教訓総数に応じてスケール)。→過剰設計。固定3で十分。

## 因果チェーン

```
cmd_2700 effectiveness_score(MIN_SAMPLES=5)
  → 直近30報告でfb<5が全件
  → score未計算→除外フィルタ未発動
  → useful=0%教訓が注入され続ける
  → useful率13.6% ALERT
  → MIN_SAMPLES=3でfb>=3の無用教訓を淘汰
```

掲示板: blt_20260519_122622_ccfd81
