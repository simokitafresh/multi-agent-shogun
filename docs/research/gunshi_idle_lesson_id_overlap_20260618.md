# 教訓ID重複分析: dm-signal/infra間745件
<!-- generated: 2026-06-18T23:30:00+09:00 by gunshi idle analysis -->

## 発見

dm-signal教訓750件のうち745件がinfra教訓815件と同一IDで重複。

| プロジェクト | 教訓数 | 重複ID数 |
|-------------|--------|---------|
| dm-signal | 750 | 745 |
| infra | 815 | 745 |

## 影響分析

deploy_task.shの`_lesson_project_allowed()`フィルタにより:
- infra(type=platform)教訓 → 全cmdに注入候補（platformは全cmd許可）
- dm-signal教訓 → dm-signal cmdにのみ注入

ID重複自体は注入ロジックに直接影響しない（教訓のロード元が別ファイルのため独立管理）。
しかし以下のリスクがある:
1. lesson_impact.tsvでlesson_idが同一→フィードバック混同の可能性
2. lesson_write.sh --retireでID指定→意図しないPJの教訓が退役される可能性
3. 効果率計算でPJ間のfeedbackが混ざる可能性

## 対処方針

構造的問題だがblast radius小（注入ロジックはPJ別ロード）。
次セッション以降のidle自走で段階的に対処:
1. 計測: lesson_impact.tsvでID重複教訓のfeedback混同件数を定量化
2. 判断: 混同が0件なら対処不要。1件以上なら命名規則(PJプレフィックス)導入を提案

## 因果リンク

- -> [[gunshi_idle_useful_rate_infra_universal_20260618]] 発見経緯
- -> [[LG027]] 計測対象のズレ
