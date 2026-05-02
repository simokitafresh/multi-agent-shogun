# 軍師idle分析: 観点冷え分析 (2026-04-28)

## 対象
- ambiguity: 直近10件連続0 (zero_streak=10/10)
- adversarial: 直近10件連続0 (zero_streak=10/10)

## adversarial冷え — 前セッション解決済み
- **根因**: 小規模cmd連続(changed_lines<200) + gate閾値がchanged_lines>=200のみ
- **対策**: GP-236 blast_radius判定追加(hook/gate/CLAUDE.md/instructions/settings→adversarial必須)
- **状態**: implemented。次回blast_radius対象draftで発火予定

## ambiguity冷え — 本分析
- **観察**: 直近14レビュー全てambiguity_points=0またはnone
- **対象cmd特性**: GS道具整備(CSV→SQLite変換、OUTPUT_DIR設計)、CI修正、直接実装レビュー
- **因果分析**:
  - 技術的に明確なcmdが連続(パラメータ/パス/形式が一意に特定可能)
  - 研究cmd/設計cmdは曖昧性が生まれやすいが、直近は実装cmdが主
  - 「曖昧性がない」と「曖昧性を見落としている」は区別困難
- **真因判定**: 対象cmdの性質による自然なゼロストリーク(偽冷え)の可能性が高い
  - ただし惰性でnone判定していないか検証不能
- **対策**:
  1. 次回draft reviewでambiguity観点を意識的に再活性化
  2. 研究cmd/設計cmdが来たらambiguity重点チェック(曖昧性が生まれやすい対象)
  3. gate化は不要(対象の性質による自然変動)

## 直近レビュー観点分布 (14件)
| 観点 | 検出率 | 評価 |
|------|--------|------|
| assumptions | 100% | 正常 |
| numbers | 86% | 正常 |
| premortem | 100% | 正常 |
| simulation | 36% | 正常(報告reviewでは不要な場面あり) |
| north_star | 43% | 正常 |
| ambiguity | 0% | 冷え(偽冷えの可能性高) |
| adversarial | 0% | 対策済み(GP-236) |

## 結論
ambiguityの冷えは対象cmdの性質変化(実装系→曖昧性少)による偽冷え。
ただしLOW confidence候補として次回draft reviewで再活性化チェックを行う。
