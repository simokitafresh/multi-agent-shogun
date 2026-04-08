<!-- last_updated: 2026-04-09 -->
# 設計索引: research_engine 4メトリクス追加

## 結論
metrics_research_engine.pyに4メトリクスを追加(34→38)。本番metrics_calculator.py L675-712 calc_dd_stats_monthlyが正本。

## メトリクス
| メトリクス | 定義 | 出力型 |
|-----------|------|--------|
| Underwater Period | 最大DDのpeak→recovery月数 | int / NaN(未回復) |
| Drawdown Length | 最大DDのpeak→trough月数 | int |
| Recovery Time | 最大DDのtrough→recovery月数 | int / NaN(未回復) |
| Information Ratio | active_return / tracking_error | float / NaN(BM無) |

## 変更箇所
- NUMERIC_METRIC_NAMES末尾4行追加
- compute_metrics_from_returns: DD3メトリクス+IR追加
- batch_rolling_metrics: Underwater=ベクトル化可、DD/Recovery=ループfallback、IR=既存値除算
- 破壊的変更なし(末尾追加のみ)

## 詳細
→ `docs/research/gunshi-4metrics-design.md`
