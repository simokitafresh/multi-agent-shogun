# cmd_4222 A0-0c: ledger月次境界フィールド確定

- 検証日時: 2026-08-03 JST
- 検証範囲: DM-Signalコード現物（read-only）+ 本番PostgreSQL（`db_capability_launcher.py` の `readonly_query` のみ）
- 結論: ledgerが確定decisionを持つ月の月次境界日SSOTは `signal_decision_ledger.effective_start_date`。

## 1. スキーマと意味

`backend/app/db/models.py` と `backend/app/db/migrations.py` はともに次を定義する。

| field | 意味 | null |
|---|---|---|
| `rebalance_decision_date` | decision eventの識別日 | NO |
| `effective_start_date` | decisionが保有へ効力を持ち始める日（月次境界日） | NO |
| `effective_end_date` | 効力区間の終端（現行open intervalはNULL） | YES |
| `decision_holding_signal` | 確定保有 | YES |
| `decision_ticker_weights` | 確定weights | YES |
| `recorded_at`, `id` | 同一効力日の訂正event順序 | NO |

設計現物 `docs/design/signal-decision-ledger-design.md` §3 も効力区間を `[effective_start_date, effective_end_date)` と定義する。`rebalance_decision_date`、`source_signal_date`、`recorded_at` は月次境界日には使わない。

## 2. consumer導出式

`backend/app/services/signal_decision_ledger.py::resolve_ledger_decisions_bulk` の現物どおり、PF `p` と対象月の候補日 `d`（`position_start_date`）に対し:

```text
eligible(p,d) = {r | r.portfolio_id=p AND r.effective_start_date<=d}
ledger_event(p,d) = argmax_r (r.effective_start_date, r.recorded_at, r.id)
monthly_boundary_date = ledger_event.effective_start_date
```

該当eventがあり `decision_holding_signal IS NULL` なら fail-visible。訂正eventは同じ式で最新を選ぶ。`monthly_trade_impl.py` は `(portfolio_id, position_start_date)` をkeyにこのresolverを呼び、ledgerのholding/weightsを優先する。

## 3. 本番readonly照合

本番 `information_schema.columns` は17列を返し、`effective_start_date` は `date NOT NULL`。ledger総数は15,212行。`effective_start_date` が暦月1日と異なる行は5,496行で、休日等による境界ずれが実在する。

代表例（暦月1日から実効力日がずれる月）:

| PF | 暦月初 | ledger effective_start_date | ledger holding | signals同日holding | expanded weights実在日 |
|---|---:|---:|---|---|---:|
| Ave-X (`a78887bf-25ae-4525-81af-cd4c630b3d36`) | 2026-03-01 | 2026-03-02 | 子PF UUID 6本 | 6本完全一致 | 2026-03-02 |

同PFの `fof_component_weights` は2026-03-02に6行あり、各 `target_weight=1/6`。したがってledger効力日、signalsの実保有日、expanded component weightsの実切替日が2026-03-02で一致する。暦日1日固定では1日早い誤境界になる。

補足: 本番15,212行では `rebalance_decision_date != effective_start_date` は0件、`source_signal_date != effective_start_date` も0件だった。これは現行データの一致であり、field意味の同一性を保証しない。consumer契約上のSSOTはあくまで `effective_start_date`。

## 4. ledger decision欠損月のfallback順序

設計書§0.6-1に還流すべき順序:

1. ledger確定decisionあり: 上式で選んだ `effective_start_date`。
2. ledger確定decisionなし: primitiveから再帰展開したexpanded weightsの実切替日（前日/直前状態とのweights差が初めて現れる取引日）。
3. 保有切替なし月: 当月の初回取引日（RULE06の月次weights reset効力日）。
4. 必要primitiveまたはweightsが欠損: fallbackせず計算不能としてfail-visible。

`root signals.holding_signal` の日付は境界SSOTに採用しない。expanded効力日と同値が別途証明された場合だけ補助証拠にできる。生 `signal`、月次リターン行、trade_performance境界への代用も禁止。

## 5. 設計書§0.6-1への還流内容案

> ledger確定decisionがある月の月次境界日は `signal_decision_ledger.effective_start_date` とする。対象 `(portfolio_id, position_start_date)` について `effective_start_date <= position_start_date` のeventから `(effective_start_date, recorded_at, id)` 最大を選ぶ。該当eventがなければexpanded weights実切替日、切替なし月は当月初回取引日を採る。root holding日付や生signalへfallbackせず、必要primitive欠損はfail-visibleとする。

## 6. 一次根拠

- `/mnt/c/Python_app/DM-signal/backend/app/db/models.py` (`SignalDecisionLedger`)
- `/mnt/c/Python_app/DM-signal/backend/app/db/migrations.py` (DDL)
- `/mnt/c/Python_app/DM-signal/backend/app/services/signal_decision_ledger.py` (`resolve_ledger_decisions_bulk`)
- `/mnt/c/Python_app/DM-signal/backend/app/services/monthly_trade_impl.py` (consumer)
- `/mnt/c/Python_app/DM-signal/backend/scripts/build_signal_decision_ledger_historical_backfill.py` (writer)
- 本番PostgreSQL readonly SELECT（schema、15,212行集計、Ave-X 2026-03 ledger/signals/component weights照合）
