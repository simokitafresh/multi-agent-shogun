# Adversarial冷え観点 再発分析
<!-- generated: 2026-06-23T12:30:00+09:00 by gunshi idle analysis -->

## 事象

冷え観点(adversarial) WARN が再発。前々セッション(2026-06-21)で11件→0件に修正済みだったが、今セッション(2026-06-23)で10件再発。

## 対象エントリ

cmd_3504〜cmd_3509のdraft/reportレビュー計10件。全てGS/WF計算系cmd。

## 根因分析

| 層 | 内容 |
|---|---|
| 表層 | finding_categoriesにadversarialが未記載 |
| 中層 | GS/WF系cmd(changed_lines < 200, セキュリティ非関連)→adversarial_review非該当→記載不要と判断 |
| 根因 | review-bundle SKILL.mdに「全レビューでadversarialを含めよ」ルールあるが、手動記入=意志依存。deepdive Phase 4再帰 |

## 再発構造

```
6/17: 家老指示「adversarial該当なしでもfinding_categoriesに含めよ」
6/21: 11件遡及修正→0件
6/23: 新規レビュー10件で再発(ルール読んだが書かなかった)
```

意志依存のルールは/clear跨ぎで確実に忘れられる。SKILL.mdに書いても読んでも実行は保証されない。

## 修正実績

- 修正前: WARN 10件(adversarial冷え)
- 修正後: WARN 0件(冷え解消)
- gate総合判定: WARN → OK

## 対策

| # | 対策 | Level | 状態 |
|---|------|-------|------|
| 1 | 次レビューからfinding_categoriesに6観点全記載を意識 | L2(doc) | 即時 |
| 2 | gate_gunshi_cs_checklist.shの冷え観点WARNがreview-bundle実行前にチェックされる仕組み | L4(BLOCK) | 中期検討 |

## 因果リンク

- → [[冷え観点WARN_20260621]] 前回修正
- → [[冷え観点WARN_20260623]] 今回再発
- → [[deepdive_why_chain Phase 4]] 意志依存=壊れる構造
- → [[LG013]] CS観点/finding_categories記録義務
