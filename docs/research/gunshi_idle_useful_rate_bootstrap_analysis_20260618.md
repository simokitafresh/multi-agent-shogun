# 教訓useful_rate構造分析: Bootstrap問題 (2026-06-18)
<!-- generated: 2026-06-18T23:45:00+09:00 by gunshi idle analysis -->

## 現状計測

| 指標 | 値 |
|------|-----|
| 効果率(referenced/injected) | 95.5% |
| useful率(USEFUL/total_feedback) | 4.0% (2/50) |
| withheld BLOCK(effectiveness除外) | 281件 |
| フィードバック受領済み教訓 | 204件 |
| 未フィードバック教訓 | 611件 (infra 815件中) |
| universal残存 | 0件 (retag完了済み) |

## 構造的根因: Bootstrap問題

1. infra教訓815件のうち611件(75%)がまだ1回もフィードバック未受領
2. 新しい教訓は初回注入でNOT_USEFUL→effectiveness_score 0%→次回からwithheld BLOCK
3. この「初回NOT_USEFUL」が直近30cmd窓のuseful率を押し下げている
4. 設計通りの自動淘汰は動作中(281件withheld BLOCK実証)
5. 611件が全て1回ずつ試されるまでuseful率は低いまま(Bootstrap期間)

## retag効果の検証

| 期間 | total_feedback | USEFUL | rate |
|------|---------------|--------|------|
| retag前(全期間) | 270 | 22 | 8.1% |
| retag後(2026-06-18T14:00〜) | 18 | 1 | 5.6% |

retag後も改善なし。Bootstrap問題がretagより支配的。

## 対処選択肢

### A. 現状維持(自然淘汰待ち)
- 611件 × 3件/cmd ÷ 30cmd窓 → 約200cmd(100日)で全件1回フィードバック
- 長期的に安定するが、100日間ALERTが続く

### B. ENABLE_ZERO_USEFUL_AUTO_DEPRECATE=1 有効化
- 190件(0% useful)を即deprecate → 注入候補から除外
- 効果: Bootstrap期間を大幅短縮
- リスク: 1回NOT_USEFULで永久deprecate(復活なし)。偽陰性で有用教訓を失う可能性
- 判断: 将軍裁定必要(教訓の永久deprecateは不可逆)

### C. 注入時のpre-filter強化(D0可能)
- cmd descriptionとの意味的類似度が低い教訓をスコア段階で除外
- キーワードスコア閾値の引き上げ(infra cmdでのMIN_KEYWORD_SCORE)
- 効果: Bootstrap期間中のNOT_USEFUL件数を削減
- リスク: 有用教訓の見逃し(recall低下)

### D. 計測方法の改善
- 30cmd窓ではなく「初回フィードバック教訓」を除外した集計
- mature教訓(2回以上フィードバック)のみでuseful率を算出
- 効果: ALERTの精度向上(Bootstrap期間のノイズ除去)
- D0可能: gate_lesson_health.shの計測ロジック修正

## 推奨

D(計測方法改善)をD0即実装。Bootstrap期間の「初回NOT_USEFUL」を計測ノイズとして除外し、
mature教訓のuseful率を正確に計測する。ALERTの精度が上がれば対処の優先度判断も正確になる。

## 因果リンク

- -> [[gunshi_idle_useful_rate_infra_universal_20260618]] infra retag(前セッション)
- -> [[gunshi_idle_useful_rate_batch_retag_20260618]] dm-signal retag
- -> [[LG027]] referenced率≠useful率
