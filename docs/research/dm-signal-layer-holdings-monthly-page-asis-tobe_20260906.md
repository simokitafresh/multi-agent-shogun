<!-- gist-master: b733364ac7dc058a20e7bd635e34ae73 dm-signal-layer-holdings-monthly-page-asis-tobe_20260906.md -->
# DM-Signal 本番「Layer Holdings Monthly」ページ 新設 AsIs/ToBe 5W1H 設計書 v0.1(2026-09-06 22:20 将軍起草)

- 殿指示 2026-09-06 22:07『今後本番に Layer Holdings Monthly ページを新規で作りたい。まずは asis/tobe 5W1H の設計書を作ろう。家老にレビューして更新してもらい、将軍がレビューしてさらに更新する。更新するべき点がなくなるまで続ける』。
- 版履歴(歴史修正禁止のため記録のみ): v0.1 22:20 将軍起草(一次情報=DM-Signal repo 現物+研究 lane の成果物)。
- 前書: 研究 lane の 1 表 `layer_holdings_monthly.csv` は `docs/research/dm-signal-market-direction-breadth-exposure-asis-tobe_20260905.md` v1.1、その入力 F1 は `docs/research/dm-signal-research-data-foundation-asis-tobe_20260905.md` v0.10。本書はそれを**本番ページ**にする設計だけを扱う。
- 実装は本書が家老・将軍の往復で「更新点なし」に到達し、殿の go が出てから cmd 単位で行う。**本番 DB 書込・DDL・deploy は殿の明示 OK のみ**(殿 09-05 22:25)。

## §0.0 前提条件と我らのスタイル(他の LLM・人がこの設計書を読む前に。殿指示 2026-09-05 13:21)

**この設計書を読む者への前提**
- 対象: DM-Signal 本番(https://dm-signal.com、backend=FastAPI+Postgres on Render `dm-signal-backend`、frontend=Next.js on Render `dm-signal-frontend`、`render.yaml` で main 自動 deploy)。読者は殿・将軍・家老(Codex)・軍師・忍者。
- 目的: 研究 lane で artifact(27c1995d)に出した「階層 L0〜L3/ALL ごとの月次 ticker 保有比率」を、**本番のログイン後ページとして常設**する。売る機能を増やすことではなく、既に手元にある 1 表を本番で毎月自動更新して見られるようにすること。
- 決定権: 殿。将軍は設計と検証まで。家老は本書のレビューと配備。忍者は cmd 単位で実装。
- 事実と推測を混ぜない。事実は「file:行」を添える。未確認は §6 の U 番号で明記し、レビュー往復で潰す。

**我らのスタイル(本書のすべての判断に適用)**
1. **あえて複雑にせず、シンプルに解決する。** 新しい表・新しい認証経路・新しい階層マスタを足す前に、既存の列・既存の規約(名前 prefix、hidden_pages、`require_viewer`)で表せないかを先に試す。
2. **既存のコードがあればそれを使う。** weight 展開は `backend/app/api/history.py:211` `_resolve_pf_ids_to_tickers` と同じ 1/N 規則、ページは `frontend/app/monthly-returns/page.tsx` と同型、API は `backend/app/api/monthly_returns.py` と同型(`require_viewer`+`enforce_page_visible`+`make_response_with_etag`)、精算済み表は `p_average_results`(`backend/app/db/models.py:1185`)と同型の「結果表+batch job」。別方式を並立させない。
3. **新規の複雑さを足さない。** 変更量の上限を §4 に書く。上限を超える案は §6「将来候補」に記録して止める。
4. **測るために必要な最小変更 → 実験 → データを見て次を決める。** まず読み取り専用の API+ページを出し、本番の値が研究 lane の CSV と一致することを二値で確かめてから、見え方(グラフ)を足す。
5. **壊さない。** 既存の Tier/hidden_pages/password/Google Auth の契約は変えない。新表は独立、既存表に列を足さない。migration は down まで用意する。
6. **可逆に、小さく、1 cmd ずつ。** AC は二値(§5)。本番は readonly で事前確認し、失敗したら restore する。
7. **読み手が別の LLM でも同じ結論に至るように書く。** 事実→制約→判断→効果の順で、file と行番号を添える。

## §1 結論(先に)

| 項目 | 結論 |
|---|---|
| 何を出すか | 研究 lane の 1 表と同じ 6 列(`year_month, is_mtd, layer, ticker, weight, pf_count`)。`is_suspect` 列は出さない(母集団 75 PF 版では列なし。市場方向書 §1 参照) |
| どこから計算するか | 本番 Postgres の `monthly_returns.holding_signal`(`backend/app/db/models.py:284`、PIT)を F1 と同じ規則で展開し、階層ごとに平均。CSV は本番に持ち込まない(CSV は検算の正本として使う) |
| どこに置くか | 新結果表 `layer_holdings_monthly`(1 表、6 列+`calculated_at`)。`p_average_results` と同じ「batch job が書き、API が読むだけ」の型 |
| いつ更新するか | 既存 cron `dm-signal-month-start-evening-recalculate`(`render.yaml:148`、毎月 1 日 09:00 UTC)の**後段**に 1 job を足す。当月行は `is_mtd=true` |
| 誰が見るか | `require_viewer` を通る全員(admin+viewer)。ページ id `layer-holdings` を `hidden_pages` 機構に載せ、Tier ごとに隠せる(既存機構。新規の権限は作らない) |
| 画面 | `/layer-holdings`。artifact 27c1995d(`docs/dashboard/layer-holdings-monthly.html`、`scripts/layer_holdings_render.py`)のレイアウトを Next.js に移植: layer タブ 5+期間 3(12/36/全)+積み上げ横棒+直近 3 ヶ月の生表 |
| 段 | P1 結果表+job(readonly 検算付き) → P2 API → P3 ページ+nav+visibility id → P4 本番 deploy(殿 OK)+post_deploy_check。各段 1 cmd |

## §2 AsIs(事実。file:行)

### §2.1 研究 lane に既にあるもの

| もの | 現物 | 状態 |
|---|---|---|
| F1 `holdings_monthly.csv`(PF×月×ticker×weight) | DM repo `analysis_runs/cmd_4479_holdings_monthly/`: `build_holdings_monthly.py`(824 行、readonly launcher 経由で `monthly_returns`/`signals`/`signal_change_log` を読む L342-389)、`holdings_monthly.csv` 23,175 行、`universe_manifest.yaml`(78 PF、as_of 2026-09-06、L2 24) | cmd_4479 終端(approved_honest_fail)、cmd_4483 で 75 PF 版に再生成(DM origin 0f2bfbcd) |
| 1 表 `layer_holdings_monthly.csv` | DM repo `analysis_runs/cmd_4481_layer_holdings/`: `build_layer_holdings.py`(264 行、入力=F1 CSV+manifest のみ、DB 接続 0)、`layer_holdings_monthly.csv` 4,493 行(78 PF 版、`is_suspect` 列あり) | cmd_4481 CLEAR。75 PF 版(3,525 行、198 ヶ月、is_suspect なし、hash 04c4f56b)は artifact 27c1995d に公開。**repo 収載先は U1** |
| 見え方 | `docs/dashboard/layer-holdings-monthly.html`(artifact 27c1995d)、生成器 `scripts/layer_holdings_render.py`(multi-agent-shogun repo、174 行) | 殿確認済みのレイアウト。JS は CSV を pivot するだけ |
| 階層の定義 | PF 名 prefix(`build_holdings_monthly.py:57-66` `layer_for`): `シン`→L0 / `GSシン`→L1 / `奥義-`→L2 / `秘奥義-`→L3。母集団 75=12/21/21/21(殿裁定 09-06 11:46、新四つ目 3 体除外) | 本番 DB に「layer」列は無い(`portfolios` に無い。`portfolio_folders` は別概念、U2) |
| weight の規則 | 1/N 展開(`history.py:224-237`): FoF は component 数で等分、component の ticker 数で等分。Cash は ticker として保持 | 投票比例 weight の FoF(新四つ目)だけ 1/N が本番と一致しない→母集団から除外済み |

### §2.2 本番に既にある型(流用元)

| 型 | 現物 | 流用の仕方 |
|---|---|---|
| 結果表+batch | `PAverageResult`(`models.py:1185-1193`: portfolio_id, n_splits, p_bar, …, calculated_at)、`backend/app/jobs/p_average_batch.py`、API `backend/app/api/p_average.py` | 同じ構造で `LayerHoldingsMonthly` を 1 表足す |
| viewer 向け読み取り API | `backend/app/api/monthly_returns.py:26-53`: `require_viewer`→`tier_id`→`enforce_page_visible`→`check_hide_portfolio_or_folder`→`make_response_with_etag` | `GET /api/layer-holdings` を同じ decorator 列で書く。PF 単位ではないので `check_hide_portfolio_or_folder` は使わない(U3) |
| ページの隠し方 | `backend/app/services/page_visibility.py:45-70`(Settings と GlobalVisibilitySettings の `hidden_pages` union、admin は常に許可、viewer は 403)、frontend `components/sidebar.tsx:334-341` `hiddenPages` filter、admin UI `frontend/app/admin/visibility/page.tsx:46` の id 一覧 | id `layer-holdings` を 3 箇所に足すだけ |
| ページの型 | `frontend/app/monthly-returns/page.tsx`(`useSignals`、`useDelayedLoading`、`usePrefetch` の `PageApiDefinition`)、nav `components/sidebar.tsx:172`+`mobile-menu.tsx:169`、API client `lib/api-client.ts:1321` | 同型で `/layer-holdings` を足す。PF 選択(`selectedId`)に依存しないページなので `useSignals` は不要(U4) |
| 月次の再計算 | `render.yaml:148-156` cron `dm-signal-month-start-evening-recalculate`(`0 9 1 * *`、`POST /admin/recalculate-sync`、`backend/app/api/etl_trigger.py:76`) | recalculate-sync の後段で layer job を呼ぶ(U5: 呼び方=同 endpoint 内 or 別 cron) |
| テスト | `backend/tests/test_compare_returns_api.py` 等の API test、`test_api_masking.py` | 契約 test 2 本(§5) |

### §2.3 AsIs の問題(なぜ本番ページが要るか)

- 1 表は CSD(CSV)として研究 lane にしかなく、毎月人手(cmd)で再生成しないと更新されない。
- artifact は multi-agent-shogun 側の静的 HTML で、ログイン不要・殿しか見ない。DM-Signal のユーザーには出ていない。
- 「今月、体系全体が何を持っているか」は本番のどのページにも無い(Monthly Returns は PF 単位、Compare も PF 単位)。

## §3 ToBe 5W1H

| 5W1H | 内容 |
|---|---|
| Why | 毎月 1 日の再計算後、階層ごとの保有比率が本番で自動的に更新され、誰でも(Tier で隠せる)見られる。研究 lane の 1 表を人手で回す運用を終える |
| What | (1) 結果表 `layer_holdings_monthly`(6 列+calculated_at) (2) batch job `layer_holdings_batch.py`(F1+1 表の規則を 1 本にまとめ、DB を読んで結果表に書く) (3) `GET /api/layer-holdings` (4) ページ `/layer-holdings`+nav+visibility id |
| Who | 実装=忍者(cmd 単位)、レビュー=軍師→家老、本番 deploy と DDL=殿 OK 後に家老 lane、検算=将軍(研究 CSV との突合) |
| When | P1〜P3 は隔離 branch で並行可(P2 は P1 の表定義に依存、P3 は P2 の JSON 形に依存)。P4 は殿 OK 後。月次更新は毎月 1 日 09:00 UTC の recalculate-sync 完了後 |
| Where | backend: `app/db/models.py`(表 1 つ)、`app/jobs/layer_holdings_batch.py`(新規)、`app/api/layer_holdings.py`(新規)、`alembic` migration 1 本(up/down)。frontend: `app/layer-holdings/page.tsx`(新規)、`components/sidebar.tsx`・`mobile-menu.tsx`・`app/admin/visibility/page.tsx`・`lib/api-client.ts`(各 1 箇所追記)。render.yaml: cron 後段(U5) |
| How | 母集団=PF 名 prefix で L0〜L3 を判定(`layer_for` と同じ 4 分岐)し、名前が `expected_names()` の 75 に一致する PF だけ。weight=`monthly_returns.holding_signal` を 1/N 展開(FoF は `signals` の同日 component 行で再帰、F1 `_resolve_weights` L187-236 と同じ)。階層平均=Σweight ÷ pf_count(distinct portfolio_id)。ALL=層を無視して同じ計算。`is_mtd`=as-of 月(job 実行日の月)のみ true |

## §4 設計(段ごと。変更量の上限つき)

### §4.1 P1 結果表+batch job

- 表 `layer_holdings_monthly`: PK `(year_month, layer, ticker)`。列 `year_month String, layer String, ticker String, weight Float, pf_count Integer, is_mtd Boolean, calculated_at UTCDateTime`。既存表に列を足さない。migration は up/down 1 本。
- job `backend/app/jobs/layer_holdings_batch.py`: `p_average_batch.py` と同じ骨格(`_load_monthly_returns` 相当→計算→`session.merge`)。読むのは `portfolios(id,name)`、`monthly_returns(portfolio_id,year_month,holding_signal)`、`signals(portfolio_id,date,holding_signal)`(FoF 再帰用)。書くのは新表だけ。**全消し→全書き**(198 ヶ月×5 層×≤8 ticker ≈ 4,000 行、1 トランザクション)。
- 変更量上限: backend 新規 2 file(job ≤250 行、migration ≤60 行)+`models.py` +20 行。既存 file の変更は `models.py` のみ。
- 検算(実装 cmd 内、readonly): 隔離 DB(本番 snapshot)で job を走らせ、出力を研究 lane の 75 PF CSV(U1)と突合。全 (year_month, layer, ticker) で |weight 差| ≤ 1e-9、pf_count 一致、行数一致。

### §4.2 P2 API

- `GET /api/layer-holdings`(query なし。全期間を返す。≈4,000 行/≈150KB、ETag 付き)。レスポンス `ApiResponse[{ months: [...], layers: {L0: {ym: {ticker: weight}}}, pf_count: {L0: {ym: n}}, mtd: [...], calculated_at }]`=`scripts/layer_holdings_render.py:67-69` の payload と同形(frontend が pivot しない)。
- decorator 列は `monthly_returns.py:26-53` と同じ: `limiter`、`require_viewer`、`enforce_page_visible(page_id="layer-holdings", tier_id)`、`make_response_with_etag`。マスク(L3/L4)は PF 単位の機構なので使わない(U3)。
- 変更量上限: 新規 1 file ≤120 行、router 登録 1 行。

### §4.3 P3 ページ

- `frontend/app/layer-holdings/page.tsx`: artifact HTML の JS(`layer_holdings_render.py:126-163`)を React に移植。layer タブ(L0/L1/L2/L3/ALL)+期間(12/36/全)+積み上げ横棒(ticker 色は既存の palette があればそれ、無ければ `PALETTE` L18-23 をそのまま)+直近 3 ヶ月の生表。`is_mtd` 月は薄く+MTD バッジ。
- nav: `sidebar.tsx`/`mobile-menu.tsx` に id `layer-holdings` を Monthly Returns の直後に 1 項目。admin visibility に `{ id: "layer-holdings", label: "Layer Holdings", group: "Core" }`。`api-client.ts` に 1 関数。
- 変更量上限: 新規 1 file ≤300 行、既存 4 file 各 ≤15 行。
- グラフ library は足さない(横棒は div の width で描く。artifact と同じ)。

### §4.4 P4 本番

- 順序: DDL(migration up)→job 初回実行→API 応答確認→FE deploy→post_deploy_check(`docs/research/cmd_4416_post_deploy_check.md` の型)。全て殿の明示 OK 後。失敗時は migration down+FE revert。
- 月次: recalculate-sync の後段で job を呼ぶ(U5 で確定)。

## §5 二値 AC(cmd に渡す)

| AC | 段 | 判定 |
|---|---|---|
| AC1 | P1 | 隔離 DB で job 実行後、新表の全行が研究 lane 75 PF CSV(U1)と一致: 行数一致、(year_month, layer, ticker) 集合一致、weight 差 max ≤ 1e-9、pf_count 一致。不一致 0 |
| AC2 | P1 | 各 (year_month, layer) で Σweight = 1.0 ± 1e-9 違反 0。pf_count ≤ 層の母集団(12/21/21/21、ALL 75) |
| AC3 | P1 | job が書くのは `layer_holdings_monthly` のみ(SQL log で他表への INSERT/UPDATE/DELETE 0)。migration down で表が消え、他表が不変 |
| AC4 | P2 | `GET /api/layer-holdings` が viewer で 200、`hidden_pages` に `layer-holdings` を入れた Tier で 403、admin は常に 200。ETag 付き。payload の months/layers/pf_count/mtd が新表と一致 |
| AC5 | P3 | `/layer-holdings` が SSR/CSR でエラー 0、nav に出る、hidden Tier では nav から消える。表示 weight の合計が各行 100%±0.1 |
| AC6 | 全 | 契約 test 2 本(AC2 Σweight=1、AC4 hidden_pages 403)を `test_necessity` 宣言付きで永続。実装用 test は同一 cmd 内で削除。SKIP 0 |
| AC7 | P4 | post_deploy_check: 本番 `GET /api/layer-holdings` の 2026-08 ALL 行が artifact の値(GLD .439/XLU .386/TMV .174、市場方向書 §進捗)と一致(±1e-6) |

## §6 未確認(U)と捨てたもの

| U | 内容 | 潰し方(レビュー往復で) |
|---|---|---|
| U1 | 75 PF 版 `layer_holdings_monthly.csv`(3,525 行、hash 04c4f56b)の DM repo 収載先。`analysis_runs/cmd_4481_layer_holdings/` の現物は 78 PF 版 4,493 行(is_suspect あり)。0f2bfbcd の stat に cmd_4481 は 1 file | 家老が cmd_4483 の report で path を確認。無ければ P1 の検算前に `build_layer_holdings.py` を 75 PF manifest で再実行して固定 |
| U2 | `portfolio_folders` が階層(L0〜L3)と一致するか。一致するなら prefix 判定の代わりに folder を使う案もあるが、本書は F1 と同じ prefix 判定を採る(研究 lane と同一規則=検算可能) | 本番 readonly で folder 名一覧を 1 回取得して記録。判定規則は変えない |
| U3 | Free tier(hide_portfolio/hide_signal)に本ページを見せるか。PF 単位の値ではないので既存マスクは掛からない。既定=`hidden_pages` で Free から隠す | 殿裁定。既定案を §1 に置く |
| U4 | ページが PF 選択(`useSignals`)に依存しないことで、既存 layout(選択 PF 前提の header)に不整合が出ないか | 忍者が `docs`/`faq` ページ(PF 非依存)の型を確認して報告 |
| U5 | 月次 job の呼び方: (a) `recalculate-sync` の末尾で同期呼出 (b) 別 cron(`render.yaml` に 1 service 追加、`0 10 1 * *`) | 既定=(b)。recalculate-sync の所要と失敗時の独立性を優先。家老レビューで確定 |
| U6 | `signals` の同日 component 行が欠ける PF-月(F1 の I7 相当)の扱い。F1 は行を出さない=pf_count の分母から外れる | 同じ扱い(行を出さない)。件数を job の log に出す |

**捨てたもの(再導入しない)**: Breadth/Aggregate Exposure の別表、asset class 集約、前月差 Δ、ticker 別の別ページ、グラフ library 追加、CSV を本番に同梱、管理画面からの手動再計算ボタン(recalculate-sync 既存で足りる)。

## §7 レビュー往復台帳(更新点がなくなるまで)

| 版 | 時刻 | 誰 | 内容 | 残 |
|---|---|---|---|---|
| v0.1 | 22:20 | 将軍 | 起草。U1〜U6 | 家老 R1 待ち |

## §8 因果リンク

- ← [[殿指示_LayerHoldingsMonthly本番ページ_20260906_2207]]
- ← [[dm-signal-market-direction-breadth-exposure-asis-tobe_20260905]] v1.1(1 表) ← [[dm-signal-research-data-foundation-asis-tobe_20260905]] F1
- → [[layer_holdings_monthly_本番表]] → [[layer-holdings_page]]
- origin: "[[殿指示_LayerHoldingsMonthly本番ページ_20260906_2207]] -> [[研究1表を本番結果表+API+ページへ]] -> [[p_average_results型の流用]]"
