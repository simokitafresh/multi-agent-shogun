<!-- gist-master: 4afbab67cc111ff723c342aa48412ff8 dm-signal-research-data-foundation-asis-tobe_20260905.md -->
# DM-Signal 研究データ基盤 — 「あれば便利だったもの」を先に解決する AsIs/ToBe v0.2(2026-09-05 22:05 覚醒更新: 殿 21:50『ledger は廃止しなかったか』21:51『既にあるもので』21:56『FoF 分解ツールは既にある。車輪の再発明禁止』→ weight は既に全量 DB にあり展開不要、既存ツール 7 本を棚卸し / v0.1 21:40、殿 21:22 指示、実装なし)

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

1. **ticker×weight は既に全量 DB にある。FoF 展開コードは不要(殿裁定 alias『FoF 展開不要で display_ticker_weights を使え』、v0.1 は再発明だった)。** fof(L1〜L3、66 体)は `signals.momentum_data.display_ticker_weights` が **日次全行**に存在(L1 2011-04-01〜 / L2 2012-02-29〜 / L3 2013-12-02〜、計 209,215 行、66/66 PF)。standard(L0、12 体)は `holding_signal` がもともと ticker 文字列(comma split 1/N、`blocks/equal_weight.py`)。v0.1 と前書の「2024-01 以降 2,178 件のみ」は月初行 fof 66 体の中で 2024-01 以降だけを数えた誤り。
2. **F1 `holdings_monthly` は「展開」ではなく「既存 2 列の月初 join」で作れる。** fof: 月初 `signals` 行の `display_ticker_weights` / standard: `monthly_returns.holding_signal` の split。新規の展開ロジックを 1 行も書かない。
3. **既存ツール 7 本(§2.6)がある。** 木構造=`scripts/fof_tree.py`、整合検証=`backend/scripts/verify_fof_consistency.py`、PF 構成=`scripts/check_pf_config.py`、独立 oracle=`backend/scripts/analysis/monthly_return_oracle.py::expand_weights`、本番展開=`history.py::_resolve_pf_ids_to_tickers` / `price_ratio_impl.py::expand_portfolio_to_tickers` / `trades_impl.py` `monthly_trade_impl.py` の `_expand_fof_tickers`、cmd_3768 の再帰。F1 の検算はこれらを呼ぶ。
4. **`signal_decision_ledger` は事実上廃止済み(殿 21:50 の記憶が正しい)。** 08-12 T7.5 で guard を detect-only 化(c13a56fe)・alert hot path 撤去(0e9d158d)、08-17 で frontend の依存(NEXT SIGNAL/過去月バッジ)を撤去、以後 0 行。ただし router は `app/main.py` L43/L426 に登録されたまま=正式廃止(router 撤去)が未完。F3 の既定案を「正式廃止」に変更。
5. `signal_change_log.new_ticker_weights`(267,514 行、2003〜)は変化イベントの独立記録として検算に使う。`fof_component_weights` JSON 4 列は全 NULL(死列)、`signal_detail_history` 0 行。不整合 I1〜I4 は記録のみ。

## §2 一次データ(2026-09-05 21:24〜21:26 readonly)

### §2.1 「ticker×weight」を持ち得る既存表の被覆

| 表 | 行 | PF | 期間 | ticker×weight の有無 | 判定 |
|---|---|---|---|---|---|
| `monthly_returns` | 78 PF 分 欠損 0(前書 §2.3) | 78 | 2010-04〜2026-09 | `holding_signal` 文字列のみ(fof は UUID)。weight 無し | **月次 PIT の正本**。展開が要る |
| `signals`(日次) | L1 74,167 / L2 76,184 / L3 58,864(全行) / L0 47,879 | fof 66 / standard 12 | L1 2011-04-01〜 / L2 2012-02-29〜 / L3 2013-12-02〜 / L0 2010-03-24〜 | fof: `momentum_data.display_ticker_weights` が **全行に存在(209,215/209,215、66/66 PF)**。L0: 0 行(不要。`holding_signal` が ticker 文字列) | **fof の ticker×weight 正本**。v0.1『2024-01 以降のみ』は誤り(22:00 実測 nonce *-ro8) |
| `signal_change_log` | 268,485 | 78(fof 56 / standard 22) | 2003-08-22〜2026-08-21 | `new_ticker_weights` 展開後 ticker keyed: fof 253,844 / standard 13,670。UUID keyed 0 | 変化イベント。前方補完すれば月次保有を再構成できる。**最良の検算材料** |
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
| I3 | `signal_change_log` に現れる fof 56 体 / 対象 66 体 | 10 体は変化が記録されていない(作成後に一度も変化していないか、ログ経路の抜けか。未確認) |
| I4 | `signal_detail_history` 0 行、`signal_decision_ledger` 0 行 | 「設計されたが空の表」が 2 つ。読み手が正本と誤認する |

### §2.6 既存ツール棚卸し(殿 21:56『FoF 分解は既にある。徹底的に探せ』。repo `/mnt/c/Python_app/DM-signal`)

| ツール | 種別 | 何をするか | F1 での使い方 |
|---|---|---|---|
| `scripts/fof_tree.py` | OPERATOR_TOOL readonly | FoF 入れ子の木を表示。子 type は portfolios JOIN で判定(`fof_component_weights.component_type` は乖離あり) | 対象 66 fof の木の確認・階層判定の検算 |
| `backend/scripts/verify_fof_consistency.py` | 検証 script | FoF の整合検証 | AC の検算経路として呼ぶ(中身の対象範囲は実装 cmd で確認) |
| `scripts/check_pf_config.py` | 一括確認(cmd_3378) | PF 構成を一発表示 | 対象 78 PF の config 確認 |
| `backend/scripts/analysis/monthly_return_oracle.py::expand_weights` | 独立 oracle(本番コード非依存) | ノード木→ticker weight を再帰展開(1/N 既定) | 第三の独立検算器 |
| `backend/app/api/history.py::_resolve_pf_ids_to_tickers`(L211) | 本番 API | UUID 列→ticker 表示 | 参照のみ(F1 は呼ばない。display_ticker_weights が正本) |
| `backend/app/services/price_ratio_impl.py::expand_portfolio_to_tickers`(L1045)、`trades_impl.py::_expand_fof_tickers`(L1167)、`monthly_trade_impl.py::_expand_fof_tickers`(L286) | 本番 services | 同規則の別実装 3 本 | 参照のみ。**A10: 4+1 箇所の重複は一元化候補** |
| `docs/research/cmd_3768_pf_l0_actual_selection_frequency.md` | 研究(2026-07) | monthly_returns.holding_signal から component_portfolios を再帰展開し L0 実選択頻度 | 手順の先例。F1 は display_ticker_weights を使うので再帰は不要 |

## §3 ToBe: 先に解決する 4 件(F1〜F4)と応用

### F1 `holdings_monthly` — PF × 月 × ticker × weight の標準 long table(最優先。v0.2: 展開コードなし)

- **何**: 列 `portfolio_id, layer, year_month, ticker, weight, source`(source ∈ {display_ticker_weights, holding_signal_split})。1 PF-月の weight 合計は 1.0(Cash 含む)。
- **どう作る(既存 2 列の月初 join のみ)**: fof 66 体は各月の**最初の `signals` 行**の `momentum_data.display_ticker_weights` をそのまま行に展開(JSON→long)。standard 12 体は `monthly_returns.holding_signal` を comma split して 1/N。**新規展開ロジック 0 行**。readonly launcher で読み、CSV を `analysis_runs/cmd_4479_holdings_monthly/` へ。DB には書かない(第 1 段)。
- **月初行の定義**: `signals` の当月最初の営業日行。`monthly_returns.holding_signal`(PIT)と当月最初の `signals.holding_signal` が一致することを AC で確認する(fof は UUID 列同士、standard は文字列同士)。不一致は I5 として記録。
- **検算 3 本**(二値): (a) fof 全 PF-月で display_ticker_weights 行が存在(欠損 0)し、`signals.holding_signal` が `monthly_returns.holding_signal` と一致 (b) `signal_change_log` を「同日最後の行(id 昇順)」で前方補完した月初保有との一致率を PF 別に出力(不一致は I2/I3 の解明材料、閾値なし) (c) `monthly_return_oracle.expand_weights` に `fof_tree.py` の木を与えた独立展開と、display_ticker_weights の一致(直近 24 ヶ月・66 fof、不一致 0)。
- **第 2 段(殿 go 後)**: 検算が通ったら置き場を 1 回で決める(`fof_component_weights.expanded_tickers` を埋めて I1 を生かす / 新表 / `monthly_returns` 列追加)。fullrecalculate の末尾に 1 関数。
- **応用**: 市場方向性 6 表(前書 §3)/ PF 間の保有相関・重複率 / 体系全体の集中度(HHI)/ turnover(月次 weight 変化の L1 距離)/ レジーム別の保有分布 / X 投稿「今月の体系は XLU に何割か」の数値 / LP の「78 PF がどう動いたか」の実証グラフ。

### F2 `holding_signal_expanded` — 月次正本に展開後表現を併記

- **何**: `monthly_returns` に `holding_tickers`(展開後 `{"XLU":0.25,"GLD":0.75}` JSON)を 1 列追加。fof 行が UUID のままなので毎回 config を再帰で辿っている手間を消す。
- **判断**: F1 が外部 long table として機能すれば **F2 は不要**(同じ情報)。F1 を DB 表へ昇格する第 2 段で「long table か列追加か」を 1 回だけ決める。二重に持たない。

### F3 `signal_decision_ledger` — 事実上廃止済み。正式廃止(router 撤去)で閉じる

- **事実(git/一次)**: 08-12 T7.5 `c13a56fe` guard を detect-only 化、`0e9d158d` signal change alert hot path 撤去(services 144 行削除)。08-17 設計書 dm-monthly-trade-pending-simplify で frontend の依存(NEXT SIGNAL/過去月バッジ)を撤去。08-16 PITR rollback 以後 0 行、再バックフィルなし。**残るのは `app/main.py` L43 import / L426 `include_router` と `app/api/signal_decision_ledger.py`、空表 1 つ。**
- **判断(既定案を v0.1 から変更)**: **正式廃止**=router 登録解除+API file 削除+表は残置(drop は不可逆なので第 2 段で殿判断)。F1 が PIT 保有の正本になるので「決定理由の台帳」は不要。殿 21:50『廃止しなかったっけ』と整合。

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
| A10 | **展開ロジック 5 箇所(history/price_ratio/trades/monthly_trade/oracle)の一元化**。正本は display_ticker_weights なので、展開コードは「display_ticker_weights を作る 1 箇所」以外は読取りに置換 | 規則変更時の修正が 1 箇所。研究 script が展開を再実装しなくなる | `backend/app/services/fof/` に 1 関数 |
| A9 | **portfolio_config_snapshots の差分ログ**(06-01 以降 6,150 行)から「定義変更が成績に効いたか」 | 設定変更の因果を PIT で追える | SQL のみ |

## §5 二値 AC(F1 第 1 段の実装 cmd_4479 に渡す。v0.2)

| AC | 判定 |
|---|---|
| AC1 | `holdings_monthly.csv` を fof=月初 `signals.display_ticker_weights` / standard=`monthly_returns.holding_signal` split(1/N)から作り、全 PF-月で `SUM(weight)` 1.0±1e-9。違反 0。**展開コード 0 行**(`component_portfolios` 再帰の新規実装が grep 0 件) |
| AC2 | fof 66 体の全 monthly_returns 月に display_ticker_weights 月初行が存在(欠損 0)し、月初 `signals.holding_signal` = `monthly_returns.holding_signal`。不一致は I5 として件数報告 |
| AC3 | `signal_change_log` 前方補完(同日最後の行=id 昇順)との月初一致率を PF 別に出力、不一致 PF-月を一覧(閾値なし、I2/I3 の材料) |
| AC4 | 独立検算: `monthly_return_oracle.expand_weights` × `fof_tree.py` の木で直近 24 ヶ月・66 fof を展開し display_ticker_weights と一致(不一致 0) |
| AC5 | 本番 DB 書込 0(readonly launcher 監査ログ) |
| AC6 | 実装用 test は同一 cmd 内で削除、残すのは AC1/AC2 の contract test 2 本(`test_necessity` 宣言)、FAIL 0/SKIP 0 |

## §6 殿裁定を要する点(既定案付き)

| # | 点 | 既定案 |
|---|---|---|
| D1 | F1 第 1 段(readonly script + 外部 long table)を今 cmd 起票するか | **起票する**(可逆・本番無変更・忍者 1 名) |
| D2 | 第 2 段の置き場: `fof_component_weights.expanded_tickers` を埋める / 新表 / `monthly_returns` 列追加 | 第 1 段の検算結果を見てから 1 回で決める(今は決めない) |
| D3 | F3 ledger: 正式廃止(router 撤去+API file 削除、表は残置)| **正式廃止**(v0.2。殿 21:50 と一致)。表 drop は不可逆なので第 2 段で別途 |
| D4 | §4 A1〜A9 の着手順 | A1・A2・A3 は F1 cmd の副産物として同時に(手入力 1 箇所化+版管理+カタログ)。A4〜A9 は F1 の後 |

## §7 因果リンク
- ← [[dm-signal-market-direction-breadth-exposure-asis-tobe_20260905]] §2.6/§7(不便の記録)← 殿下問 21:19『すんなり取れたか』
- → [[holdings_monthly_long_table]] → [[市場方向性6表]] / [[PF保有相関]] / [[体系集中度HHI]] / [[turnover観測]] / [[X_今月の体系_数値]]
- → [[signal_change_log_健全性]](I2/I3)→ [[fof_component_weights_死列]](I1)→ [[空表の可視化]](I4)
- origin: "[[殿下問_便利だったもの_20260905_2119]] -> [[weight列不在の誤認]] -> [[既存表走査で検算材料発見]] -> [[holdings_monthly]]"
