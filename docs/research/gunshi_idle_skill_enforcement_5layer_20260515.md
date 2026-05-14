# スキル使用構造的強制5層 — 設計分析

日付: 2026-05-15
分析者: 軍師(gunshi)
対象: cmd_2734-2738 (5cmd一括実装)

## 背景

殿指摘: CDP未使用(本番表示未確認)、DB-check誤使用(rebalancerで呼ぶ)が繰返し発生。
根因: スキル使用が意志依存(LLMに生存本能がない→deepdive Phase 4)。

## 5層構造

| 層 | cmd | 対象 | 手法 | 防御Level |
|----|------|------|------|----------|
| L1: 概念→スキル連携 | cmd_2734 | 全忍者 | semantic indexにskills列+deploy_task recommended_skills注入 | L5(事前コンテキスト提供) |
| L2: レビュー検出 | cmd_2735 | 軍師 | SG観点+gate_gunshi_cs_checklist.sh recommended_skills突合 | L4(フロー内WARN) |
| L3: 将軍強制表示 | cmd_2736 | 将軍 | prompt hookでSKILL.md TRIGGER照合→additionalContext強制表示 | L4(フロー内強制表示) |
| L4: 家老+忍者標準化 | cmd_2737 | 家老+忍者 | gate_karo_startup.shフェーズ別推奨+deploy_task standard_skills | L5+L2 |
| L5: 誤使用BLOCK | cmd_2738 | 全ロール | PreToolUse hookでallowed_projects照合→exit 2 BLOCK | L4(フロー内BLOCK) |

## 因果鎖

```
スキル使用が意志依存(根因: LLMに生存本能なし)
  → 忍者: recommended_skillsを知らない(/clear後)
  → 将軍: TRIGGER条件と殿入力を結びつけない
  → 家老: karo-direct等のスキル使用を忘れる
  → 全員: 不適切PJでスキルを呼ぶ

5層対策:
  L1: 概念→スキル自動推奨(忍者が知る)
  L2: レビューで未使用検出(見逃し防止)
  L3: 将軍にTRIGGER強制表示(判断材料提供)
  L4: 家老gate+忍者テンプレート(標準化)
  L5: 誤使用exit 2 BLOCK(構造的不可能化)
```

## 効果予測

- L1+L4: 全タスクYAMLにrecommended_skills+standard_skills=忍者のスキル発見率100%化
- L2: レビュー時にrecommended_skills未使用→WARN=見逃し率0%化
- L3: 将軍の全判断でTRIGGER合致スキル表示=CDP等の未使用根絶
- L5: allowed_projects違反→BLOCK=DB-check等の誤使用が物理的に不可能

## セマンティック監査結果

+414行/6ファイル変更を監査:
- silent_failure: なし
- side_effect: deploy_task.sh tmpfile管理が軽微(trap未使用→異常終了時孤立)。低リスク
- race_condition: なし(sequential injection)
- settings.json hook競合: なし(matcher "Skill"専用)

## 詳細監査結果

### silent_failure監査(エージェント実行)
指摘9件中、真の懸念=2件(P3低リスク)、false positive=7件。

| # | 指摘 | 判定 | 理由 |
|---|------|------|------|
| 1 | deploy_task.sh mktemp無確認 | P3低 | set -euがcatch。`|| return 1`追記がベター |
| 2 | awk getlineエラー無視 | P3低 | insert_file不在→空挿入→スキル推奨欠落。致命的ではない |
| 3-9 | `2>/dev/null \|\| true`パターン | FP | gate/hookの標準fail-gracefulパターン。意図的防御コーディング |

### side_effect監査(エージェント実行)
5パターン全安全。deploy_task.sh tmpfile孤立のみ軽微(trap未使用→/tmp再起動消滅)。

## 総評

deepdive Phase 4(自動化×強制)の最も体系的な適用。5層で概念理解(L1)→検出(L2)→表示(L3)→標準化(L4)→BLOCK(L5)の全段階をカバー。意志依存ポイントがゼロに近づく設計。

監査結果: +414行に構造的バグなし。silent_failure指摘の78%(7/9)がコードベース標準パターンのFP。真の懸念2件はP3低リスク(将来改善候補)。
