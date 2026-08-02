# cmd_4222 A0-0c — ledger境界効力日フィールド現物確定

- 検証日時: 2026-08-03 JST
- 検証範囲: DM-Signalコード現物（read-only）+ 本番PostgreSQL（`db_capability_launcher.py readonly_query`）
- 結論: スキーマ上、確定decisionの効力開始を表すフィールドは `signal_decision_ledger.effective_start_date`。ただし現行writerと本番歴史データはこれを `rebalance_decision_date` と同値で埋めており、代表的な執行ずれ月2022-04の実切替日2022-04-04と一致しない。したがって、現本番データの `effective_start_date` を歴史月の月次境界日SSOTとして無条件採用してはならない。

## 1. スキーマ・writer・consumerの一次証跡

| 対象 | 現物 | 確定事項 |
|---|---|---|
| ORM schema | `/mnt/c/Python_app/DM-signal/backend/app/db/models.py:145-170` | `effective_start_date DATE NOT NULL`。`rebalance_decision_date`、`source_signal_date`、`decided_at`、`recorded_at`とは別フィールド |
| resolver | `/mnt/c/Python_app/DM-signal/backend/app/services/signal_decision_ledger.py:190-254` | 対象日以下の行を絞り、`(effective_start_date, recorded_at, id)` 最大のeventを採用。導出式は `argmax(E where E.effective_start_date <= target_date, key=(effective_start_date, recorded_at, id))` |
| initial writer | 同 `:523-539` | `effective_start_date = rebalance_decision_date` と直接代入。実切替日を独立導出していない |
| correction writer | 同 `:298-314` | `effective_start_date = target_date`。API呼出側が渡した日を効力開始とする |
| Monthly Trade consumer | `/mnt/c/Python_app/DM-signal/backend/app/services/monthly_trade_impl.py:575-607` | `position_start_date`をresolverへ渡し、解決したledgerのholding/weightsを優先 |

本番 `information_schema.columns` でも `effective_start_date: date, NOT NULL` を確認した。名称とconsumer意味論から、ledger内で効力開始を表す唯一のフィールドは `effective_start_date` である。

## 2. 本番DB全数集計

readonly SELECT結果:

| event_type | 行数 | `effective_start_date <> rebalance_decision_date` | effective期間 |
|---|---:|---:|---|
| baseline | 52 | 0 | 2011-08-31..2016-11-30 |
| historical_backfill | 15,082 | 0 | 2003-09-02..2026-07-01 |
| initial | 78 | 0 | 2026-07-01..2026-07-01 |
| 合計 | 15,212 | 0 | 2003-09-02..2026-07-01 |

よって本番現物では `effective_start_date` は全15,212行でdecision日を複写した値であり、独立した実切替日の記録になっていない。

## 3. 執行ずれ月の代表実例（2022-04）

確定仕様 `docs/research/dm-monthly-trade-bug-asis-tobe-5w1h_20260802.md:39-44` は、2022-04の実効力日を2022-04-04（expanded weights実切替）と確定し、root日付2022-04-01を不採用としている。

本番readonly SELECT（PF=`basicデュアルモメンタム`, id=`e0826b59-93a2-4565-9c07-832eaf69af73`）:

| ledger id | event_type | rebalance_decision_date | effective_start_date | source_signal_date | decision_holding_signal | decision_ticker_weights | 実切替日 |
|---:|---|---|---|---|---|---|---|
| 47953 | historical_backfill | 2022-04-01 | 2022-04-01 | 2022-04-01 | XLU | NULL | 2022-04-04 |

signals現物も2022-03-31、2022-04-01、2022-04-04でholding=`XLU`のため、root holding日付から4/4は導出不能。照合結果は `effective_start_date(4/1) != 実切替日(4/4)`。AC1が要求する一致確認を実施した結果、一致ではなく現行ledger値の不適合を確定した。

## 4. 境界日導出式とfallback順序

現物に適合する安全な導出は次の通り。

1. 対象月の確定ledger eventをresolver式で選ぶ。
2. その `effective_start_date` がexpanded weights実切替日と一致する証跡を持つ場合のみ、月次境界日として採用する。
3. ledger decisionが無い月、または歴史backfillのように効力日が実切替日として検証できない月は、expanded weightsの実切替日へfallbackする。
4. 保有切替がない月は確定仕様どおり当月初回取引日（RULE06月次ウェイトリセット効力日）。
5. root `holding_signal` 日付は境界SSOTにしない。同値が独立に証明された場合のみ補助証拠とする。

式:

`boundary(month) = verified(ledger.effective_start_date == expanded_switch_date) ? ledger.effective_start_date : expanded_switch_date`

切替なし月は `boundary(month) = first_trading_date(month)`。この検証条件なしに単純な `COALESCE(ledger.effective_start_date, expanded_switch_date)` とすると2022-04を4/1へ誤分類する。

## 5. 設計書確定仕様節への還流内容案（将軍単一writer向け）

`§0.6-1` のledger優先文を次へ置換する案:

> ledger内で効力開始を表すフィールドは `signal_decision_ledger.effective_start_date`、resolverは対象日以下のeventから `(effective_start_date, recorded_at, id)` 最大を採る。ただし2026-08-03時点の本番15,212行は全件 `effective_start_date = rebalance_decision_date` で、2022-04実例は4/1対4/4と不一致。歴史backfill値を無条件SSOTにせず、expanded weights実切替日との一致が検証できたledger値のみ優先し、不一致・未記録時はexpanded weights実切替日へfallbackする。root holding日付は採用しない。

## 6. 下流への明示事項

- A0-0b/B1/A0-1は `effective_start_date` の存在だけをもってStart前提充足と解釈してはならない。上記verification付き導出を使用する。
- ledgerの歴史効力日を実切替日に再基線化するかは本cmdのread-only範囲外。route裁定候補として扱う。
- 設計書本体とDM-Signal repoは本cmdでは変更していない。
