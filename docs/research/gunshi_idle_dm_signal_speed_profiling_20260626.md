# DM-Signal Backend 速度プロファイリング結果
<!-- generated: 2026-06-26T06:48:00+09:00 by gunshi idle analysis -->

## 手法

```python
# cProfileで1PF計算時間を計測
import cProfile
pr = cProfile.Profile()
pr.enable()
result = service.calculate(pf.id, 0)
pr.disable()
ps = pstats.Stats(pr).sort_stats('cumulative').print_stats(15)
```

## 全サービス1PF計測結果(2026-06-26)

| # | サービス | 修正前 | 修正後 | 根因 | cmd |
|---|---|---|---|---|---|
| 1 | monthly_trade | 86.2s | 4.5s(94.7%) | N+1 1023クエリ | cmd_3543 CLEAR |
| 2 | annual_returns | 5.71s | 3.44s(40%) | N+1 37クエリ | cmd_3542 CLEAR |
| 3 | monthly_returns | 1.93s | 1.37s(29%) | N+1 30クエリ | cmd_3544 CLEAR |
| 4 | metrics | 4.0s | 1.1s(73%) | to_datetime 15122回 | cmd_3539 CLEAR |
| 5 | trades | 0.72s | 0.33s | to_datetime同型 | cmd_3540 CLEAR |
| 6 | return_calculator | 2.9s | — | 呼出し元キャッシュ渡しで改善見込み | cmd_3542/3544で改善 |
| 7 | benchmark_returns | 3.6s | — | DB connection確立(プーリング) | インフラ問題 |
| 8 | deterioration | 1.3s | — | 純粋計算(newey_west) | 本質的コスト |
| 9 | drawdowns | 0.26s | — | 正常 | — |
| 10 | regime_analysis | 0.19s | — | 正常 | — |

## 本番検証

cmd_3546: fullrecalculate前後 102PF signal_diffs=0 metrics_diffs=0 verdict=PASS

## 速度バグパターン

### パターン1: pd.to_datetimeリスト内包個別呼出し
```python
# BAD: 15122回個別呼出し = 764ms
pd.DataFrame([{"date": pd.to_datetime(e.date), ...} for e in data])

# GOOD: 1回ベクトル化 = 4ms (99.4%削減)
pd.DataFrame({"date": pd.to_datetime([e.date for e in data]), ...})
```

### パターン2: N+1 DBクエリ(ループ内個別SELECT)
monthly_trade: expand_portfolio_to_tickers×月数 → signal cache一括preload
annual_returns: FoF構成PF個別取得 → IN一括+portfolio_cache渡し

## 因果リンク
- → [[cmd_3539]] to_datetimeベクトル化(起点)
- → [[cmd_3543]] monthly_trade N+1解消(最大効果)
- → [[cmd_3546]] 本番冪等性証明
