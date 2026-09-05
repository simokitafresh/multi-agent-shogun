<!-- gist-master: 4afbab67cc111ff723c342aa48412ff8 dm-signal-research-data-foundation-asis-tobe_20260905.md -->
# DM-Signal 研究データ基盤 — 「あれば便利だったもの」を先に解決する AsIs/ToBe v0.1(2026-09-05 21:40、殿 21:22 指示、実装なし)

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

1. **weight は DB に「無い」のではなく「取り出しにくい場所に、部分的に」ある。** `signal_change_log.new_ticker_weights` が fof/standard とも展開後 ticker→weight を 267,514 行持つ(2003-08〜2026-08-21)。ただし変化イベントのみ(前方補完が必要)、対象 fof 66 体中 56 体しか現れない、同日往復の二重行がある。∴ そのままでは正本にならないが、**検算材料としては最良**。
2. **`fof_component_weights` の JSON 3 列(`component_tickers` / `expanded_tickers` / `child_components`)は 24,348 行すべて NULL。** 書き手が埋めていない死んだ列。設計意図(日次の再帰展開保存)は本書 F1 と同じなので、F1 はこの列を「生かす」方向で設計できる。
3. **最初に作るのは F1 `holdings_monthly`(PF × 月 × ticker × weight、標準化 long table)1 表だけ。** 市場方向性の 6 表・PF 相関・集中度・turnover・X 投稿の数値・LP の実証数値がすべてここから派生する。
4. 副産物として本番の不整合 3 件(§2.5)が見つかった。修正は別 cmd、本書は記録のみ。

## §2 一次データ(2026-09-05 21:24〜21:26 readonly)

### §2.1 「ticker×weight」を持ち得る既存表の被覆

| 表 | 行 | PF | 期間 | ticker×weight の有無 | 判定 |
|---|---|---|---|---|---|
| `monthly_returns` | 78 PF 分 欠損 0(前書 §2.3) | 78 | 2010-04〜2026-09 | `holding_signal` 文字列のみ(fof は UUID)。weight 無し | **月次 PIT の正本**。展開が要る |
| `signals`(日次) | 月初行 2,178(fof 2024-01〜) | 66 fof | 2024-01〜 | `momentum_data.display_ticker_weights`(展開後)2,178/2,178 | 検算用。2023 以前は無し |
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

## §3 ToBe: 先に解決する 4 件(F1〜F4)と応用

### F1 `holdings_monthly` — PF × 月 × ticker × weight の標準 long table(最優先)

- **何**: 列 `portfolio_id, layer, year_month, ticker, weight, source`。1 PF-月の weight 合計は 1.0(Cash 含む)。
- **どう作る**: `monthly_returns.holding_signal` を前書 §2.4 の規則で展開(既存 `history.py` `_convert_pf_ids_to_ticker_display` と同じ)。readonly script 1 本、出力は CSV/Parquet を `analysis_runs/foundation/holdings_monthly/` へ。**DB には書かない(第 1 段)**。
- **検算 3 本**(二値): (a) 2024-01 以降 fof 2,178 PF-月を `display_ticker_weights` と全一致 (b) `signal_change_log` を「同日最後の行」で前方補完した月初保有と、全期間で一致率を数える(不一致は I2/I3 の解明材料) (c) standard 24 PF を `month_start_signal_input_snapshots` と突合。
- **第 2 段(殿 go 後)**: 検算が通ったら `fof_component_weights.expanded_tickers` を埋める(I1 を生かす)か、新表 `holdings_monthly` を `migrations.py` の add_if_missing 型で追加。fullrecalculate の末尾に 1 関数追加で月次更新。
- **応用**: 市場方向性 6 表(前書 §3)/ PF 間の保有相関・重複率 / 体系全体の集中度(HHI)/ turnover(月次 weight 変化の L1 距離)/ レジーム別の保有分布 / X 投稿「今月の体系は XLU に何割か」の数値 / LP の「78 PF がどう動いたか」の実証グラフ。

### F2 `holding_signal_expanded` — 月次正本に展開後表現を併記

- **何**: `monthly_returns` に `holding_tickers`(展開後 `{"XLU":0.25,"GLD":0.75}` JSON)を 1 列追加。fof 行が UUID のままなので毎回 config を再帰で辿っている手間を消す。
- **判断**: F1 が外部 long table として機能すれば **F2 は不要**(同じ情報)。F1 を DB 表へ昇格する第 2 段で「long table か列追加か」を 1 回だけ決める。二重に持たない。

### F3 `signal_decision_ledger` の復活 or 廃止判定

- **何**: 07-07 cmd_3711 でバックフィルした記録があるのに本番 0 行(08-16 PITR rollback)。API `app/api/signal_decision_ledger.py` は生きている。
- **判断**: 「空の表を正本と誤認する」害(I4)が実害。**復活(再バックフィル)か廃止(API を閉じる)かを殿が決める**。将軍案: F1 が PIT 保有の正本になるなら ledger は「決定理由」の記録に役割を絞り、再バックフィルは F1 完成後。

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
| A9 | **portfolio_config_snapshots の差分ログ**(06-01 以降 6,150 行)から「定義変更が成績に効いたか」 | 設定変更の因果を PIT で追える | SQL のみ |

## §5 二値 AC(F1 第 1 段の実装 cmd に渡す)

| AC | 判定 |
|---|---|
| AC1 | `holdings_monthly` の全 PF-月で `SUM(weight)` が 1.0±1e-9。違反 0 |
| AC2 | 2024-01 以降 fof 2,178 PF-月が `display_ticker_weights` と ticker 集合・weight とも全一致(不一致 0) |
| AC3 | `signal_change_log` 前方補完(同日最後の行)との月初一致率を PF 別に出力し、不一致 PF-月を I2/I3 の候補として一覧化(件数を報告。閾値は置かない) |
| AC4 | standard 24 PF が `month_start_signal_input_snapshots` と ticker 集合一致(不一致 0) |
| AC5 | 本番 DB への書込 0(readonly launcher の監査ログで証明) |
| AC6 | 実装用 test は同一 cmd 内で削除、残すのは AC1/AC2 の contract test 2 本のみ(`test_necessity` 宣言) |

## §6 殿裁定を要する点(既定案付き)

| # | 点 | 既定案 |
|---|---|---|
| D1 | F1 第 1 段(readonly script + 外部 long table)を今 cmd 起票するか | **起票する**(可逆・本番無変更・忍者 1 名) |
| D2 | 第 2 段の置き場: `fof_component_weights.expanded_tickers` を埋める / 新表 / `monthly_returns` 列追加 | 第 1 段の検算結果を見てから 1 回で決める(今は決めない) |
| D3 | F3 ledger: 復活 / 廃止 | F1 完成後に判断。今は API を触らない |
| D4 | §4 A1〜A9 の着手順 | A1・A2・A3 は F1 cmd の副産物として同時に(手入力 1 箇所化+版管理+カタログ)。A4〜A9 は F1 の後 |

## §7 因果リンク
- ← [[dm-signal-market-direction-breadth-exposure-asis-tobe_20260905]] §2.6/§7(不便の記録)← 殿下問 21:19『すんなり取れたか』
- → [[holdings_monthly_long_table]] → [[市場方向性6表]] / [[PF保有相関]] / [[体系集中度HHI]] / [[turnover観測]] / [[X_今月の体系_数値]]
- → [[signal_change_log_健全性]](I2/I3)→ [[fof_component_weights_死列]](I1)→ [[空表の可視化]](I4)
- origin: "[[殿下問_便利だったもの_20260905_2119]] -> [[weight列不在の誤認]] -> [[既存表走査で検算材料発見]] -> [[holdings_monthly]]"
