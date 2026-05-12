# 免疫系効果測定 — precheck導入前後のWA率推移
<!-- generated: 2026-05-12T01:30:00+09:00 by gunshi idle analysis -->

## 要約

karo_workaroundsデータで免疫系効果を定量計測。WA率56.0%→6.1%（89%低減）。
直近37件WA=0%。post-precheck WA 61件中、根絶済み2カテゴリ・収束中3カテゴリ。

## 全体推移

| 期間 | WA件数 | clean件数 | WA率 |
|------|--------|-----------|------|
| precheck前(<04-07) | 51 | 40 | 56.0% |
| precheck後(>=04-07) | 61 | 944 | 6.1% |
| 直近37件 | 0 | 37 | 0.0% |

## post-precheck WA原因TOP5と収束状況

| カテゴリ | 件数 | 最終発生 | 状態 |
|----------|------|---------|------|
| report_yaml_format | 9 | 2026-05-05 | 収束中(37件clean) |
| verdict_override | 9 | 2026-04-15 | 根絶 |
| stale_report | 6 | 2026-05-02 | cmd_2481集中(一時的) |
| deploy_error | 5 | 2026-05-04 | 収束中 |
| commit_missing | 4 | 2026-04-13 | 根絶 |

## report_yaml_format 9件の根因

- report_field_set.sh不備: 4件(44%) → ツールバグ。LG014適用
- yaml_field_set.sh構造問題: 2件 → mapping/list挿入位置
- 教訓注入ミスマッチ: 1件 → task_type無関係注入
- Codex忍者手順不完走: 1件 → CLI制約
- triple quote: 1件 → sed修正

## 結論

免疫系（precheck+autofix+gate）は機能している。WA率89%低減。
根絶2カテゴリ(verdict_override, commit_missing)は構造的に二度と発生しない。
収束中カテゴリは道具(report_field_set.sh)改善で対応済み。
