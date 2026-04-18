# Phase 4 fullrecalculate改善方針 v3 (C1後改訂)

<!-- created: 2026-04-17 -->
<!-- v2 revised: 2026-04-17T01:40 殿指摘: 本番=Render(Singapore内RTT 1-5ms)、ローカル=WSL2(RTT 80ms) -->
<!-- v3 revised: 2026-04-18T00:40 C1(DELETE→UPSERT化)完了後の本番計測反映。A面優先順位をself timeで改訂 -->
<!-- source: cmd_1994 cProfile + cmd_1998偵察 + RTT実測 + cmd_2000 SQLクエリ実測 + cmd_2007 preload3パターン実測 + cmd_2001 Render cProfile + cmd_2012 DELETE分析 + cmd_2017 C1 impl + cmd_2021 C1後本番計測 -->

## §0 前提(v3改訂)

| 項目 | 値 |
|------|-----|
| 対象 | `backend/app/jobs/recalculate_fast.py` (2960行) + 関連モジュール |
| **本番実測(C1前)** | **480s** (Phase 3完了時点) |
| **本番実測(C1後)** | **842s (cProfile込み)** → 推定 **~124s (cProfile overhead 6.8x除去)** |
| cProfile overhead | **6.8x** (3250s/480s で推定。operation typeにより変動) |
| Render cProfile(C1前) | 3250s (うちDELETE FROM signals 2505s = 77%) |
| Render cProfile(C1後) | **842s** (DELETE除去後。cmd_2021実測) |
| パリティツール | compare_recalc_results.py + compare_snapshots.py + --exclude-months (完成済み) |
| Phase 3パターン | A: precomputed masks (100x, monthly-only), B: キャッシュ+再利用 (3-5x) |

### ★ v2→v3の根本変更: C1(DELETE→UPSERT化)完了

| 指標 | C1前 | C1後 | 改善 |
|------|------|------|------|
| Render cProfile total | 3250s | **842s** | **-74%** |
| DELETE FROM signals | 2505s (77%) | **0s** | **-100%** |
| cleanup除外後(≈Python計算) | 746s | 842s | (cProfile条件差) |

**C1の効果**: DELETE 2505s の完全除去。signals 627k行の毎回全件DELETE+再INSERTが、UPSERT(INSERT ON CONFLICT DO UPDATE)に変換された。

### 2環境の分離(v2から継続)

| 環境 | DB RTT | cursor.execute 10293回(実測) | DB I/O比率 | ボトルネック |
|------|--------|----------------------|-----------|------------|
| **本番(Render内)** | 1-5ms | 10-50s | **2-10%** | **Python計算** |
| ローカル(WSL2) | 80ms(実測) | 823s | **69%** | DB往復latency |

### cmd_1998偵察で否定された仮説(v2から継続)

| v1仮説 | 偵察結果 | 判定 |
|--------|---------|------|
| T1-1: signal_cache miss大量 | miss 0/26806 (0%) | **否定** |
| T1-2: fallback大量 | 436/26738 (1.63%, 全件partial_final_month) | **限定的** |
| T2-2: component_weights N+1 | N+1なし、既バッチ化(79405 INSERT削減) | **既達成** |

## §1 ★ C1後self time分析(cmd_2021 — A面優先順位逆転)

C1後Render本番計測(cmd_2021)で**cumtimeとself timeの決定的乖離**が判明。

| 関数 | cumtime | self time | 乖離率 | 意味 |
|------|---------|-----------|--------|------|
| A2 _generate_trade_performance | 100.01s | **1.48s** | 98.5%子関数 | A2自体は1.5sしか消費していない |
| A3 expand_portfolio_to_tickers | 65.92s | **19.07s** | 71%自身 | **A3自体が19s消費 = 唯一の有意なターゲット** |
| A1 calculate_trade_period_return | 8.90s | **0.61s** | 93%子関数 | A1自体は0.6sで改善余地ほぼゼロ |

**優先順位逆転**:
- v2 cumtime順: A2(534s) > A3(402s) > A1(383s)
- **v3 self time順: A3(19.07s) >> A2(1.48s) > A1(0.61s)**

**結論**: A2のcumtime 100sの98.5%は子関数(expand等)が消費。A2自体を軽量化しても1.5sしか改善しない。A1は0.6sで改善余地ほぼゼロ。**A3(月粒度キャッシュ, -19s)が唯一の有意な改善ターゲット**。

## §2 両面作戦(v3改訂)

### 面C: cleanup最適化 — ★完了(C1)

| # | 対象 | 改善手法 | 結果 | status |
|---|------|---------|------|--------|
| **C1** | signals DELETE 2505s(77%) | DELETE→UPSERT化 | **-2505s (-100%)** | **★DONE (cmd_2017)** |

C1実装: `recalculate_fast.py` の `_cleanup_before_recalculate()` でsignals DELETEスキップ → `signal_flush.py` のINSERT ON CONFLICT DO UPDATEで上書き。

### 面A: 本番改善(v3改訂 — self time基準)

**★ v2からの根本変更**: cumtime基準→self time基準。

| # | 対象 | self time | 改善手法 | 推定効果 | ROI |
|---|------|-----------|---------|---------|-----|
| **A3** | expand_portfolio_to_tickers | **19.07s** | 月粒度キャッシュ。1.17M回→~50K回 | **-15〜19s** | **★★★** |
| A2 | _generate_trade_performance | 1.48s | オブジェクト軽量化 | **-1s** | ☆ (費用対効果低い) |
| A1 | calculate_trade_period_return | 0.61s | NumPy化 | **<1s** | ☆ (費用対効果低い) |
| A4 | _recalculate_fof_history | 未計測 | 月中バッチ | 要計測 | ? |
| A5 | flush/write | 未計測 | COPY Protocol | 要計測 | ? |

**v3の焦点**: A3のみが有意な改善ターゲット。A1/A2はself timeが小さく、単体最適化の費用対効果が低い。

#### A3詳細: expand_portfolio_to_tickers月粒度キャッシュ

```
現状: 1,168,384回呼出。cache hit 100%だが呼出自体のPythonオーバーヘッド(self 19.07s)
改善: 同一PF×同一月の結果をメモ化(月初signal不変→月中呼出は全て同一結果)
      monthly granularity cacheで呼出回数 1.17M → ~50K (月数×PF数)
期待: self time 19.07s → 数秒 (-15〜19s)
```

### 面B: ローカル改善(v2から継続)

| # | 対象 | 改善手法 | 推定効果 | status |
|---|------|---------|---------|--------|
| **B1** | SELECT 7022回 | IN句バルク化 | **-554s(ローカル)/-5s(本番)** | **★DONE(cmd_2006)** |
| B2 | INSERT 2433回+DELETE 838回 | bulk UPSERT統合 | -260s(ローカル) | 未着手 |
| B3 | flush 181回 | flush削減+commit集約 | 検証要 | 未着手 |

### A面・B面の関係(v3改訂)

```
C1完了(DELETE除去) + B1完了(N+1除去) = ループ内が純Python計算のみ
  → A3(月粒度キャッシュ)が唯一の有意ターゲット
  → A1/A2のself timeが極小 = 単体最適化の前にA3を先行
```

## §3 実装計画(v3改訂)

| 順序 | ID | 対象 | 面 | 推定本番効果 | status |
|------|-----|------|---|-----------|--------|
| ~~偵察~~ | ~~cmd_2001~~ | ~~Render cProfile~~ | A | — | **★DONE** |
| ~~C1~~ | ~~cmd_2017~~ | ~~DELETE→UPSERT~~ | C | **-2505s(cProfile)** | **★DONE** |
| ~~計測~~ | ~~cmd_2021~~ | ~~C1後本番計測~~ | — | ベースライン確定 | **★DONE** |
| ~~B1~~ | ~~cmd_2006~~ | ~~preload N+1除去~~ | B→A前提 | **-5s(本番)/-554s(ローカル)** | **★DONE** |
| **次** | **A3** | **expand月粒度キャッシュ** | A | **-15〜19s** | **未着手** |
| (後) | A4/A5 | daily_loop/flush | A | 要計測 | 未着手 |
| (後) | B2/B3 | bulk UPSERT/flush削減 | B | ローカル改善 | 未着手 |

### 本番推定改善(v3)

| 状態 | cProfile時間 | 推定本番(÷6.8x) | 改善率 |
|------|-------------|-----------------|--------|
| Phase 3完了(C1前) | 3250s | **480s** | baseline |
| **C1完了(現在)** | **842s** | **~124s** | **-74%** |
| A3完了後 | ~823s | **~121s** | -2.4% |
| B2/B3完了後 | 要計測 | — | — |

※ cProfile overhead 6.8xはoperation typeにより変動するため、推定本番=cProfile÷6.8xは近似値。
※ A3の-15〜19sはself timeベース。cProfile overheadを考慮すると推定本番効果は-2〜3s程度。

### 次の偵察候補

A3のself time 19.07sが本番でどの程度になるかの精密推定:
1. **expand_portfolio_to_tickers 内の処理breakdown**: 19.07sの内訳(辞書lookup/リスト構築/signal decode)
2. **月粒度キャッシュの重複率実測**: 1.17M回のうちPF×月の一意組合せは何通りか

## §4 cmd_2000結果(SQLクエリ実測 — v2から継続)

cmd_2000(半蔵)でSQLAlchemy queryロギングをcmd_1994ハーネスに追加し実測完了。

**Top N+1パターン(バルク化候補)**:
| rank | パターン | 回数 | cProfile時間 | 発生元 |
|------|---------|------|-------------|--------|
| 1 | portfolio N+1 (SELECT WHERE id=?) | 2,706回 | 224s | price_ratio_calculator.py:1042,1096,1171 |
| 2 | signal N+1 (SELECT date<=? LIMIT1) | 1,985回 | 161s | price_ratio_calculator.py:1004-1007 |
| 3 | signals batch INSERT | 136回 | 101s | — |
| 6 | signals IN句 (avg 12.7s) | 4回 | 51s | 全体スキャン疑い |

**N+1真因(cmd_2003疾風偵察で確定)**:
- monthly_returns.py L183-191: signal_cacheに親PFがあるとpreload_fof_signals_recursive()をスキップ → child signal/portfolioが未プリロード → 月ループ(L222-277)内で遅延DB呼出
- **修正完了**: B1(cmd_2006)でpreload条件修正済み

## §5 FE/UI影響範囲(v2から継続)

### §5.1 AC1結論: preload有無で monthly_return 計算値は変わらない

結論: `backend/app/jobs/generators/monthly_returns.py:183-191` の preload 分岐は、**monthly_return の計算結果ではなくクエリ経路だけ**を変える。

根拠:
- `monthly_returns.py:183-191` は `portfolio_id not in signal_cache` のときだけ `preload_fof_signals_recursive()` を呼ぶ。外部 `signal_cache` が親PFのみ保持している場合、child signal / child portfolio の事前投入をスキップする。
- その後の実計算では `monthly_returns.py:272-277` が毎月 `expand_portfolio_to_tickers(..., signal_cache, portfolio_cache, component_signal_date=calc_start_date)` を呼ぶ。
- `price_ratio_calculator.py:993-1030` の `get_signal_payload_at_date()` は cache miss 時に `SELECT ... WHERE portfolio_id = pid AND date <= dt ORDER BY date DESC LIMIT 1` を実行し、取得結果をその場で `signal_cache` に memoize する。
- `price_ratio_calculator.py:1038-1045, 1093-1099, 1168-1173` も `portfolio_cache` miss 時に DB から Portfolio を読み、その場で cache に入れる。
- よって **Signal / Portfolio が DB に存在する限り**、preload あり/なしで `expand_portfolio_to_tickers()` が得る holding/weights は同一であり、後段 `monthly_returns.py:280-320` の `calculate_weighted_return()` / benchmark 上書き結果も同一。

含意:
- 差が出るのは query count / latency のみ。`cmd_2000` の signal N+1 (1,985回) / portfolio N+1 (2,706回) はこの preload 漏れと整合。
- したがって `monthly_returns.py:183-191` の修正は **性能修正** であり、期待されるユーザー向け値差分はない。

### §5.2 monthly_returns系 API 影響範囲

| API | 根拠 | monthly_returns由来の影響フィールド | FE使用先 |
|-----|------|------------------------------|---------|
| `/api/monthly-returns/{id}` | `backend/app/api/monthly_returns.py:84-112` + `services/monthly_returns_calculator.py:152-330` | `monthly_returns[]`, `portfolio.return(_open)`, `portfolio.balance(_open)`, `benchmark.return(_open)`, `benchmark.balance(_open)`, `tickers`, `tickers_open`, `partial_note`, `is_mtd`, `is_pending`, `total_months` | `frontend/app/monthly-returns/page.tsx`, `frontend/components/monthly-returns-table.tsx` |
| `/api/annual-returns/{id}` | `backend/app/api/annual_returns.py:70-98` + `services/annual_returns_calculator.py:63-220` | `annual_returns[]` の `portfolio.return(_open)`, `portfolio.balance(_open)`, `benchmark.return(_open)`, `benchmark.balance(_open)`, `tickers(_open)`, `partial_note` | `frontend/app/annual-returns/page.tsx`, `AnnualReturnsTable`, `AnnualReturnsChart` |
| `/api/monthly-trade/{id}` | `backend/app/api/monthly_trade.py:133-183` + `services/monthly_trade_calculator.py:69-105` | `entries[]` の `monthly_return(_open)`, `cumulative_return(_open)`, `benchmark_return`, `is_mtd`, `is_partial`, `expanded_tickers` | `frontend/app/monthly-trade/page.tsx`, `MonthlyTradeTable` |
| `/api/performance/{id}` | `backend/app/api/performance.py:76-147` | `total_return[]` の `cumulative_return(_open)`, `benchmark_return(_open)`, `signal/raw_signal` | `frontend/app/dashboard/page.tsx`, `frontend/app/compare/page.tsx`, `TotalReturnChart`, `ComparisonChart` |
| `/api/drawdowns/{id}` | `backend/app/api/drawdowns.py:55-62` + `services/drawdowns_calculator.py:40-70,106-139` | `portfolio_drawdowns`, `benchmark_drawdowns`, `chart_data`（`monthly_returns.cumulative_*` / `benchmark_cumulative*` 由来） | `frontend/app/drawdowns/page.tsx`, `DrawdownsChart`, `DrawdownsTable` |
| `/api/rolling-returns/{id}` | `backend/app/api/rolling_returns.py:58-69` + `jobs/generators/rolling_returns.py:23-129,144-219` | `summary`, `chart_data`（`cumulative_return(_open)`, `benchmark_cumulative(_open)` 由来の事前計算） | `frontend/app/rolling-returns/page.tsx`, `RollingReturnsSummaryTable`, Rolling Returns chart |
| `/api/metrics/{id}/up-down-market` | `backend/app/api/metrics.py:366-373` + `services/up_down_market_analyzer.py:57-97` | `summary.up_market/down_market`, `bins[]`（`monthly_return`, `benchmark_return` 由来） | `frontend/app/metrics/page.tsx`, `UpDownMarketChart` |
| `/api/trades/{id}` | `backend/app/api/trades.py:145-169` + `services/trades_calculator.py:472-499,800-847` | `risk_management` fallback, `trades[].portfolio_return`, `benchmark_return`, `excess_return`（MonthlyReturn / trade-period return 由来） | `frontend/app/_deprecated/trades/page.tsx`, `ModelTradesTable` |

### §5.3 FE/UI結論

結論: `monthly_returns.py:183-191` の preload 条件修正だけなら、**FE表示差分は発生しない想定**。

## §6 preload動作3パターン実測(cmd_2007)

cmd_2006(B1 impl)の事前確認。production target_date=2026-04-15で実測。

### §6.1 代表PF選出

| パターン | 代表PF | UUID | depth | components | descendants |
|---------|--------|------|-------|------------|-------------|
| standard | ALM朱雀-常勝 | d5bd051e-7948-58a3-9f48-42bf9412af0b | 0 | 0 | 0 |
| FoF | Ave-X | a78887bf-25ae-4525-81af-cd4c630b3d36 | 1 | 6 | 6 |
| nestedFoF | MIX1 | 899b3d8e-f5c6-43ef-ae5e-134e78952ee1 | 2 | 8 | 20 |

### §6.2 preload_fof_signals_recursive() 実測(parent-only cache seed)

| PF | preload呼出 | missing descendants | portfolio SELECT | signal SELECT |
|----|------------|-------------------|-----------------|--------------|
| ALM朱雀-常勝 | なし | — | 0 | 0 |
| Ave-X | あり | 6→0 | 1 | 1 |
| MIX1 | あり | 20→0 | 3 | 3 |

### §6.3 baseline成果物

| ファイル | 内容 |
|---------|------|
| `outputs/analysis/cmd_2007_preload_scout/cmd_2007_preload_probe_light.json` | 3体preload実測JSON |
| `outputs/analysis/cmd_2007_preload_scout/cmd_2007_monthly_returns_snapshot.csv` | 509行(進行中月2026-04除外) |

### §6.4 golden data

| 項目 | 値 |
|------|----|
| golden path | `outputs/golden/phase4_monthly_returns_baseline.csv` |
| source cmd | `cmd_2007` |
| line count | 509 |
| target_date | `2026-04-15` |
| parity condition | `compare_recalc_results.py` で差 `< 1e-6` |
| md5 | `cc0a5a3bb0ea64185c0b3cf451181f2e` |

## §7 C1実装詳細(cmd_2012→cmd_2017→cmd_2021)

### §7.1 DELETE真因(cmd_2012)

- `_cleanup_before_recalculate()` (L718-769) がsignals含む全core/precompute/global tablesを毎回全件DELETE
- signals DELETE = 627k行 × 毎回 = 2505s (77%)
- UPSERT化可能: PK(portfolio_id, date)にON CONFLICT既存(signal_flush.py)
- CASCADE不一致: models.py=ondelete CASCADE vs 本番DB=CASCADE欠落(スキーマドリフト)→cmd_2016で確認

### §7.2 UPSERT化前提(cmd_2013)

- fullrecalculate PF×date網羅性: **181/181 (100%)**
- orphan signal行: **0件**
- inactive PF: **0件**
- full recalcはis_activeフィルタなしで全PF対象 → UPSERT化の前提(網羅性)成立

### §7.3 C1後本番計測(cmd_2021)

- total: 3250s → **842s (-74%)**
- C1効果実証
- self time分析 → §1参照(A面優先順位逆転)
- 追加発見: FoF deferred flush UniqueViolation → PR#13修正

## §8 Phase 4全体進捗

| Phase | 内容 | 結果 | status |
|-------|------|------|--------|
| Phase 1 | CoDD Python適用検証 | review/implement=codd-pro依存→ハイブリッド確定 | **★DONE** |
| Phase 2 | 全量cProfile(139本) | Top3=yotsume(5.3s)/nukimi(3.4s)/oikaze(2.2s) | **★DONE** |
| Phase 3 | レベルA改善5本 | yotsume -98.6%/oikaze -99.3%/nukimi -63.3%/bunshin -78%/l1_alm_wf -81% | **★DONE** |
| Phase 4 | fullrecalculate改善 | C1(-74%)+B1(N+1除去)+self time分析完了 | **進行中** |
| — | A3(月粒度キャッシュ) | 唯一の有意なA面ターゲット(-15〜19s) | **次** |
