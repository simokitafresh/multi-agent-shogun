# DM-Signal 本番の不整合 I1〜I8 — 事象・影響・改善時の本番変化・影響範囲・依存関係 設計書 v0.2(2026-09-06 14:35 将軍自己検証 3 点: I1 の frontend 参照あり・I6 は monthly_return 経路と同一関数・change_log 前方補完の一致率 26〜79%=change_log は履歴として再構成不能) / v0.1(14:25 起草、家老 R1 依頼)

- 発端: 殿 2026-09-06 14:11『dm-signal-research-data-backlog_20260905.md を参考に DM-signal の本番の不整合について深く調査しよう。家老と繰り返しレビュー交換をせよ。本番の不整合、それによる影響、改善時にどのような変化が本番に起きるか、改善の影響範囲・依存関係なども明確にせよ』
- 親: `docs/research/dm-signal-research-data-backlog_20260905.md` v1.5 §B5(I1〜I8)、`dm-signal-research-data-foundation-asis-tobe_20260905.md` v0.10 §2、`analysis_runs/cmd_4480_shin_yotsume_parity/root_cause_summary.md`(DM-Signal origin 07632b14)
- 正本 repo: DM-Signal origin/main 0f2bfbcd(2026-09-06 13:30)。行番号は全て origin/main の現物。

## §0.0 前提条件と我らのスタイル
- 本書は**調査と設計**であり実装しない。本番 DB への書込・DDL・deploy は殿の明示 OK のみ(殿 09-05 22:25/22:27、CLAUDE.md)。
- シンプル・既存コード・複雑さを足さない・最小変更→実験。改善は「今よりマシか/新しい長期問題を生まないか」の 2 問で判断。
- 数値は一次情報(readonly launcher nonce、cmd 報告、CI 上の verify_*.md)に限る。本書で新規に測っていない数値は「未検証」と明記し、偵察 cmd の対象にする。
- 改善時の本番変化は「誰が何を見る/どの job が何を書く」で書く。抽象語(整合性向上)は禁止。

## 進捗ビジュアル(将軍 loop 更新 2026-09-06 14:25)

**全項目(I1〜I8)** `░░░░░░░░░░ 0/8` ✅完了 🟡走行中 ⏳待ち 🔴要判断
状態集計: ✅ 0 / 🟡 0 / ⏳ 6 / 🔴 2(表の 8 行)
次の一手: 家老 R1 レビュー→未検証 4 点の偵察 cmd(readonly)起票→殿裁定 2 点(I4 ledger の復活/廃止、I6 の正本)

| # | 不整合 | 状態 | 現在値 |
|---|---|---|---|
| I1 | fof_component_weights の未使用 8 列 | ⏳ | 事象確定(24,348 行 NULL)。改善案=列廃止 or writer 補完の二択、殿裁定不要(廃止推奨) |
| I2 | signal_change_log 同日往復の二重行 | ⏳ | 事象確定、発生経路 2 候補=未検証(偵察) |
| I3 | signal_change_log 未出現 PF | ⏳ | 66/78→75 母集団で再計上要(偵察) |
| I4 | signal_detail_history 0 行 / signal_decision_ledger 0 行 | 🔴 殿裁定 | 前者=writer 不在(廃止候補)、後者=PITR 後の再バックフィル未実施(復活/廃止) |
| I5 | 月初 signals.holding_signal ≠ monthly_returns.holding_signal | ⏳ | F1 で計測済み(件数は cmd_4479 verify_change_log.md)、原因分類=偵察 |
| I6 | display_ticker_weights 非 unit 35 行・parity 不一致 29/2,096 | 🔴 殿裁定 | 根因=price_ratio_impl L1237-1250 の選択後再正規化不在。正本を F1 再帰規則にする(A10)か display を直すか |
| I7 | component holding_signal 欠落で展開不能 | ⏳ | 実測 0(cmd_4479/4483)。監視化のみ |
| I8 | 新四つ目 3 体 parity 不一致(102+2) | ⏳ | 母集団除外で決着(殿 11:46)。残 2=2014-04 初月の root signal 不在=偵察 |

## §1 読み方
各 I について (a) 事象と証拠 (b) 本番での影響(誰が何を見るか) (c) 改善案 (d) 改善時に本番で起きる変化 (e) 影響範囲(table/file/API/UI) (f) 依存関係 (g) 検証方法 (h) 未検証事項 を書く。証拠の行番号は origin/main 0f2bfbcd。

## §2 不整合カタログ

### I1 `fof_component_weights` の未使用列(JSON 4 列を含む 8 列が全 NULL)
- (a) 事象: 24,348 行で `component_type / nested_depth / asset_value / daily_return / component_holding_signal / component_tickers` が NULL、`actual_weight` も NULL(∴ `drift` も NULL)。証拠: 09-05 readonly 実測(基盤書 §2.1)+ writer の現物: `backend/app/jobs/flush/fof_flush.py` L139-152 は `target_weight / actual_weight(None) / drift` しか values に入れない。生成側 `backend/app/jobs/recalculate_fof.py` L1270-1284 も `target_weight` と `actual_weight: None` のみ。fof_flush.py L107 に「モデルには追加カラムがあるが…」と自認コメントあり。models.py L768-781 の定義(cmd_1101)がスキーマだけ先行した。
- (b) 本番影響: **読者は 1 箇所**=`backend/app/api/portfolios.py` L597 `GET /fof-weights/{portfolio_id}`(L683-690 で nested_depth/asset_value/holding_signal/component_tickers を返す)。frontend は `frontend/lib/api-client.ts` L959-965 `getFoFWeights` にクライアント関数があるが、**それを呼ぶ画面は origin/main の frontend に 0 件**(grep getFoFWeights/fofWeights=api-client のみ、14:33 将軍確認)=死んだ API+死んだ列。**runtime 計算(monthly_return・/api/signals)への影響 0**: 計算は `target_weight` のみ使う(cmd_4480 A2: price_ratio_impl.py:1239-1250)。
- (c) 改善案: **廃止(推奨)**=8 列を DROP し API 応答から外す。代替=writer 補完(recalculate_fof で actual_weight/daily_return/component_tickers を計算して書く)は「新しい長期問題」(FoF 計算に列の維持義務が増える)を生むため非推奨。
- (d) 改善時の本番変化: DROP=migration 1 本、`GET /fof-weights` の JSON から 4 key が消える(frontend 参照があれば同時修正)。データ・リターン・シグナル表示は不変。
- (e) 影響範囲: `backend/app/db/models.py` L768-781、`backend/app/db/migrations.py`(fof_component_weights 10 箇所)、`backend/app/api/portfolios.py` L597-690、`backend/app/jobs/flush/fof_flush.py` L107 コメント、frontend(未検証)。
- (f) 依存: 独立。ただし I8 残 2 件(初月 0 行)と A8(drift 観測)は同じ表を見るので、DROP は I8 偵察の後。
- (g) 検証: 隔離 DB で migration up/down 往復、`GET /fof-weights` の契約 test、本番は readonly で NULL 率 100% を再確認してから。
- (h) 未検証: admin(別 repo/画面)の参照有無。frontend 本体は参照 0 で確定。

### I2 `signal_change_log` 同日往復の二重行
- (a) 事象: 同一 (portfolio, date) で同日に A→B と B→A の 2 行(基盤書 §2.2、09-05 実測)。証拠: 生成側 `backend/app/jobs/flush/signal_flush.py` L98-153 `_collect_signal_change_logs` は**flush バッチごと**に「DB 既存 holding_signal ≠ 今回の holding_signal」を 1 行にする。dedupe は L236-262 の「ledger drift 署名の既出判定」だけで、**同 run 内の往復や、pending fill→確定の 2 段書込(L141-143 `is_pending_fill_transition`)は抑止していない**。
- (b) 本番影響: (1) SIGNAL CHANGE ALERT(cmd_3679、recalculate_fast.py L1583-1585 の buffer→通知)が往復分だけ過剰に鳴る/鳴った(08-23 cmd_4337『SIGNAL ALERT 復旧』が同表を根拠にしている)。(2) 研究側 I3 の「PF 出現」判定と turnover 計測(A4)が二重計上される。(3) `/api/signals` 表示・monthly_return には影響 0(change_log は read されない。読者は recalculate_fast/ledger/writer_inventory のみ)。**(4) 最重要: change_log は保有履歴として再構成不能**。cmd_4479 AC3 `verify_change_log.md`(同日最後の行で前方補完し F1 月初保有と突合)で L0 12 体の一致率は 26〜79%(例: シン朱雀-鉄壁 24/92、シン青龍-常勝 94/188)。原因は設計: L131 で INSERT(初回確定・pending fill の新規行)を除外し UPDATE 差分だけ記録するため、初期状態と月初 fill が欠ける。∴ この表を「いつ何を持っていたか」の根拠に使うと誤る。ALERT 用途に限定するか、F1(cmd_4483)を履歴の正本にする。
- (c) 改善案(2 段): 段 1=**計測**: 往復ペア(同 pf・同 date・同 changed_at ±数秒・old/new が入替)の件数と、`is_pending_fill_transition` の分布を readonly で出す。段 2=**抑止**: 生成側で「同 run・同 key の最終状態が変化なし」なら行を書かない(run 単位の collector で相殺)。既存行の物理削除はしない(履歴は残し、集計側で往復ペアを除外する view を置く)。
- (d) 改善時の本番変化: 以後の run で change_log 行数が減り、ALERT 本文の件数が実変化のみになる。過去行は不変。
- (e) 影響範囲: `signal_flush.py` L98-153、`recalculate_fast.py` L1583/L2717-3073(collector 呼出 5 箇所)、`recalculate_fof.py`(1 箇所)、ALERT 文面、A4 監視。
- (f) 依存: I3 の再計上は I2 段 1 の後。ledger(I4)を復活させる場合は L236-262 の署名 dedupe と同時に見直す。
- (g) 検証: 隔離 DB で pending fill→確定の 2 段 flush を再現し行数 1 を契約 test 化。本番は段 1 の readonly 計測のみ。
- (h) 未検証: 往復の発生経路が「pending fill 2 段」か「同日 2 run(fast+fof)」か。件数と時期分布。

### I3 `signal_change_log` に現れる対象 PF が 66/78
- (a) 事象: 09-05 nonce *-ro9 で対象 78 中 66(L0 10/12・L1 17/21・L2 21/24・L3 18/21)。殿裁定 11:46 で母集団は 75(L2 21)へ。
- (b) 本番影響: 未出現 PF は「一度も holding_signal が変わったことがない」か「変化検知の前に signals 行が無かった(INSERT は L131 で除外)」のどちらか。前者なら正常、後者なら **ALERT の死角**(初回 INSERT で確定した保有は通知されない、signal_flush.py L155-166 の docstring が意図として明記)。
- (c) 改善案: 計測のみ。未出現 12 体の signals 行数・初回 date・holding_signal の distinct 数を出し、「変化なし」と「INSERT 由来」を分ける。INSERT 由来が LP/ALERT の期待と矛盾するなら A4 監視に「初回確定」イベントを追加。
- (d) 改善時の本番変化: なし(計測)。監視追加時は ALERT 種別が 1 つ増える。
- (e) 影響範囲: readonly SQL、A4(verification tables)。
- (f) 依存: I2 段 1 の後(往復ペア除外後に再計上)。母集団は cmd_4483 の universe_manifest(75)を使う。
- (g) 検証: 75 PF で `signal_change_log` distinct portfolio_id と signals の初回 date を突合。
- (h) 未検証: 未出現 12 体の内訳(9 体は 75 母集団内、3 体は除外新四つ目に含まれるかどうか)。

### I4 `signal_detail_history` 0 行 / `signal_decision_ledger` 0 行
- (a) 事象: 両表 0 行。証拠: `signal_detail_history` は models.py L942-953 に定義があるが **writer が 1 箇所も無い**(origin/main grep: migrations/models のみ)=死表。`signal_decision_ledger` は writer が `services/signal_decision_ledger.py` L580 `insert_initial_ledger_events`(初期バックフィル)と L326(訂正行)のみで、runtime の recalc は読むだけ(monthly_returns.py L248-263『ledger が空なら no-op』、monthly_trade_impl.py L35-78)。08-16 PITR rollback 以後、再バックフィル(07-07 cmd_3711 相当)が実行されていないため 0 行。
- (b) 本番影響: detail_history=0(誰も読まない)。ledger=**確定月の保護が効いていない**: 設計(cmd_3703 §4 target 2)では確定月の holding_signal は ledger の決定値を優先し再計算で上書きされないはずが、0 行なので毎 run の再計算結果がそのまま `monthly_returns.holding_signal` になる。これが I5 の一因候補。また signal_flush.py L155-166 の「ledger-covered INSERT の drift ALERT」も発火しない。
- (c) 改善案: **殿裁定 2 択**(backlog B2 中立を維持): (a) 復活=cmd_3711 と同手順で初期バックフィル(insert_initial_ledger_events)を本番へ再投入。(b) 廃止=ledger 依存(7 file+API router main.py L43/L426+models guard+PI-P06)を撤去。detail_history は裁定不要で DROP 候補。
- (d) 改善時の本番変化: (a) 復活=バックフィル直後の run から確定月の holding_signal が ledger 値に固定され、**現在の monthly_returns と差がある月があれば表示が変わる**(差の有無は I5 の計測で事前に出す)。ALERT に ledger drift 種別が復活。(b) 廃止=挙動は現状のまま、コードが減る。
- (e) 影響範囲: (a) `services/signal_decision_ledger.py`、`jobs/recalculate_fast.py`(6)、`recalculate_fof.py`(3)、`generators/monthly_returns.py`(5)、`api/signal_decision_ledger.py`、`main.py`、`monthly_trade_impl.py`、`safe_bundle_v2.py`、`portfolio_restore.py`、`writer_inventory.py`、`projects/dm-signal.yaml` PI-P06。(b) 同じ file 群の撤去。
- (f) 依存: **I5 の計測が先**(復活で何月の表示が変わるかを事前に知るため)。I2 の署名 dedupe(L236-262)は ledger 前提。
- (g) 検証: 隔離 DB(PITR clone)でバックフィル→full recalc→monthly_returns 差分 0 件/非 0 件の一覧。本番は殿 OK 後、バックアップ+revert 手順付き。
- (h) 未検証: 07-07 cmd_3711 の投入手順が現 schema で再実行可能か、08-12 T7.5(guard detect-only 化)との整合。

### I5 月初 `signals.holding_signal` ≠ `monthly_returns.holding_signal`
- (a) 事象: backlog B5 は「F1 で計測」とするが、cmd_4479 の `verify_change_log.md` は change_log 前方補完との突合(I2/I3 側)であり、**signals.holding_signal と monthly_returns.holding_signal の直接突合は未実施**(14:33 将軍確認)。v0.2 では件数を「未検証」に戻し、偵察 cmd の AC にする。生成側: monthly_returns.py L265-283 は standard のみ signals から holding_signal を取り(`require_holding_signal`)、FoF は別経路(L28 ledger 優先→展開)。
- (b) 本番影響: `/api/signals`(当日)と月次リターン表(その月の保有ラベル)で**同じ月の保有が別の名前で見える**可能性。数値(リターン)は影響しないケースと、FoF 展開の月初境界(docs/future/055 FoF MTD entry asymmetry、L240 コメント)で weight が変わるケースがある。
- (c) 改善案: まず分類: (1) pending→確定の時間差(月初は pending が確定に置換される正常差)、(2) ledger 不在で再計算が上書き(I4)、(3) FoF の月初境界差(055)。分類ごとに「正常」「I4 で解消」「055 の設計課題」に振り分け、修正は (2) のみ I4 と同時に。
- (d) 改善時の本番変化: (2) 分は I4 復活で確定月ラベルが固定される。(1)(3) は変化なし(仕様として文書化)。
- (e) 影響範囲: readonly SQL、I4 の file 群、docs/future/055。
- (f) 依存: I4 裁定の入力。cmd_4483 の F1 CSV(75 PF、origin 0f2bfbcd)を突合材料に使う。
- (g) 検証: 不一致 1 件ずつに (1)(2)(3) のラベルを付けた表を作り、ラベル別件数を出す。
- (h) 未検証: 不一致件数(cmd_4479 verify_change_log.md を再読)、分類比率。

### I6 `display_ticker_weights` 非 unit 35 行・α=0 parity 不一致 29/2,096
- (a) 事象: 08-06 partial-turnover v1.10 で棄却済み(`docs/research/partial-turnover-experiment-asis-tobe-5w1h_20260805.md` v1.10-v1.12)。根因=`backend/app/services/price_ratio_impl.py` L1237-1250: `raw_weights` を `_normalize_weights` した後、`selected_pf_ids` を weight>0 に絞るが、**絞った後に再正規化しない**(選択外 PF の weight 分だけ合計が 1 を割る)。producer=`recalculate_fof.py` L149-170 `_compute_display_ticker_weights`→`expand_portfolio_to_tickers`(同 L1045)、L1108-1192 で `momentum_data.display_ticker_weights / pending_display_ticker_weights` に格納。
- (b) 本番影響: 読者=`backend/app/api/signals.py` L90-112(`/api/signals` の FoF ticker 表示)と `backend/app/api/monthly_trade.py` L43-45(月次売買表示)。**殿・顧客が見る FoF の ticker×weight が、該当月は合計 <1 のまま表示される**(35 行)。monthly_return の計算は **同じ関数を使う**: `backend/app/jobs/generators/monthly_returns.py` L387-396 `expanded_weights_on(day)` が `expand_portfolio_to_tickers` を呼び、その返値で区間リターンを合成する(14:33 将軍確認)。∴ 非 unit 35 行の月は**表示だけでなく monthly_return も Σ<1 の weight で計算されている**(現金相当が暗黙に混ざる)。他の呼出し: api/signals.py L224/L448、trade_performance.py L651、return_calculator.py L210/L254、monthly_trade_impl.py L328、trades_impl.py L1198=同じ 1 関数に集約済み(A10 の一元化は事実上この関数の中の再正規化 1 行)。
- (c) 改善案: **殿裁定**: (a) display 側を直す=L1243-1247 の絞込み後に Σ=1 へ再正規化(1 行変更)+ 過去 signals の display 列を full recalc で再生成。(b) 正本を F1 の再帰規則(d14a4ec3 `_resolve_weights`)に一元化(A10)し、display は F1 由来の値を書く。(a) は最小変更、(b) は A10 の本体。推奨=(a) を先に、(b) は A10 で。
- (d) 改善時の本番変化: (a) 該当 35 行の月で `/api/signals`・monthly_trade の weight 表示が Σ=1 に変わる。monthly_return が同経路なら**その月のリターン数値が変わる**(要事前計測: 変わる PF-月と差の大きさ)。full recalc が必要(所要 ~480s、殿 OK のみ)。
- (e) 影響範囲: `price_ratio_impl.py` L1237-1317、`trades_impl.py` L1167、`monthly_trade_impl.py` L286(同規則の別実装 3 本=A10)、`recalculate_fof.py` L149-192/L1108-1192、`api/signals.py`、`api/monthly_trade.py`、frontend の weight 表示。
- (f) 依存: A10(展開一元化)の第 1 歩。I8 の投票比例 weight とは同じ L1237-1250 を通るため、修正は I8 の理解(cmd_4480 A2)を前提にする。
- (g) 検証: 隔離 DB で 35 行の PF-月を再計算し Σ=1 と monthly_return 差分表。F1 CSV(75 PF)との parity が 12,372→? で悪化しないこと。
- (h) 未検証: 35 行の PF-月の monthly_return が再正規化でどれだけ動くか(差の分布)。経路が同一であることは確定。

### I7 component holding_signal 欠落で展開不能な PF-月
- (a) 事象: 実測 0(cmd_4479 i7_unexpandable=0、cmd_4483 で 0 維持)。
- (b) 本番影響: 現状なし。将来 PF 追加・signals 欠落時に F1/表示が黙って落ちる可能性(黙る=Silent Fallback、PI-018 の対象)。
- (c) 改善案: 監視のみ。F1 の i7 出力を A4 の健全性チェックに 1 行追加。
- (d)(e)(f): 変化なし/verification tables/独立。
- (h) 未検証: なし。

### I8 新四つ目 3 体の parity 不一致(explained 102+unexplained 2)
- (a) 事象: cmd_4480 で 102 件=投票比例 FoF weight(`fof_component_weights.target_weight` 非 1/N ↔ F1 の 1/N)、2 件=2014-04 初月に root signal 行・fof_component_weights 0 行。殿裁定 11:46 で 3 体を母集団から除外(cmd_4483 CLEAR)。
- (b) 本番影響: 3 体の本番 monthly_return は本番規則(投票比例)で一貫しており**本番側の不整合ではない**。残 2 件は「初月は signals 生成前に monthly_returns が計算される」仮説=本番の初月処理の順序問題であれば、**新規 PF 登録直後の初月リターンが root signal 無しで計算されている**可能性(一般化すると全 FoF の初月に及ぶ)。
- (c) 改善案: 偵察 1 本: 全 FoF(66)の初月について root signal 行の有無と monthly_returns 行の有無を突合し、「signal 無し・return 有り」の件数を出す。0 でなければ初月処理順序の修正候補(recalculate_fof の初月 handling)。
- (d) 改善時の本番変化: 修正すれば該当 PF の初月 monthly_return が変わる(件数は偵察で)。
- (e) 影響範囲: `recalculate_fof.py` の初月処理、monthly_returns generator。
- (f) 依存: 独立。I1 の DROP より先。
- (h) 未検証: 一般化件数(2 件が新四つ目固有か全 FoF 共通か)。

## §3 依存関係と順序

```
I2 段 1(計測) ─┬─> I3 再計上(75 母集団)
                └─> I2 段 2(抑止、契約 test)
I5 分類 ────────> I4 殿裁定(復活/廃止) ──> I4 実施(隔離 DB→殿 OK→本番)
I8 残 2 偵察(全 FoF 初月) ──> I1 DROP(migration)
I6 殿裁定((a) 再正規化 / (b) A10 一元化) ──> (a) 1 行修正+full recalc(殿 OK) ──> A10
I7 監視 1 行(独立)
```
- 本番書込を伴うのは I4(a)・I6(a)・I1 DROP・I2 段 2 の 4 つ。全て「隔離 DB で差分表→殿 OK→バックアップ→本番→revert 手順」の順。
- 読むだけ(偵察)は I2 段 1・I3・I5・I8 の 4 本で、1 cmd にまとめて readonly launcher(nonce 付き)で走らせられる。

## §4 改善時に本番で起きる変化(要約表)

| 改善 | 変わるもの | 変わらないもの | 可逆性 |
|---|---|---|---|
| I1 DROP | `GET /fof-weights` の 4 key、schema | リターン・シグナル・表示 | migration down |
| I2 抑止 | 以後の change_log 行数、ALERT 件数 | 過去行、表示 | コード revert |
| I4 復活 | 確定月の holding_signal 固定(差がある月の表示)、ledger ALERT | pending 月 | ledger 行削除+recalc |
| I4 廃止 | コード量 | 挙動 | revert |
| I6 (a) | 35 行の月の FoF weight 表示 Σ=1、同月 monthly_return(要計測) | 他の月 | revert+full recalc |
| I8 初月修正 | 該当 FoF の初月 return(件数は偵察) | 2 ヶ月目以降 | revert+recalc |

## §5 家老レビュー往復台帳
| R | 時刻 | 指摘 | 採否 | 反映 |
|---|---|---|---|---|
| R1 | (家老待ち) | | | |

## §6 殿裁定を要する点(v0.1 時点)
1. I4: signal_decision_ledger を復活(再バックフィル)するか廃止するか。判断材料=I5 分類の結果(復活で表示が変わる月の件数)。
2. I6: display の再正規化 1 行修正を先行するか、A10 一元化まで待つか。判断材料=非 unit 35 行の月の monthly_return 影響有無(偵察)。
(I1 DROP・I2 抑止・I7 監視・I8 偵察は裁定不要、順序は §3。本番書込は全て個別に殿 OK を取る)

## 因果リンク
- ← [[dm-signal-research-data-backlog_20260905]] §B5 I1〜I8 / ← [[dm-signal-research-data-foundation-asis-tobe_20260905]] §2 / ← [[cmd_4480_shin_yotsume_parity]] / ← [[partial-turnover-experiment-asis-tobe-5w1h_20260805]] v1.10-v1.12
- origin: "[[殿指示_本番不整合深掘り_20260906_1411]] -> [[backlog_B5_I1-I8]] -> [[production-inconsistency-asis-tobe]]"
