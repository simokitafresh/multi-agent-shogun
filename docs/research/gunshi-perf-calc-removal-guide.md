# Phase 4 perf_calc除去ガイド (軍師作成)

## 概要
recalculate_fast.py Phase4メイン日次ループ内の「パフォーマンス計算ブロック」は
出力先を失ったorphaned code。実測351.34s (Standard PF calcの85.7%)を消費。

## 除去対象

### 1. 変数初期化の除去 (L1355-1374, L1402-1403, L1437)

```
削除: L1355: prev_perf_cache: Dict[str, Tuple[float, float, float, float]] = {}
削除: L1358: segment_start_dates: Dict[str, date] = {}
削除: L1359: segment_value_cache: Dict[str, float] = {}
削除: L1360: segment_value_cache_open: Dict[str, float] = {}
削除: L1363: segment_start_cum: Dict[str, float] = {}
削除: L1364: segment_start_cum_open: Dict[str, float] = {}
削除: L1374: holding_signal_cache: Dict[str, Tuple[List[str], Dict[str, float]]] = {}
削除: L1401: prev_perf_cache[portfolio.id] = (1.0, 1.0, 1.0, 1.0)
削除: L1402: segment_start_cum[portfolio.id] = 1.0
削除: L1403: segment_start_cum_open[portfolio.id] = 1.0
削除: L1437: _seg_start_px: Dict[...] = {}
```

### 2. 月変わりリバランス内のperf_calc初期化 (L1489-1496)
```
削除: L1489-1496のブロック:
    segment_start_dates[portfolio.id] = current_date - _one_day
    segment_value_cache[portfolio.id] = 1.0
    segment_value_cache_open[portfolio.id] = 1.0
    segment_start_cum[portfolio.id] = prev_perf_cache[portfolio.id][0]
    segment_start_cum_open[portfolio.id] = prev_perf_cache[portfolio.id][1]
    _seg_start_px.pop(portfolio.id, None)
```

### 3. perf_calcブロック本体 (L1498-1623)
```
削除: L1498-1623の全体:
    # 1. パフォーマンス計算 (Day T)
    t_perf_start = time.perf_counter()
    prev_cum, prev_cum_open, ... = prev_perf_cache.get(...)
    ... (全累積リターン計算ロジック)
    prev_perf_cache[portfolio.id] = (new_cum, new_cum_open, new_bench, new_bench_open)
    std_profiling["perf_calc"] += time.perf_counter() - t_perf_start
```

### 4. profilingセクションの更新 (L1747-1762)
```
更新: std_profiling["perf_calc"] への参照を除去
更新: [Standard PF Profiling] のログ出力フォーマットを調整
更新: [088b Profiling] のPerfフィールドを除去
```

### 5. std_profiling初期化の更新
```
更新: std_profiling dict から "perf_calc" エントリを削除
```

## 除去しなくてよいもの (ただしdead code化)

以下の関数はperf_calc除去後に呼出し元がなくなるが、
他ファイルからのimportがないため安全に除去可能:
- `_calculate_portfolio_value_at_date_both()` (L378-442)
- `_calculate_portfolio_value_fast()` (L444-530)

**ただし**: これらはPRレビューで判断してもよい。Phase4ブロック除去だけでも効果は同じ。

## 除去してはいけないもの

- L1473-1487: 月変わりリバランスの `holding_signal` 更新 → signals_batchに使用
- L1625-1717: シグナル判定+状態更新ブロック → signals_batchに使用
- L1697-1705: `signals_batch.append(...)` → DB書込み必須

## 検証方法

1. テスト: `pytest tests/ -q --tb=short` (全テスト通過確認)
2. fullrecalculate実行 → `[Standard PF Profiling]`のPerf Calcが0sになることを確認
3. Signalテーブルの値が変わらないことを確認:
   ```sql
   -- 除去前後でsignalの中身が同じか検証
   SELECT portfolio_id, date, signal, holding_signal
   FROM signals WHERE portfolio_id = '<any_pf_id>'
   ORDER BY date LIMIT 10;
   ```

## 推定効果
- Standard PF calc: 410s → ~59s (Signal Calc 0.6s + DB Write 58.2s)
- 全体recalc: 3324.7s → ~2973s (10.6%追加削減)
