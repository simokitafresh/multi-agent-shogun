# cmd_4246 現物接続マップ・月次リターン基本原理照合

- 調査日: 2026-08-09
- task: `cmd_4246_scout`
- 対象: `/mnt/c/Python_app/DM-Signal` の現物コード・schema・frontend
- 制約: read-only偵察。コード変更、DB書込み、deployは実施していない
- 原文: `docs/research/dm-monthly-return-first-principles-original_20260809.md`（殿原文・改変禁止）
- 参照設計: `docs/research/dm-monthly-trade-bug-asis-tobe-5w1h_20260802.md` v5.22

## 1. 結論

1. 確定月の通常計算は `Return = End / Start - 1` の形を保っている。実装上の複雑性は、価格比そのものではなく、expanded holdingの切替日、Open/Close二系列、ledger確定域、MTD/Partial/Not-started分類、FoFキャッシュに集中している。
2. 書込み正本は `monthly_returns` で、`_generate_monthly_returns()` が Close/Open・benchmark・累積・holdingを同一rowへUPSERTする。API/UIはこの保存値を読み、当月だけ同じcalculatorで再計算する。
3. `Monthly Trade` は通常の保存済み月と、価格未到着時の動的pendingを同じレスポンスへ束ねる。pending行は `monthly_returns` に保存されず、`is_pending=true` かつreturn=nullで返る。
4. `historical_backfill` は一回限りの復元用eventとして設計されているが、読み側の `resolve_ledger_decisions_bulk()` はevent_typeを通常計算用と分離せず、同じ適用候補へ入れる。これは「履歴修復レイヤーを通常経路へ混ぜない」という原則に対する境界上の残課題である。
5. 月替わり直後に新月の初回価格が未到着なら、Monthly Tradeはpendingを返せる。一方、Monthly Returns APIは当月MonthlyReturnが無い場合にpendingを生成せず、既存の確定行だけを返す（全rowが無ければ404）。前市場日の確定Closeを利用するprovisional sourceは、現行ではOpen系列の速報補助に限定され、通常のClose確定値へ混入していない。

## 2. AC1: 8系統の接続マップ

### 2.1 全体経路

```text
recalculate_fast Phase 4.5 / Layer 2
  -> _generate_monthly_returns
     -> Signal/Portfolio/Price/TickerMonthlyReturn読込
     -> expanded holding切替日を算出
     -> resolve_ledger_decisions_bulk
     -> resolve_monthly_boundary
     -> PriceCache.get_price_ratio_both (Close, Open)
     -> cumulative + MonthlyReturn records
     -> monthly_returns DELETE条件判定 + PostgreSQL UPSERT + commit

MonthlyReturn rows
  -> /api/monthly-returns/{portfolio_id}
     -> precomputed_raw hit OR MonthlyReturnsCalculator
        -> 当月だけ calculate_monthly_return で動的再計算
     -> MonthlyReturnsResponse
        -> frontend/app/monthly-returns/page.tsx
        -> MonthlyReturnsTable (OPEN/CLOSE toggle)

MonthlyReturn rows + Signal + Price + ledger
  -> /api/monthly-trade/{portfolio_id}
     -> precomputed_raw hit OR MonthlyTradeCalculator
        -> MonthlyTradeImpl._build_entries
        -> 無価格の当月/翌月は _create_pending_entry
     -> MonthlyTradeTable (Confirmed/Historical/Pending/MTD)
```

### 2.2 系統別の現物表

| 系統 | 呼出し元→呼出し先 | 主入力 | 出力・条件分岐 | 現物位置 |
|---|---|---|---|---|
| 月次return計算 | `recalculate_fast` → `_generate_monthly_returns` | Portfolio, Signal, PriceCache, benchmark、ledger | 月別boundaryを作り、重み付きClose/Open比を計算。weights無し/records無しは0件return | `backend/app/jobs/recalculate_fast.py:2832-2859`; `backend/app/jobs/generators/monthly_returns.py:167-181,228-345,396-504,533-624,634-719` |
| MTD計算 | Monthly Returns/Trade → `calculate_monthly_return`; `/api/mtd` → `build_pf_mtd_data` | 当月初営業日、as_of、Price、holding/expanded weights | `month_start→as_of`。翌月初未到着ならMTDへ倒す。価格が無ければcalculatorはNone/空行 | `backend/app/services/return_calculator.py:88-242`; `backend/app/services/monthly_returns_calculator.py:308-365`; `backend/app/services/monthly_trade_impl.py:522-670`; `backend/app/services/mtd_returns.py:164-208` |
| Open/Close系列 | `_generate_monthly_returns` → `PriceCache.get_price_ratio_both` | 同一Start/End、price rowのopen/close | `port_ret`/`port_ret_open`、benchmarkも両系列を別列保存。片系列欠損はnull/既存fallback | `backend/app/jobs/generators/monthly_returns.py:552-624,704-718`; `backend/app/services/price_ratio_impl.py:22-40,66-91,310-345`; `backend/app/db/models.py:264-278` |
| monthly_returns生成 | recalc Phase 4.5（standard）およびLayer 2 generator | 上記計算records | 新rangeが既存rangeを覆う時だけPF全row置換、それ以外はDELETEせずcomputed月だけUPSERT。PKはPF+YYYY-MM | `backend/app/jobs/recalculate_fast.py:2832-2859,3141-3177`; `backend/app/jobs/generators/monthly_returns.py:133-164,721-759`; `backend/app/db/models.py:252-284` |
| UI/API表示 | FE page → `api.getMonthlyReturns`; API → precomputed raw/calculator | viewer auth、visibility、months/years、initial_balance | APIは存在/visibility確認後に保存rawを優先し、無ければcalculator。FEはquick→idle fullを取得し、表はOPENならOpen列、それ以外Close列 | `backend/app/api/monthly_returns.py:26-120`; `frontend/app/monthly-returns/page.tsx:60-194`; `frontend/lib/api-client.ts:1332-1364`; `frontend/components/monthly-returns-table.tsx:62-86` |
| trade_performance | recalc Layer 2 → `_generate_trade_performance` → `_extract_trades_unified` | Signal, Portfolio, PriceCache, MonthlyReturn、expanded weights | weights変化/月境界でtrade区切り。期間returnをClose/Open別に計算しtrade_performanceへbatch INSERT。monthly return計算の保存先ではない | `backend/app/jobs/recalculate_fast.py:470-483`; `backend/app/jobs/generators/trade_performance.py:41-65,119-182,562-721` |
| boundary helper | monthly returns/trade/return calculator → `resolve_monthly_boundary` | first trading day、next boundary、as_of、operational start、ledger検証、expanded switch | `NORMAL/PARTIAL/MTD/NOT_STARTED`。verified ledgerのみledger日を採用し、不一致/未記録はexpanded switchへ戻す。completed/partialでend無しは例外 | `backend/app/services/monthly_boundary.py:1-110`; `backend/app/jobs/generators/monthly_returns.py:414-504`; `backend/app/services/return_calculator.py:198-242` |
| ledger resolver | monthly returns/trade/signal flush → `resolve_ledger_decisions_bulk` | (PF,date) keys、DB又はimmutable snapshot、rebalance trigger | effective区間内かつ次rebalance境界前の候補から `(effective_start, recorded_at, id)` 最大を選ぶ。coverage無しはpending/pass-through、decision無しは例外 | `backend/app/services/signal_decision_ledger.py:190-265,268-275,412-487`; caller `monthly_returns.py:267-278,670-685`; `monthly_trade_impl.py:477-494,575-617` |

### 2.3 DB schemaの境界

- `monthly_returns` は `(portfolio_id, year_month)` primary keyで、`monthly_return`/`monthly_return_open`、累積、benchmark、`in_market`、`holding_signal`だけを保持する。`is_mtd`/`is_pending`/provenance列は無い（`backend/app/db/models.py:252-284`, `backend/app/db/migrations.py:389-423`）。
- `signal_decision_ledger` はeffective start/end、decision signal/weights、source、event_type、decided_atを持つappend-only表で、update/deleteは例外化される（`backend/app/db/models.py:145-202`）。
- `ticker_monthly_returns` はsymbol+year_monthのClose/Open系列を保持し、monthly return generatorはbenchmark値の優先ソースとして使う（`backend/app/db/models.py:568-588`, `monthly_returns.py:506-521,626-632`）。
- `trade_performance`はtrade単位の保存表で、Open/Close return列の追加migrationは通常monthly returnのschemaとは別である（`backend/app/db/migrations.py:381-385`）。

## 3. AC2: 通常経路へ混入した履歴修復・migration概念

### 3.1 列挙と分類

| 概念 | 現物 | 本来の責務 | 通常経路への接触 |
|---|---|---|---|
| `historical_backfill` ledger | `backend/scripts/build_signal_decision_ledger_historical_backfill.py:1-26,50-62,187-240` | 既存signalsの全履歴を「今日記録された値」でledger化する一回限りの復元 | eventを作るのは別scriptだが、read resolverはevent_typeを区別せず通常月のdecision候補にする |
| ledger未導入以前のhistory分類 | `backend/app/services/monthly_trade_impl.py:609-617` | ledger開始日より前を暗黙confirmedとして表示する後方互換 | Monthly Tradeの表示badgeに`historical`を流し、通常confirmedと別表示する |
| ledger migration/partial unique index | `backend/app/db/migrations.py:278-335` | 起動時に表/indexを作り、historical backfill再実行をdedupする | migration自体は計算式ではないが、同一app startupで通常サービスと同居する |
| MonthlyReturn replacement guard | `backend/app/jobs/generators/monthly_returns.py:133-164,727-730` | 狭い/空の再計算結果で完全履歴を消さないfail-safe | recovery由来の保護ロジックが通常generatorの保存境界に存在する。これは妥当な安全底線だが、repair処理そのものではない |
| boundary verification | `monthly_returns.py:396-504`, `monthly_boundary.py:64-79` | 2022-04型のledger日と実expanded switch日の不一致を防ぐ | 履歴ledger値を通常の境界選択へ入れるため、verified_equal以外はexpandedへ戻す二重境界が必要 |
| precomputed raw cache | `backend/app/api/monthly_returns.py:84-90`, `backend/app/api/monthly_trade.py:303-309` | API応答高速化・再計算済みrawの再利用 | cache miss時だけcalculatorへfallback。履歴修復の正本ではないが、stale rawなら表示状態がDBと時間差を持つ |

### 3.2 月替わり直後（暦上は新月、初回取引価格未到着）の現状

#### DB / generator

`_generate_monthly_returns`はSignal日付を月別resampleし、SPY business-day一覧から対象月のfirst trading dateを探す（`monthly_returns.py:228-265,414-420`）。対象月のbusiness dayが無ければboundaryを作らず、その月のMonthlyReturn rowは生成しない（`monthly_returns.py:541-549`）。初回価格未到着の未来月をDBへprovisional rowとして保存する契約は現物にない。既存月のrecordが無ければ保存件数は0で、既存行の削除も行わない（`monthly_returns.py:721-730`）。

#### Monthly Returns API / UI

APIは`precomputed_raw`があればそれを返し、無ければ`MonthlyReturnsCalculator`を呼ぶ。calculatorは保存済み`monthly_returns`が無いとNoneを返し、APIは`No data`として404にする（`backend/app/api/monthly_returns.py:84-93`; `monthly_returns_calculator.py:90-104,184-185`）。保存済みの過去行がある場合も、当月rowが無ければMonthly Returns表にpending行を追加しない。

当月rowが既に存在する場合だけcalculatorが年月一致を`is_mtd`とみなし、同じ`calculate_monthly_return(..., as_of_date)`で当月値を動的更新する（`monthly_returns_calculator.py:308-365,411-432`）。従ってAPI/UIのMTDは「保存rowがある当月」に限られ、価格未到着の新月をpendingとして明示するものではない。

#### Monthly Trade API / UI

Monthly Tradeは既存MonthlyReturnをentriesへ変換し、当月entryが無いか翌月候補が無い場合に`_check_pending_for_month`を実行する。前月末signalが存在し、未来でなく、当月初営業日価格が無い場合にpendingと判定する（`monthly_trade_impl.py:793-884`）。pendingは`MonthlyReturn`へ保存せず、return/price/position startをnull、`is_pending=true`で動的生成する（`monthly_trade_impl.py:885-954`）。FEはPending badge/灰色表示を行う（`frontend/components/monthly-trade-table.tsx:458-495,543-578,694-703`）。

#### `/api/mtd` と provisional source

`/api/mtd`は当月first business dayが無ければ空の`mtd_data`を返す（`backend/app/api/performance.py:240-250`）。価格がある場合は`build_pf_mtd_data`が当月初→最新日の日次累積をClose/Open双方で作り、さらにOpen系列だけ、最後の確定日Close/Open比を使った`is_preliminary=true`行を追加できる（`backend/app/services/mtd_returns.py:164-208,100-161`）。この実装は「前市場日の確定Close等を使うprovisional候補」に最も近い現行実装だが、暫定行はOpen用途に限定され、monthly_returnsの確定Close rowへ保存されない。

PriceCacheは対象日以前の最近傍営業日を`direction="backward"`で解決し、Close/Openを同時に返せる（`backend/app/services/price_ratio_impl.py:22-91,310-345`）。したがって候補sourceのデータ充足機構は存在するが、通常MonthlyReturnのpending lifecycle（provisional→confirmedのstatus/provenance昇格）は未実装である。

## 4. 基本原理との照合と残課題

### 保持できているもの

- Start/Endを`PriceCache`から解決し、Close/Openを別系列として計算する。
- 不存在価格を0やCashへ黙って変換せず、boundary無し/price無しはrow無し、None、pendingへ分岐する。
- 確定ledgerと再計算値が不一致ならdriftを記録し、ledger値を採用する。
- MTDは同一`calculate_monthly_return`で再計算でき、Open速報は別フィールド/flagで区別される。

### 分離が不十分なもの

- `historical_backfill`は生成側がone-offでも、resolver側では通常ledger eventと同じ候補集合である。通常計算が「歴史復元済みの値」を読み込むこと自体は必要だが、source/provenanceを分離しないと、履歴修復値とlive confirmed値の意味が同じに見える。
- `monthly_returns` schemaに`status`、`as_of`、`provenance`、`input_start/end`が無く、MTD/confirmed/provisionalをDB rowだけで判定できない。現在はAPI側の年月一致やMonthly Trade側の動的pendingに分散している。
- Monthly ReturnsとMonthly Tradeは同じreturn計算を再利用するが、価格未到着の新月に対して前者は欠落、後者はpendingとなる。UI/API/DBの三者でlifecycleが一致していない。
- MonthlyReturn全履歴置換の安全guardは通常generatorへ内蔵されている。これは必要なfail-safeだが、migration/incident recoveryの操作を通常計算と同じ関数へ追加する場合は、計算contractと保存/recovery contractを明示的に分ける必要がある。

## 5. pending検討に必要な最小境界（設計提案ではなく現物からの整理）

1. 入力: `price source`, `holding/weights`, `start`, `as_of`, `end availability`を一つの計算inputとして記録する。
2. provisional: 初回価格未到着なら、前市場日の確定Closeを通常の確定Endと誤認せず、Open速報と同様に`provisional` flag・as_of・sourceを付ける。現行の`PriceCache.get_resolved_prices(..., "backward")`は候補取得に利用できる。
3. confirmed: 正式な月初/翌月初価格が到着したら、同じPrice Ratio engineで再計算し、確定rowへ昇格する。Close/Openを同一rowの別列として混合しない。
4. history repair: `historical_backfill`、backup/restore、ledger correction、migrationは通常計算のinput判定から分離し、source/provenanceで追跡する。
5. API: Monthly ReturnsにもMonthly Tradeと同じ`pending/provisional/confirmed`の明示を返す。現行のMonthly Return schemaは`is_mtd`/`is_pending`を型に持つが、DB保存rowには持たないため、次段設計ではstatusのSSOTを決める必要がある。

## 6. 検証証跡

- 8系統のコード位置を確認し、本ファイルへ記録した。
- schema現物（`MonthlyReturn`, `TickerMonthlyReturn`, `SignalDecisionLedger`、migration DDL）を確認した。
- 月替わり直後のDB/API/UI分岐を、Monthly Returns、Monthly Trade、`/api/mtd`の3経路で確認した。
- `test -s docs/research/cmd_4246_monthly_return_principles_recon_20260809.md` は成果物作成後に実行し、成功を確認する。
- 対象projectのgit statusには先行作業による変更が多数存在するが、本偵察ではコード・DB・deployを変更していない。
