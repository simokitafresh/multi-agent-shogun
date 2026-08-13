# DM-Signal 判定プロヴェナンス保存 — AsIs/ToBe 5W1H設計書 v1.0
<!-- semantic-links: [[recalculate_pipeline]] [[momentum_window]] [[dm-fullrecalculate-cache-reuse-asis_20260813]] -->

> ★前提情報のないLLM/人へ: 本書だけで自己完結する。§1(5W1H)→§2(AsIs)→§3(ToBe)→§4(速度保護)→§5(工程)の順に読め。ToBeは**殿裁定済みの方向**(2026-08-13 17:36「専用の設計書を作ろう。実装にあたって計算速度が低下しない工夫も必要だ」)だが、**実装はRB6収束後**(生成コード変更がoracle突合の安定を乱すため)。

## §1 5W1H(前提)

- **What(何を保存するか)**: fullrecalculate/再計算の各リバランス判定について「保有(結果)」だけでなく**「その保有を選んだ理由」= 判定プロヴェナンス**を保存する。具体: ①各候補アセットのmomentum scalar ②判定に使ったstart/end日付と実際に引いた価格 ③standard PFの展開後ticker×weightスナップショット ④層別run結果サマリの台帳化。
- **Why(なぜ)**: 現行は「結果(holding_signal)は残るが理由(数値と入力)が残らない」。2026-08-13のRB6独立oracle構築では、保存値が無いためモメンタム・リターンを一から独立再実装して検算する必要があった(cmd_4296 AC4=momentum scalar保存0件でparity検証不能)。プロヴェナンスがあれば「なぜこのPFが選ばれた」の検証がSQL一発になり、障害調査・oracle検算・殿への説明が全て高速化する。
- **Who**: 設計=将軍(殿裁定を仰ぐ)。実装=家老配備の忍者。検証=軍師レビュー+将軍の本番一次確認。使用者=デバッグを行う全員+殿(調査下問への即答材料)。
- **When**: 設計=2026-08-13。**実装はRB6(prices独立oracle全量)CLEAR後**。理由: 生成コードの変更はoracle突合中の派生データ安定を乱す。
- **Where(一次情報)**: `backend/app/jobs/recalculate_fast.py`(Phase 4判定ループ・`momentum_data`書込み箇所)・`recalculate_fof.py`・`signals`テーブル(`momentum_data` JSONカラム=既存)・`recalculation_status`台帳。仕様正本=`dm-fullrecalculate-cache-reuse-asis_20260813.md`(gist 1b875a44)+`cmd_4296_momentum-window-recon_20260813.md`(gist bf4ac198)。
- **How(完了基準)**: full 1回実行後、(a)全リバランス判定行のmomentum_dataにscalar+入力スナップショットが非nullで存在 (b)保存値から手計算した選抜結果がholding_signalと全数一致 (c)**full実行時間がプロヴェナンスなし比で+5%以内**(§4)を数値で証明。

## §2 AsIs(2026-08-13確定・全て一次証拠あり)

### §2.1 残るもの / 残らないもの

| データ | 現状 | 一次証拠 |
|---|---|---|
| 保有シグナル日次履歴(`signals.holding_signal`) | ✅残る | RB6 FoF oracleの入力に使用 |
| 確定月判定の凍結(ledger) | ✅残る | signal_decision_ledger |
| FoF展開後構成(`fof_component_weights`) | ✅残る | schema現物 |
| run identity(git SHA+fingerprint) | ✅残る | `_resolve_source_identity()` |
| **momentum scalar** | ❌残らない | cmd_4296: `momentum_data.relative=null`・`block_results.momentum_values={}`(standard/leaf/nested 3系統とも0件) |
| **判定入力(start/end日付・実際に引いた価格)** | ❌残らない | 同上 |
| **standardの展開後ticker×weight** | ❌残らない | oracle構築時にholdingトークンから毎回再展開した |
| 非リバランス日の判定痕跡 | `{"skipped":true}`のみ | cmd_4296 §3 |
| 層別run結果(rows/failed/TIMING) | Renderログのみ(流失する) | recalculation_statusには件数サマリなし |

### §2.2 AsIsの帰結(実害の実証)

1. RB6検算(2026-08-13)で独立runnerを一から実装する必要が生じた(保存値とのparityが構造的に不可能)。
2. 「なぜ2026-08-01にTMV/TQQQが選ばれたか」の検証に、コード追跡+DB価格照会+手計算(cmd_4296 §2)を要した — プロヴェナンスがあればSELECT一発。
3. run273事案(cache混線)・run351事案(holding seed欠落)の診断で、判定時点の入力を事後再構成する工数が支配的だった。

### §2.3 計測期間仕様(判定の定義。cmd_4296正本の要約)

- standard: 日次prices closeの営業日窓(月=21営業日)。end=前月末(最終取引日close、ラベルは暦月末)。
- leaf/nested FoF: 子PF `monthly_returns.cumulative_return`(close)の暦月差分。end=前月末、start=n暦月前の月末。深度差なし。
- リターン境界: 当月最初の取引日→翌月最初の取引日(`monthly_boundary.py:81-99`)。

## §3 ToBe

### §3.1 保存内容(判定プロヴェナンス・4点)

**書込み先は既存の`signals.momentum_data`(JSON)を埋める。新テーブルは作らない**(シンプル最優先=殿裁定2026-08-13 03:46の延長。schema migration不要・読み出しAPIも既存)。

リバランス判定日の行に以下を格納:

```json
{
  "provenance_version": 1,
  "window": {"lookback": [{"months": 12, "weight": 1.0}],
              "end_date": "2026-07-31", "end_actual": "2026-07-30",
              "start_date": "...", "start_actual": "..."},
  "candidates": {
    "TECL": {"momentum": -0.1112306076, "start_px": 195.2700042725, "end_px": 173.5500030518},
    "TQQQ": {"momentum": "..."}
  },
  "absolute": {"asset": "...", "momentum": "...", "threshold": "..."},
  "selection": {"relative": "TECL", "final": "TQQQ", "reason": "absolute<threshold→safe_haven"},
  "expanded_weights": {"TQQQ": 1.0}
}
```

- FoFは`candidates`のキーが子PF ID、価格の代わりに`cumulative_return`のstart/end値。
- `expanded_weights`=standardにも展開後ticker×weightを保存(§2.1の欠落③の解消)。
- 非リバランス日は現行`{"skipped":true}`を維持(容量とhot pathを守る。§4)。

### §3.2 層別runサマリの台帳化

full/portfolio再計算の終端で、`recalculation_status`行(既存)へ`summary` JSON 1フィールドを追記: `{"rows":1533,"portfolios":102,"failed":0,"timing":{"L2":"...","L3":"...","L5":"...","total":"..."}}`。Renderログ流失後も前回runと比較可能になる。

### §3.3 使い方(完成後のデバッグ手順)

- なぜこの保有か: `SELECT momentum_data FROM signals WHERE portfolio_id=? AND date=?` — 1クエリで判定全根拠。
- oracle検算: 保存scalarと独立再計算の直接parity(cmd_4296 AC4が初めて実行可能になる)。
- run間比較: `recalculation_status.summary`同士のdiff。

## §4 計算速度を低下させない工夫(殿要件・設計制約)

fullの現行実測=TOTAL 7m45s(L2=2m5s/L3=4m21s/L5=41.3s、2026-08-13 run `2026081304021264BB4C`)。**目標: +5%(≈23s)以内**。

1. **新規計算ゼロの原則**: 保存する値は全てPhase 3.7/Phase 4/FoFループが**既に計算しているメモリ上の値**(vectorized momentum dict・選抜結果・展開weight)。プロヴェナンスは「計算の副産物の書き出し」であり、追加の価格照会・momentum再計算を1回もしない。dictから辞書を組むだけ=CPUコストはO(判定数×候補数)の辞書構築のみ。
2. **書込み回数を増やさない**: `signals`行は現行もUPSERTされている。momentum_dataフィールドの中身が大きくなるだけで、**INSERT/UPDATE文の回数は不変**。JSON構築はDB書込みバッチに同乗。
3. **リバランス判定日のみ**: 非リバランス日(圧倒的多数)は現行の`{"skipped":true}`のまま。書込み増分は約240判定月×102PF規模に限定され、日次行の膨張なし。
4. **同期経路に検証を入れない**: 保存時の整合チェック(scalar→選抜の再導出確認)はhot pathで行わず、事後の検証クエリ(§3.3)に任せる — 厳密さは最終checkpointへ集中(殿裁定2026-07-14)。
5. **計測で証明**: 実装cmdのACに「TIMING SUMMARY比較でprovenanceあり/なしのfull実行時間差+5%以内」を二値で固定。canary(5PF)→fullの2段で、値の不変(monthly_returns hash一致)と速度の両方を前後比較する — TIMING復元(2026-08-13)と同じ検証型を再利用。
6. **容量の見積り**: 1判定≈候補5個×数値3個≈500B。102PF×240月×500B≈12MB — pg上で無視できる規模。必要ならJSONB圧縮はpg任せ。

## §4.5 計算速度「向上」への転用(殿指示 2026-08-13 17:41「デバッグ観点だけではなく計算速度向上の面からも」)

プロヴェナンスは守り(デバッグ)だけでなく、**再計算スキップの安全な基盤**として攻め(速度向上)に転用できる。鍵は「判定の入力を記録している=入力が変わっていないことを証明できる」こと。

1. **fingerprint skip(最大の効果見込み)**: 各判定のprovenanceへ**入力fingerprint**(使用した価格系列区間のhash+config hash)を1フィールド追加する。次回再計算時、確定月について「保存fingerprint == 現入力のfingerprint」なら**その判定月の再計算を丸ごとskip**し保存済み結果を再利用する。価格の過去分とconfigは通常不変ゆえ、fullの大半(確定済み月×102PF)がskip対象になり、full再計算が「差分だけ計算する増分再計算」へ構造転換する。これは速度レーンの既存標的「fingerprint skip」(60秒化3標的の一つ)へ、従来欠けていた**「skipして良い証明」(何をもって同一入力とみなすかの記録)**を与えるものである。
2. **expanded_weightsの再利用**: standardの展開後ticker×weightが保存されれば、L5生成・trade performance・oracle検算がholdingトークンからの再展開(パース+config参照+再帰)を省略し、保存値を読むだけになる。RB6 oracleでFoF再帰展開が重い工程だった実証に基づく。
3. **skip判定のコストはO(1)を不変量に**: fingerprint比較はhash文字列一致のみ。skip判定のために出力(momentum)を再計算したら本末転倒 — 比較対象は入力のhashであり出力ではない。
4. **速度回帰の恒常監視**: §3.2のrunサマリ台帳化で、TIMING SUMMARYがrun間でSQL比較可能になり、速度劣化検知が「ログを目で追う」から「前回比クエリ」へ変わる。
5. **段階導入**: P1-P6は記録のみ=挙動不変でリスク極小。fingerprint skipの有効化は別工程P7とし、skip有効/無効のA/B fullで**値の完全一致(monthly_returns hash)を証明してから**恒久有効化する(canary→full・hash一致の検証型を再利用)。

期待効果の概算(現行実測TOTAL 7m45s): 確定月の判定・生成が支配的なL2/L3(計6m26s)の大半がskip可能領域。入力不変の通常運用ではfullが**分オーダー→数十秒オーダーへ**短縮しうる(速度レーンの60秒目標と整合)。正確な短縮幅はP7のA/B実測で確定する。

## §5 工程(実装はRB6 CLEAR後)

| # | 工程 | 二値出口 |
|---|---|---|
| P0 | 本設計書の殿裁定 | §3の保存内容・§4の速度制約が承認される |
| P1 | 書込み実装(standard) | Phase 4判定でmomentum_data埋め込み+対象テストFAIL0/SKIP0 |
| P2 | 書込み実装(FoF) | FoFループで同スキーマ+nested深度差なしをfixture確認 |
| P3 | runサマリ台帳化 | recalculation_status.summary追記+終端で1行 |
| P4 | canary 5PF | monthly_returns hash一致5/5+provenance非null+ERROR0 |
| P5 | full+速度検証 | 102/102・failed0・**TOTAL増分+5%以内**・保存値から選抜再導出全数一致 |
| P6 | 検証クエリの定型化 | §3.3のSQLをdb-checkスキルへ追記 |
| P7 | fingerprint skip有効化(速度向上・別cmd) | skip有効/無効のA/B fullでmonthly_returns hash完全一致+TOTAL短縮幅の実測記録(§4.5) |

## §6 改訂履歴

- v1.0 (2026-08-13 17:40): 殿指示(17:32「どのようなデータがfullrecalculateの時に取得できていると便利だ」→17:36「専用の設計書を作ろう。計算速度が低下しない工夫も必要」)を受け新規作成。AsIsはcmd_4296調査(gist bf4ac198)とRB6 oracle構築の実証に基づく。

origin: `[[殿指示_判定プロヴェナンス設計_20260813]] -> [[cmd_4296_momentum_scalar未保存確定]] -> [[dm-decision-provenance-asis-tobe-5w1h]]`
