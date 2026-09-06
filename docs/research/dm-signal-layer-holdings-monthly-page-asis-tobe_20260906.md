<!-- gist-master: b733364ac7dc058a20e7bd635e34ae73 dm-signal-layer-holdings-monthly-page-asis-tobe_20260906.md -->
# DM-Signal 本番「Layer Holdings Monthly」ページ 新設 AsIs/ToBe 5W1H 設計書 v0.2(家老R1)

- 殿指示 2026-09-06 22:07『今後本番に Layer Holdings Monthly ページを新規で作りたい。まずは asis/tobe 5W1H の設計書を作ろう。家老にレビューして更新してもらい、将軍がレビューしてさらに更新する。更新するべき点がなくなるまで続ける』。
- 版履歴(歴史修正禁止のため記録のみ): v0.1 22:20 将軍起草(一次情報=DM-Signal repo 現物+研究 lane の成果物)。v0.1.1 22:22 殿指示『gist 共有、軍師には artifact も共有(前提情報のずれ防止)』→前提 artifact URL を本文に明記。
- v0.2 2026-09-06 22:24 家老R1。DM作業tree HEAD `6c61321277639354c5d9f95cdfd15d676462fdaf`と研究正本`0f2bfbcd`を区別して検分。以下のfile:行は特記なき限り作業tree。v0.1/v0.1.1の記録・artifact URLは保持。公開artifact取得は失敗したため同名ローカルHTMLと生成器を検分した（公開画面一致はU7）。
- **前提wireframe HTML**: https://gist.github.com/6ae60a9c0f84efcb8c15bb503951f9fa 。表示用 https://htmlpreview.github.io/?https://gist.githubusercontent.com/simokitafresh/6ae60a9c0f84efcb8c15bb503951f9fa/raw/layer-holdings-monthly.html 。repo正本docs/dashboard/layer-holdings-monthly.htmlと設計書gist b733364ac7dc058a20e7bd635e34ae73を対で読む。旧artifact URLは来歴に限り保持し、以後のレビュー入口にしない。
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
2. **既存のコードがあればそれを使う。** 計算の正本は固定75 PF版F1の同月MonthlyReturn再帰。本番history.pyの1/Nは参考だが日次入力を直接流用しない。ページはPF非依存で既存layoutを利用、APIは既存require_viewer/page_visibility/ETagを流用、結果表+batchはp_average_results型を使う。
3. **新規の複雑さを足さない。** 結果表1つ・ページ1つ・既存認可の流用を変更境界とする。§4の行数は見積であり、正確性を削る上限や探索範囲の制限にしない。境界を超える追加機構は必要性をレビューする。
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
| いつ更新するか | 別cron案を採る。ただし固定時刻差でなく対象回の全体再計算成功を確認して集計する（U5の成功証跡接続をP4前に確定）。月次集計であり日次ライブ値ではない |
| 誰が見るか | 初期はGlobal hidden_pagesにlayer-holdingsを入れ全Tier+Free viewerを403/nav非表示、adminは既存規則で閲覧可。後日の殿裁定でGlobalから外す1運用操作により公開 |
| 画面 | `/layer-holdings`。artifact 27c1995d(`docs/dashboard/layer-holdings-monthly.html`、`scripts/layer_holdings_render.py`)のレイアウトを Next.js に移植: layer タブ 5+期間 3(12/36/全)+積み上げ横棒+直近 3 ヶ月の生表 |
| 段 | P1 結果表+job(readonly 検算付き) → P2 API → P3 ページ+nav+visibility id → P4 本番 deploy(殿 OK)+post_deploy_check。各段 1 cmd |

## §2 AsIs(事実。file:行)

### §2.1 研究 lane に既にあるもの

| もの | 現物 | 状態 |
|---|---|---|
| F1 `holdings_monthly.csv`(PF×月×ticker×weight) | DM repo `analysis_runs/cmd_4479_holdings_monthly/`: `build_holdings_monthly.py`(824 行、readonly launcher 経由で `monthly_returns`/`signals`/`signal_change_log` を読む L342-389)、`holdings_monthly.csv` 23,175 行、`universe_manifest.yaml`(78 PF、as_of 2026-09-06、L2 24) | cmd_4479 終端(approved_honest_fail)、cmd_4483 で 75 PF 版に再生成(DM origin 0f2bfbcd) |
| 1 表 `layer_holdings_monthly.csv` | 正本=`0f2bfbcd:analysis_runs/cmd_4481_layer_holdings/layer_holdings_monthly.csv`。git showのbytesから3,525行・6列を確認。SHA256=`04c4f56b9d8d42ee3dcf7b8ad31cb80cd1b533fafd479267b3fca1211dc51f91` | U1解消。作業treeの78 PF版4,493行と区別。同commitのF1入力・manifest・生成器を検算に用いる |
| 見え方 | `docs/dashboard/layer-holdings-monthly.html`(artifact 27c1995d)、生成器 `scripts/layer_holdings_render.py`(multi-agent-shogun repo、174 行) | 殿確認済みのレイアウト。JS は CSV を pivot するだけ |
| 階層の定義 | PF 名 prefix(`build_holdings_monthly.py:57-66` `layer_for`): `シン`→L0 / `GSシン`→L1 / `奥義-`→L2 / `秘奥義-`→L3。母集団 75=12/21/21/21(殿裁定 09-06 11:46、新四つ目 3 体除外) | 本番 DB に「layer」列は無い(`portfolios` に無い。`portfolio_folders` は別概念、U2) |
| weight の規則 | 固定0f2bfbcdのF1 build_artifact L426以降はmonthly_return非NULLの月次行から同月索引を作り、_resolve_weightsで再帰する。FoFのholding列にあるcomponentを等分しleaf tickerを等分、Cash/DTB3を保持 | 引数名signals_by_pf_dateでも中身はMonthlyReturn。日次signalsや現在configへのfallbackはしない。component閉包は母集団75 PFの外も読み込む |

### §2.2 本番に既にある型(流用元)

| 型 | 現物 | 流用の仕方 |
|---|---|---|
| 結果表+batch | `PAverageResult`(`models.py:1185-1193`: portfolio_id, n_splits, p_bar, …, calculated_at)、`backend/app/jobs/p_average_batch.py`、API `backend/app/api/p_average.py` | 同じ構造で `LayerHoldingsMonthly` を 1 表足す |
| viewer 向け読み取り API | `backend/app/api/monthly_returns.py:26-53`: `require_viewer`→`tier_id`→`enforce_page_visible`→`check_hide_portfolio_or_folder`→`make_response_with_etag` | `GET /api/layer-holdings` を同じ decorator 列で書く。PF 単位ではないので `check_hide_portfolio_or_folder` は使わない(U3) |
| ページの隠し方 | `backend/app/services/page_visibility.py:45-70`(Settings と GlobalVisibilitySettings の `hidden_pages` union、admin は常に許可、viewer は 403)、frontend `components/sidebar.tsx:334-341` `hiddenPages` filter、admin UI `frontend/app/admin/visibility/page.tsx:46` の id 一覧 | id `layer-holdings` を 3 箇所に足すだけ |
| ページの型 | `frontend/app/monthly-returns/page.tsx`(`useSignals`、`useDelayedLoading`、`usePrefetch` の `PageApiDefinition`)、nav `components/sidebar.tsx:172`+`mobile-menu.tsx:169`、API client `lib/api-client.ts:1321` | 同型で `/layer-holdings` を足す。PF 選択(`selectedId`)に依存しないページなので `useSignals` は不要(U4) |
| 月次の再計算 | render.yaml:148-156はPOST /admin/recalculate-sync。etl_trigger.py:76-98,154-172はbackground taskを起動しacceptedを即時返す | HTTP成功やcurl終了は計算完了ではない。別cronでも対象回の成功・全体scope・完了時刻確認が必要。statusの再起動時の永続性はU5 |
| テスト | `backend/tests/test_compare_returns_api.py` 等の API test、`test_api_masking.py` | 契約 test 2 本(§5) |

### §2.3 AsIs の問題(なぜ本番ページが要るか)

- 1 表はCSVとして研究 lane にあり、月次更新の本番経路が未接続。
- artifact は multi-agent-shogun 側の静的 HTML で、ログイン不要・殿しか見ない。DM-Signal のユーザーには出ていない。
- 「今月、体系全体が何を持っているか」は本番のどのページにも無い(Monthly Returns は PF 単位、Compare も PF 単位)。

## §3 ToBe 5W1H

| 5W1H | 内容 |
|---|---|
| Why | 毎月 1 日の再計算後、階層ごとの保有比率が本番で自動的に更新され、誰でも(Tier で隠せる)見られる。研究 lane の 1 表を人手で回す運用を終える |
| What | (1) 結果表 `layer_holdings_monthly`(6 列+calculated_at) (2) batch job `layer_holdings_batch.py`(F1+1 表の規則を 1 本にまとめ、DB を読んで結果表に書く) (3) `GET /api/layer-holdings` (4) ページ `/layer-holdings`+nav+visibility id |
| Who | 実装=忍者(cmd 単位)、レビュー=軍師→家老、本番 deploy と DDL=殿 OK 後に家老 lane、検算=将軍(研究 CSV との突合) |
| When | P1〜P3は隔離branchで実装。P2の表定義・P3のJSON契約を事前固定すれば並行可能。P4は殿OK後。月次更新は対象回の全体再計算成功後（accepted応答直後や時刻差だけでは不可） |
| Where | backend: `app/db/models.py`(表 1 つ)、`app/jobs/layer_holdings_batch.py`(新規)、`app/api/layer_holdings.py`(新規)、`alembic` migration 1 本(up/down)。frontend: `app/layer-holdings/page.tsx`(新規)、`components/sidebar.tsx`・`mobile-menu.tsx`・`app/admin/visibility/page.tsx`・`lib/api-client.ts`(各 1 箇所追記)。render.yaml: cron 後段(U5) |
| How | 固定75 PF版expected_namesとlayer_forで75件・12/21/21/21を検証。Portfolioのtypeと参照先閉包を読み、monthly_return非NULLの同月holdingを1/N再帰。各層はPFごとのweight合計÷当月有効PF数、ALLは全有効PFで同様（層平均の単純平均ではない）。as-of業務日付はAsia/Tokyo、MTDは集計時点の当月と定義。開始前の不在と参照child欠損を分ける |

## §4 設計(段ごと。変更量の上限つき)

### §4.1 P1 結果表+batch job

- 表 `layer_holdings_monthly`: PK `(year_month, layer, ticker)`。列 `year_month String, layer String, ticker String, weight Float, pf_count Integer, is_mtd Boolean, calculated_at UTCDateTime`。既存表に列を足さない。migration は up/down 1 本。
- job `backend/app/jobs/layer_holdings_batch.py`: p_average_batch.py:20-38,64-73,102以降の一括load→純粋計算→transactionの型を流用する。portfolio単位merge/複数commitは移植しない。読む列はportfolios(id,name,type)とmonthly_returns(portfolio_id,year_month,holding_signal,monthly_return)、対象とcomponent閉包。研究CLIの固定日付・launcher・検算用signals/change_logは持ち込まない。
- 一貫したsnapshotで全計算・key重複/有限値/合計/分母を検証し、新結果表のみを同一transactionでDELETE→INSERT。失敗・欠損・途中終了はrollbackし旧結果を保持。DB排他で並行jobを防ぎ、calculated_atは全行同一。APIは旧/新いずれか一世代のみを読む。
- 変更境界: 結果表1・job1・migration up/down1・models登録。現3,525行は実測でありticker数や期間を打ち切らない。job250行/migration60行/models20行は見積。U5で必要なcron wrapperまたは完了接続箇所を変更一覧に追加してから実装する。
- 検算(実装 cmd 内、readonly): 隔離 DB(本番 snapshot)で job を走らせ、出力を研究 lane の 75 PF CSV(U1)と突合。全 (year_month, layer, ticker) で |weight 差| ≤ 1e-9、pf_count 一致、行数一致。

### §4.2 P2 API

- `GET /api/layer-holdings`はqueryなし・全期間。ApiResponse.dataは単一object: `layers: string[]`, `months: string[]`, `data: {layer:{ym:{ticker:weight}}}`, `pf: {layer:{ym:count}}`, `mtd: string[]`, `calculated_at`。実artifactはlayers配列/data/pf（scripts/layer_holdings_render.py:48-69）。API数値は丸めず、色/順序は画面側で扱う。初回空表は集計未完503、旧世代は更新日時を表示する。
- require_viewerはDepends、enforce_page_visibleは関数呼出、limiterはdecorator。認証→global/Tierページ認可→ETagの順とし、304でも認可を迂回しない。集約値はU3で承認したTierだけへ返す。PF非表示・symbolマスクを単純に無視しない。
- 変更境界: 新API file1つとrouter登録。120行は見積、既存認証/visibility/response helperを使う。

### §4.3 P3 ページ

- `frontend/app/layer-holdings/page.tsx`: artifact HTML の JS(`layer_holdings_render.py:126-163`)を React に移植。layer タブ(L0/L1/L2/L3/ALL)+期間(12/36/全)+積み上げ横棒(ticker 色は既存の palette があればそれ、無ければ `PALETTE` L18-23 をそのまま)+直近 3 ヶ月の生表。`is_mtd` 月は薄く+MTD バッジ。
- nav: `sidebar.tsx`/`mobile-menu.tsx` に id `layer-holdings` を Monthly Returns の直後に 1 項目。admin visibility に `{ id: "layer-holdings", label: "Layer Holdings", group: "Core" }`。`api-client.ts` に 1 関数。
- 変更境界: 新ページ1つと既存nav/admin/clientの登録、300行/各15行は見積。frontend/app/layout.tsx:70-82の共通provider内でページ自身はselectedIdを参照しない。未選択/選択変更でも同じ表。401/403/未集計/取得失敗/古い集計日時を区別する(U4解消)。
- グラフ library は足さない(横棒は div の width で描く。artifact と同じ)。

### §4.4 P4 本番

- 順序: 殿OK→DDL up→新BE/API/job配備→初回job→認可を含むAPI確認→FE配備→承認済みTier設定→post_deploy_check。失敗時は公開停止・cron停止→FE/BEを旧版へ→新表を参照するprocessが無いことを確認→必要時だけdown。表を先に落とさない。
- 月次: 別cron案。0 10 1 * *は候補時刻に過ぎず、対象回の全体再計算成功証跡を確認できなければ旧結果を保持して未更新を記録。accepted応答へ直結しない。成功証跡の永続性・取得方法はU5で確定。

## §5 二値 AC(cmd に渡す)

| AC | 段 | 判定 |
|---|---|---|
| AC1 | P1 | 固定commitのCSVと同一入力snapshot/as-ofで3,525行・全key集合・pf_count・is_mtd一致、weight差max≤1e-9。更新済み本番入力に古いCSV値を強制しない |
| AC2 | P1 | 各 (year_month, layer) で Σweight = 1.0 ± 1e-9 違反 0。pf_count ≤ 層の母集団(12/21/21/21、ALL 75) |
| AC3 | P1 | 他表DML0。再実行は同入力ならcalculated_at以外一致。失敗/child欠損/並行実行で空・部分世代を公開しない。downは参照process停止後に新表だけを対象とする |
| AC4 | P2 | 初期Global非表示で全Tier+Free viewer403/nav非表示、adminは認可通過、未認証は既存認証エラー。If-None-Matchでもviewer403。Global解除後は既存Tier設定に従う。payloadは一世代の新表と一致、初回空表503 |
| AC5 | P3 | `/layer-holdings` が SSR/CSR でエラー 0、nav に出る、hidden Tier では nav から消える。表示 weight の合計が各行 100%±0.1 |
| AC6 | 全 | test_necessity付き契約testでAC1-5の不変量を覆う。件数を2本に固定して再帰/欠損/原子的更新/認可を省略しない。共通code同士の自己比較だけでなく独立正負fixtureを持つ。FAIL0/SKIP0 |
| AC7 | P4 | 同一入力世代で本番結果と独立計算を全key突合、weight差≤1e-9。固定研究例2026-08 ALLはGLD=0.43944444444444436、XLU=0.38611111111111107、TMV=0.17444444444444446、pf_count75。丸めた.439/.386/.174を1e-6基準にしない。本番入力更新時は同世代で再検算 |

## §6 未確認(U)と捨てたもの

| U | 内容 | 潰し方(レビュー往復で) |
|---|---|---|
| U1 | 解消: 0f2bfbcdのcmd_4481_layer_holdings配下、3,525行・6列・全hashを§2.1に記録 | git show bytesで再計数済み |
| U2 | 解消: folder代替案不採用。固定研究75 PFの名前集合/prefixを正本とする | folder一致は設計依存から外し、不要な本番取得を追加しない |
| U3 | 解消: 殿22:30裁定で初期はGlobal hidden_pagesにより全Tier+Free非表示。adminのみ閲覧可 | 後日の殿裁定でGlobalから解除する |
| U4 | 解消: 共通layout配下でselectedId非依存のページを構成できる | §4.3とAC5で未選択/選択変更を試験 |
| U5 | 別cron案は採用、対象回の全体再計算成功を示す永続証跡の取得方法は未確定 | accepted≠完了。statusの永続性・scope・失敗判定と接続箇所をR2で確定 |
| U6 | 解消: 同月MonthlyReturn再帰。対象月行のない開始前PFは通常分母外、存在する親のchild欠損/循環/型不明は集計失敗 | 研究CLIのi7記録→continueと区別し、本番は欠損を正常な分母縮小に見せず旧結果保持。PF/月/理由をlogへ |
| U7 | 解消: ローカルHTMLがそのまま発行された来歴を将軍確認。第三者向けHTML gistを新前提に採用 | 旧artifactのURL直接取得をレビュー依存にしない |

**捨てたもの(再導入しない)**: Breadth/Aggregate Exposure の別表、asset class 集約、前月差 Δ、ticker 別の別ページ、グラフ library 追加、CSV を本番に同梱、管理画面からの手動再計算ボタン(recalculate-sync 既存で足りる)。

## §7 レビュー往復台帳(更新点がなくなるまで)

| 版 | 時刻 | 誰 | 内容 | 残 |
|---|---|---|---|---|
| v0.1 | 22:20 | 将軍 | 起草。U1〜U6 | 家老 R1 待ち |
| v0.2 | 22:24（22:40追補） | 家老 | 更新10点: 正本固定、同月再帰、job流用境界、cron完了判定、Tier境界、payload/ETag、原子的更新、PF非依存UI、rollback/変更量、全精度AC。Global hide裁定とHTML gistを追補 | U1/U2/U3/U4/U6/U7解消、残U5 |

## §8 因果リンク

## §10 殿裁定（22:40記録）

- 2026-09-06 22:30: 初期はL1 Global Page Visibilityで全Tier+Freeをhide。Settings/GlobalVisibilitySettingsのhidden_pages unionにlayer-holdingsを登録、admin閲覧可、viewer403/nav非表示。公開は殿裁定後、Globalの両保存元に当該idが残らないよう1運用操作で解除する。Tier設定は維持する。
- 2026-09-06 22:34受領: wireframeはHTML gistを前提とする。冒頭の旧artifact取得失敗の留保は、発行者のローカルHTML来歴確認とU7解消により更新する。

- ← [[殿指示_LayerHoldingsMonthly本番ページ_20260906_2207]]
- ← [[dm-signal-market-direction-breadth-exposure-asis-tobe_20260905]] v1.1(1 表) ← [[dm-signal-research-data-foundation-asis-tobe_20260905]] F1
- → [[layer_holdings_monthly_本番表]] → [[layer-holdings_page]]
- origin: "[[殿指示_LayerHoldingsMonthly本番ページ_20260906_2207]] -> [[研究1表を本番結果表+API+ページへ]] -> [[p_average_results型の流用]]"
