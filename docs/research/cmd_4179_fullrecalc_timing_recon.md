# cmd_4179 — fullrecalculate TIMING SUMMARY 時点間偵察

- 実施日: 2026-07-27
- 対象: 本番 Render backend `srv-d4ja7q15pdvs739a4q1g`
- 方法: Render Logs CLIによる読み取り限定回収。コード変更・本番実行・DB変更なし
- 結論: v1.1の「id214全体671.18秒から、別runのL5=66.64秒を引いてL5比率9.9%」はrun lineage混算であり棄却する。直近のFoF runではL3が70.3%、L2が21.6%、L5が5.9%で、trade_perfは117秒。standardとFoFは別runなので合算・差引きしない。

## §1 一次ログ原文

### §1.1 直近 standard run

取得コマンド:

```text
render logs -r srv-d4ja7q15pdvs739a4q1g \
  --start 2026-07-27T01:16:05Z --end 2026-07-27T01:16:28Z
```

原文:

```text
2026-07-27 01:16:20 INFO:app.jobs.precompute_raw:precompute_raw completed: rows=363 portfolios=24 failed=0 elapsed=12.61s rss=990.3MB
2026-07-27 01:16:20 INFO:app.utils.timing:[TIMING SUMMARY] recalculate (portfolio)
2026-07-27 01:16:20 INFO:app.utils.timing:  L1_ticker: ⏭️ SKIPPED (mode=portfolio)
2026-07-27 01:16:20 INFO:app.utils.timing:  L2_portfolio: 57.5s (63.3%) ⚠️ BOTTLENECK
2026-07-27 01:16:20 INFO:app.utils.timing:    └─ trade_perf: 1.5s
2026-07-27 01:16:20 INFO:app.utils.timing:  L5_precompute_raw: 12.6s (13.9%)
2026-07-27 01:16:20 INFO:app.utils.timing:  (unaccounted): 20.8s (22.9%)
2026-07-27 01:16:20 INFO:app.utils.timing:  TOTAL: 1m 30s
2026-07-27 01:16:20 INFO:app.utils.timing:[TIMING] Saved to DB: run_id=20260727011449IYJS2V
2026-07-27 01:16:20 INFO:app.jobs.recalculate_fast:[RECALC] Recalculation completed: 4904 days, 97927 signals in 77.68s (calc: 43.22s, 1 commits, matched_weight_warn_count: 0)
```

### §1.2 直近 FoF run

取得コマンド:

```text
render logs -r srv-d4ja7q15pdvs739a4q1g \
  --start 2026-07-27T01:52:30Z --end 2026-07-27T01:52:45Z
```

原文:

```text
2026-07-27 01:52:37 INFO:app.jobs.precompute_raw:precompute_raw completed: rows=1173 portfolios=78 failed=0 elapsed=42.24s rss=1872.9MB
2026-07-27 01:52:37 INFO:app.utils.timing:[TIMING SUMMARY] recalculate (portfolio)
2026-07-27 01:52:37 INFO:app.utils.timing:  L1_ticker: ⏭️ SKIPPED (mode=portfolio)
2026-07-27 01:52:37 INFO:app.utils.timing:  L2_portfolio: 2m 34s (21.6%)
2026-07-27 01:52:37 INFO:app.utils.timing:    └─ drawdown_periods: 2.7s
2026-07-27 01:52:37 INFO:app.utils.timing:    └─ rolling_summary: 8.7s
2026-07-27 01:52:37 INFO:app.utils.timing:    └─ rolling_chart: 5.4s
2026-07-27 01:52:37 INFO:app.utils.timing:    └─ metrics: 8.0s
2026-07-27 01:52:37 INFO:app.utils.timing:    └─ trade_perf: 1m 57s
2026-07-27 01:52:37 INFO:app.utils.timing:    └─ risk_mgmt: 0.9s
2026-07-27 01:52:37 INFO:app.utils.timing:  L3_fof: 8m 23s (70.3%) ⚠️ BOTTLENECK
2026-07-27 01:52:37 INFO:app.utils.timing:  L5_precompute_raw: 42.3s (5.9%)
2026-07-27 01:52:37 INFO:app.utils.timing:  (unaccounted): 15.6s (2.2%)
2026-07-27 01:52:37 INFO:app.utils.timing:  TOTAL: 11m 55s
2026-07-27 01:52:37 INFO:app.utils.timing:[TIMING] Saved to DB: run_id=20260727014042HSIHNE
2026-07-27 01:52:37 INFO:app.jobs.recalculate_fast:[RECALC] Recalculation completed: 0 days, 0 signals in 671.15s (calc: 0.00s, 0 commits, matched_weight_warn_count: 0)
```

## §2 時点間突合

| 時点・run | 対象条件 | TOTAL | trade_perf | L3 | L5 | 判定 |
|---|---|---:|---:|---:|---:|---|
| 2026-06-26 分析 | 当時full run、357.28秒基準 | 357.28s | 約100-105s (約28%) | daily_loop 67.88s + mr_gen 55.21s等 | 当時表に独立記録なし | run ID未記録のため直近runと直接同一条件比較不可 |
| 2026-07-10 id206 / `20260710_040539` | 103PF一括、L5未配線の旧TIMING表 | 2497s | 272.35s (L2内86.3%) | 234s (9.4%) | 1659.78s (66.5%、独立log) | L5 cold再生成が全体を支配 |
| 2026-07-22 id214 | DB statusの総時間のみ | 671.18s | 原文未回収 | 原文未回収 | 原文未回収 | 66.64sはcmd_3835 Phase4の別run。差引き禁止 |
| 2026-07-27 standard `20260727011449IYJS2V` | 24 standard PF | 90.0s | 1.5s (1.7%) | 対象外 | 12.6s (13.9%) | standard単独run |
| 2026-07-27 FoF `20260727014042HSIHNE` | 78 FoF PF | 715.0s | 117s (16.4%、L2内76.0%) | 503s (70.3%) | 42.3s (5.9%) | 現在の主犯はL3 FoF、次点L2 trade_perf |

## §3 矛盾の確定説明

1. **id214のL5=9.9%は無効**: `671.18 − 66.64` は同一runの内訳ではない。671.18秒はid214のDB status、66.64秒はcmd_3835 Phase4の別runであり、先行敵対レビューの不一致判定を一次ソースの出典分離で独立確認した。
2. **trade_perf 100-105→272.35→117秒は同条件の単純回帰系列ではない**: 06-26はrun lineageが索引に残らず、07-10は103PF一括、07-27はstandard 24PFとFoF 78PFが分離runである。PF数・PF集合・cold/warm状態を固定しない倍率比較は不可。ただし直近FoF run内ではtrade_perf 117秒がL2の76.0%を占めるため、二次ボトルネックであることは確定する。
3. **precompute比率差はcold/warmとrun分割で説明できる**: id206は103PF・1548 rowsをcold再生成して1659.78秒(66.5%)、直近はstandard 24PFで12.6秒、FoF 78PFで42.3秒。直近2runのL5合計54.9秒/102PFはid206より約96.7%短い。
4. **設計書再構築の入力**: 優先順位は直近FoF runの同一run内訳に従い、L3 FoF 503秒 → L2 trade_perf 117秒 → L5 42.3秒。L5 9.9%という異run差引きは根拠から除外する。

## §4 未解決事項

- 2026-06-26の357.28秒についてrun ID、PF集合、cold/warm、TIMING SUMMARY原文が索引に残っていない。保持ログから回収できない場合は、比較基準をrun ID付きの07-10と07-27に限定する。
- id214のTIMING SUMMARY原文は今回の指定時刻窓で回収できなかった。DB status総時間は保持するが、Layer内訳には使わない。
- standard/FoFを通した運用壁時計は現在cron分離実行であるため、各runを別々に最適化し、総運用時間は91.3秒+716.6秒=807.9秒として扱う。並列・直列関係を確認せず単一runへ再結合しない。

## §5 因果

`[[id214総時間]] -> [[別run_L5_66.64秒の混算]] -> [[L5_9.9%誤判定]] -> [[run_id単位のTIMING再回収]]`

