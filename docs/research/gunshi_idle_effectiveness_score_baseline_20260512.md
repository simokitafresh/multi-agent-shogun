# Effectiveness Score 効果 Baseline (cmd_2700 CLEAR時点)
## 2026-05-12 軍師idle自走計測

### cmd_2700導入パラメータ
- USEFUL_RATE_THRESHOLD: 0.40
- USEFUL_RATE_MIN_SAMPLES: 5
- 計算式: USEFUL / (USEFUL + NOT_USEFUL)。他result種別は分母除外

### 導入時即時効果
| 指標 | 値 |
|------|-----|
| qualified feedback教訓数 | 94件 |
| MIN_SAMPLES≥5の教訓 | 15件 |
| EXCLUDED (score<0.40) | 11件 |
| KEPT (score≥0.40) | 4件 |
| サンプル不足(除外対象外) | 79件 |

### 除外教訓リスト(score<0.40, fb≥5)
| ID | Score | USEFUL/Total | 除外理由 |
|----|-------|-------------|---------|
| L087 | 0.00 | 0/5 | 既修正バグ |
| L314 | 0.00 | 0/6 | 廃棄ツール互換性 |
| L415 | 0.00 | 0/5 | 廃止CDP仕様 |
| L511 | 0.00 | 0/7 | gate_metrics最適化失敗例 |
| L509 | 0.14 | 1/7 | コールド計測重複 |
| L512 | 0.17 | 1/6 | WSL2 I/O詳細 |
| L287 | 0.20 | 1/5 | WSL2パスエッジケース |
| L324 | 0.20 | 1/5 | 旧PJ詳細 |
| L510 | 0.20 | 1/5 | gate_fire_log分析 |
| L583 | 0.20 | 1/5 | gate_loop_healthバグ |
| L262 | 0.33 | 2/6 | 陳腐化指示 |

### 推定CTX削減
- 1教訓≈150-200 tokens
- 11件除外 → 1,650〜2,200 tokens/タスク削減

### 次回計測ポイント(5-10配備後)
1. 実際の除外教訓数(withheld log確認)
2. 忍者のlessons_useful変化(除外後のuseful率)
3. feedback率(79/94=84%がサンプル不足→feedback率向上が次のボトルネック)

### 前回baseline(cmd_2685 CLEAR時)
- useful率: 28.4%(直近20cmd)
- referenced率: 50.9%
