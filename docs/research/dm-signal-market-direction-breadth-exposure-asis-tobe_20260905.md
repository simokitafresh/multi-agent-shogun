<!-- gist-master: e2219c69d927f32dc84d53e3e7daa97d dm-signal-market-direction-breadth-exposure-asis-tobe_20260905.md -->
# DM-Signal 体系全体の市場方向性を PIT で観測する実験 — AsIs/ToBe 設計書 v0.2(2026-09-05 21:40: §2.6 に signal_change_log/fof_component_weights の実測を追記、基盤設計書へリンク / v0.1(2026-09-05 20:10、殿指示 19:32。実装なし・設計のみ)

> 殿指示 2026-09-05 19:32。「全 PF の当月 ticker × weight から DM-Signal 全体の市場方向性を可視化する実験」。対象は L0 GS・真・四神 / L1 忍法 / L2 奥義 / L3 秘奥義のみ。目的は新しい売買シグナルを作ることではなく、体系全体が今月どちらを向いているかを PIT で観測・時系列化すること。既存 DB・PF 定義・ticker/weight 生成ロジックを実確認して書く。最適化や新しい恣意的パラメータは導入しない。
> 本書の数値は 2026-09-05 19:5x〜20:0x に本番 PostgreSQL を `/db-check` readonly launcher で読んだ一次値。推測箇所は「(未確認)」と明記。

## §0.0 前提条件と我らのスタイル(他の LLM・人がこの設計書を読む前に。殿指示 2026-09-05 13:21)

**この設計書を読む者への前提**
- 対象: DM-Signal(本番 Postgres on Render、backend FastAPI、repo `/mnt/c/Python_app/DM-signal`)。全 PF は月次リバランス(`rebalance_trigger: monthly` 固定、cmd_190 裁定)。standard PF は ticker を直接保有、fof PF は component PF(UUID)を top_n=1 で選ぶ入れ子。
- 「L0〜L3」は本書では**体系の階層**(L0=シン四神 standard、L1=GSシン忍法 fof、L2=奥義 fof、L3=秘奥義 fof)。`context/dm-signal-ops.md` の ETL cron の L0〜L3(同期レイヤー)とは別物なので混同しない。
- 「PIT(Point In Time)」= その月に**実際に適用されていた保有**。生シグナル(`signal`)ではなく、リバランス月でなければ前月を維持する `holding_signal` を使う(`context/dm-signal-core.md` L020/誤解 7)。
- 目的: 観測と時系列化。売買判断・スコアリング・閾値・新指標の導出はしない。
- 決定権: 殿。将軍(筆者)は設計と一次確認まで。実装は殿の go の後に忍者が cmd 単位で行う。

**我らのスタイル(この設計書が守る原則)**
1. シンプルに解決する。既存の月次正本 1 表(`monthly_returns`)と既存の展開規則(FoF 1/N・comma split 1/N)だけで作る。新テーブル・新 API・新 daemon を作らない。
2. 既存のコードがあればそれを使う。FoF→ticker 展開は `backend/app/api/history.py` `_convert_pf_ids_to_ticker_display` と cmd_3768 の再帰展開と同じ規則。
3. 新規の複雑さを足さない。パラメータは 0(閾値・lookback・重み調整なし)。唯一の手入力は「ticker→asset class」の対応表で、それは §4 に全量を明記する。
4. 最小変更→実験→データを見て次を決める。読み取り専用 SQL + 1 本の集計 script(analysis_runs 配下、本番書込なし)。
5. 測れないものは書かない。未確認は「(未確認)」。
6. 歴史修正禁止。過去月の値は `monthly_returns` の確定値から再計算し、月末に上書きしない(2026-09 は MTD と明記)。
7. 壊さない。本番 DB は readonly launcher のみ、UPSERT/DELETE なし。

## §1 結論(先に)

- **既存データで全て賄える。** 78 PF(L0 12 / L1 21 / L2 24 / L3 21)の月次 PIT 保有は `monthly_returns.holding_signal` に 2010-04〜2026-09 まで欠損 0 で入っている(§2.3)。weight 列は存在しないが、体系の規則が「EqualWeight 1/N」なので、保有文字列から決定的に復元できる(§2.4)。
- 観測する 6 表(§3)は全て「PF × 月 × ticker × weight」の 1 つの long table から派生する。派生に判断は入らない。
- **保有 ticker の宇宙は 5 つだけ**(XLU, TQQQ, GLD, TMV, TECL、および TECL+TQQQ の 2 銘柄同時)。asset class は Equity(leveraged)/Equity(defensive)/Gold/Bond(inverse)/Cash の 5 区分で、対応表は §4 に固定する。
- 除外する既存機構: `signal_decision_ledger`(本番 0 行、§2.6)、`month_start_signal_input_snapshots`(standard 24 PF のみ)。使わない理由を §2.6 に記す。

## §2 一次データ(2026-09-05 本番 readonly)

### §2.1 対象 PF の確定(名前規則で機械的に決まる)
| 階層 | 名前規則(`portfolios.name`) | type | 件数 | 例 |
|---|---|---|---|---|
| L0 | `シン{四神}-{モード}`(`GSシン` を除く) | standard | 12 | シン青龍-激攻 |
| L1 | `GSシン{忍法}-{モード}` | fof | 21 | GSシン加速D-激攻 |
| L2 | `奥義-GS-{忍法}-{モード}` | fof | 24(新四つ目を含む 8 忍法 × 3) | 奥義-GS-加速D-激攻 |
| L3 | `秘奥義-{忍法}-{モード}` | fof | 21 | 秘奥義-加速D-激攻 |
| 除外 | 上記以外の 23(DM2〜DM7+、Basic-DualMomentum、Ave-X/裏Ave-X、MIX、劇薬、CAGR4/greedy2/Sharpe4、New Fund of Funds 系) | — | 23 | — |
- 全 `is_active=true` は 101 体(fof 77、standard 24)。対象 78 体。殿指示の「GS・真・四神」は DB 名では `シン{四神}` の 12 体に当たる(GS で選抜された真=シン四神。名前に GS は付かない)。
- 入れ子の実例: 秘奥義-加速D-激攻 → 奥義-GS-{加速D,加速R,抜き身,追い風}-激攻 → GSシン{…} → シン{四神}-{モード}。各段 `component_portfolios` は 4 体、`top_n: 1`、terminal `EqualWeight`。

### §2.2 保有の記録方法(コードで確認)
- standard の `signal` は選ばれた ticker を `,` で連結した文字列、無ければ `Cash`(`backend/app/services/pipeline/executor.py` L356、`blocks/equal_weight.py` L49)。
- 複数 ticker の weight は等分(executor L358-364: `weights = {t: 1/len(tickers)}`)。threshold_band(50% 選択 + 50% safe haven)を使う PF は**対象 78 体に 0 件**(config に `threshold_band` 無し)。
- fof の `signal`/`holding_signal` は選ばれた component PF の UUID(top_n=1)。ticker 展開は `history.py` `_convert_pf_ids_to_ticker_display`: 選ばれた PF を 1/N、その PF の保有 ticker をさらに 1/N。
- `holding_signal` = リバランス月でなければ前月維持(core.md L265)。2024-01 以降の L0 月初行 396 のうち 88(22%)で `signal ≠ holding_signal`。**PIT には holding_signal を使う**。

### §2.3 月次正本 `monthly_returns` の被覆
| 階層 | 行数 | PF 数 | 最初の月 | 最後の月 | holding_signal 欠損 |
|---|---|---|---|---|---|
| L0 | 2,284 | 12 | 2010-04 | 2026-09 | 0 |
| L1 | 3,572 | 21 | 2011-04 | 2026-09 | 0 |
| L2 | 3,674 | 24 | 2012-02 | 2026-09 | 0 |
| L3 | 2,842 | 21 | 2013-12 | 2026-09 | 0 |
- 列: `portfolio_id, year_month, cumulative_return, cumulative_return_open, monthly_return, monthly_return_open, benchmark_*, in_market, holding_signal`。
- 例(2026-09、MTD): シン青龍-激攻=`XLU`、GSシン加速D-激攻=`a3c4e3d3…`(=シン朱雀-常勝 等 4 体のうち 1 体)、秘奥義-加速D-激攻=`81bfb403…`。
- 全階層が揃うのは **2013-12 以降**(L3 の開始月)。それ以前は「揃っている階層のみ」で表を作り、欠けを明示する。

### §2.4 ticker 宇宙と weight の決定性
- L0 config の ticker: relative=`TQQQ,TECL` / `XLU` / `TECL,TQQQ`、absolute=`LQD`/`SPXL`/`TMF`/`^VIX`、safe_haven=`XLU`/`TQQQ`/`TMV`/`GLD`、risk_free=`DTB3`。absolute/risk_free は判定用で保有されない。
- L0 全履歴の `holding_signal` 実績: `XLU` 13,710 / `TQQQ` 9,645 / `GLD` 7,174 / `TMV` 5,775 / `TECL` 5,692 / `TECL,TQQQ` 5,661 / NULL 222(日次 signals 表、2003〜)。**保有され得るのは 5 ticker + 2 銘柄同時の 1 組**。`Cash` は L0 実績に無い(safe haven が常に資産)。
- L3 の展開後 ticker(2024-01 以降、`display_ticker_weights` の key)も同じ 5 つ(XLU 9,785 / GLD 7,406 / TECL 7,265 / TQQQ 6,410 / TMV 3,362)。
- ∴ weight は「comma split → 1/N」「FoF → component 1/N の積」で決定的に復元でき、恣意的パラメータは不要。

### §2.5 日次 `signals` 側の補助情報(検算用)
- fof の月初行の `momentum_data` に `display_ticker_weights`(展開後 ticker→weight)と `weights`(component UUID→weight)が入る。2024-01 以降の対象 fof 66 体 × 33 ヶ月=2,178 PF-月で **2,178 全件に存在**。§3 の展開結果はこれと突合して検算する(§6 AC)。
- 月初行の日付は月の第 1 営業日(2024 以降 33 ヶ月中 14 ヶ月は 1 日でない)。`monthly_returns.year_month` を主キーにすれば暦のずれを扱わずに済む。

### §2.6 使わない既存機構と理由
| 機構 | 状態 | 理由 |
|---|---|---|
| `signal_decision_ledger` | 本番 **0 行**(列は 18 個定義済み) | 2026-07-07 cmd_3711 でバックフィルした記録があるが、08-16 の DB PITR rollback 以後は空。正本にできない。空である事実は別件として記録に残す(§7) |
| `month_start_signal_input_snapshots` | 3,591 行、standard 24 PF のみ、2003-09〜2026-09 | fof を含まないので体系全体には使えない。standard の検算に使える |
| `signal_change_log` | 268,485 行、fof 56/standard 22、2003-08〜2026-08-21、`new_ticker_weights` は展開後 ticker keyed 267,514 行 | **v0.2 追記(21:26 実測)**: 変化イベントのみ・同日往復 2 行・fof 66 中 56 のため正本にしないが、2003 年からの検算材料になる(v0.1 は未走査=見落とし)。詳細 `dm-signal-research-data-foundation-asis-tobe_20260905.md` §2 |
| `fof_component_weights` | 24,348 行、77 fof、月初 2011-04〜2026-09 | **v0.2 追記**: JSON 4 列(`expanded_tickers` 等)が全 NULL。展開保存の設計意図はあるが機能していない(同上 I1) |
| 日次 `signals` 全走査 | fof 242,659 行 + standard 99,790 行 | 月次正本があるので不要。§2.5 の検算にのみ使う |

## §3 ToBe: 観測する 6 表(全て 1 つの long table から派生)

### §3.0 基礎 long table `exposure_long`(PF × 月 × ticker × weight)
1. `monthly_returns` から対象 78 PF の (`portfolio_id`, `year_month`, `holding_signal`) を読む。
2. standard: `holding_signal` を `,` で split、各 ticker weight = 1/N。
3. fof: `holding_signal`(UUID)の component について同じ `year_month` の行を再帰的に解き、weight を 1/N の積で配る(top_n=1 なので実質 1 本の経路、`display_ticker_weights` と同値)。参照先の行が無い月は「未展開」として件数を記録し、値を捏造しない。
4. 出力列: `year_month, tier, portfolio_id, portfolio_name, ticker, weight, depth`。1 PF-月の weight 合計は 1.0(検算)。

### §3.1 ticker 別 Breadth(保有 PF 率)
- `breadth[ym, ticker] = 保有 PF 数 / 対象 PF 数`(weight > 0 の PF を 1 と数える)。階層別 `breadth_tier[ym, tier, ticker]` も同じ式。
### §3.2 ticker 別 Aggregate Exposure
- `exposure[ym, ticker] = Σ weight / 対象 PF 数`(= 全 PF 等額保有時の当該 ticker 比率)。階層別も同式。
### §3.3 階層別 Breadth・Exposure
- §3.1/§3.2 を tier で群化。4 階層 × 5 ticker × 月。
### §3.4 asset class 集約
- §4 の対応表で ticker → class に写し、`exposure_class[ym, class] = Σ exposure`。class は Equity(leveraged) / Equity(defensive) / Gold / Bond(inverse) / Cash の 5 つ。
### §3.5 前月からの変化
- `Δexposure[ym, ticker] = exposure[ym] − exposure[ym−1]`、`Δbreadth` 同様。切替 PF 数 `switches[ym] = holding_signal が前月と異なる PF 数`(展開前の PF 単位、階層別も)。
### §3.6 仮想等額ポートフォリオ
- `virtual_weight[ym, ticker] = exposure[ym, ticker]`(定義上同じ値)。参考として `virtual_return[ym] = 平均(monthly_return of 78 PF)` を `monthly_returns.monthly_return` から取る(新計算をしない。既存列の単純平均)。2026-09 は MTD と明記。

## §4 ticker → asset class 対応表(唯一の手入力。全量を固定)
| ticker | asset class | 根拠 |
|---|---|---|
| TQQQ | Equity(leveraged) | Nasdaq-100 3 倍 |
| TECL | Equity(leveraged) | Tech 3 倍 |
| XLU | Equity(defensive) | 公益セクター。体系では safe haven として使われる(§2.4) |
| GLD | Gold | 金 ETF |
| TMV | Bond(inverse) | 20 年超米債 −3 倍。「債券ロング」ではない点を表で明示 |
| Cash | Cash | 実績 0 件だが規則上あり得る(`executor.py` L356) |
- 保有され得る ticker が 5 つだけなので、この表以外の分類判断は発生しない。将来 ticker が増えたら本表に追記し、追記日を残す(歴史修正禁止)。
- 「Equity 合計」を見るときは leveraged と defensive を分けて示す。XLU を Equity に足すと方向性が見えなくなる。

## §5 実装方針(殿 go 後の cmd 1 本、忍者 1 名。本書では実装しない)
- 場所: `analysis_runs/market_direction/`(DM-signal repo、本番書込なし)。script 1 本 `market_direction_exposure.py` が §3.0→§3.6 を出力(CSV 6 本 + 1 枚の md 表)。
- 入力: 本番 PostgreSQL readonly launcher(`/db-check` 2 ステップ)または `backend/static/data/dm_signal.db` ミラー(参照のみ)。両方で同値になることを AC にする。
- 可視化: まず md 表(月 × ticker の exposure・breadth、階層別、class 別、Δ)。図は次段。
- 再現性: 入力 = `monthly_returns` + `portfolios.config.component_portfolios` のみ。乱数・閾値・順位付けなし。同じ DB スナップショットなら byte 一致。

## §6 二値 AC(実装 cmd に渡す)
1. 対象 PF 数 = 78(L0 12 / L1 21 / L2 24 / L3 21)を name 規則で抽出し、除外 23 を list に出す。
2. `exposure_long` の各 PF-月で Σweight = 1.0(誤差 1e-9)。未展開 PF-月の件数を出し、2013-12 以降は 0。
3. 2024-01 以降の fof 2,178 PF-月で、展開結果が `signals` 月初行の `display_ticker_weights` と ticker 集合・weight とも一致(不一致 0)。
4. standard 396 PF-月(2024 以降 L0)で、`monthly_returns.holding_signal` と `month_start_signal_input_snapshots.holding_signal` が一致(不一致件数を報告。0 でなければ差分を列挙し理由を書く)。
5. 6 表の CSV 行数が期待値(月数 × ticker 数 等)と一致し、`virtual_return` は `monthly_returns.monthly_return` の単純平均と一致。
6. 2026-09 行に `MTD` フラグがある。

## §7 見つかった別件(本設計の対象外。記録のみ)
- `signal_decision_ledger` が本番で 0 行。context/dm-signal-core.md L515-516 の「初期構築・全履歴バックフィル済み」と食い違う。08-16 の PITR rollback が原因と推定(未確認)。監査台帳としての再構築要否は殿裁定。

## §8 殿裁定を要する点(既定案付き)
| # | 論点 | 既定案 |
|---|---|---|
| A | XLU の class | Equity(defensive) として Equity(leveraged) と分ける(§4) |
| B | 期間の始点 | 全階層が揃う 2013-12 から本表、2010-04〜は L0 のみの参考表 |
| C | 2 銘柄同時(`TECL,TQQQ`) | 1/2 ずつ(体系の EqualWeight どおり)。別扱いしない |
| D | 仮想 PF の return | 既存 `monthly_return` の単純平均のみ。再計算しない |

## §9 因果リンク
- ← [[殿指示_市場方向性可視化_20260905_1932]] / ← [[cmd_3768_pf_l0_actual_selection_frequency]](FoF 再帰展開の先例) / ← [[history_py_convert_pf_ids_to_ticker_display]](1/N 展開規則) / ← [[core_L020_signal_vs_holding_signal]]
- → [[market_direction_exposure_cmd]](殿 go 後) → [[signal_decision_ledger_empty_20260905]](§7 別件)
