# Adversarial観点 冷え分析
<!-- generated: 2026-06-11T13:25:00+09:00 by gunshi idle analysis -->

## 計測結果

- adversarial: 直近10件本番レビューで1/10件(10%)使用
- zero_streak: 不明(startup gateに未表示)
- 全期間: 106件中56件(52.8%)で記録あり

## 因果分析

### 冷えの根因
- adversarial観点のトリガー条件: `changed_lines >= 200` or blast radius大
- 直近10件は clinic-expense-tracker 関連の小規模cmd(changed_lines < 200)が大半
- トリガー条件に合致しないため合理的に不発火

### 記録ギャップの発見
- cmd_3288(report review): SQLインジェクション確認を実施(execute()のパラメータ化クエリ全10件確認、f-string set_clauseのPydanticモデル固定キー確認)
- しかし finding_categories に adversarial を含めなかった
- **セキュリティ関連コード変更のレビューは実質的にadversarial観点の適用だが、記録されていない**

### 改善提案
1. adversarialトリガー条件を拡張: `changed_lines >= 200` に加え「認証/DB操作/ファイル操作を含むコード変更」もトリガーに
2. セキュリティ確認を行った場合はfinding_categoriesにadversarialを明記する
3. changed_lines < 200でもセキュリティ関連ならadversarial_review記録を推奨

## 遡及検証(直近5件)

| cmd | type | changed_lines | adversarial記録 | セキュリティ関連 | 判定 |
|-----|------|--------------|----------------|--------------|------|
| cmd_3288 draft | draft | shallow | No | Yes(SQLi確認) | **記録漏れ** |
| cmd_3288 report | report | 563行 | No | Yes(SQLi確認) | **記録漏れ**(200行超だが報告レビュー) |
| cmd_3285 report | report | 408行 | Yes | Yes(Guard12) | OK |
| cmd_3286 draft | draft | shallow | No | No | OK |
| cmd_3286 report | report | N/A | No | No | OK |

## 結論
- 冷えの主因は「閾値による合理的不発火」だが「記録ギャップ」も混在
- セキュリティ確認を実施してもfinding_categoriesに記録しないケースが存在
- 改善: セキュリティ関連確認時はadversarialを明記する自問を追加

## 因果リンク
- -> [[LG039]] adversarial冷え検知はadaptive gating設計の一部
- -> [[gunshi.md §5.6]] Adaptive Gating運用ルール
- -> [[cmd_3288]] SQLi確認実施but記録漏れの実例
