# daily_etl 前段3ステップ分析 — cmd_2233偵察

> hanzo作成 2026-04-22。コード読解 + DB recalculation_timings実測に基づく。

## AC1: 前段3ステップの目的・処理内容・呼出し先 + admin fullrecalculate照合

### daily_etl.py の処理フロー

`backend/app/jobs/daily_etl.py:16` `run_etl()`

```
Step 0: run_maintenance_check()         ← maintenance.py:112
Step 1: DataFetcherJob(client).run()    ← data_fetcher.py:26
Step 1.5: generate_ticker_daily_returns(db) ← ticker_returns.py:161
Step 2: RecalculatorJob().run(start_date=FULL_HISTORY_START)
         → recalculate_history_fast(..., mode=PORTFOLIO)  ← recalculate_fast.py:1209
```

---

### Step 0: `run_maintenance_check()` (maintenance.py:112)

**目的:**
1. signal_changeトリガーPFの削除/monthly変換（クリーンアップ）
2. 株式分割・調整データの検出と修正（データ整合性維持）

**処理内容:**
- `_purge_signal_change_portfolios(db)`: rebalance_trigger=="signal_change"のPFを削除またはFoFをmonthlyに変換。DB commit。
- `client.check_adjustments(stock_symbols)`: Stock API `/check_adjustments` 呼出し → needs_refresh_count確認
- splits検出時: `client.fix_adjustments(affected_symbols)` → job_id取得 → polling完了待ち → `client.get_prices()` → `loader.save_prices()` で修正後価格をDB保存

**呼出し先:**
- `StockApiClient.check_adjustments()` / `fix_adjustments()` / `get_prices()`
- `EtlLoader.save_prices()` (etl/loader.py)
- `PortfolioRepository.load()`

**admin fullrecalculate (`recalculate_history_fast`) に同等処理あるか:**
**なし。** `recalculate_history_fast` はDB内の価格データを所与として計算するのみ。分割検出・修正・signal_changeクリーンアップは一切行わない。

---

### Step 1: `DataFetcherJob.run()` (data_fetcher.py:26)

**目的:** 全ポートフォリオ銘柄の直近株価・DTB3データをStock APIから取得してDB更新

**処理内容:**
- `PortfolioRepository.load()` で全PF銘柄収集 (relative_assets / absolute_asset / risk_free_asset / safe_haven_asset / benchmark_ticker)
- `_get_latest_common_date(db, stock_symbols)` でDB最新日確認
- 既存データあり: `latest_date - REFETCH_DAYS` から再取得（差分更新）
- 既存データなし: `today - 730days` から全量取得（初回）
- `fetcher.fetch_prices()` → `loader.save_prices()` で株価保存
- DTB3も同様に `fetch_economic_data()` → `loader.save_economic_data()` で保存

**呼出し先:**
- `DataFetcher.fetch_prices()` (etl/fetcher.py)
- `EtlLoader.save_prices() / save_economic_data()` (etl/loader.py)
- `StockApiClient`

**admin fullrecalculate に同等処理あるか:**
**なし。** `recalculate_history_fast` は価格データ取得を行わない。価格はDBに存在することを前提とする。

**重複判定:** sync-prices cron (01:00 UTC) が同じ `DataFetcherJob.run()` を使用して先に実行済み。daily_etl (03:00 UTC) でのStep 1は2時間後の重複実行。

---

### Step 1.5: `generate_ticker_daily_returns()` (ticker_returns.py:161)

**目的:** Priceテーブルから全銘柄の日次リターン(close-to-close / open-to-open)を事前計算してTickerDailyReturnテーブルに格納

**処理内容:**
- `db.query(Price).order_by(Price.symbol, Price.date).all()` — 全Price読込
- 銘柄別にclose-to-close / open-to-open日次リターンを計算
- `db.query(TickerDailyReturn).delete()` — 既存データ全削除
- `db.bulk_save_objects(records)` — 全件一括保存（冪等）

**呼出し先:**
- `db.query(Price)` / `db.query(TickerDailyReturn)`
- `db.bulk_save_objects()`

**admin fullrecalculate に同等処理あるか:**
**なし（PORTFOLIO modeでは未呼出）。**
- `recalculate_history_fast` FULL mode: `generate_ticker_monthly_returns` のみ呼出(line 1275)。`generate_ticker_daily_returns` は不呼出。
- PORTFOLIO mode (daily_etl使用): ticker層全スキップ。
- sync_tickers cron (01:05 UTC): `generate_ticker_monthly_returns` + `generate_ticker_daily_returns` を両方実行（Layer 1）。

**重複判定:** sync-tickers cron (01:05 UTC) が同じ関数を1時間55分前に実行済み。daily_etlのStep 1でDataFetcherJob.runで新規価格を取得した場合、その新価格を反映するための再計算として意味があるが、sync-pricesが既に01:00に取得しているため価格変化なし = 冗長。

---

## AC2: 66分の実測内訳（DB recalculation_timings + job履歴）

**直近成功job:** `job-d7k7k1cm0tmc73acvga0`

| セグメント | 開始(UTC) | 終了(UTC) | 所要時間 | 割合 | データソース |
|-----------|-----------|-----------|---------|------|------------|
| Build (pip install等) | 07:31:56 | 07:33:47 | ~112s | — | Render build logs |
| Job起動 | 07:33:47 | 07:34:29 | ~42s | — | jobs list vs logs |
| **前段3ステップ** (Step0+1+1.5) | 07:34:29 | 07:37:01 | **152s (2m32s)** | **3.8%** | recalculation_timings started_at計算 |
| **recalculate_history_fast 全体** | 07:37:01 | 08:40:24 | **3803s (63m23s)** | **96.0%** | recalculation_timings elapsed=3802.95s |
| → L2_portfolio | 07:37:01 | ~08:17 | **2382s (39m42s)** | **60.1%** | layer_breakdown.L2_portfolio |
| → L3_fof | ~08:17 | 08:40 | **1151s (19m11s)** | **29.1%** | layer_breakdown.L3_fof |
| → Other (Phase1-3, 4.5, 5等) | 内包 | 内包 | **270s (4m30s)** | **6.8%** | 残差 |
| Job終了処理 | 08:40:24 | 08:40:29 | ~5s | 0.1% | jobs list |
| **合計(実行フェーズ)** | 07:34:29 | 08:40:29 | **3960s (66分)** | 100% | |

**前段3ステップ内の個別時刻は Render logs 未取得のため計測不能。**
代替根拠: sync_layers.pyのLayer 1実測 (recalculation_timings run_id=20260422_085215) で `L1_ticker = 3.8s`。
generate_ticker_daily_returns単体は数秒〜数十秒と推定。

---

## AC3: 前段3ステップのcronで毎日走る必要性判定

| ステップ | 必要か | 判定根拠 |
|---------|--------|---------|
| `run_maintenance_check()` | **必要（代替なし）** | 株式分割検出はどのcron job(sync-prices/sync-tickers/sync-standard/sync-fof)にも含まれていない。分割未検出→価格汚染→全PF計算誤り。signal_changeクリーンアップも同様。 |
| `DataFetcherJob.run()` | **不要（重複）** | sync-prices cron (01:00 UTC, crn-d5e8rabe5dus73fhlkj0) が同一関数を使用して先行実行済み。03:00 UTCに再実行しても新規価格データなし（01:00〜03:00は株式市場closed）。 |
| `generate_ticker_daily_returns()` | **条件付き不要（重複）** | sync-tickers cron (01:05 UTC) が先行実行済み。ただし: daily_etlのStep 1で価格更新後の再計算として設計された経緯あり。sync-pricesが確実に完了していれば不要。 |

**コード引用（DataFetcherJob.runが同一実装）:**
- sync_layers.py:76-87: `sync_prices()` → `DataFetcherJob(client).run(days=days)` — daily_etlのStep 1と同一クラスの同一メソッド
- sync_layers.py:146-158: `sync_tickers()` → `generate_ticker_daily_returns(db)` + `generate_ticker_monthly_returns(db)` — Step 1.5と同一関数

---

## AC4: startCommand変更時の影響列挙

**変更案:** `python -m app.jobs.daily_etl` → `recalculate_history_fast` 直接呼出し (例: `python -c "from app.jobs.recalculate_fast import recalculate_history_fast; ..."`)

### 失われる処理

| 処理 | 影響 | 深刻度 |
|------|------|--------|
| `_purge_signal_change_portfolios()` | signal_changeトリガーPFが残存し続ける。FoFのtrigger補正も未実施 | 中 |
| `client.check_adjustments()` / split修正 | 株式分割・逆分割が未検出のまま誤価格でシグナル計算 → 全PFのリターン誤り | **高** |
| `DataFetcherJob.run()` / 価格取得 | 01:00のsync-pricesが先行実行済みなら影響なし（価格はDB更新済み）| 低 |
| `generate_ticker_daily_returns()` | TickerDailyReturnテーブルが01:05のsync-tickers基準のまま | 低（同じデータ） |

### 問題ない処理

| 処理 | 理由 |
|------|------|
| `recalculate_history_fast` 自体 | 変更後も同じ関数を直接呼ぶため影響なし |
| L2_portfolio / L3_fof計算 | 価格DB状態が01:00のsync-prices完了済みなら同一結果 |

---

## AC5: daily_etl廃止可否の判定根拠

### 判定: **部分廃止可（run_maintenance_checkのみ要分離）**

**廃止可能な根拠:**
- DataFetcherJob.run() → sync-prices (01:00) が代替: `sync_layers.py:84` `fetcher_job = DataFetcherJob(client)` — 完全同一実装
- generate_ticker_daily_returns() → sync-tickers (01:05) が代替: `sync_layers.py:158` `daily_count = generate_ticker_daily_returns(db)` — 完全同一関数
- RecalculatorJob.run() → cronのstartCommandを `curl ... /admin/sync-standard` + `curl ... /admin/sync-fof` に置換可能（既存cronと同一パス）

**廃止不可な根拠 (run_maintenance_check):**
```python
# maintenance.py:112-213
async def run_maintenance_check() -> bool:
    _purge_signal_change_portfolios(db)          # signal_change cleanup
    check_result = client.check_adjustments(...)  # split detection
    if needs_refresh_count > 0:
        client.fix_adjustments(...)               # split fix
        loader.save_prices(chunk_prices)          # corrected data save
```
- この処理はsync-prices/sync-tickers/sync-standard/sync-fof/deteriorationのどのcronにも存在しない
- 株式分割はまれだが発生時の影響が全PF全期間に及ぶ（高リスク）

**廃止シナリオ（条件付き）:**
1. run_maintenance_checkを独立cronとして切り出す (例: 02:55 UTC)
2. daily_etlをrecalculate_history_fastの直接呼出しに変更、またはsync-standard/sync-fofのcronで代替
3. generate_ticker_daily_returnsはsync-tickers（01:05）が代替するため不要

**結論:** daily_etlのボトルネックはrecalculate_history_fast (L2+L3=3533s, 94%)。前段3ステップは152s(3.8%)のみ。廃止・置換の主目的はrun_maintenance_check以外の処理のcronアーキテクチャ整理（重複排除）。
