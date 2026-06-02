# 洗脳監査: 三層学習ループ×三層記憶の隠れたバグ全件対処
<!-- generated: 2026-06-02T14:15:00+09:00 by gunshi brainwash audit -->

## 経緯

殿命令「洗脳監査。1つ見つけて満足したら洗脳の証拠」→5バグ発見→「全部直せ」→3件D0修正+2件CMD起票→「L0-L7貫通していないものは」→L5昇格2件→「利他で将軍にCMD起票」→2件素案→「実際の効果は」→現物データ計測→「更に改善要素を」→6件穴発見→「Obsidian活用率少なくないか」→10件断裂発見→「3つだけか？想像するな」→全箇所走査で10件確定。

## 定量成果

### 概念充填(cmd_3116-3118)
| 指標 | Before | After |
|------|--------|-------|
| 全体 | 53.1% | **70.3%** |
| gate | 0.8% | **97.8%** |
| workaround | 0% | **96.2%** |
| lesson | 2% | **68.6%** |
| cmd_quality | 0.2% | **100%** |
| report(テキスト品質) | 3/10件 | **10/10件** |
| event_concepts | 83,494 | **105,349行** |

### 教訓注入精度(cmd_3121)
| 指標 | Before | After |
|------|--------|-------|
| 偽陽性率 | 71.2% | **22.7%** |
| useful率(直近窓) | 58.6% | **77.3%** |

### 防御階層昇格
| Bug | 修正前 | 修正後 |
|-----|--------|--------|
| Bug2(計測→行動) | L2(表示のみ) | **L4**(auto_idle_actions+prompt注入) |
| Bug3(useful率二重基準) | L2(スコープ明示) | **L5**(直近窓統一SSOT) |
| Bug4(alias乖離) | L3(再生成依存) | **L5**(index.md SSOT統一) |
| Bug5(ロール偽陽性) | L4(フィルタ) | L4(SKILL.mdロール検出) |

## Obsidian断裂10件

### 強制あり(100%遵守)
- review_log origin: 100%
- lesson_candidate origin: 100%

### 強制なし(0-35%)
1. infra教訓origin: 15% → cmd_3127(origin必須gate)で対処
2. dm-signal教訓origin: 0%
3. context/*.md因果リンク: 35%
4. event_links接続率: 1.2% → cmd_3128(自動抽出)で対処
5. workaround origin: 0%
6. gate_fire_log origin: 0%
7. 掲示板origin: 13%
8. instructions因果リンク: 25%
9. causal_backlinks実行率: 1.5%
10. cmd archive origin: 計測不能

### 根因
強制(gate)がある箇所は100%。ない箇所は0-35%。deepdive Phase 4の証明。

## CMD一覧(本セッション)

| cmd | 内容 | verdict | gate |
|-----|------|---------|------|
| cmd_3114 | shogun cmd_new L4 BLOCK | LGTM | CLEAR |
| cmd_3115 | 教訓useful率改善6件精密化 | RC→LGTM | CLEAR |
| cmd_3116 | 記憶DB live_insert概念付与 | APPROVE→LGTM | CLEAR |
| cmd_3117 | 概念付与テキスト品質改善 | APPROVE→LGTM | CLEAR |
| cmd_3118 | 歴史データ31617件backfill | APPROVE→LGTM | CLEAR |
| cmd_3119 | event_concepts→教訓注入接続 | APPROVE→LGTM | CLEAR |
| cmd_3120 | WARN→idle自走L4化 | APPROVE→LGTM | CLEAR |
| cmd_3121 | 偽陽性71.2%→22.7% | APPROVE→LGTM | CLEAR |
| cmd_3122 | report概念空メタデータスキップ | APPROVE→LGTM | CLEAR |
| cmd_3123 | 短alias完全一致化 | APPROVE→LGTM | CLEAR |
| cmd_3124 | useful率直近窓統一 | APPROVE→LGTM | CLEAR |
| cmd_3125 | hook_automation alias精査 | APPROVE | 配備中 |
| cmd_3126 | DB boost計測ログ | APPROVE→LGTM | CLEAR |
| cmd_3127 | 教訓origin必須gate | APPROVE | 配備中 |
| CI RED | SSH-003c cache汚染修正 | LGTM | CLEAR |

## 洗脳脱却の学び

1. 「1つ見つけて満足」= 洗脳パターン8(完了急ぎ)
2. 「3つだけか」= 想像で結論した。全箇所走査で10件
3. 「十分」と感じた瞬間に疑え
4. 強制(gate)がある=100%遵守。ない=0-35%。例外なし
5. 概念付与(タグ)は自動化できた。因果リンク(なぜ)は判断が必要→半自動化(origin必須gate+フォールバック生成)が解
