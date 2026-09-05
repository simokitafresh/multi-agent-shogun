<!-- gist-master: 4afbab67cc111ff723c342aa48412ff8 dm-signal-research-data-foundation-asis-tobe_20260905.md -->
# DM-Signal 研究データ基盤 F1 `holdings_monthly` — PF × 月 × ticker × weight を 1 表に固める 設計書 v0.5(2026-09-05 22:55 家老 R2 REJECT blt_223658 7 点を全採用: F1 だけに絞り F2〜F4/A1〜A11/I 一覧を `dm-signal-research-data-backlog_20260905.md` へ移設、流用元を full SHA+path+関数に一本化、展開辺を記録済み holding_signal の同月再帰に定義、semantic alias 正本訂正 / v0.4 22:35 家老 REJECT 6 点採用 / v0.3 22:25 / v0.2 22:05 / v0.1 21:40 殿 21:22『便利なものを先に解決』)

- 発端: 殿 21:19『ticker×weight はすんなり DB から取れたか』→取れなかった → 21:22『先に解決しないか。他にも応用できる』→ 22:29『シンプルにデータを見たいだけ。複雑さは捨てろ』。
- 本書の範囲: **F1 `holdings_monthly.csv` の生成・検算・provenance だけ。** それ以外(ledger の扱い、階層関数、アイデア、本番不整合一覧)は `docs/research/dm-signal-research-data-backlog_20260905.md` に移した(記録のみ、実装しない)。
- 消費者: `dm-signal-market-direction-breadth-exposure-asis-tobe_20260905.md` v1.1(1 表 layer_holdings_monthly)。

## §0.0 前提とスタイル

- 対象は DM-Signal 本番 Postgres(Render)。数値は 2026-09-05 21:24〜22:30 に readonly launcher で実測(nonce *-ro1〜ro9)。
- 保有 = `monthly_returns.holding_signal`(PIT。リバランス月でなければ前月維持)。生シグナルではない。
- 展開 = **その月の記録済み holding_signal を辿る再帰**(fof の UUID → その component の同月 holding_signal → … → ticker)。1 段ごとに 1/N、同一 ticker は合算。展開辺は記録済み holding_signal と `portfolios.config.type` だけで決まり、**現在の config tree を過去月へ当てない**(家老 R2-2。`portfolio_config_snapshots` は 2026-06 以降しか無く、PIT を証明できない)。config は対象 78 PF の選定と type 判定にだけ使う。
- 本番に触るのは殿が明示的に OK を出した時だけ(殿 22:27)。本書は readonly、DDL/UPSERT なし。第 2 段(DB 昇格)は本書の範囲外。
- 設計書が家老・軍師の APPROVE に到達するまで往復し、慌てて実装しない(殿 22:25)。cmd_4479 は draft のまま。
- 既存コードを使う。新規の再帰は書かない。パラメータ 0。測れないものは書かない。歴史修正禁止。

## §1 結論(先に)

1. **weight は DB に列として無い。** `monthly_returns.holding_signal` は文字列(standard は ticker のカンマ連結、fof は component UUID)。
2. **正しい展開規則は「同月 holding_signal の再帰+1/N 合算」で、その実体は DM-Signal commit `d14a4ec3ce8457ce17ef702079028dbb9c58a367` の `scripts/analysis/partial_turnover_phase0_lagged.py::_resolve_weights`。** 08-06 cmd_partial_turnover_phase1 で 75 PF・α=0 parity 75/75 を実証。rollback 233c2303 で現 HEAD から消えているため、この blob を復元して使う(意味差分 0 を AC)。現 HEAD の `history.py::_resolve_pf_ids_to_tickers` は 1 段のみで L2/L3 に使えない。
3. **`display_ticker_weights` は正本にしない。** 08-06 v1.10 で weight 合計 非 unit 35 行・parity 不一致 29/2,096(max 差 0.1713575056)が実測され棄却済み。真因は `price_ratio_impl.py` L1237-1317 の選択後再正規化不在で現 HEAD にも残る。検算列(I6)として突合だけする。
4. **F1 の成果物は 3 つ**: `holdings_monthly.csv`、検算 3 本の md、provenance(universe manifest+全 SQL の nonce/as-of/query hash)。DB には書かない。

## §2 一次データ

### §2.1 「ticker×weight」を持ち得る既存表の被覆

| 表 | 行 | PF | 期間 | ticker×weight の有無 | 判定 |
|---|---|---|---|---|---|
| `monthly_returns` | 78 PF 分 欠損 0(前書 §2.3) | 78 | 2010-04〜2026-09 | `holding_signal` 文字列のみ(fof は UUID)。weight 無し | **月次 PIT の正本**。展開が要る |
| `signals`(日次) | L1 74,167 / L2 76,184 / L3 58,864(全行) / L0 47,879 | fof 66 / standard 12 | L1 2011-04-01〜 / L2 2012-02-29〜 / L3 2013-12-02〜 / L0 2010-03-24〜 | fof: `momentum_data.display_ticker_weights` が **全行に存在(209,215/209,215、66/66 PF)**。L0: 0 行(不要。`holding_signal` が ticker 文字列) | 検算用(I6: 非 unit 35 行・parity 不一致 29/2,096 の既知反証)。正本ではない。v0.1『2024-01 以降のみ』は被覆の誤認(22:00 実測 nonce *-ro8) |
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

### §2.3 v0.1〜v0.4 の誤りと教訓(歴史修正禁止で残す)

- v0.1/前書: 関数名 `_convert_pf_ids_to_ticker_display` は実在しない。
- v0.2: 『weight は display_ticker_weights に全量ある、展開不要』= 08-06 v1.10 の既存反証(I6)を三層記憶で引かずに、古い semantic alias(08-06 v1.8)を最新と誤認。alias は v0.5 で `context/semantic-map.md` を正本訂正(『→ v1.10 で棄却、正=d14a4ec3 _resolve_weights』を併記)。
- v0.3/v0.4: 『history.py 方式=再帰』は事実誤認(1 段のみ)。真の再帰は d14a4ec3 の `_resolve_weights`。『config を月ごとに取り as-of 固定』は 2010〜2026 の PIT を証明できない(snapshots は 2026-06〜)。
- 教訓: 設計前に (1) semantic_search で殿の過去裁定を引き、(2) その裁定の**後**に実測で覆されていないかを同日以降の研究 md(partial-turnover v1.x)で確認し、(3) 既存ツールは「存在」でなく「現 HEAD にあるか・接続経路・対象範囲」まで確認する。

### §2.4 対象 PF の階層判定(前書 §2.1 と同じ名前規則)

| 階層 | 規則 | 数 |
|---|---|---|
| L0 | standard かつ 名前が シン四神 系 | 12 |
| L1 | fof かつ 名前 `GSシン忍法` | 21 |
| L2 | fof かつ 名前 `奥義-` | 24 |
| L3 | fof かつ 名前 `秘奥義-` | 21 |

### §2.6 既存ツール棚卸し(殿 21:56『FoF 分解は既にある。徹底的に探せ』。v0.4 家老 6 件訂正+v0.5 R2-1 流用元一本化。repo `/mnt/c/Python_app/DM-signal`)

| ツール | 種別 | 何をするか | F1 での使い方 |
|---|---|---|---|
| `backend/app/api/history.py::_resolve_pf_ids_to_tickers`(L211-244) | 本番 API(表示) | component 1/N→holding_signal comma split 1/N→同一 ticker 合算。**再帰せず 1 段のみ**(家老 R2-1。L2/L3 では子 FoF の UUID を ticker 扱いする) | 規則の出自として参照のみ。F1 の流用元ではない |
| **DM-Signal commit `d14a4ec3ce8457ce17ef702079028dbb9c58a367` `scripts/analysis/partial_turnover_phase0_lagged.py::_resolve_weights`(L388〜)** | 研究 script(08-06 cmd_partial_turnover_phase1、75 PF) | 同月 holding_signal の component UUID を再帰し 1/N 合算(memo・cycle 検出・Cash/DTB3 終端・非 UUID 検出付き)。**75/75 α=0 parity を出した実体。rollback 233c2303 で現 HEAD から削除済み** | **F1 の唯一の流用元**。この blob を復元し意味差分 0 を AC 化 |
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

## §3 F1 `holdings_monthly` の設計

### §3.1 出力
- `analysis_runs/cmd_4479_holdings_monthly/holdings_monthly.csv`: 列 `portfolio_id, layer, year_month, ticker, weight, monthly_return`。1 PF-月の Σweight=1.0(Cash 含む)。`monthly_return` は `monthly_returns.monthly_return` をそのまま同梱(消費者 v1.1 は使わないが parity 検算 AC2 の入力)。
- `universe_manifest.yaml`: 対象 78 PF の id・name・layer・type、as-of(実行時刻)、`is_mtd` 判定に使う as-of 月。
- `provenance.yaml`: 実行した全 SQL の readonly launcher nonce・as-of・query sha256、流用 blob の sha256(`git show d14a4ec3:scripts/analysis/partial_turnover_phase0_lagged.py | sha256sum` = `5a556df615be3c32204136fb5439b1a33320d49b68bb569587531c9a0d493487`、2026-09-05 22:40 将軍実測)。

### §3.2 入力と展開
- 入力 SQL(全て readonly launcher): (a) 対象 78 PF(`portfolios` name 規則+type) (b) `monthly_returns(portfolio_id, year_month, holding_signal, monthly_return)` 対象 78 PF+**component として現れる全 PF**(再帰に必要。対象外の component も holding_signal だけ読む) (c) `portfolios.config->>'type'` 全 PF。
- 展開: `_resolve_weights` を復元して呼ぶ。standard=`return_calculator_pure.holding_signal_to_weights`(現 HEAD、1/N)と同値であることを 1 回確認。fof=同月 component holding_signal を再帰。Cash/DTB3 終端、非 UUID 検出、cycle 検出は blob のまま。
- 展開不能(component の同月 holding_signal 欠落)は行を出さず I7 として PF-月を列挙する。

### §3.3 検算 3 本(全て閾値なし・件数報告)
- (a) **α=0 parity**: holdings_monthly の weight と `ticker_daily_returns` から月次リターンを再計算し `monthly_returns.monthly_return` と突合。展開できた全 PF-月で不一致 0(v1.12 の 75/75 と同手順)。
- (b) **display_ticker_weights 突合(I6)**: fof 66 体の月初 `signals` 行と突合し、PF 別一致率・非 unit 行数・不一致行数。
- (c) **signal_change_log 前方補完(I2/I3)**: 対象 66 体(L0 10/L1 17/L2 21/L3 18)について同日最後の行(id 昇順)で前方補完した月初保有との一致率と不一致 PF-月一覧。

## §4 二値 AC(cmd_4479 に渡す。v0.5)

| AC | 判定 |
|---|---|
| AC1 | 復元した `_resolve_weights` が `git show d14a4ec3:scripts/analysis/partial_turnover_phase0_lagged.py` の当該関数群(`_holding_tokens`/`_standard_weights`/`_resolve_weights`)と意味差分 0(AST 比較または unified diff が import/型注釈以外 0 行)。新規再帰コード 0 行 |
| AC2 | `holdings_monthly.csv` の全 PF-月で Σweight=1.0±1e-9 違反 0。展開不能 PF-月は I7 として件数と一覧を報告 |
| AC3 | α=0 parity: 再計算月次リターンが `monthly_returns.monthly_return` と展開できた全 PF-月で一致(不一致 0) |
| AC4 | display_ticker_weights 突合の PF 別一致率・非 unit 行数・不一致行数を I6 として報告 |
| AC5 | signal_change_log 前方補完との一致率 PF 別・不一致 PF-月一覧を報告 |
| AC6 | 本番 DB 書込 0(readonly launcher 監査ログ)。`create_db_engine` 直結 script 不使用 |
| AC7 | `universe_manifest.yaml`(12/21/24/21=78、as-of)と `provenance.yaml`(全 SQL nonce・as-of・query hash、流用 blob sha256)を同梱 |
| AC8 | contract test は AC2(Σweight=1)と AC3(parity)の 2 本を `analysis_runs/cmd_4479_holdings_monthly/tests/` に置く(`test_necessity` 宣言)。選択実行 FAIL 0/SKIP 0。実装用 test は同一 cmd 内で削除 |

## §5 殿裁定を要する点

| # | 点 | 既定案 |
|---|---|---|
| D1 | F1(readonly script+CSV、本番無変更)の cmd_4479 を、家老・軍師 APPROVE 後に delegate してよいか | APPROVE 後に殿へ 1 報し、殿の go で delegate(殿 22:25/22:27) |

## §6 因果リンク
- ← [[殿下問_便利だったもの_20260905_2119]] / ← [[partial-turnover-experiment-asis-tobe-5w1h_20260805]] v1.10-v1.12(既存反証と真の再帰)
- → [[holdings_monthly_long_table]] → [[dm-signal-market-direction-breadth-exposure-asis-tobe_20260905]] v1.1 1 表
- → [[dm-signal-research-data-backlog_20260905]](F2〜F4・A1〜A11・I1〜I7)
- origin: "[[殿下問_便利だったもの_20260905_2119]] -> [[display直接採用の既存反証を三層記憶で引かず_v0.2]] -> [[家老REJECT2往復で流用元をd14a4ec3に一本化]] -> [[holdings_monthly_F1のみ]]"
