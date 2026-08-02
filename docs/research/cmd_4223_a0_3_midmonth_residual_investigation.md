# cmd_4223 A0-3 月中残余14件の個別調査

- 検証日時: 2026-08-03 03:20-03:23 JST
- 対象: `trade_performance.trade_type='Monthly'` の同一PF・同一`trade_date`暦月重複行で、`ROW_NUMBER() >= 2` かつ `EXTRACT(DAY FROM trade_date) >= 8`
- 接続: `db_capability_launcher.py` の `readonly_query` のみ。本番書込み0件
- 判定軸: 親PFの確定保有が変われば実トレード、確定保有と同じallocationを境界だけ誤分割していれば境界記録バグ、確定保有不変なのに前後どちらとも異なる一過性allocationを永続化していれば暫定値永続化

## 結論

対象は設計書§1cどおり14/14件再現した。分類は実トレード0件、境界記録バグ0件、暫定値永続化14件。全件で親`holding_signal`は開始日→終了日不変、ledger被覆9件も9/9不変（残5件は両端ともledger未被覆）、候補allocationは14/14件で直前・直後の両方と異なる一過性値だった。候補allocationの非Cash ticker価格は開始・終了の全38/38組で存在したため、価格欠損による見かけの分類ではない。

## 行単位分類

|PF|trade no.|期間|候補allocation|直前 → 直後|holding / ledger|分類|
|---|---:|---|---|---|---|---|
|秘奥義-分身-常勝|2|2013-09-30→10-01|Cash 50%, TECL 19%, TQQQ 19%, XLU 12%|Cash 75%, XLU 12%, TECL 6%, TQQQ 6% → Cash 50%, TECL 22%, TQQQ 22%, XLU 6%|holding不変 / ledger両端なし|暫定値永続化|
|秘奥義-分身-激攻|5|2013-09-30→11-01|Cash 50%, XLU 25%, TECL 12%, TQQQ 12%|Cash 75%, XLU 25% → Cash 50%, TECL 19%, TQQQ 19%, TMV 12%|holding不変 / ledger両端なし|暫定値永続化|
|秘奥義-分身-常勝|7|2014-01-31→02-03|GLD 33%, TECL 33%, XLU 21%, TQQQ 12%|Cash 50%, TECL 25%, GLD 12%, XLU 12% → XLU 65%, TQQQ 22%, GLD 8%, TECL 5%|holding不変 / ledger不変|暫定値永続化|
|秘奥義-分身-激攻|9|2014-01-31→02-03|XLU 50%, Cash 25%, TECL 25%|Cash 50%, TECL 25%, XLU 25% → XLU 62%, Cash 25%, TQQQ 9%, TECL 3%|holding不変 / ledger両端なし|暫定値永続化|
|秘奥義-分身-激攻|13|2014-03-31→04-01|TQQQ 50%, XLU 50%|TQQQ 50%, Cash 25%, XLU 25% → TECL 47%, TQQQ 44%, XLU 9%|holding不変 / ledger不変|暫定値永続化|
|New Fund of Funds_copy_copy_copy|11|2014-06-30→07-01|Cash 50%, TQQQ 28%, GLD 12%, XLU 9%|Cash 75%, TQQQ 16%, XLU 9% → Cash 50%, TQQQ 19%, TECL 16%, XLU 3%|holding不変 / ledger両端なし|暫定値永続化|
|秘奥義-鉄壁|15|2015-03-31→04-01|TQQQ 78%, XLU 22%|TQQQ 61%, Cash 33%, XLU 6% → XLU 58%, GLD 25%, TQQQ 12%, TECL 4%|holding不変 / ledger不変|暫定値永続化|
|New Fund of Funds_copy|44|2016-03-31→04-01|TQQQ 78%, TECL 16%, XLU 6%|Cash 50%, TQQQ 28%, TECL 16%, XLU 6% → GLD 56%, TECL 38%, TQQQ 6%|holding不変 / ledger不変|暫定値永続化|
|New Fund of Funds_copy_copy|24|2016-03-31→04-01|TQQQ 100%|Cash 50%, TQQQ 50% → GLD 50%, TECL 38%, TQQQ 12%|holding不変 / ledger不変|暫定値永続化|
|秘奥義-堅守|34|2016-03-31→04-01|TECL 33%, TQQQ 33%, XLU 33%|Cash 33%, XLU 25%, TECL 21%, TQQQ 21% → GLD 50%, TECL 29%, XLU 17%, TQQQ 4%|holding不変 / ledger不変|暫定値永続化|
|秘奥義-常勝|33|2016-03-31→04-01|TECL 44%, TQQQ 31%, XLU 25%|Cash 33%, TECL 31%, TQQQ 19%, XLU 17% → GLD 54%, TECL 25%, XLU 17%, TQQQ 4%|holding不変 / ledger不変|暫定値永続化|
|New Fund of Funds_copy_copy_copy|47|2016-03-31→04-01|TQQQ 64%, Cash 25%, TECL 8%, XLU 3%|Cash 50%, TQQQ 39%, TECL 8%, XLU 3% → GLD 41%, Cash 25%, TECL 25%, TQQQ 9%|holding不変 / ledger両端なし|暫定値永続化|
|秘奥義-分身-鉄壁|34|2016-03-31→04-01|TECL 46%, TQQQ 29%, XLU 25%|Cash 33%, TECL 33%, TQQQ 17%, XLU 17% → TECL 38%, XLU 33%, GLD 25%, TQQQ 4%|holding不変 / ledger不変|暫定値永続化|
|秘奥義-激攻|21|2016-03-31→04-01|TECL 46%, TQQQ 46%, XLU 8%|Cash 33%, TECL 33%, TQQQ 33% → GLD 58%, TECL 17%, XLU 17%, TQQQ 8%|holding不変 / ledger不変|暫定値永続化|

## 検算

readonly集計出力:

```text
total=14
start_date=trade_date: 14/14
holding_signal unchanged: 14/14
ledger unchanged among covered: 9/9
ledger uncovered at both ends: 5/5
allocation distinct from both previous and next: 14/14
fof_component_weights rows at end_date: 14/14
allocation ticker prices present at start/end: 38/38, 38/38
classified: 14/14
```

`fof_component_weights`は候補`start_date`には0/14、翌境界の`end_date`には14/14で存在した。親の確定holding/ledgerが変わらないまま、展開途中のticker allocationだけが候補行へ保存された構造と整合する。

## 設計書§1cへの還流内容案

「8日以降14件を個別調査した結果、実トレード0、境界記録バグ0、暫定値永続化14。全件で親holding不変、ledger被覆9/9不変、allocationは前後両方と異なる一過性値、価格欠損0。したがって真の月中トレード残余は0件であり、14件すべてを暫定FoF展開weightsの誤永続化として浄化対象へ含める。」

## 因果

`[[設計書v4.11_§1c_月中疑い14件]] -> [[親holdingとledger不変_展開allocationのみ一過性]] -> [[暫定値永続化14_実トレード0]]`
