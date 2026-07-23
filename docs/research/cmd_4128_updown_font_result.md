# cmd_4128 Up vs. Down Market表フォント是正結果

- 検証日: 2026-07-23
- 対象: `/metrics` の「Up vs. Down Market Performance」表（`frontend/components/up-down-market-chart.tsx`）
- 原因: cmd_4127はページ名から`metrics-table.tsx`を対象化したが、残存表の実体は別componentだった
- canonical: 本体数値14px・`ui-monospace`・`tabular-nums`、文字ラベルInter、ヘッダ14px

| 二値計測 | 修正前 | 修正後 |
|---|---:|---:|
| 数値セルの`font-mono text-sm tabular-nums` | 0 | 28 |
| 文字行ラベルへのmono誤適用 | 0 | 0 |
| 対象contract test | 未対象 | 1/1 PASS |
| TypeScript | 未実行 | exit 0 |
| frontend全量Jest | 未実行 | 354/354 PASS・SKIP0 |

数値色classは変更せず、Up Market・Sideways・Down Market・Totalの文字ラベルはInterを維持した。本番デプロイ後の`getComputedStyle`全数再計測と逸脱0証明は将軍の出口責務。

origin: `[[cmd_4127本番CDP出口検証]] -> [[metrics_t1実体_up_down_market_chart]] -> [[cmd_4128全表canonical完了]]`
