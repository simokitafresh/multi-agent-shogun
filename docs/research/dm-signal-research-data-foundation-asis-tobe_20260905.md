<!-- gist-master: 4afbab67cc111ff723c342aa48412ff8 dm-signal-research-data-foundation-asis-tobe_20260905.md -->
# DM-Signal 研究データ基盤 — 「あれば便利だったもの」を先に解決する AsIs/ToBe v0.4(2026-09-05 22:35 家老最終 REJECT blt_221857 の 6 点を全採用: §2.1 行/非 NULL 分離、I3 交差実測 66/78、I4 表現訂正、§2.6 棚卸し訂正(producer/standard helper/precomputed consumer 追加、fof_tree・check_pf_config は create_db_engine 直結、verify_fof_consistency は HTTP+2PF 固定)、AC 再構築(oracle 撤回、contract test を target_path 内、A2 manifest+nonce/as-of/query hash 同梱)、F3 に PI-P06 SSOT / v0.3(2026-09-05 22:25 家老レビュー途中報告 blt_221512 を一次根拠で確認→2 点訂正: display_ticker_weights 直接採用は 08-06 partial-turnover v1.10 で棄却済み(非 unit 35 行・parity 不一致 29/2,096)→F1 の正本を history.py L224-237 方式(既存)に戻す / ledger は monthly_returns generator に生きた依存あり→F3 は router 撤去では廃止にならない / v0.2(2026-09-05 22:05 覚醒更新: 殿 21:50『ledger は廃止しなかったか』21:51『既にあるもので』21:56『FoF 分解ツールは既にある。車輪の再発明禁止』→ weight は既に全量 DB にあり展開不要、既存ツール 7 本を棚卸し / v0.1 21:40、殿 21:22 指示、実装なし)

- 発端: 殿 21:19『市場方向性設計書をやるにあたって、あれば便利だったことは？ticker×weight はすんなり DB から取れたか？』→ 将軍『取れなかった。weight 列が無く、コードから復元規則を確定した』→ 殿 21:22『あれば便利なものを先に解決しないか。他にも応用できる。今後便利になりそうなアイデアもまとめて gist に』
- 上流: `docs/research/dm-signal-market-direction-breadth-exposure-asis-tobe_20260905.md`(v0.1、§2.6/§7 に不便の記録)
- 実装正本(予定): `/mnt/c/Python_app/DM-signal/backend/analysis_runs/foundation/`(readonly script)+ 既存 `app/db/migrations.py`(テーブル追加は殿 go 後)

## §0.0 前提条件と我らのスタイル

**前提**
- 対象は DM-Signal 本番 Postgres(Render)。本書の数値は 2026-09-05 21:24〜21:26 に readonly launcher で実測した一次データ。
- 「保有」= `monthly_returns.holding_signal`(PIT。リバランス月でなければ前月維持)。生シグナル `signal` ではない。
- 「展開」= FoF の component UUID を再帰で辿り最終 ticker→weight に落とすこと(規則: comma split 1/N、FoF component 1/N の積)。
- 決定権は殿。将軍は設計と一次確認まで。実装は cmd 単位で忍者。

**スタイル**
1. 既存の表・既存の展開コードを使う。新 daemon・新 API を作らない。
2. 新規の複雑さを足さない。パラメータ 0。手入力は ticker→asset class の 1 表だけ(既存設計書 §4 を参照テーブル化)。
3. まず readonly の materialize(script 1 本、出力 1 表)。効いたら DB 表へ昇格。順序を逆にしない。
4. 測れないものは書かない。未確認は「(未確認)」。
5. 歴史修正禁止。過去月は確定値から再計算、月末上書きなし。
6. 本番 DB は readonly launcher のみ。DDL/UPSERT は殿 go 後の cmd で、`migrations.py` の add_if_missing 型に従う。

## §1 結論(先に)

**v0.3 訂正(最上位。家老 blt_20260905_221512 の 2 点を将軍が一次根拠で確認)**
1. **F1 の weight 正本は `display_ticker_weights` ではなく、本番表示と同じ history.py L224-237 方式(`_resolve_pf_ids_to_tickers`: holding_signal を component へ再帰し 1/N 合算・同一 ticker 合算)。** 根拠: `docs/research/partial-turnover-experiment-asis-tobe-5w1h_20260805.md` v1.10(08-06 01:00)で FoF 4 体の display_ticker_weights に **weight 合計 非 unit 35 行、α=0 parity 不一致 29/2,096** が実測され FAIL-close、v1.11 で真因=`expand_portfolio_to_tickers()` の選択後再正規化不在、v1.12 で history.py 方式に切替え **本番 monthly_returns と 75/75 一致**。v0.2 の「展開不要」はこの既存実測を三層記憶で引かずに書いた誤り(殿裁定 alias『FoF 展開不要で display_ticker_weights を使え』は 08-06 00:05 v1.8 時点の裁定で、同日 01:00 v1.10 の実測で上書きされている。alias が古い=I6)。
2. **「展開コードを書かない」は維持する。** 既存の history.py 方式を呼ぶ(または partial-turnover が v1.12 で実装した再現コードを再利用)。自作の再帰は書かない。display_ticker_weights は「本番表示 cache」として検算列に降格し、非 unit 行・不一致行を I6 として件数報告する。
3. **`signal_decision_ledger` は「事実上廃止」ではない。** `app/jobs/generators/monthly_returns.py` L28/L252-263 が「確定月は ledger の決定値を優先、空なら no-op」で読む生きた依存。writer は `recalculate_fof.py` `signal_flush.py` 等 8 file。0 行なので今は no-op だが、router 撤去では廃止にならない。F3 は「(a) 復活=再バックフィル」か「(b) 廃止=generator/flush/restore の依存撤去 cmd」の二択で殿裁定。
4. 既存表の被覆(§2.1)、既存ツール 7 本(§2.6)、不整合 I1〜I5 は v0.2 のまま有効。

## §2 一次データ(2026-09-05 21:24〜21:26 readonly)

### §2.1 「ticker×weight」を持ち得る既存表の被覆

| 表 | 行 | PF | 期間 | ticker×weight の有無 | 判定 |
|---|---|---|---|---|---|
| `monthly_returns` | 78 PF 分 欠損 0(前書 §2.3) | 78 | 2010-04〜2026-09 | `holding_signal` 文字列のみ(fof は UUID)。weight 無し | **月次 PIT の正本**。展開が要る |
| `signals`(日次) | L1 74,167 / L2 76,184 / L3 58,864(全行) / L0 47,879 | fof 66 / standard 12 | L1 2011-04-01〜 / L2 2012-02-29〜 / L3 2013-12-02〜 / L0 2010-03-24〜 | fof: `momentum_data.display_ticker_weights` が **全行に存在(209,215/209,215、66/66 PF)**。L0: 0 行(不要。`holding_signal` が ticker 文字列) | **fof の ticker×weight 正本**。v0.1『2024-01 以降のみ』は誤り(22:00 実測 nonce *-ro8) |
| `signal_change_log` | 総行 268,485 / `new_ticker_weights` 非 NULL 267,514(全 101 PF 基準) / **対象 78 PF 基準: 258,480 行、非 NULL 258,344、PF 66/78**(22:30 nonce *-ro9: L0 10/12・L1 17/21・L2 21/24・L3 18/21) | 対象 66/78 | 2003-08-22〜2026-08-21 | 展開後 ticker keyed(UUID keyed 0) | 変化イベント。前方補完すれば月次保有を再構成できる。検算材料 |
| `fof_component_weights` | 24,348 | 77 fof | 2011-04-01〜2026-09-01(月初) | `target_weight`/`actual_weight` は component 単位。`component_tickers`/`expanded_tickers`/`child_components`/`component_holding_signal` **全 NULL(0/24,348)** | 死んだ列。F1 の受け皿候補 |
| `signal_detail_history` | **0** | 0 | — | 設計上 `holding_signal`+`composite_momentum` | 未使用 |
| `signal_decision_ledger` | **0** | 0 | — | 18 列定義済み | 07-07 バックフィル後、08-16 PITR rollback で消失(前書 §7) |
| `month_start_signal_input_snapshots` | 3,591 | standard 24 | 2003-09〜2026-09 | 入力 snapshot。fof 無し | standard の検算用 |
| `portfolio_config_snapshots` | 6,150 | 101 | 2026-06-01〜2026-09-05 | config 履歴(relative_assets, top_n, pipeline_config) | 06 月以降の PF 定義変更の追跡に使える |

### §2.2 signal_change_log の中身(fof 直近 3 行、2026-08-21)

```
秘奥義-加速R-鉄壁  old=f16fcd15… new=f37a9954…  new_ticker_weights={"XLU":0.25,"GLD":0.75}
秘奥義-抜き身-常勝 old=b1ef6669…,f37a9954… new=3307d430…,f37a9954… {"XLU":0.375,"GLD":0.625}
秘奥義-加速R-鉄壁  old=f37a9954… new=f16fcd15…  {"XLU":0.75,"GLD":0.25}
```
- 展開後 weight は 1/N の積(0.25/0.75、0.375/0.625)で、前書 §2.4 の復元規則と整合。
- **同一 PF・同一日に往復 2 行**(f16→f37、f37→f16)。再計算の再ログか、日次 signals 側の揺れの記録か(未確認)。前方補完の際は「同日最後の行」を採る規則が要る。

### §2.3 前書で見落とした点(歴史修正禁止で本書に記録)

- 前書 §2.6 は `signal_decision_ledger` と `month_start_signal_input_snapshots` だけを「使わない機構」に挙げ、`signal_change_log` と `fof_component_weights` を調べなかった。理由: 前書は「月次正本 1 表から作る」を先に決め、日次系の表を横断しなかった。**教訓: 「weight が無い」と書く前に `__tablename__` 全 44 表を JSON 列の有無で走査すべきだった**(本書 §2.1 がその走査)。
- 前書の結論(月次正本+決定的復元)は変わらない。変わるのは「検算材料が 2024-01 以降だけ」→「2003 年から `signal_change_log` で検算できる」。
- **v0.2 追記(殿 21:51/21:56 で崩れた前提 3 つ)**: (a) 前書・v0.1 が引いた関数名 `_convert_pf_ids_to_ticker_display` は実在しない(実物 `history.py` L211 `_resolve_pf_ids_to_tickers`、`price_ratio_impl.py` L1045 `expand_portfolio_to_tickers`) (b) `display_ticker_weights` は fof 全行にある(2024-01 以降だけではない)。前書 §2.5 は月初行かつ 2024-01 以降で絞って数えた (c) 「weight は DB に無い」は誤り。殿の過去裁定(semantic alias『全 PF の ticker×weight は display_ticker_weights に確定値として保存、FoF 展開不要』)を三層記憶で先に引いていれば v0.1 の F1 展開設計は書かなかった。教訓: **設計前に semantic_search で殿の過去裁定を引く。既存ツール棚卸し(§2.6)を §2 の最初に置く。**

### §2.4 対象 PF の階層判定(前書 §2.1 と同じ名前規則)

| 階層 | 規則 | 数 |
|---|---|---|
| L0 | standard かつ 名前が シン四神 系 | 12 |
| L1 | fof かつ 名前 `GSシン忍法` | 21 |
| L2 | fof かつ 名前 `奥義-` | 24 |
| L3 | fof かつ 名前 `秘奥義-` | 21 |

### §2.5 見つかった本番の不整合(記録のみ。修正は別 cmd)

| # | 事象 | 影響 |
|---|---|---|
| I1 | `fof_component_weights` JSON 4 列が 24,348 行 全 NULL | 設計意図(展開保存)が機能していない。列を生かすか落とすかの判断が要る |
| I2 | `signal_change_log` に同日往復の二重行(§2.2) | イベントを「変化回数」として数える分析(turnover)が過大になる |
| I3 | `signal_change_log` に現れる対象 PF は **66/78**(交差実測 nonce *-ro9: L0 10/12・L1 17/21・L2 21/24・L3 18/21)。v0.2 の『fof 56/66』は全 fof 77 基準の総数からの推定で誤り | 12 体は変化イベント 0(理由未確認)。前方補完検算はこの 66 体に限る |
| I4 | `signal_detail_history` 0 行、`signal_decision_ledger` 0 行 | 0 行=未使用ではない(ledger は generator/flush/restore が読む現役参照、PI-P06 で SSOT 宣言)。『空だが参照される表』を読み手が正本値ありと誤認する |
| I5 | 月初 `signals.holding_signal` と `monthly_returns.holding_signal` の不一致(件数未計測) | F1 AC で計測 |
| I6 | `display_ticker_weights` に weight 合計 非 unit 35 行・α=0 parity 不一致 29/2,096(08-06 partial-turnover v1.10 実測、真因=`expand_portfolio_to_tickers()` 選択後再正規化不在)。semantic alias『FoF 展開不要で display_ticker_weights を使え』(v1.8 00:05)が v1.10 01:00 の棄却で上書きされたまま索引に残る | display 列を正本にすると誤る。alias の訂正(A11)|

### §2.6 既存ツール棚卸し(殿 21:56『FoF 分解は既にある。徹底的に探せ』。v0.4 で家老指摘 6 件を訂正。repo `/mnt/c/Python_app/DM-signal`)

| ツール | 種別 | 何をするか | F1 での使い方 |
|---|---|---|---|
| `backend/app/api/history.py::_resolve_pf_ids_to_tickers`(L211-244) | 本番 API(表示) | component 1/N→holding_signal comma split 1/N→同一 ticker 合算 | **F1 の展開規則の正本**(partial-turnover v1.12 が 75/75 parity を実証) |
| `backend/app/services/return_calculator_pure.py::holding_signal_to_weights`(L15) | 本番 pure helper | standard の holding_signal→ticker weight(1/N) | F1 の standard 経路はこれを呼ぶ(自作 split 禁止) |
| `backend/app/jobs/recalculate_fof.py::_compute_display_ticker_weights`(L149) | 本番 producer | display_ticker_weights を生成 | 参照のみ。非 unit の根因側(price_ratio_impl L1237-1317 の再正規化不在と併せ A10) |
| `backend/app/api/signals.py::_get_precomputed_fof_display_weights`(L88)/`monthly_trade.py`(L43-45) | 本番 consumer | precomputed display 列を優先表示 | 参照のみ。display 列は検算用(I6) |
| `backend/app/services/price_ratio_impl.py::expand_portfolio_to_tickers`(L1045、L1237-1317)、`trades_impl.py::_expand_fof_tickers`(L1167)、`monthly_trade_impl.py::_expand_fof_tickers`(L286) | 本番 services | 同規則の別実装 3 本。price_ratio は selected_pf_ids 抽出後に再正規化しない(v1.11 真因) | 参照のみ。A10 一元化候補 |
| `scripts/fof_tree.py` | OPERATOR_TOOL | 最新日の component 木を表示。**`create_db_engine` 直結**(readonly launcher 経由ではない) | AC5(launcher 限定)と矛盾するため F1 では呼ばない。木は launcher SQL(`portfolios.config.component_portfolios`)で取る |
| `scripts/check_pf_config.py` | 一括確認(cmd_3378) | PF 構成表示。**`create_db_engine` 直結** | 同上。手元確認のみ |
| `backend/scripts/verify_fof_consistency.py` | 検証 script | **本番 HTTP(httpx→onrender)+PF 2 体ハードコード** | 66 体の検算器ではない。F1 では使わない |
| `backend/scripts/analysis/monthly_return_oracle.py::expand_weights`(L51) | 独立 oracle | nodes JSON→weight 再帰。**入力は自前で組む必要あり、過去月の木は与えられない** | v0.2 AC4 は接続不能のため撤回。使わない |
| `docs/research/partial-turnover-experiment-*_20260805/06.md` | 研究(08-05/06) | v1.10 で display 直接経路を FAIL-close、v1.12 で history.py 方式に切替え 75/75 parity | **F1 の先例。再現コードの流用元** |
| `docs/research/cmd_3768_pf_l0_actual_selection_frequency.md` | 研究(07) | holding_signal→component_portfolios 再帰で L0 実選択頻度 | 手順の先例 |

## §3 ToBe: 先に解決する 4 件(F1〜F4)と応用

### F1 `holdings_monthly` — PF × 月 × ticker × weight の標準 long table(最優先。v0.3: history.py 方式、自作展開なし)

- **何**: 列 `portfolio_id, layer, year_month, ticker, weight, source`(source=history_l224 固定)。1 PF-月の weight 合計は 1.0(Cash 含む)。
- **どう作る**: `monthly_returns.holding_signal`(PIT)を入力に、本番表示と同じ `backend/app/api/history.py` L224-237 の規則(component 1/N → holding_signal comma split 1/N → 同一 ticker 合算、ネストは再帰)で展開する。**実装は既存関数の再利用(standard=`holding_signal_to_weights`、FoF=history.py 規則)または partial-turnover v1.12 の再現コードの流用。新規再帰コードを書かない。** 展開に必要な component 木は launcher SQL で `portfolios.config.component_portfolios` を月ごとに取り(`portfolio_config_snapshots` は 2026-06 以降のみ)、木の版は as-of で固定して報告する。 readonly launcher で読み、CSV を `analysis_runs/cmd_4479_holdings_monthly/` へ。DB には書かない(第 1 段)。
- **検算 3 本**(二値): (a) partial-turnover v1.12 と同じ α=0 parity: holdings_monthly から再計算した月次リターンが本番 `monthly_returns.monthly_return` と一致(75/75 の先例。対象 78 PF 全月、不一致 0。component の holding_signal 欠落で展開できない PF-月は I7 として件数報告し parity 母数から除外を明示) (b) `display_ticker_weights` 月初行との突合。一致率と、非 unit 行・不一致行を **I6 として件数報告**(閾値なし。08-06 実測 35/29 の再現確認) (c) `signal_change_log` 前方補完(同日最後の行=id 昇順)との一致率 PF 別(I3 の 66 体に限る。I2 の材料)。**成果物に A2 universe manifest(対象 78 PF の id・layer・as-of)と source nonce・as-of・query hash を同梱**(家老 (6))。
- **第 2 段(殿 go 後)**: 検算が通ったら置き場を 1 回で決める(`fof_component_weights.expanded_tickers` を埋めて I1 を生かす / 新表 / `monthly_returns` 列追加)。fullrecalculate の末尾に 1 関数。
- **応用**: 市場方向性 6 表(前書 §3)/ PF 間の保有相関・重複率 / 体系全体の集中度(HHI)/ turnover / レジーム別の保有分布 / X 投稿「今月の体系は XLU に何割か」/ LP の実証グラフ。

### F2 `holding_signal_expanded` — 月次正本に展開後表現を併記

- **何**: `monthly_returns` に `holding_tickers`(展開後 `{"XLU":0.25,"GLD":0.75}` JSON)を 1 列追加。fof 行が UUID のままなので毎回 config を再帰で辿っている手間を消す。
- **判断**: F1 が外部 long table として機能すれば **F2 は不要**(同じ情報)。F1 を DB 表へ昇格する第 2 段で「long table か列追加か」を 1 回だけ決める。二重に持たない。

### F3 `signal_decision_ledger` — 依存が生きている。復活か依存撤去かの二択(v0.3)

- **事実(コード一次)**: `app/jobs/generators/monthly_returns.py` L28 import、L252-263「確定済み月は ledger の決定値を優先。空の間は no-op」、L298-301 ledger の ticker_weights を all_tickers に合流。writer/reader は `recalculate_fof.py` `recalculate_fast.py` `signal_flush.py` `safe_bundle_v2.py` `writer_inventory.py` `portfolio_restore.py` `monthly_trade_impl.py` の 7 file+API router(`main.py` L43/L426)+models の append-only guard(L197-202)+`projects/dm-signal.yaml` PI-P06 の SSOT 宣言。08-12 T7.5 は guard を detect-only 化・alert hot path 撤去(c13a56fe/0e9d158d)したが読取依存は残る。08-16 PITR rollback 以後 0 行=全経路 no-op。
- **判断**: v0.1「復活/廃止」・v0.2「正式廃止=router 撤去」はいずれも不十分。**(a) 復活**=07-07 cmd_3711 と同じ再バックフィル(ledger が generator の正本になる)/ **(b) 廃止**=generator/flush/restore/API から依存を撤去する cmd(表は残置、drop は別途)。将軍案: F1 が PIT 保有の正本になれば (b)。ただし generator の「確定月優先」ロジックは月次確定の仕組みそのものなので、撤去の影響範囲(pending 表示・確定境界)を偵察 cmd で出してから殿裁定。

### F4 階層ラベル関数 `layer_of(portfolio)` の一元化

- **何**: L0〜L3 の判定を名前規則で毎回書いている(前書 §2.1、本書 §2.4)。`backend/app/services/` に 1 関数(または `portfolios.config.layer` 1 キー)として置く。
- **応用**: 全研究 script・admin の階層フィルタ・LP の階層別表示が同じ関数を呼ぶ。名前規則が変わっても 1 箇所。

## §4 今後便利になりそうなアイデア(未着手。優先順は殿)

| # | アイデア | 何が楽になるか | 既存に乗せる先 |
|---|---|---|---|
| A1 | **ticker→asset class 参照表**を YAML 1 本で持つ(前書 §4 の 5 ticker+Cash) | 全研究で同じ分類。手入力を 1 箇所に | `backend/analysis_runs/foundation/asset_class.yaml` |
| A2 | **対象 PF 集合の版管理**(L0〜L3 78 体の id 一覧を日付付き YAML) | 「対象 78」が PF 追加で 80 になった時に過去の研究が再現できる | 同上 `pf_universe_YYYYMMDD.yaml` |
| A3 | **研究用 readonly view カタログ** 1 ページ(表名・行数・期間・JSON 列の中身・正本/検算/死亡の区分) | 次の設計書で §2 走査を繰り返さない。本書 §2.1 がその第 1 版 | `context/dm-signal-research.md` から参照 |
| A4 | **signal_change_log の健全性チェック**(同日往復 I2、未出現 fof I3)を fullrecalculate 後の verification に 1 本 | turnover 分析の前提が壊れたら即わかる | 既存 `verification tables v076` 系 |
| A5 | **空表の可視化**(0 行の表を admin/debug に一覧) | I4 の誤認を構造で防ぐ | `app/api/debug.py` |
| A6 | **月次 PIT スナップショットの 1 行サマリ**(その月の体系全体 weight 合計・Breadth 上位・Cash 率)を `monthly_returns` 更新時に 1 行 log | X 投稿・Live OOS の「今月の体系」を人手で集計しない | F1 の第 2 段 |
| A7 | **PF 相関行列の月次 materialize**(F1 から weight ベクトルの cos 類似) | 「奥義と秘奥義はどれだけ同じ賭けをしているか」を一発で | F1 派生 |
| A8 | **fof_component_weights の `actual_weight`/`drift` を使ったリバランス乖離の観測** | 既に 24,348 行ある未活用の数値列 | 追加コード無し、SQL のみ |
| A11 | **semantic alias の時系列訂正**: 『FoF 展開不要で display_ticker_weights を使え』(08-06 v1.8)に『→ v1.10 で棄却、history.py 方式が正』を併記 | 三層記憶が古い裁定を最新として返す事故(本書 v0.2)の再発防止 | `context/semantic-map.md` dmsignal_operations |
| A10 | **展開ロジック 5 箇所(history/price_ratio/trades/monthly_trade/oracle)の一元化**。正本は display_ticker_weights なので、展開コードは「display_ticker_weights を作る 1 箇所」以外は読取りに置換 | 規則変更時の修正が 1 箇所。研究 script が展開を再実装しなくなる | `backend/app/services/fof/` に 1 関数 |
| A9 | **portfolio_config_snapshots の差分ログ**(06-01 以降 6,150 行)から「定義変更が成績に効いたか」 | 設定変更の因果を PIT で追える | SQL のみ |

## §5 二値 AC(F1 第 1 段の実装 cmd_4479 に渡す。v0.4)

| AC | 判定 |
|---|---|
| AC1 | `holdings_monthly.csv` を history.py L224-237 規則(standard=`holding_signal_to_weights` 再利用、FoF=既存規則/partial-turnover v1.12 再現コード流用、新規再帰 0 行、流用元 path を報告)で作り、展開できた全 PF-月で `SUM(weight)` 1.0±1e-9 違反 0。展開不能 PF-月(component holding_signal 欠落)は I7 として件数報告 |
| AC2 | α=0 parity: holdings_monthly から再計算した月次リターンが `monthly_returns.monthly_return` と展開できた全 PF-月で一致(不一致 0。v1.12 の 75/75 と同手順) |
| AC3 | `display_ticker_weights` 月初行との突合: 一致率 PF 別+非 unit 行数+不一致行数を I6 として報告(閾値なし) |
| AC4 | `signal_change_log` 前方補完(同日最後の行=id 昇順)との一致率 PF 別(I3 の 66 体)、不一致 PF-月一覧 |
| AC5 | 本番 DB 書込 0(readonly launcher 監査ログ)。`create_db_engine` 直結 script(fof_tree/check_pf_config)は使わない |
| AC6 | 成果物に universe manifest(A2: 78 PF id・layer・as-of)と source nonce・as-of・query hash を同梱 |
| AC7 | contract test 2 本(AC1 sum=1 / AC2 parity)を `analysis_runs/cmd_4479_holdings_monthly/tests/` に置き(target_path 内)、`test_necessity` 宣言、選択実行 FAIL 0/SKIP 0。実装用 test は同一 cmd 内で削除 |

## §6 殿裁定を要する点(既定案付き)

| # | 点 | 既定案 |
|---|---|---|
| D1 | F1 第 1 段(readonly script + 外部 long table)を今 cmd 起票するか | **起票する**(可逆・本番無変更・忍者 1 名) |
| D2 | 第 2 段の置き場: `fof_component_weights.expanded_tickers` を埋める / 新表 / `monthly_returns` 列追加 | 第 1 段の検算結果を見てから 1 回で決める(今は決めない) |
| D3 | F3 ledger: (a) 復活=再バックフィル / (b) 廃止=generator/flush/restore/API の依存撤去 cmd | **(b) 方向だが、先に依存撤去の影響範囲 偵察 cmd 1 本**(v0.3。router 撤去だけでは廃止にならない) |
| D4 | §4 A1〜A9 の着手順 | A1・A2・A3 は F1 cmd の副産物として同時に(手入力 1 箇所化+版管理+カタログ)。A4〜A9 は F1 の後 |

## §7 因果リンク
- ← [[dm-signal-market-direction-breadth-exposure-asis-tobe_20260905]] §2.6/§7(不便の記録)← 殿下問 21:19『すんなり取れたか』
- → [[holdings_monthly_long_table]] → [[市場方向性6表]] / [[PF保有相関]] / [[体系集中度HHI]] / [[turnover観測]] / [[X_今月の体系_数値]]
- → [[signal_change_log_健全性]](I2/I3)→ [[fof_component_weights_死列]](I1)→ [[空表の可視化]](I4)
- origin: "[[殿下問_便利だったもの_20260905_2119]] -> [[weight列不在の誤認]] -> [[既存表走査で検算材料発見]] -> [[holdings_monthly]]"
