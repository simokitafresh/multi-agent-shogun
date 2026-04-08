# cmd_498 Karo Independent Assessment

- 実施者: karo
- 実施日時: 2026-03-03 19:26 JST
- 対象リポジトリ: `/mnt/c/Python_app/DM-signal`
- 判定: **一致**（将軍見解「ticker_daily_returns更新のみでは当月holding_signalは変わらない」と一致）

## §1 `backend/app/api` での `TickerDailyReturn` 参照範囲（AC1）

### 1.1 直接参照（モデルをimport/query）

| 分類 | API | 実装行 | 根拠 |
|---|---|---|---|
| 本番利用 | `GET /api/benchmark/{ticker}` | `backend/app/api/benchmark.py:12,51-57,61,63` | `TickerDailyReturn` を直接queryし、日次を月次集計して返却。認証は `require_viewer` (`benchmark.py:27`) |
| 管理用 | `GET /api/debug/ticker-daily-returns` | `backend/app/api/debug.py:10,555-586` | `TickerDailyReturn` を直接query/count/distinct。認証は `require_admin` (`debug.py:560`) |

### 1.2 コメント/説明のみ（実データ参照なし）

| 分類 | API | 実装行 | 根拠 |
|---|---|---|---|
| コメントのみ | `POST /admin/sync-tickers` | `backend/app/api/etl_trigger.py:782` | Docstringで `ticker_daily_returns` を説明するのみ |
| コメントのみ | `GET /api/mtd/{portfolio_id}` | `backend/app/api/performance.py:158` | Docstringで `ticker_daily_returns` を説明するのみ |

補足:
- `backend/app/api/backfill.py:284-286` は `generate_ticker_daily_returns()` 呼び出し（再生成トリガー）であり、`TickerDailyReturn` の直接queryではない。

## §2 「ticker_daily_returns更新だけで当月holding_signalが変わるか」（AC2）

### 結論
**No（変わらない）**。  
条件: 「ticker_daily_returnsテーブルのみ更新」「Priceやportfolio設定は不変」。

### 根拠コード経路

1. `holding_signal` の更新タイミングは月変わり時のみ。  
   - `backend/app/jobs/recalculate_fast.py:1426-1430`  
   - 月替わりで `current_holding_signals[pf] = last_generated_signals[pf]`

2. `last_generated_signals` は当日 `signal` から更新。  
   - `backend/app/jobs/recalculate_fast.py:1573-1638,1658`

3. その `signal` 計算入力は `Price` 系データ。  
   - 価格ロード: `recalculate_fast.py:721` → `load_prices_as_df()`  
   - `load_prices_as_df()` は `Price` テーブルをquery: `backend/app/utils/data_loader.py:24-28`  
   - pipeline実行入力は `price_data_cache=price_by_symbol`: `recalculate_fast.py:1597,1624`

4. `TickerDailyReturn` は読み込むが、現行実装では計算に未使用。  
   - ロード: `recalculate_fast.py:839`  
   - 参照検索結果: `returns_by_symbol` は定義/代入/ログ以外で未使用（`recalculate_fast.py:295,297,839,842,845,850`）

5. L1 `sync-tickers` は ticker return再生成のみで、Signal更新を行わない。  
   - `backend/app/jobs/sync_layers.py:155-158`（monthly/daily returns生成）  
   - Signal再計算はL2 `sync_standard` で `recalculate_history_fast` 呼び出し: `sync_layers.py:243-248`

## §3 将軍見解との照合（AC3）

- 将軍見解: 「holding_signalは変わらない」
- 家老独立判定: **一致**
- 追加発見:
  - `recalculate_fast.py` で `TickerDailyReturn` をロードしているが、実計算経路で未使用（デッドコード相当）。
  - 現時点の仕様では、`ticker_daily_returns` は主に benchmark/debug/管理系補助用途。

