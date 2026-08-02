# DM-Signal 月次リターン境界是正 — AsIs/ToBe 5W1H設計書 v4.27 【B3=RC待ちへ是正・全体32%。checker v3=待ち理由stale検査追加。残る殿裁定=routeのみ】

> **本書の位置づけ**: v1.0-v2.5の追記累積を廃し、殿裁定完結後の確定事実だけで書き直した唯一の正本。旧版の経緯は§3(evidence)と§7(履歴)に圧縮。前提知識ゼロのLLMが本書だけで作業可能なことを設計要件とする。

## §0 セーブポイント

- 正本: 本ファイル(repo `/mnt/c/tools/multi-agent-shogun`)。gist鏡: `8cbc86a555dff983d316c4e15441b7b7`
- **現在地(2026-08-03 05:02セーブ=v4.27発行時)**: 仕様=全確定(残る殿裁定=A0-4b routeのみ)。**GATE CLEAR 11工程**=W0 5/5+A0-0a/A0-0b+A0-1+B1+B2c+B2d。進行中=B2a(CI RED対応中)/B2e(task done・GATE待ち)の2件のみ。**B3=RC待ち**(才蔵task failed・軍師FAIL→B2e CLEAR後に合同scope再配備)。空き待ち=B2b。**解放済み未配備=A0-2/A0-2p/S1-S3+レーンA(A1-A5)**。運用=毎版相互不可視レビュー+両者完了後に次版発行+版発行前機械照合(checker v3=待ち理由stale検査追加。task/report terminal stateの照合は家老側rg集計で補完)+将軍単一writer+gist毎版同期(--filename指定fetchが正)+将軍15分巡回loop+家老goal駆動。復帰点knowledge=421a42fe32e8067c

### §0.1 全体進捗トラッカー(将軍が進捗変化のたび更新。工程別詳細=§2.5 WBS Status列)

```
全体進捗: ██████░░░░░░░░░░░░░░ 32% (GATE CLEAR 11 + 進行中 2×0.5 = 12.0 / 38工程)
レーンA0: ███████░░░  67% (6.0/9: GATE CLEAR=A0-0a,A0-0b,A0-0c,A0-1,A0-3,A0-4a残件。次=A0-2/A0-2p)
レーンA :  ░░░░░░░░░░   0% (0/5。A0-1 CLEAR済み・配備待ち)
レーンB :  █████░░░░░  55% (6.0/11: GATE CLEAR=B1,B2c,B2d,B3i,B3.5。進行中=B2a(CI RED対応中),B2e(GATE待ち)。RC待ち=B3。空き待ち=B2b)
レーンS :  ░░░░░░░░░░   0% (0/3。A0-1 CLEAR済み・配備待ち)
レーンC :  ░░░░░░░░░░   0% (0/4。A5待ち)
レーンD/E: ░░░░░░░░░░   0% (0/6。A0-4b殿裁定待ち)
```

- **見込み時間(根拠=gate_metrics実測: cmd_4222/4223 work_sec=477/416秒≈7-8分、e2e_sec=1019/1037秒≈17分/工程。e2e=deploy+work+finalize+gate)**:
  - A0再裁定完了(A0-4b殿裁定入口まで): **残り約1-1.5時間**(A0-1=CLEAR済み04:30:58。クリティカルパス=A0-2/A0-2p+S1-S3(未配備)→A0-4b。e2e≈17分×3-4工程。配備は家老goal采配待ち)
  - 発生源根治B(並列進行): A0と並行で約1.5-2時間(B1着手可。lane内直列7工程×e2e17分をlane間並列で圧縮)
  - 裁定後(D浄化+E検証): **約2-4時間の保守レンジ**(本番書込み・route依存で実測なし。現行維持routeなら大幅短縮)
  - **全体完了見込み: 殿裁定待ち時間を除き約4-6時間**(readonly系は今夜中に収束可能)
- 進捗の定義: done=Goal二値PASS(GATE CLEAR含む)を1.0、進行中=0.5、未着手=0。母数=WBS38工程(Phase5凍結分は除外)

- 起点: 殿指摘 2026-08-02 21:33「複数PFで極端にCAGRが下がっている」
- 転換: 殿の連続指摘(2026-08-03 00:47-01:46)で「月中トレード汚染」認定が覆り、真の問題=**月次リターンの月境界仕様が未明文で、実装が誤った境界(月初固定)を使っていた**ことに確定
- 合格基準(殿裁定2026-03-11・比較器はv3.4で一意化=家老F4): 全数値フィールドが全PF×全期間で誤差ゼロの完全一致。**比較方法=双方の値を本番計算の保存前round規約(Pythonの`round(x, 10)`=round-half-even、実装=price_ratio_impl.py:900)で量子化した後のexact一致のみ**(DB列自体はFloat型=models.py:271-272のため「DB保存精度」とは呼ばない)。raw差1e-12等の別基準は用いない(二重基準の判定割れ防止)
- ルール正本: DM-signal repo `docs/rule/trade-rule.md`(RULE01-11)。**本書§0.6の確定仕様を正本へ転記する作業がA0-4aの残件**

## §0.5 前提知識(自己完結定義)

### 対象システム
- **DM-Signal**: 投資PFシグナル配信アプリ。repo=`/mnt/c/Python_app/DM-signal`(Python/FastAPI+PostgreSQL、Render稼働)
- **PFの2型**: `portfolios.type='standard'`(ticker×weight直接構成) / `'fof'`(他PFを組合せるFund of Funds。FoFのholding_signalは子PFのUUID。入れ子あり)
- **層(Layer)**: L0=standard / L1=構成が全てstandardのFoF / L2・L3=入れ子FoF。下位層が誤れば上位層は必ず誤るため、検証はL0→L1→L2/L3の順(層間直列・層内並列)
- **忍法**: FoF系列の戦略ファミリー。L1検証は忍法単位レーンに分解(殿指示2026-08-03 00:24)

### 主要テーブル
- `signals(portfolio_id, date, signal, holding_signal)`: holding_signal=確定保有(FoFは子PF UUID)。**signalは生シグナルでholdingの代用禁止(fallback禁止)**
- `monthly_returns(portfolio_id, year_month, monthly_return, monthly_return_open, cumulative_return, ...)`: year_month='YYYY-MM'
- `trade_performance(portfolio_id, trade_number, start_date, end_date, trade_date, trade_type, allocation, portfolio_return, ...)`: PK=(portfolio_id, trade_number)のみ(models.py:343-375)。日付/種別制約なし
- `prices(symbol, date, open, close, ...)`: **配当調整済み(adjusted)**

### 役割分担(殿裁定2026-08-03)
- **営業日=pricesテーブルに価格が存在する日**(基準symbol=SPY、実装=business_day_utils.py L33-58)。DM-signal側で営業日を独自判定しない。価格供給=stock data API(別PJ)。固定休日表・独自カレンダー新設禁止
- **配当調整=stock data API側の責務**(2026-07-05にyfinance adjusted→EODHD raw+自前調整へ移行。正本=DM-signal `docs/design/gs-recalibration-plan.md`、精度検証=cmd_3691 commit d7abccd)。DM-signal側・オラクル側での独自調整禁止

### 運用タイムライン(殿確定・実測裏付け済み)
1. 前月末最終営業日の市場終了後に価格確定
2. 月初(暦日1日、非営業日でも可)の再計算で当月holding_signalが**初めて**算出される
3. **執行=当月に保有が実際に切り替わる日**(通常は月の初営業日。例: 2026-08は8/1土・8/2日が非営業日ゆえ8/3月。ただし切替が遅延した月は実際の切替日=§0.6-1)。執行前のOpen表示が再計算のたび収束・変化するのは正常動作
4. 月初リバランス前後で保有tickerが変わるのは自明。境界遷移を「同月中のトレード」と扱ってはならない

## §0.6 確定仕様(殿裁定2026-08-03 01:26-02:25。本節が計算仕様・記録仕様の唯一の正。**未決事項なし**)

1. **月次リターン区間 = 当月の月次境界日→翌月の月次境界日**。**月次境界日は全ての暦月に必ず1つ存在する**(保有切替の有無に依存しない — 家老F1):
   - **保有切替がある月**: 境界日=**切替が実際に効力を持った日**。市場の月内初営業日と同一視してはならない(2022-04は4/1が営業日だが効力発生=4/4。遅延した月はその実際の日)
   - **保有切替がない月**(非リバランス月・holding継続月・Cash継続月・同一シグナルのリバランス月): 境界日=**当月の初回取引日**(RULE06の暗黙的月次ウェイトリセットの効力日。切替がないため遅延は発生し得ない)
   - **RULE06(毎月ウェイトリセット)は意図的な確定ルール(殿裁定2026-08-03 02:14-02:16)**: 設計意図=「四半期リバランスのPFに途中から参加しても成り立つよう、同一保有シグナルでもあえて毎月リセットする」(trade-rule.md L153に明文)。理論上はdrift保有の複利と乖離するが、**リバランス日・モメンタム計算日を変える感度分析でロバストネスが実証されており実務上許容**(artifact=家老N3: 第一弾N感度 `docs/research/month-end-n-day-momentum-sensitivity-asis-tobe-5w1h_20260731.md`(v3.4完了・崩壊なし)、第二弾E感度 `docs/research/execution-delay-sensitivity-asis-tobe-5w1h_20260731.md`(v1.5完了・全E優位維持)、第三弾gist b2a97d63)。driftへの変更は行わない。monthlyリバランスで同一シグナルになった月もリセットは執行される(RULE04: 銘柄同一でもリバランスは発生)
   - **切替効力日の判定優先順位(家老N1是正→A0-0c実測還流=cmd_4222 commit 455e682fa)**: ledger内で効力開始を表すフィールドは `signal_decision_ledger.effective_start_date`(resolver=対象日以下のeventから `(effective_start_date, recorded_at, id)` 最大を採用)。**ただし2026-08-03時点の本番15,212行は全件 `effective_start_date = rebalance_decision_date` の複写であり、2022-04実例はledger 4/1 vs 実切替4/4で不一致**。よって歴史backfill値を無条件SSOTにしてはならない。導出式: `boundary(month) = verified(ledger.effective_start_date == expanded_switch_date) ? ledger.effective_start_date : expanded_switch_date`(**expanded weights実切替日との一致が検証できたledger値のみ優先、不一致・未記録月はexpanded weights実切替日へfallback**)。切替なし月は当月初回取引日(§0.6-1本文)。検証条件なしの単純 `COALESCE(ledger, expanded)` は2022-04を4/1へ誤分類するため禁止。**root holding_signalの日付は境界日として採用しない**(実証: 2022-04はroot切替=4/1だが実効力=expanded切替4/4)。root日付はexpanded効力日との同値が証明された場合の補助証拠のみ。ledger歴史効力日の実切替日への再基線化はA0-4b route裁定候補
   - 例: 4月=4/4→5/2。直感に反するが**4/1-4/4は3月に属する**(殿裁定01:40)
   - **用語統一(家老N1)**: 以後、本書で境界を指す語は「**月次境界日**」のみを用いる。「執行」はholding切替の事象(§0.5タイムライン3)を指し、切替なし月のRULE06リセット効力日は執行ではなく月次境界日である
2. **空白ゼロの構造保証**: 連続月は月次境界日という単一の境界点を共有(前月の終点価格=当月の起点価格)。空白があるとpre/afterの価格変動を無視してしまう — これが是正の核心理由。端点はPF開始(Partial起点=全ticker価格が揃う実運用開始日)と現在(MTD終端=as_of)の2つのみ
3. **系列**: Close系列=月次境界日のclose、Open系列=月次境界日のopen。混在禁止(RULE09)
4. **モメンタム(シグナル判定)はリターン区間と別物**: 終点=常に月の最終営業日の終値。始点=ルックバック期間に応じて変動。全て営業日ベース(現行実装momentum_cache.py:79-93/212-230は殿裁定と一致=変更不要)
5. **月の四分類(家老F6で未開始を分離)**: Normal=確定済み月(上記区間で計算) / MTD=進行中の未確定月(**当月の月次境界日→as_of**の動的計算=家老F3。歴史突合対象外) / Partial=PF実運用初月(実運用開始日→翌月の月次境界日。**開始日を含む初回不完全区間のみ**) / **未開始**=実運用開始日より前の月(検証対象外。Partialと混同しない)
6. **取引費用=0**(システムに費用概念なし。rg全域hit 0で確定)
7. **fallback禁止・fail-visible**: holding_signal欠損・weights空を0や代用値で握りつぶさない(現行return_calculator.py:212-225の空weights→0.0化は修正対象)
8. **数値意味論の規約**(軍師#8+家老F4): weights系の一次データはJSON格納(decision_ticker_weights/config/momentum_data)であり、本番展開はfloat化・equal-weight除算・再帰乗算を行う(price_ratio_impl.py:1096-1112)。**オラクルは本番と同一の数値意味論(float64)で展開・計算する。本番実装が行う正規化のみ同一に適用し、それ以外の正規化・丸めの追加は禁止**(独自Decimal化・中間丸め含む)。比較は§0の一意基準(10桁量子化後exact一致)に従う — 基準は§0の一箇所のみで定義し本節では参照する。子PF weight合計の1.0乖離は補正せずfail-visibleで記録。展開の各段(JSON→float・除算・再帰積)の規約はA0-1実装時にfixtureで固定

### 現行実装の誤り(是正対象。家老D0現物特定)
- 月境界を「月初SPY存在日→翌月初SPY存在日」に固定: return_calculator.py:159-181/245-249、monthly_returns.py:353-364/388-392 → **執行ずれ月に空白が生じる根因**
- trade生成器がFoF展開weightsの日次変化を無条件trade化: trade_performance.py:613-659 → 暫定値・非取引日付のMonthly行を永続化
- signal fallback: trade_performance.py L497(Standard側)+L223+repo同型 → 全数除去対象

### オラクルv2入力SSOT(家老D0固定・証拠行番号付き)
prices(open/close, adjusted)・SPY prices日付カレンダー・portfolio.type/config(rebalance_trigger/component_portfolios/pipeline_config/weights)・signals.holding_signal・pipeline FoFのみsignals.momentum_data.weights・全子PFのconfig+signals再帰展開・signal_decision_ledger.decision_ticker_weights(確定月は最優先)・as_of_date(証拠: return_calculator.py:145-210, monthly_returns.py:209-213/371-385, price_ratio_impl.py:1045-1080/1174-1188/1220-1247)。本番のcache・修正経路を経由しない独立再帰計算とする

### trade_performance正規形(✅確定 — 殿裁定2026-08-03 02:25+家老B1是正)
**月次境界日/trigger eventごとに1行**(家老B1: allocationが前月と同一でも行を分割する — RULE06の毎月resetイベントを記録可能に保つため。「同一状態の連続区間を1行に結合」は採らない)。隣接行はend=次行start・gap/overlap 0。非Openはtrade_date=当該月次境界日かつ**typeはrebalance_trigger由来(Monthly/Bimonthly/Quarterly)に統一。Signal型は廃止**(殿裁定: RULE04の独立性維持・DB制約が単純化。**signal変更の正本はsignals/ledgerでありtrade記録から読むものではない**=家老WARN: 異なる子PFが同一expanded allocationになる場合、allocation差分ではsignal変更を判別できない)。terminal Openは1行のみ(trade_date NULL)。allocationは月次境界日時点の確定weights。非取引日・暫定weightsの行は禁止。producer不一致(trades_impl.py:1027-1081のSignal型)はB2dのproducer一本化で是正。**必須fixture: 同一allocation連続月**(行分割が保たれること)

### 検証者規約(不一致を「誤り」と断定する前の4問)
1. その月は実運用開始日以降か?(**実運用開始日を含む初回不完全月=Partial、それより前=未開始(対象外)** — Partialと未開始を混同しない=家老F6)
2. 確定済みの月か?(進行中ならMTD — 歴史突合対象外)
3. 境界を**§0.6-1の月次境界日**で解決したか?(誤り方は2種を区別せよ=家老F7: (a)暦日1日固定→初営業日への解決漏れ(実証: 影丸104件が「1日非営業日月」に集中) (b)初営業日固定→実効力日への解決漏れ(実証: 2022-04執行ずれ、A0初回オラクル1,861行誤判定)。両方を通過して初めて正)
4. リターン境界とモメンタム窓を混同していないか?

### 作業環境と制約
- 調査は本番readonly厳守。SQLは`/db-check`スキル(db_capability_launcher readonly_query)のみ
- 本番書込みはPF単位transaction+事前backup+transactional_restore手順固定の実装cmd経由のみ
- 横断制約(殿原則): 粒度を小さくシンプルに確認×レーン間並列。一括検証・一括再生成禁止
- cmd化規約: 1工程=1cmd。ACは§2.5のGoal二値をそのまま使用。バンドル起票禁止

## §1 AsIs(確定事実・全て本番readonly実測)

### 1a. 引き金(2026-08-02)
- rootfix `b90f04ee`(親FoF消費是正。commit=2026-08-02 11:57:56 JST git log確定。cache補正`0ed7de44`とは別物)+fullrecalculate id=218後、monthly_returnsが7,661行変化(値変化1,885行・59PF)。保有シグナル=0/363,652行で無傷
- 「旧値」=04:06Z backup(13:06 JST、commit後)。revert可否は「recalc id=218実行前か」で決まる — backup実体(パス/manifest/row count/hash)+deploy時刻+recalc開始時刻の三点provenanceはA0-2 Startで確定
- 集計恒等式(積=累積)は102/102PF PASS=内部整合

### 1b. CAGR急落の真因=歴史の書換え
- 変化1,885行は2012〜2026年全期間に散在(2023年264行・2016年205行・2022年200行…今月分96行のみ)。年平均デルタは大半の年で負(最大単月-28.1pt)。57PF中50PFが累積低下方向、ワーストPF累積係数≈0.19倍
- ∴「1ヶ月のマイナスで10年CAGRは動かない」(殿)は正しく、原因は歴史行の書換え。旧新どちらが確定仕様に近いかはA0-2の突合で判明する

### 1c. 「月中トレード」の実体=境界の分割記録+空白
- 同一暦月に複数Monthly行=1,900PF月・69PF(Monthly重複1,839+Open余剰56+PF開始月8)。2本目の発生日: 月初1-3日1,188/4-7日642/8日以降9、3本目5(全て8日以降)。**8日以降計14件のみが真の月中トレード疑い(A0-3個別調査)**
- 実例(奥義-GS-加速R-激攻 2022-04): holding_signalは4/1に正常切替。trade_performanceは「4/1旧構成(4/1→4/4)」+「4/4新構成(4/4→5/2)」に分割。monthly_return=+14.131%は4/4→5/2区間**のみ**と桁一致。3月=3/1→4/1 close(+12.867%桁一致)。∴**4/1→4/4(+0.415%)はどの月にも算入されない空白** — 確定仕様では3月を4/4まで延長して吸収する(是正対象)
- 4/1断片行のallocation(XLU56/TMV44)は直前保有(XLU100)とも不一致=FoF日次展開の暫定値。暫定状態のMonthly化が2026年159件の進行の正体(8/1土曜付Monthly行の実例あり)

### 1d. 過去の検証の無効化(教訓込み)
- Phase 0初回三者突合(neither=1,861/new=21/old=3、artifact=`logs/recon_artifacts/kotaro_phase0_threeway_20260802.csv`)は**§0.6確定前のオラクル(月初固定・境界誤り)によるもので無効**。旧値不正の結論は不採用
- L0検証6忍者の「不一致133件」も三分類(Partial12+/MTD6/resolver バグ104)で**汚染0件**と確定済み。standard層の計算可能なNormal行は全て誤差ゼロ一致
- 教訓: 審判(オラクル)の仕様が未確定のまま突合すると偽不一致を量産する。§0.6の4問規約が再発防止

## §2 ToBe

1. **仕様の正**: §0.6がtrade-rule.md正本へ明文化されている
2. **値の正**: 全PF×全期間のmonthly_return系(Close/Open両系列)が§0.6準拠オラクルと誤差ゼロ一致
3. **記録の正**: trade_performanceが§0.6正規形に従う(非取引日付・暫定値のMonthly行=0)
4. **構造の正**: 境界解決はboundary helper(単一関数)経由のみ。計算・記録・表示の全callerが共用。fallback=0箇所・fail-visible
5. **監視の正**: 正規形違反INSERTの拒否+検知が常設(fail-visible)。本番UI/API/DBの三面一致(RULE11)を全PFで検証済み・翌月初サイクルの継続監視あり
6. **シグナル影響の管理(v3.6是正 — 家老現物確認msg_023141により「一切変更なし」の当初主張を撤回)**:
   - **Standard PF: 理論上シグナル不変が成立**(モメンタム入力=ticker価格系列のみ。pricesは本修正で不変)。B4/D4/E1でstandard PFのsignalsスナップショット差分=0を二値確認(checkpoint直前後比較、正常日次追加は別枠)
   - **FoF(L1/L2/L3): 理論上シグナルが変わり得る** — FoF選択モメンタムは子PFのMonthlyReturn.cumulative_returnを擬似価格として使う(一次証拠: component_price.py:54-80、recalculate_fof.py:333-336/976、multi_view_momentum_filter.py:39-42/202-208)。月次是正が僅差ランキングを反転させればcomputed signalが変わり、nested構造(recalculate_fof.py:1318-1364)で上位層へ再帰伝播する
   - ただし**ledger reconcile(recalculate_fof.py:221-235)が確定holding_signalを維持するため、computed変化≠即座のDB holding変化**。∴「DB差分0」は理論不変の証明にならない — **computed-vs-confirmed driftを別計測**する
   - **シグナル遡及の原則(✅殿裁定2026-08-03 02:34)**: ①**price遡及変更**由来の差 → 計算時点のpriceでは正しい計算が行われていた → シグナル維持が正(ledger guardの本来の守備範囲) ②**計算ルールの是正**由来の差 → 過去シグナルが誤った計算式で固定されるのは許されない → **正しいシグナルを受け入れ本番も修正する。フル再計算は正しい変更を反映しなければならない**。∴レーンSでholding_changedが出た場合の扱いは裁定済み=受容・修正(実行はbackup+PF単位transaction+ledger再基線の正規手順で。ledger guardはルール是正の反映を妨げてはならず、価格遡及ノイズのみを弾く役割へ精密化する — 実装はB/Dレーンで設計)
   - 影響の全数確定=**レーンS(dual replay)**: 旧系列と是正系列の2入力で全FoF×全リバランス判断日をL0→L3のtopological順に再走し、各blockのscore/rank/cutoff/threshold/selected setを保存。判定は固定epsilonでなく実差の符号反転/tie変化で行い、**相互排他の三分類(unchanged / computed_changed_should_guard / computed_changed_should_apply)の全数表**を作成(readonly replay時点では適用は観測不能のため予定分類とし、実適用/guardの確認はD/Eレーンで行う=家老v3.9-(4)。signal_changed・holding_changedの予定boolean列を併記)、件数合計=全FoF×全判断日で二値証明。**holding_changedの扱いは裁定済み(§2-6原則: 受容し本番修正)。A0-4bに残る裁定はrouteのみ**

## §2.4 依存・並列・影響範囲マトリクス(殿指示2026-08-03 02:41。起票順の唯一の根拠)

**順序の唯一の正本=§2.5 WBS各工程のStart列。本表はそこから機械導出した投影であり、矛盾時はWBSが勝つ(家老v3.9-(1))。Waveは「最速で着手可能になる時点」の目安であり、barrierではない — 各工程はStart列の前提が揃い次第、Waveを待たず着手してよい(家老WARN: lane間並列・lane内直列)。影響範囲=そのcmdが読む/書く対象。本番DB書込みはDレーンのみ。**

| Wave | 工程 | 依存(前提) | 影響範囲(read) | 影響範囲(write) | 本番write |
|---|---|---|---|---|---|
| W1 | A0-0b | A0-0c+§0.6-1(家老v4.4-B1: ledgerフィールド確定後) | 本番DB(readonly) | docs成果物 | なし |
| **W0(即時・全並列可)** | A0-0c | §0.6-1のみ | ledger/DB/コード現物 | 独立成果物md(還流内容案含む。本書追記は将軍直接還流) | なし |
| W0 | A0-3 | §1cの14件のみ | 本番DB(readonly) | docs成果物 | なし |
| W0 | A0-4a残件 | §0.6のみ | — | trade-rule.md(docs) | なし |
| W0 | B3.5(caller inventory) | §0.6のみ | DM-signalコード(read) | docs(inventory表) | なし |
| W0 | B3i(fallback inventory。B3の調査前半を独立工程化=家老v3.9-(3)) | §0.6のみ | DM-signalコード(read) | docs(inventory表) | なし |
| W1 | A0-0a(四分類) | A0-0c還流済み+CSV+本番readonly join | 本番DB(readonly)+CSV | docs成果物 | なし |
| **W1** | A0-1(オラクル) | A0-0a+A0-0c+A0-4a残件(WBS Start列と同一。全W0待ちではない) | prices等(readonly) | 新規オラクルツール+fixture(隔離) | なし |
| W1 | B1(boundary helper) | A0-0c+§0.6(家老v4.3-B1: resolverはledgerフィールド確定が前提) | prices/signals/config/ledger(readonly) | 新規オラクルツール+fixture(隔離) | なし |
| **W2(第二段階・各行Start列準拠)** | A0-2 | A0-1+A0-0a+A0-0b+backup provenance | backup+本番DB(readonly) | docs(層別全数表) | なし |
| W2 | A0-2p | A0-1+A0-0a | 本番DB(readonly) | docs | なし |
| W2 | A1-A5(L0確定。lane内はA1-A4並列→A5) | A0-1 | 本番DB(readonly) | docs | なし |
| W2 | S1→S2→S3(dual replay。lane内直列) | A0-1+旧snapshot固定 | 本番DB(readonly)+旧snapshot | docs(三分類全数表+S3規模報告) | なし |
| W2 | B2a-B2e | B1 | DM-signalコード | DM-signalコード(隔離branch) | なし |
| W2 | B3(fallback除去実装) | B1+W0のinventory | DM-signalコード | DM-signalコード(隔離branch) | なし |
| **W3** | A0-4b(殿route裁定) | A0-2+A0-2p+A0-3+S2/S3(WBS Start列と同一) | 全数表 | 裁定文書 | なし |
| W3 | B4(隔離ドライラン) | B2a-e+B3+B3.5 | 隔離環境 | docs(差分表) | なし |
| W3 | C0→C-x→C9(L1忍法) | A5 | 本番DB(readonly)+L0確定値 | docs | なし |
| **W4** | B5(拒否gate常設) | B4 | — | DM-signalコード(本番deploy) | コードのみ(データ書込みなし) |
| W4 | C2-x(L2/L3) | C9 | 本番DB(readonly) | docs | なし |
| **W5** | D0→D-x→D3→D4(浄化) | A0-4b+B4。D-xはL0→L3 topological直列(子孫完了後のみ親) | backup | **本番DB(PF単位transaction)** | **あり(唯一)** |
| **W6** | E1→E2(本番検証) | B5+(D4または浄化不要証跡) | 本番UI/API/DB(readonly) | docs | なし |

**並列可能性の原則**: W0の5工程(A0-0c・A0-3・A0-4a残件・B3i・B3.5)は相互依存ゼロで並列可(A0-0a・A0-0b・B1はA0-0c後のW1)(6名超過分は2巡目、配備順は家老采配)。**設計書本体への還流追記は各cmdのGATE CLEAR直後に将軍が直接実施(将軍直接還流。工程レーンのD0とは無関係)**(家老v4.3-B2: W0並列cmdが同一設計書fileを編集する競合の根絶。各cmdの成果物は独立ファイル+還流内容案の報告記載まで)。A0-1のStartはWBS列(A0-0a+A0-0c+A0-4a残件)であり全W0待ちではない(家老v4.3-B3)。W2以降はレーン間並列・レーン内直列。直列が必須なのは (a)A0-1がA0-0a+A0-0c(将軍還流済み)+A0-4a残件を待つ点 (b)殿裁定(A0-4b) (c)D-xのtopological順 (d)E最終検証のみ。

## §2.5 工程WBS(唯一の状態正本。全工程にStart(前提)/Goal(二値)。1工程=1cmd)

**依存(枝別・家老v4.5-B1)**: 枝1=W0の5工程(A0-0c/A0-3/A0-4a残件/B3i/B3.5)即時並行。枝2=A0-0c(GATE CLEAR+将軍還流済み)→{A0-0a, A0-0b, B1}。枝3=A0-1←{A0-0a, A0-4a残件}→A0-2/A0-2p/S1-S3並列→**A0-4b(殿route裁定=唯一の残関門。前提にS2/S3を含む)**。A(L0確定)=A0-1後。B(根治)=B1/B3i/B3.5が即時、B2群はB1後。C=A5後、C2=C後、D=B4+A0-4b+対象PF所属層確定後、E=B5+(D4または浄化不要証跡)後。

### レーンA0: 再裁定(readonly)

| ID | Status | Start | 作業 | Goal(二値) |
|---|---|---|---|---|
| A0-0a | GATE CLEAR(gate 03:44:10。cmd_4220全1,885行分類確定) | **A0-0c(GATE CLEAR+将軍還流済み)**+三者突合CSV(§1d)+**本番readonly join(operational_start・ledger/expanded境界証拠)**(v4.7実走知見: CSV単独ではQ1/Q3判定材料なし=cmd_4220初回実走で全行要調査に退化) | 全行を証拠付きでNormal/Partial/MTD/未開始へ確定分類し合計式固定(和=1,885)。要調査・未分類が1件でも残る間はA0-0a未完了(in_progress/RC)であり代替PASSなし(家老v4.9-B1) | 証拠付き四分類の和=1,885かつ要調査=0かつ未分類=0か? |
| A0-0c | GATE CLEAR(gate_metrics 03:22:33。455e682fa・還流済v4.12) | §0.6-1優先順位+ledger/DB現物(readonly) | **境界日SSOTのledgerフィールドを現物で確定**し、独立成果物md(還流内容案含む)を作成(本書§0.6-1への追記は将軍直接還流=単一writer、本工程の外) | フィールド名と効力日導出式が成果物mdで確定したか?(還流はA0-0b/B1/A0-1のStart側が「A0-0c GATE CLEAR+将軍還流済み」で確認=家老v4.5-B2) |
| A0-0b | GATE CLEAR(gate 03:53:22。17,379 PF月全走査・欠落0・執行ずれ8,847) | **A0-0c(ledgerフィールド確定済み+§0.6-1のverification付き導出式)**+primitive(signals+ledger+prices+再帰展開) | **執行ずれ月(境界日≠初回取引日の月)の全数一覧をprimitiveから独立導出**(家老F9: 汚染疑いのあるtrade_performance境界を母集団SSOTにしない)。`effective_start_date` の存在のみでStart充足と解釈せず、§0.6-1のverification付き導出式(検証済ledger優先/expanded fallback)を使用。A0-2とroute裁定の母集団へ接続 | 全PF×全月を走査した独立導出一覧が完成し、境界日は全行verification付き導出式によるか? |
| A0-4a残件 | GATE CLEAR(gate 04:07:09。§0.6正本転記完了) | §0.6 | trade-rule.md正本へ§0.6を転記(営業日定義・区間定義・境界日優先順位・モメンタム窓・四分類・RULE06意図)。裁定は完結済みゆえ書記作業 | 正本に§0.6全項が存在するか? |
| A0-1 | GATE CLEAR(gate 04:30:58。確定仕様オラクル+fixture2名突合) | A0-0a+**A0-0c(ledgerフィールド確定済み+§0.6-1のverification付き導出式)**+A0-4a残件(正本転記)+§0.6全項 | **確定仕様オラクル実装**: primitive入力(§0.6 SSOT)からの独立再帰計算(数値意味論=§0.6-8)。fixture期待値=**軍師+家老の2名独立手計算突合で凍結**。fixtureは分類/日付用とreturn用を分離、MTDはas_of固定。**必須fixture月: 1日非営業日月・1日営業日だが効力遅延月(2022-04型)・保有不変月・非リバランス月(bimonthly/quarterly)・Partial・MTD** | 全return fixtureで2名手計算と一致するか? |
| A0-2 | 未着手 | A0-1+**A0-0a+A0-0b**+backup三点provenance確定(§1a) | A0-0aのNormal行+**A0-0bで導出した母集団外の執行ずれ月行**を「旧値(母集団外は現在値の歴史整合検査)vsオラクル」「新値vsオラクル」の2系で突合し、PF型×層×年代×境界種別の層別全数表を作成(家老N2: 母集団外行もroute裁定へ接続) | 対象全行に2系判定+層別表完成か? |
| A0-2p | 未着手 | **A0-0a**のPartial/MTD行+A0-1(専用オラクル含む) | Partial/MTD行を各専用オラクルで判定。計算不能が残る間はA0-2p未完了(要調査移管による完了不可=家老v4.9-B2) | 全行が専用判定済みかつ要調査=0か? |
| A0-3 | GATE CLEAR(gate_metrics 03:34:16) | §1cの8日以降14件 | 真の月中トレード疑い14件の個別調査(実トレードか記録バグか行単位確定) | 14件全行に確定分類が付いたか? |
| **A0-4b** | 未着手(殿裁定待ち) | A0-2+A0-2p+A0-3+**S2/S3(シグナル影響全数表)** | **殿がrouteを裁定**: 層別(PF型/層/年代/境界種別)に①backup restore ②現行維持 ③PF単位再生成の混合route。**月次値routeとsignal/ledger再基線routeを同時に一意化**。判定粒度=年月単位基本。restore路は行単位restore可否+最小列閉包(stale child/cache・派生列を巻き戻さない)を先に検証。D3恒久制約の要否・D省略時のE到達経路(浄化不要証跡)も本裁定に含む | 層別routeが一意+D省略時経路定義済みか? |

### レーンA: L0確定(A0-1後。審判=確定仕様オラクル)

| ID | Status | Start | 作業 | Goal(二値) |
|---|---|---|---|---|
| A1 | 未着手 | 影丸L0スクリプト+§0.6規約3 | 境界解決を月次境界日基準へ修正しfixture自己テスト(1日非営業日月含む)後、DM4系を再検証 | 対象PF全確定Normal月が誤差ゼロか? |
| A2 | 未着手 | 6忍者L0報告の不一致133行 | 全行を証拠付きでNormal一致/Partial/MTDへ確定分類し合計式固定の証跡表を作成。要調査・未分類が残る間はA2未完了(家老v4.10指摘: 全行要調査のvacuous PASSとA5空洞化の禁止) | Normal+Partial+MTD=133かつ要調査=0かつ未分類=0か? |
| A3 | 未着手 | A2のPartial行 | Partial専用オラクル(実運用開始日→翌月の月次境界日、開始日holding展開)で突合 | Partial全行が誤差ゼロか? |
| A4 | 未着手 | A2のMTD行 | MTD専用オラクル(**当月の月次境界日→as_of**=§0.6-5)で突合。計算不能が残る間はA4未完了 | 全行が一致か?(計算不能残=未完了) |
| A5 | 未着手 | A1-A4 | L0確定宣言(4条件全PASS) | 4条件すべてyesか? |

### レーンB: 発生源根治(§0.6仕様で即着手可)

| ID | Status | Start | 作業 | Goal(二値) |
|---|---|---|---|---|
| B1 | GATE CLEAR(gate 04:13:04。helper+13/13 PASS・2022-04型fixture含む) | **A0-0c**+§0.6 | boundary helper実装(**四分類**+月次境界日解決(§0.6-1のverification付き導出式=検証済ledger優先/expanded fallback。無条件ledger優先・単純COALESCE禁止)+モメンタム窓分離)+単体テスト(1日非営業日月・効力遅延月(2022-04型: ledger 4/1≠実切替4/4でexpanded採用)・保有不変月・非リバランス月・PF開始月・進行月) | 全fixture月で分類・日付・境界日が期待値一致し、2022-04型fixtureで4/4を返すか? |
| B2a | 進行中(CI RED BLOCK 04:36:40 run 30763603748=家老ci_fix対応中) | B1+return_calculator.py:159-181/245-249現物 | **計算経路へhelper適用**(家老F8 BLOCKER解消: 空白根因の本丸)。月境界の月初固定を§0.6-1境界日へ差替え | 隔離再計算で執行ずれ月の前月が境界日まで延長され空白=0か? |
| B2b | 未着手 | B1+monthly_returns.py:353-364/388-392現物 | **月次生成経路へhelper適用**(同上) | 同経路の境界が§0.6-1と一致するか? |
| B2c | GATE CLEAR(gate 04:53:17。記録経路helper適用) | B1+trade_performance.py:613-659現物 | **記録経路(FoF生成器)へhelper適用**。暫定状態・非取引日付のMonthly化を構造的に不能化 | 隔離環境で暫定値/非取引日付のMonthly新規生成=0か? |
| B2d | GATE CLEAR(gate 04:37:30。producer一本化) | B1+trades_impl.py:1027-1081現物 | **producer一本化**(家老B2): Signal型producerをtrigger型へ変換・統合。B4の正規形検証前に完了させる | producer=単一系統+Signal型新規生成=0か? |
| B2e | 進行中(task done 04:53:56・GATE CLEAR待ち) | B1+recalculate_fof.py:221-235現物 | **ledger guardのmode化**(家老N3): recalc invocationへ明示provenance/modeを導入し、price_retro=guard維持 / rule_correction=適用+ledger再基線 / 未知mode=fail-closed。差分から原因を推測しない。**敵対fixture3種**(price遡及・ルール是正・未知mode)必須 | 3 fixtureで期待挙動(guard/適用/停止)が全一致か? |
| B3i | GATE CLEAR(gate 04:03:02。fallback inventory完成) | §0.6のみ(即時可) | **fallback全数inventory作成**(L497+L223+repo同型をgrep全数列挙。読み取りのみ) | inventory表が全数列挙+件数根拠付きで完成したか? |
| B3 | RC待ち(才蔵task failed・軍師FAIL。B2e CLEAR後に合同scopeで再配備=家老v4.26) | B1+**B3i(inventory完成済み)** | signal fallback全数除去(L497+L223+repo同型をgrep全数列挙)。欠損はfail-visible | fallback経路=0箇所(inventory添付)+可視エラーか? |
| B3.5 | GATE CLEAR(gate 04:03:02。caller inventory完成) | §0.6のみ(読み取りinventory。helper不要) | 計算/記録/表示の全callerをgrep全数列挙したinventory表を作成(適用漏れ0の検証はB4が本表を使って行う) | caller一覧が全数列挙+件数根拠付きで完成したか? |
| B4 | 未着手 | B2a/B2b/B2c/B2d/**B2e**/B3/B3.5 | 隔離ドライランを**PF単位レーン分割**で実行し全数集約。§0.6正規形違反の新規発生0+非対象フィールド不変+**signalsスナップショット差分(§2-6方式: standardは差分0、FoFはSレーン分類で裁定済み変更(applied)と非意図差分を区別)**を確認 | 全PFレーンで非対象差分=0+新規違反=0+**standard signals差分=0+FoF非意図差分=0**か? |
| B5 | 未着手 | B4 | 正規形違反INSERT**拒否gateの常設のみ**(producer一本化はB2dで完了済み=家老B2)。DB恒久制約はD3まで保留 | 違反注入テストで拒否+通知100%か? |

### レーンC: L1忍法検証(A5後、1忍法=1レーン並列) / C2: L2/L3(C後)

| ID | Status | Start | 作業 | Goal(二値) |
|---|---|---|---|---|
| C0 | 未着手 | A5+本番DB | L1対象FoF全数一覧と忍法系列分類表 | 全L1 FoFが1レーンに1回だけ属するか? |
| C-x | 未着手 | C0+L0確定値 | 忍法ごとに確定仕様オラクル(入力=直下L0確定値のみ)で全Normal月突合+Partial/MTD専用オラクル | Normal=誤差ゼロ・Partial/MTD=専用判定PASS・未開始のみ対象外、で全行が確定したか?(除外PASS禁止=家老F10) |
| C9 | 未着手 | 全C-x PASS | FoF合成恒等式(構成weight×子PF確定値=親月次)を全L1で確認しL1確定 | 恒等式不一致=0か? |
| C2-x | 未着手 | C9+本番DB | L2→L3の順に直下層確定値のみを入力に同型検証(1親FoF=1レーン) | 各層全行が誤差ゼロか? |

### レーンS: シグナル影響dual replay(A0-1後・C系と並列可。readonly)

| ID | Status | Start | 作業 | Goal(二値) |
|---|---|---|---|---|
| S1 | 未着手 | A0-1(是正系列オラクル)+旧MonthlyReturn snapshot固定 | 全FoF×全リバランス判断日を旧/正2入力でdual replay(L0→L3 topological順、同一pipeline config)。各blockのscore/rank/cutoff/threshold/selected set/computed signalを両系で保存 | 全FoF×全判断日の両系記録が完成したか? |
| S2 | 未着手 | S1+ledger確定値 | 相互排他の三分類(unchanged / computed_changed_should_guard / computed_changed_should_apply)全数表を作成(予定分類。実適用確認はD/E。boolean列併記。件数合計=全FoF×全判断日)。僅差判定は実差の符号反転・0到達・tie変化(固定epsilon禁止) | 三分類の合計が母集団と一致するか? |
| S3 | 未着手 | S2 | 結果を殿へ報告(holding_changedの件数と内訳)。**扱いは裁定済み(§2-6原則: 受容し本番修正)** — 報告は規模と実行計画の確認のため | 報告完了+修正対象リスト確定か? |

### レーンD: 浄化(A0-4b裁定で要る場合のみ。本番書込み・直列)

| ID | Status | Start | 作業 | Goal(二値) |
|---|---|---|---|---|
| D0 | 未着手 | A0-4b+B4 | 浄化方式確定(restore計画または対象PFリスト+立証証跡)を殿へ提示。route=現行維持のみなら「浄化不要」証跡を発行しEへ直行 | 各項に証跡があるか?(省略時=証跡発行済みか?) |
| D-x | 未着手 | D0承認+当該PFの所属層検証PASS+**当該PFの全子孫PFのD-x完了**(家老N4: 実行順=L0→L1→L2→L3のtopological直列。下位monthly→上位signal→上位monthlyの伝播があるため、子のcommit/検証後にのみ親へ進む) | 1PF=1 transaction: backup→浄化→オラクル誤差ゼロ→commit。FAILは当該PFのみtransactional_restore(冪等) | 当該PF正規形違反=0+誤差ゼロ+子孫全完了済みか?(noならrestore済みか?) |
| D3 | 未着手 | 全D-x | DB恒久制約(正規形一意)有効化 | 制約有効+既存違反0か? |
| D4 | 未着手 | D3 | 全PF事後検証(正規形違反全数0+§1a恒等式+**signalsスナップショット差分(standard=0、FoF=裁定済み変更のみ)**) | 全数0+PASS+**standard差分=0+FoF非意図差分=0**か? |

### レーンE: 本番表示・継続検証(B5+(D4または浄化不要証跡)後)

| ID | Status | Start | 作業 | Goal(二値) |
|---|---|---|---|---|
| E1 | 未着手 | B5+(D4または浄化不要証跡) | Monthly Trade画面/API/monthly_returnsの三面一致(RULE11)を**全PF**で確認(サンプリング禁止) | 全PFで三面矛盾=0+**standard signals差分=0+FoF非意図差分=0**か? |
| E2 | 未着手 | E1 | 翌月初の定期再計算1サイクルを監視し新規違反0+表示正常を確認 | 1サイクル完走で違反0か? |

### Phase 5(GS再検証判定) — 凍結
殿指示(2026-08-02 23:22)により凍結維持。判定は一点のみ予約: Bレーンで修正した発生源コードがGSスクリプト群(shin_shijin_l1_gs.py・run_077系・grid_search_metrics_v2.py)から参照・コピーされているかのimport/実装照合。着手は殿の下知まで行わない

## §3 経緯evidence(旧版の要点圧縮。詳細は§7と記憶DB)

- 2026-08-02: rootfix後のCAGR急落を殿が検知→調査5トラック→「月中トレード1,839件=汚染」と初期認定→Phase 0初回三者突合(→後に無効化)
- 2026-08-03 00:22-00:34: 三者評定(将軍D1-D7案+家老COUNTER3件+軍師全受容)。boundary helper・PF単位transaction・忍法レーン等の骨格合意
- 2026-08-03 00:47-01:54: 殿の連続指摘で問題定義が転換し、§0.6の全裁定が完結。独立レビュー2巡(家老16+11件・軍師5+1件)+相互不可視最終確認を全反映
- 教訓(§1d): 審判の仕様確定前の突合は偽不一致を量産する / 追記累積は矛盾を残す(本v3.0全面書き直しの理由=殿指摘01:58)

## §4 5W1H

- **WHY**: 月次リターンの月境界仕様が未明文のまま実装が月初固定を使い、執行ずれ月の空白脱落と暫定値Monthly行が歴史とCAGRの信頼を崩したため。殿ゴール「全PFが正しく計算され正しく表示されて継続する」への回帰
- **WHAT**: §2.5の6レーン。最初の成果物=A0-0a分類表+A0-0b執行ずれ月一覧+A0-0c ledgerフィールド確定+A0-1オラクル+A0-2層別突合表
- **WHEN**: W0の5工程(A0-0c・A0-3・A0-4a残件・B3i・B3.5)は即時。A0-0a・A0-0b・B1はA0-0c後。D(本番書込み)はA0-4b裁定+殿承認後
- **WHERE**: DM-signal backend(return_calculator.py・monthly_returns.py・trade_performance.py・boundary helper新設)+本番DB(D実行時のみ)
- **WHO**: 配備=家老采配(忍者6名、相互参照禁止)。将軍=版管理・裁定検分・殿上程。軍師=オラクルfixture独立手計算+レビュー
- **HOW**: 判定は常に§0.6準拠オラクルを審判とする突合。修正はboundary helper単一関数を全出口(計算・記録・表示)へ — ledger guardのDB門と同型

## §5 二値AC(設計書レベル)

- AC-A0: 1,885行の証拠付き四分類(Normal+Partial+MTD+未開始)の和=全行・要調査0・未分類0 / **執行ずれ月のprimitive独立導出一覧完成(A0-0b)** / Normal全行に旧新×オラクル2系判定 / Partial・MTDは専用オラクル判定済み / 14件全行確定分類 / **§0.6のtrade-rule正本転記完了(A0-4a残件)** / A0-4b route(月次値route+signal/ledger再基線route)が層別に一意でS2/S3全数表を前提に含む
- AC-B: helper適用後の隔離再計算で正規形違反の新規発生=0+全caller適用漏れ=0+fallback=0箇所+**producer単一系統化+standard signals差分=0+FoF非意図差分=0(Sレーン分類基準)**
- AC-層: L0/L1/L2/L3各層でNormal誤差ゼロ+Partial/MTD専用オラクルPASS(層間直列厳守)
- AC-D: 浄化後、全PFで正規形違反=0・オラクル突合誤差ゼロ・DB制約有効(または浄化不要証跡)+**standard signals差分=0+FoF非意図差分=0**
- AC-E: 本番UI/API/DBの三面一致を全PFで確認+翌月初1サイクル監視で新規違反0+**standard signals差分=0+FoF非意図差分=0**

## §6 因果

`[[殿指摘_CAGR低下_20260802]] -> [[歴史1885行の書換えが真因]] -> [[殿指摘_境界遷移は自明_20260803]] -> [[Phase0オラクル無効化]] -> [[殿裁定_月次区間は執行日から執行日]] -> [[空白脱落バグ確定]] -> [[§0.6確定仕様]] -> [[A0再突合 -> route裁定 -> 根治・浄化]]`

## §7 改訂履歴

- **v4.27 (2026-08-03 05:02): 家老v4.26 REVISE反映: ①B3=進行中→RC待ちへ是正(才蔵task failed一次確認+軍師FAIL。B2e CLEAR後合同scope再配備) ②レーンA/S注記「A0-1待ち」→「A0-1 CLEAR済み・配備待ち」(stale解消) ③checker v3=レーン注記の待ち理由IDがCLEAR済み工程を指すとFAILする検査追加(task/report terminal state照合はWBS ID→task名マッピングが動的なため家老側rg集計で補完と分担)。検証値=母数38・CLEAR11件・進行中2件(B2a/B2e)・score12.0・32%=checker v3 PASS(待ち理由stale検査含む)。全体33%→32%(12.0/38)、B=55%。仕様不変**
- **v4.26 (2026-08-03 04:57): 家老v4.25 REVISE反映: ①§0.1見込みのA0-1(進行中)stale解消=クリティカルパスをA0-2/A0-2p+S1-S3(未配備)起点へ更新・残1-1.5時間 ②checkerへ§0.1見込み内の進行中ID参照とWBS進行中集合の突合検査を追加(v2) ③B2c=GATE CLEAR(04:53:17)・B2e=task done・GATE待ちへ精密化。検証値=母数38・CLEAR11件・進行中3件(B2a/B2e/B3)・score12.5・33%=checker v2 PASS(見込みstale検査含む)。全体32%→33%(12.5/38)、B=59%。仕様不変**
- **v4.25 (2026-08-03 04:44): 家老v4.24 REVISE反映: ①§0現在地をv4.25発行時へ全面更新(2版連続stale再発の恒久防御=scripts/check_design_progress_consistency.py新設。版発行前に§0/tracker/WBSを機械照合) ②B2d=GATE CLEAR(04:37:30) ③B2a=CI RED BLOCK(04:36:40 run 30763603748、家老ci_fix対応中)を注記。検証値=母数38・CLEAR10件(A0-0a/0b/0c/A0-1/A0-3/A0-4a残件/B1/B2d/B3.5/B3i)・進行中4件(B2a/B2c/B2e/B3)・score12.0・32%=チェッカーPASS。全体30%→32%、B=55%。仕様不変**
- **v4.24 (2026-08-03 04:36): 家老v4.23 REVISE反映: ①gist SHA不一致の真因訂正=CDNキャッシュ説は誤因果、真因はfilenameなしview/raw出力の先頭にgist description+空行が付加されること(家老byte実測59900B vs 59573B、将軍再実証一致)。検証正本=--filename指定fetch ②A0-1=GATE CLEAR(04:30:58)=A0-2/A0-2p/S1-S3のStart解放 ③B2c=進行中(影丸)。全体28%→30%(11.5/38)、A0=67%、B=50%。仕様不変**
- **v4.23 (2026-08-03 04:27): 家老v4.22 REVISE 2点是正: ①§0現在地を版発行時刻へ更新しB1=GATE CLEAR・A0-1=task done/report完了/GATE CLEAR待ちへ精密化(04:12のstale解消) ②gist SHA検証=gh gist view -f指定でlocal一致(1eb74b11)を再実証。家老実測の不一致(419848cb)の原因当時推定=CDNキャッシュはv4.24で誤因果と判明(真因=description混入)、検証方法の正をview -fに固定・現在地へ注記。%不変(28%)。仕様不変**
- **v4.22 (2026-08-03 04:23): 家老v4.21 APPROVE付帯2点反映: ①B2a/B2d/B2e/B3=in_progress(家老goal配備。B2b/B2cは忍者空き待ち)。全体22%→28%(10.5/38)、B=45%(5.0/11) ②運用是正=毎版、家老+軍師両者のレビュー完了を待って次版へ進む(v4.20が家老レビュー完了前にv4.21で上書きされた反省。進捗は§0.1へ随時集約し、版発行はレビュー完了で束ねる)。仕様不変**
- **v4.21 (2026-08-03 04:16): 巡回#3反映: B1=GATE CLEAR(gate_metrics 04:13:04。boundary helper+単体テスト13/13 PASS・2022-04型fixture=4/4返却含む)。B2a-B2e/B3のStart前提解放。全体21%→22%(8.5/38)、B=27%。進行中=A0-1のみ。仕様不変**
- **v4.20 (2026-08-03 04:14): 家老v4.19 REVISE是正: 「W0全完了(7工程)」表現を§2.4正本に合わせ「W0 5/5(A0-0c/A0-3/A0-4a/B3i/B3.5)+W1のA0-0a/A0-0b=入口累計7工程CLEAR」へ分離(A0-0a/A0-0bはW1のためW0に含めない)。数値・仕様不変**
- **v4.19 (2026-08-03 04:12): 進捗反映: B3.5=GATE CLEAR(04:03:02)・B3i=GATE CLEAR(04:03:02)・A0-4a残件=GATE CLEAR(04:07:09。§0.6正本転記完了)=**W0全工程完了**。A0-1=Start充足で影丸へ配備(進行中)。B1=家老RC後13/13 PASS・軍師review_bundle再生成中(進行中)。全体16%→21%(8.0/38)、A0=61%、B=23%。仕様不変**
- **v4.18 (2026-08-03 04:00): 家老v4.17 REVISE 2点是正: ①表題「W0全完了」→「W0全配備(起票残0)」(A0-4a/B3i/B3.5はreport PASS/レビュー待ちでGATE CLEAR未達のため「完了」は偽) ②見込みクリティカルパスをA0-0a再走→からA0-4a残件CLEAR→へ更新(A0-0aはCLEAR済み)。数値・仕様不変**
- **v4.17 (2026-08-03 03:58): 家老v4.16 REVISE 2点是正: ①A0-0a(cmd_4220)=GATE CLEAR(gate_metrics 03:44:10・/cmd-complete済み)へ更新(v4.16時点で見落とし) ②「W0四工程」表現を是正(B1はW1=A0-0c後。正=A0-4a残件/B3i/B3.5がW0、B1がW1)。算術再計算=全体16%(6.0/38)・A0=50%(4.5/9)・B=14%不変。仕様不変**
- **v4.16 (2026-08-03 03:55): 進捗反映: A0-0b(cmd_4221)=GATE CLEAR(03:53:22。PF月17,379全走査・欠落0・執行ずれ月8,847件=A0-2/route裁定の母集団確定)。W0残四工程(A0-4a残件/B3i/B3.5/B1)=家老goal駆動karo_direct配備で全てin_progress(軍師draft APPROVE済み)。全体8%→14%、A0=44%、B=14%。仕様不変**
- **v4.15 (2026-08-03 03:42): 家老v4.14 REVISE 3点反映: ①A0-0c/A0-3のStatus=GATE CLEAR(gate_metrics一次記録03:22:33/03:34:16)へ更新+§0現在地同期 ②レーンA0=33%へ算術修正(3.0/9) ③見込み時間をgate_metrics実測(work_sec 477/416秒・e2e_sec 1019/1037秒≈17分/工程)から再計算し全体=裁定待ち除き約4-6時間へ。A0-1のみ実測なし独自見積と明示。※cmd_4222のgate_metrics最終行はBLOCK(03:26 review_two_phase_pending)だが家老の世代誤判定根治(03:34掲示板)で解消済みと突合**
- **v4.14 (2026-08-03 03:37): 殿裁定03:36+03:38反映: ①§2.5 WBS全7レーン38工程へStatus列新設(値=未着手/進行中(cmd番号)/done(証跡)/GATE CLEAR)。工程別進捗の正本=WBS Status列 ②§0.1全体進捗トラッカー新設(テキストバー+全体%+レーン別%+見込み時間。定義: done=1.0/進行中=0.5/母数=38工程)。将軍が進捗変化のたび単一writerとして両方更新。仕様変更なし**
- **v4.13 (2026-08-03 03:28): 進捗随時反映(殿指示03:26): §0現在地更新 — A0-0c=成果物確定+v4.12還流完了/cmd_4220=初回classifier全行要調査BLOCK→join再分類で再走中/cmd_4221=in_progress/cmd_4223(A0-3)=done報告レビュー待ち/疾風並行上書きは中断済み(正本=455e682fa)。仕様変更なし(§0.6は不変)**
- **v4.12 (2026-08-03 03:22): 家老v4.11反映=A0-0c実測(cmd_4222 commit 455e682fa)の将軍直接還流: §0.6-1のledger無条件優先を廃止し、`effective_start_date`(本番15,212行全件=decision日複写、2022-04はledger 4/1≠実切替4/4)を「expanded実切替との一致が検証できた場合のみ優先、不一致/未記録はexpanded実切替へfallback、切替なし月は初回取引日」のverification付き導出式へ置換(単純COALESCE禁止)。A0-0b/B1/A0-1のStart/Goalへ同導出式を同期(B1に2022-04型fixture必須化)。ledger再基線化はA0-4b route裁定候補として明記**
- **v4.11 (2026-08-03 03:24): 家老真v4.10レビュー反映: A2にも同型逃げ道廃止(133行の証拠付き三分類・要調査0・残存中はA2未完了。A3/A4/A5のvacuous PASS連鎖を遮断)**
- **v4.10 (2026-08-03 03:21): 家老v4.9反映: A0-0a/A0-2p/A4の要調査移管・解消工程の代替PASSを全廃し、残存中は当該工程未完了へ一意化(実適用は前回送信が空振りだった訂正版=assert検証済み)**
- **v4.9 (2026-08-03 03:16): 家老v4.8-B2残反映: AC-A0へ要調査0を明記、matrixの空ダミー行を除去しW0見出しをA0-0c行へ。B1(WBS A0-0a Start)はv4.8補で同期済み**
- **v4.8補(2026-08-03 03:14): 軍師指摘=v4.7のWBS A0-0a行置換が文字列不一致で無適用だった(matrix側のみ更新)。WBS行を本補で更新(assert検証付き)。教訓: 設計書のpython置換は全てassert必須**
- **v4.8 (2026-08-03 03:12): 家老v4.6-B2反映: A0-0a Goalを「証拠付き四分類の和=全行+要調査=0」へ強化(全件要調査でもPASSする空虚ACの禁止)。B1(A0-0a W0独立不能)はv4.7で反映済み**
- **v4.7 (2026-08-03 03:10): 実走知見の還流(cmd_4220初回実走→家老レビューBLOCK blt_030844): 三者突合CSV単独では検証者規約Q1(実運用開始)とQ3(境界証拠)の判定材料がなく全1,885行が要調査へ退化。A0-0aをW1(A0-0c還流済み+本番readonly join前提)へ移動、W0=5工程へ。設計時の机上依存が実走で覆った初例=実験ファーストの実証**
- **v4.6 (2026-08-03 03:08): 家老v4.5同期残3件解消: 依存要約を枝1/枝2/枝3へ分離(A0-0b/B1はA0-1を経由しない)/A0-0c Goalを成果物確定までに限定し還流済み確認を依存側Startへ移動/W2見出しを「第二段階・Start列準拠」へ(B2群はB1のみ依存の偽前提解消)**
- **v4.5 (2026-08-03 03:04): 家老v4.4残3件解消: A0-0b=A0-0c後W1へ(ledgerフィールド確定が前提。cmd_4221は配備采配でcmd_4222後の直列へ=家老へ通知済み)/A0-0cの成果=独立md+還流内容案へ(本書追記は将軍直接還流)/還流語を「各cmd GATE CLEAR直後の将軍直接還流(工程レーンD0と無関係)」へ一意化/A0-1待ち表現を名指しへ。W0=6工程**
- **v4.4 (2026-08-03 02:59): 家老v4.3の3 BLOCKER解消: B1=A0-0c後のW1へ(resolver前提)/設計書還流を将軍単一writer方式へ(W0並列の同一file競合根絶。cmdは独立成果物+還流内容案まで)/A0-1依存表現をWBS列へ統一(全W0待ち表現の削除)。W0=7工程**
- **v4.3 (2026-08-03 02:56): 両名v4.2レビューの同期残5件を解消: B3.5をW0へ(WBS Start=§0.6のみ・inventoryはhelper不要と定義変更、適用漏れ0検証はB4へ移管)/B1をW0へ(Start=§0.6のみ)/依存要約とWHENへA0-3含むW0=8工程を明記/工程数6→8訂正/§2-6末尾のholding_changed扱いを裁定済みへ統一。W2表現を「レーン間並列・レーン内直列」へ精密化**
- **v4.2 (2026-08-03 02:52): 軍師v4.0レビュー(msg_024750)の新矛盾解消: B3i行をWBSレーンB本文へ正式定義(Start=§0.6のみ即時可、Goal=inventory全数列挙)しB3 Startを「B1+B3i」へ。A0-4b Start同期はv4.1で解消済みと相互確認**
- **v4.1 (2026-08-03 02:49): 軍師v3.9レビュー(msg_024553)のBLOCKER解消: WBS A0-4b Start本文へS2/S3を同期(v3.8で§2.4のみ更新されWBS未同期だった真因=置換文字列不一致の無検証)+依存要約行へS1-S3並列とA0-4b前提を明記。S3の§2.4所属はv4.0で反映済み**
- **v4.0 (2026-08-03 02:46): 家老v3.9レビュー4 BLOCKER+WARN反映+殿指示「先頭から読むLLMの誤解防止・整合性」。①順序の唯一の正本=WBS Start列と宣言し§2.4を投影へ格下げ(矛盾時はWBSが勝つ) ②WaveはbarrierでなくStart前提充足で随時着手 ③S3のWave所属明記+lane内直列(A1-A4→A5、S1→S2→S3) ④B3のinventory前半をB3iとして独立工程化(1工程1cmd整合) ⑤S2分類をshould_guard/should_apply予定分類へ(readonly時点で実適用は観測不能、実確認はD/E) ⑥AC-A0へS2/S3前提とroute二本柱を同期**
- **v3.9 (2026-08-03 02:43): §2.4依存・並列・影響範囲マトリクス新設(殿指示02:41)。W0=即時全並列6工程(A0-0a/0b/0c/A0-3/A0-4a残件/inventory)、W1=A0-1+B1、W2=検証系全並列、本番DB書込みはW5のDレーンのみと明確化**
- **v3.8 (2026-08-03 02:40): 家老v3.7レビュー(BLOCKER4+B3/B4残+WARN)を全採択。N1=S分類を相互排他化(unchanged/computed_changed_and_guarded/computed_changed_and_applied+boolean列)。N2=A0-4b StartへS2/S3を追加し月次値route+signal/ledger再基線routeを同時一意化。N3=B2e新設(ledger guardのmode化: price_retro=guard/rule_correction=適用+再基線/未知=fail-closed、敵対fixture3種)。N4=D-xをtopological直列化(子孫完了後にのみ親へ)。B3/B4=signals検証をstandard差分0+FoF非意図差分0へ分離(裁定済み変更の受容と整合)。WARN=Signal型廃止理由からallocation差分可読性を削除(signal正本はsignals/ledger)**
- **v3.7 (2026-08-03 02:36): 殿裁定「シグナル遡及の原則」を焼込み。price遡及変更→シグナル維持が正(計算時点priceでは正しい計算) / 計算ルール是正→過去シグナルが誤式で固定されるのは許されず、正しいシグナルへ本番修正する(フル再計算は正しく変更を反映すべき)。レーンS holding_changedの扱いは裁定済み(受容・修正)へ更新、S3は規模報告と実行計画確認に変更。ledger guardの役割を「価格遡及ノイズのみ弾く」へ精密化(実装はB/Dレーン)**
- **v3.6 (2026-08-03 02:36): 家老のFoFモメンタム入力現物確認(msg_023141)により§2-6「シグナル一切不変」を撤回・是正。確定事実: FoF選択モメンタムは子PFのcumulative_returnを擬似価格として使用(component_price.py/recalculate_fof.py/multi_view_momentum_filter.py行番号証跡)→月次是正でFoF computed signalは理論上変わり得る(nested伝播あり)。standardのみ理論不変。ledger reconcileによりcomputed変化≠DB holding変化のためcomputed-vs-confirmed drift別計測。レーンS(dual replay全数検出・三分類全数表)を新設し、holding_changedの扱いは殿裁定(A0-4b統合)へ**
- **v3.5 (2026-08-03 02:33): 家老v3.4レビュー(BLOCKER3+WARN1+N1残)を全採択。B1=正規形を「月次境界日/trigger eventごとに1行(同一allocationでも分割)」へ是正(連続区間結合ではRULE06の毎月resetイベントが記録不能)+同一allocation連続月fixture必須化。B2=producer一本化をB2d工程として新設しB4前へ(B5は拒否gate常設のみ)。B3=signalsスナップショット差分=0をB4/D4/E1のGoalとAC-B/D/Eへ明記。B4 WARN=不変検証をcheckpoint直前後のsnapshot比較方式へ(正常な日次行追加の誤FAIL防止)。N1=旧語4箇所を月次境界日へ統一。F4=比較器呼称を「本番計算の保存前round規約」へ精密化(DB列はFloat型)**
- **v3.4 (2026-08-03 02:27): 仕様未決ゼロ達成。①殿裁定02:25: trade_performance種別=**trigger型へ統一・Signal型廃止**(RULE04独立性維持/allocation差分で情報欠損なし/DB制約単純化) ②家老v3.3残件3件解消: F4=比較器を「双方10桁量子化(round-half-even)後exact一致」の単一基準へ一意化(1e-12基準廃止)、N2=A0-0c新設(ledgerフィールド現物確定のreadonly独立工程。A0-1 Start循環解消)、N3=感度分析artifact参照追記(N感度/E感度設計書パス) ③N1語統一: 境界を指す語=「月次境界日」のみ、「執行」はholding切替事象に限定**
- **v3.3 (2026-08-03 02:20): 殿裁定2件+家老v3.2再レビュー残件を反映。①RULE06(毎月ウェイトリセット)は意図的確定ルールと最終確定 — 設計意図=途中参加の公平性(trade-rule.md L153現物確認)、感度分析(N感度/E感度)でロバストネス実証済み・理論上の不純は実務上許容(殿裁定02:14-02:16)。driftへの変更なし。同一シグナルのリバランス月もリセット執行 ②家老N1: 境界日優先順位をledger効力日→expanded実切替日へ是正(root holding日付は不採用 — 2022-04でrootは4/1と誤る) ③N2旧A0-0参照の全数置換+A0-2へ母集団外行接続 ④N3 B1四分類化 ⑤F3 A4のMTD起点=境界日 ⑥F4正規化文言+誤差基準の一意化(§0参照方式) ⑦F6検証者規約1の未開始分離**
- **v3.2 (2026-08-03 02:10): 家老v3.1最終確認(REVISE・疑義10件=msg_020501)を全反映。BLOCKER 2件解消: F1=月次境界日を全暦月に定義(切替あり月=実効力日/切替なし月=初回取引日、判定優先順位=ledger→root holding→expanded weights) / F8=Bレーンへ計算経路適用工程B2a(return_calculator)+B2b(monthly_returns)を新設。他: F2切替判定SSOT優先順位/F3 MTD起点=境界日/F4数値意味論=本番同一float64/F5計算仕様と記録仕様の分離明示/F6四分類(未開始分離)/F7境界誤り2種の区別/F9執行ずれ月一覧のprimitive独立導出(A0-0b)/F10 C-x除外PASS禁止+AC-A0拡張/軽微3件(A0-1 Start・fixture必須月・監査数表記)。軍師v3.1確認=疑義ゼロ(msg_020435)**
- **v3.1 (2026-08-03 02:05): v2.5宛て独立レビュー(家老指摘群msg_015947・軍師5件、大半はv3.0書き直しで解消済み)のうちv3.0にも残る実質指摘を反映。最重要=家老F3: **執行日の定義を「保有(expanded weights)が実際に切り替わった日」と明文化し、市場の月内初営業日との同一視を禁止**(2022-04は4/1営業日でも執行=4/4)。軍師#8残件=weights精度規約を§0.6-8へ新設(DB保存値をそのまま消費・独自丸め/再正規化禁止・合計乖離はfail-visible)。検証者規約3の表現統一+誤字修正**
- **v3.0 (2026-08-03 02:00): 全面書き直し(殿指示01:58「追記は矛盾を残す。丁寧に覚醒してアップデート」)。確定裁定(§0.6)を起点に再構成し、S1/S2両論併記・裁定前表現・旧工程ID(A0-1a/2a/4a等)・重複記述を全廃。§3.8は§0.6へ吸収。工程は§2.5 WBSに一本化**
- v2.0-v2.5 (2026-08-03 01:28-01:56): 独立レビュー2巡統合→殿裁定完結(S2執行日基準→区間=執行日→執行日→モメンタム窓→adj→§3.8同期)。詳細は記憶DB(knowledge:3fe9f871/c03420ab/5b0aa9fc/2a86d812/9f696beb/a01711d2)
- v1.0-v1.9 (2026-08-02 22:52-2026-08-03 01:17): 初版→Phase 0初回裁定(後に無効化)→三分類→三者評定→WBS化→独立レビュー。経緯は§3
