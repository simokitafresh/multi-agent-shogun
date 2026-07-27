# cmd_4180 — fullrecalculate L3 FoF 未確定事項の一次偵察

検証日: 2026-07-27 / 対象run: `20260727014042HSIHNE` / 本番source commit: `00c20c542b70c506874269fbfa3daaf8b7df7fa7`

## 結論

- L3内部内訳は「未計測」ではなく、本番`recalculation_timings.layer_data.L3_fof.metadata.profiling`に保存済みだった。最大は`monthly_returns_gen=275.20s`、次いで`unmeasured=122.41s`、`dw_signals_flush=115.26s`、`daily_loop=80.61s`。
- `calculation_performance_log`の同run行は0件でPF別内訳は回収不能。次の最小配線は既存`FoF portfolio ... completed in ...`のPF時間を`CalculationPerformanceLog(portfolio_id, substep='fof_total')`へ保存する設計であり、今回は実装しない。
- advisory lock排他、FoF依存順の逐次実行、MR生成→commit→cache reload→後続親FoF、全PF終了後のdeferred signal flush、standard→FoF cron直列はコード現物で確定。層内並列は現実装にない。
- trade_perfはFoFだけ別経路ではなく全`target_portfolios`共通ループ。共有cache/N+1除去はFoFにも渡されるため「標準側だけ適用・FoF側未適用」は棄却。ただしFoF 78PFで117.35sという実測ボトルネック自体は確定。

## AC1 — 本番DBの原文

`/db-check` readonly launcherでrun_id固定照合:

```text
('20260727014042HSIHNE', 'recalculate', 'portfolio', 715.74, 'L3_fof',
 'L3_fof': {'status': 'completed', 'metadata': {'profiling': {
 'total_sec': 502.67,
 'db_query_sec': 0.68,
 'db_write_sec': 7.72,
 'cache_init_sec': 14.25,
 'daily_loop_sec': 80.61,
 'price_load_sec': 0.01,
 'unmeasured_sec': 122.41,
 'unmeasured_pct': 24.4,
 'dl_signal_gen_sec': 22.98,
 'dataframe_prep_sec': 1.8,
 'dl_batch_append_sec': 3.52,
 'dl_pipeline_exec_sec': 30.14,
 'dw_signals_flush_sec': 115.26,
 'portfolios_processed': 78,
 'dl_rebalance_check_sec': 23.45,
 'monthly_returns_gen_sec': 275.2,
 'dw_component_weights_sec': 7.43}}})
```

```text
SELECT count(*) FROM calculation_performance_log
WHERE run_id='20260727014042HSIHNE';
(0,)
```

注: profiler項目は重複包含がある。`dw_signals_flush`は`db_write`内訳名だが、最終deferred flush加算分は外側`db_write`計測後であるため、単純合計をtotalと比較しない。最大の未計測塊は122.41s。

保存経路: `backend/app/jobs/recalculate_fast.py:2942-2956`がFoF profilerをL3 metadataへ格納し、`backend/app/utils/timing.py:284-350`が`layer_data`を本番DBへUPSERTする。既存PF別ログ用schemaは`backend/app/db/models.py:832-869`にあるが、当該runは0行。

## AC2 — 引継ぎ仮説の確定/棄却

| 仮説 | 判定 | 一次根拠 |
|---|---|---|
| cross-process advisory lockで再計算排他 | 確定 | `recalc_status.py:297-326,361-404`。`pg_try_advisory_lock`失敗はfail-closed |
| FoFは依存順に逐次 | 確定 | `dependency.py:9-61` Kahn sort、`recalculate_fast.py:1766-1769` sort、`recalculate_fof.py:486-497`単一for-loop |
| 同一依存層内は並列可能/実装済み | 棄却（実装なし） | ready集合はsortされるだけで、executor/async並列なし。並列化にはSession・共有cache・commit境界の再設計が必要 |
| MR/flush/cacheに順序制約 | 確定 | `recalculate_fof.py:1184-1225`: 各子FoFのMR生成→commit→global cache reload後に次PF。signalsは`1124-1146`でin-memory cacheへ即反映し、`1260-1278`で全PF後に一括UPSERT |
| `holding_signal_raw`と当回signal cacheの優先順 | 確定 | `recalculate_fof.py:523-541`でDB生値を入れた後、当回deferred cacheを重ね、後続FoFが当回値を参照 |
| trade_perf N+1除去がFoFに未適用 | 棄却 | `recalculate_fast.py:3105-3129`でbusiness daysと各種preload/cacheを全`target_portfolios`共通ループへ渡す。generator側も外部`price_cache`時は再loadを省略 (`trade_performance.py:208-224`) |
| standard/FoF cronは並列 | 棄却 | `render.yaml:121-143`は01:10/01:40起動だが、FoFは`etl_layer_sync_wait.sh L2_standard sync-fof`。同script `15-19,42-77`が上流の当日成功まで待つため論理直列 |

## 次段の最小計測配線（設計のみ）

1. 既存`CalculationPerformanceLog`を再利用し、`recalculate_fof.py`のPF loop `pf_start_time`〜完了を`layer=L3_fof, portfolio_id, substep=fof_total`としてbuffer保存する。
2. 内訳は既存集計キーを壊さず、PFごとの`daily_loop/monthly_returns/component_weights`差分だけを`extra_data`へ格納する。
3. 78PF行をrun終端で一括INSERTし、run_id FKへ結ぶ。これでPF別top-Nと依存深度別比較が可能になる。
4. 先に122.41s unmeasuredを、PF間GC/キャッシュreload/ログ等へ追加区分する。実装時は既存出力との完全一致を契約にする。

## 二値検証

- AC1: 本番DB L3内訳あり、PF別ログ0件、不能条件と最小配線案あり = yes
- AC2: 6仮説+cron関係を現物行番号で確定/棄却 = yes
- AC3: 本ファイル非空、結論索引へ還流 = yes

