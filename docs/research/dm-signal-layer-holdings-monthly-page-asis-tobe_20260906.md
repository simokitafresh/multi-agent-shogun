<!-- gist-master: b733364ac7dc058a20e7bd635e34ae73 dm-signal-layer-holdings-monthly-page-asis-tobe_20260906.md -->
# DM-Signal 本番「Layer Holdings Monthly」ページ 新設 AsIs/ToBe 5W1H 設計書 v0.6(家老R5)

- 殿指示 2026-09-06 22:07『今後本番に Layer Holdings Monthly ページを新規で作りたい。まずは asis/tobe 5W1H の設計書を作ろう。家老にレビューして更新してもらい、将軍がレビューしてさらに更新する。更新するべき点がなくなるまで続ける』。
- 版履歴(歴史修正禁止のため記録のみ): v0.1 22:20 将軍起草(一次情報=DM-Signal repo 現物+研究 lane の成果物)。v0.1.1 22:22 殿指示『gist 共有、軍師には artifact も共有(前提情報のずれ防止)』→前提 artifact URL を本文に明記。
- v0.2 2026-09-06 22:24 家老R1。DM作業tree HEAD `6c61321277639354c5d9f95cdfd15d676462fdaf`と研究正本`0f2bfbcd`を区別して検分。以下のfile:行は特記なき限り作業tree。v0.1/v0.1.1の記録・artifact URLは保持。公開artifact取得は失敗したため同名ローカルHTMLと生成器を検分した（公開画面一致はU7）。
- v0.3 2026-09-06 22:50 将軍R2。U5 を既存機構(recalculation_status 表・sync-status・etl_layer_sync_wait.sh)の接続で確定。新規の状態管理を足さない。
- v0.5 2026-09-06 23:08 将軍R4。家老の配備懸念 2 点を確定: (1) P1 固定入力=`0f2bfbcd:analysis_runs/cmd_4479_holdings_monthly/input_snapshot_raw.json`(99.9MB、sha256 729ec9a6…)を job の `--input-json` で読む (2) 共通 readiness=`backend/app/services/layer_holdings_readiness.py`。
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
| どこに置くか | 新結果表layer_holdings_monthly（6業務列+calculated_at+nullable source_recalc_id）。結果表1つをbatch jobが書きAPIが読む。source_recalc_idは参照した再計算行の監査用ID |
| いつ更新するか | 別cronから、対象月初runの完了・対象範囲・キャンセルなし・失敗なしを永続行で確認して集計する。modeだけで全PFを推定しない。詳細§4.4。条件不成立は旧結果保持 |
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
| 月次の再計算 | render.yaml:148-156の月初cronはmode指定なし、etl_trigger.py:87の既定はportfolio。mode=fullでもportfolio_id指定可能。recalc_status.py:204-255はmode/status/start/endを保存するが、既存summaryへ対象範囲・結果を記録していない。etl_trigger.py:223-230は例外時mark_recalculation_error→finally end_recalculation | interrupted保存後は_current_db_record_id=Noneとなり、finallyのcompleted更新はDBへ作用しない(recalc_status.py:408-428)。ただし正常returnにcancelled/errorsを含む経路もあり、completedだけでは成功十分条件にならない。R3で既存summaryへの証拠記録を追加する設計へ是正 |
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
| Where | backend: `app/db/models.py`(表 1 つ)、`app/jobs/layer_holdings_batch.py`(新規)、`app/api/layer_holdings.py`(新規)、`alembic` migration 1 本(up/down)。frontend: `app/layer-holdings/page.tsx`(新規)、`components/sidebar.tsx`・`mobile-menu.tsx`・`app/admin/visibility/page.tsx`・`lib/api-client.ts`(各 1 箇所追記)。render.yaml: cron `dm-signal-layer-holdings` 1 service 追加。`app/api/etl_trigger.py` sync-status 辞書に `L4_recalc` +6 行、admin endpoint `POST /admin/layer-holdings`(§4.4) |
| How | 固定75 PF版expected_namesとlayer_forで75件・12/21/21/21を検証。Portfolioのtypeと参照先閉包を読み、monthly_return非NULLの同月holdingを1/N再帰。各層はPFごとのweight合計÷当月有効PF数、ALLは全有効PFで同様（層平均の単純平均ではない）。as-of業務日付はAsia/Tokyo、MTDは集計時点の当月と定義。開始前の不在と参照child欠損を分ける |

## §4 設計(段ごと。変更量の上限つき)

### §4.1 P1 結果表+batch job

- 表 `layer_holdings_monthly`: PK(year_month,layer,ticker)。year_month String、layer String、ticker String、weight Float、pf_count Integer、is_mtd Boolean、calculated_at UTCDateTime、source_recalc_id Integer nullable。既存表への列追加はせずmigration up/down1本。固定入力の隔離検算はsource_recalc_id=null、本番実行はreadinessで確認したIDを全行へ保存する。
- job `backend/app/jobs/layer_holdings_batch.py`: p_average_batch.py:20-38,64-73,102以降の一括load→純粋計算→transactionの型を流用する。portfolio単位merge/複数commitは移植しない。読む列はportfolios(id,name,type)とmonthly_returns(portfolio_id,year_month,holding_signal,monthly_return)、対象とcomponent閉包。研究CLIの固定日付・launcher・検算用signals/change_logは持ち込まない。
- 一貫したsnapshotで全計算・key重複/有限値/合計/分母を検証し、新結果表のみを同一transactionでDELETE→INSERT。失敗・欠損・途中終了はrollbackし旧結果を保持。DB排他で並行jobを防ぎ、calculated_atは全行同一。APIは旧/新いずれか一世代のみを読む。
- 変更境界: 結果表1・job1・migration up/down1・models登録。現3,525行を打切り上限としない。R3により既存recalc_status.pyへのsummary保存、etl_trigger.pyでのscope/result受渡しと共通readiness判定・admin endpoint、render cron登録を明記する。sync-status辞書+6行だけで足りるとは見積もらない。
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
- 月次(U5、R3是正): 別cron `dm-signal-layer-holdings` は既存 `etl_layer_sync_wait.sh L4_recalc layer-holdings` を利用する。月初09:00 UTCの既存全PF portfolio再計算を対象とし、mode=fullへの変更を新ページのためだけに要求しない。既存再計算入口が正規化した対象範囲・start/end期間をrecalculation_status.summaryへ開始時に、cancelled/errorsと必要なcoverage検証結果を終了時に記録する。新しい表・状態機械は作らない。

## §5 二値 AC(cmd に渡す)

R3追加の月次接続契約（§4.4の続き）:
- readinessは既存summaryに記録された全PF対象・必要期間/母集団coverage、対象月初09:00 UTC以後のstart_time、completed/end_time、cancelled=false、当該生成のerrors=0を確認する。legacy summary欠落やDB記録失敗は成功根拠にしない。modeは計算layer、scopeは対象集合であり別の値として検証する。
- 「最新成功行」だけを選ばない。対象を更新した後続runがrunning/interrupted/cancelled/失敗なら古い成功行で許可しない。入力を更新する再計算と重ならないよう既存の再計算advisory lockをjob側で取得し、同じDBセッションでreadiness再確認からsnapshot読取・結果置換まで保持する。取得不可は409、finallyで解放。新しいlock台帳は作らない。
- last_success_dateは既存wait scriptのTODAY=date -uに合わせUTC日付。表示のas-ofはAsia/Tokyoのまま区別する。scriptはlockedを見ないので、不適格時は日付を返さず、POST入口でも共通readinessを再検査する。
- wait上限は既存20回・60秒間隔で失敗可。遅いrunで当日の窓を外した場合は再試行運用を必要とするため、「必ず当日更新」を保証しない。新しい無限待機を追加しない。
- 受入追加: (a)全PF portfolio成功を許可 (b)特定PF fullを拒否 (c)cancelled/errorsあり/summary欠落/記録失敗を拒否 (d)古い成功後の新失敗を拒否 (e)UTC/JST日付境界でwaitとAPI判定が一致 (f)再計算との競合時に旧/新結果以外を公開しない。既存機構の正負テストで確認する。

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
| U5 | R3で是正: 既存recalculation_status.summaryへscope/期間/結果を記録し、UTC日付で既存wait scriptへ接続。最新適格runと後続未完了/失敗runを区別する | mode fullだけの全PF推定、成功行だけを検索して新しい失敗を隠す判定、DB記録失敗時の成功扱いは禁止。仕様は§4.4に列挙し将軍R4で再確認 |
| U6 | 解消: 同月MonthlyReturn再帰。対象月行のない開始前PFは通常分母外、存在する親のchild欠損/循環/型不明は集計失敗 | 研究CLIのi7記録→continueと区別し、本番は欠損を正常な分母縮小に見せず旧結果保持。PF/月/理由をlogへ |
| U7 | 解消: ローカルHTMLがそのまま発行された来歴を将軍確認。第三者向けHTML gistを新前提に採用 | 旧artifactのURL直接取得をレビュー依存にしない |

**捨てたもの(再導入しない)**: Breadth/Aggregate Exposure の別表、asset class 集約、前月差 Δ、ticker 別の別ページ、グラフ library 追加、CSV を本番に同梱、管理画面からの手動再計算ボタン(recalculate-sync 既存で足りる)。

## §7 レビュー往復台帳(更新点がなくなるまで)

| 版 | 時刻 | 誰 | 内容 | 残 |
|---|---|---|---|---|
| v0.1 | 22:20 | 将軍 | 起草。U1〜U6 | 家老 R1 待ち |
| v0.2 | 22:24（22:40追補） | 家老 | 更新10点: 正本固定、同月再帰、job流用境界、cron完了判定、Tier境界、payload/ETag、原子的更新、PF非依存UI、rollback/変更量、全精度AC。Global hide裁定とHTML gistを追補 | U1/U2/U3/U4/U6/U7解消、残U5 |
| v0.3 | 22:50 | 将軍 R2 | U5 確定(既存 recalculation_status 表+sync-status L4_recalc key+etl_layer_sync_wait.sh 流用、endpoint 側の再検査 409)。§1/§2.2/§4.4/§6 を同時更新、全体整合を通読。他の家老 10 点は採用 | 残 U なし。家老 R3 へ(更新点なしなら往復終了) |
| v0.4 | 23:0x | 家老 R3 | 更新 6 点(mode/scope、summary 結果、interrupted と cancel/errors、後続失敗、UTC、排他)+§9 実装パック統合(API 引数・P2 所有 path・migration 先行・source_recalc_id 列)。公開 0b2fdbd8c | 配備懸念 2(P1 固定入力 fixture の所在、P2 readiness 関数の配置) |
| v0.5 | 23:08 | 将軍 R4 | 配備懸念 2 点を確定: 固定入力=0f2bfbcd input_snapshot_raw.json(`--input-json`)、readiness=services/layer_holdings_readiness.py(+契約 test 6 通り)。公開 c39d171ae | 残 U 0・配備懸念 0 |
| v0.6 | 23:08 | 家老 R5 | 固定 JSON を実測(portfolios 101/monthly 16,298/欠落列 0/対象 75 不足 0/重複 0)。更新 3 点: 実キー monthly と列・件数確定、mode=portfolio 負例の是正、配備懸念文言更新。公開 227526668 | 設計上の未確定なし。将軍 R6 へ |
| R6 | 23:14 | 将軍 | v0.6 の 3 点を diff で確認、いずれも現物実測に基づく訂正で採用。本 R6 で追記したのは §7 台帳の v0.4〜v0.6 行(家老版で欠けていた記録の補完)のみで設計本文の変更 0。**更新点なし=往復終了(殿指示 22:07 の終了条件)**。v0.6 本文を最終版とする | 次=殿の go。go 後に §9.5 の順で家老が P1/P2/P3 を 3 名並行配備 |

## §8 因果リンク

R5履歴（v0.6、2026-09-06 23:08家老）: 更新3点=固定JSONの実キー/列/件数確定、mode=portfolio負例の矛盾是正、解消済み配備懸念の文言更新。固定入力はhash一致・parse成功。残る設計上の未確定事項なしと判断するが、更新ありのため将軍R6で再確認する。

R3履歴（v0.4、2026-09-06 22:50家老）: 更新6点=modeとscope分離、summary成功根拠、interrupted/正常returnの失敗区別、古い成功へのfallback防止、UTC日付整合、再計算との排他。R2の「mode full+completedなら十分」「+6行」「JSTのままwait流用」は本仕様で訂正。将軍R4へ、未実装の受入検証は上記6項目。


## §9 実装パック(cmd 単位。忍者がそのまま着手でき、家老が配備で悩まない形。殿 22:50『利他の精神で実際に忍者が実装することをイメージして設計書は作れ。家老は配備するときに悩まないように』)


### §9.0 共通(全 cmd)
- repo: DM-Signal(`/mnt/c/Python_app/DM-signal`)。作業は隔離 worktree+非 main branch `feat/layer-holdings-P<n>`。**main への push は本番 deploy 相当=禁止**。成果は branch push+報告 YAML。
- 母集団・規則の正本: `0f2bfbcd:analysis_runs/cmd_4479_holdings_monthly/build_holdings_monthly.py`(`expected_names()` L48-55、`layer_for()` L57-66、`_resolve_weights()` L187-236)と `0f2bfbcd:analysis_runs/cmd_4481_layer_holdings/layer_holdings_monthly.csv`(3,525 行、sha256 04c4f56b…)。忍者は `git show 0f2bfbcd:<path>` で取り、作業 tree の 78 PF 版(4,493 行)を使わない。
- 本番 DB: readonly 取得は 既存db-checkのreadonly capability発行→launcher→nonce監査の経路(既存 launcher、回数制限なし)。書込・DDL・deploy は行わない(P4 は殿 OK 後の家老 lane)。
- テスト: 契約 test は `test_necessity` 宣言付きで永続、実装用 test は同 cmd 内で削除。`pytest` は `backend/tests/` の既存 conftest に乗せる。SKIP 0。
- 報告 YAML: `binary_checks` は下記 AC 番号ごとに yes/no+生出力 1 行。`files_modified` は path 形式。
- 忍者が自分で決めてよいこと: 変数名・関数分割・test fixture の形・SQL の書き方。決めてはいけないこと: 表の列名/PK、API path と payload key、page id、cron 名、AC の閾値(全て本書が固定)。

### §9.1 cmd P1: 結果表+batch job(backend)
| 項目 | 値 |
|---|---|
| task_type | implement(DM-Signal backend) |
| 依存 | なし(先頭) |
| planned_paths | `backend/app/db/models.py`(+`LayerHoldingsMonthly` 1 class)、`backend/alembic/versions/<rev>_layer_holdings_monthly.py`(新規、up/down)、`backend/app/jobs/layer_holdings_batch.py`(新規)、`backend/tests/test_layer_holdings_batch.py`(契約 test、新規) |
| 表定義(固定) | `layer_holdings_monthly`: PK(`year_month` String, `layer` String, `ticker` String)、`weight` Float、`pf_count` Integer、`is_mtd` Boolean、`calculated_at` UTCDateTime(全行同一)、`source_recalc_id` Integer nullable(参照した `recalculation_status.id`、P4 の AC7 証跡) |
| job の入出力(固定) | 入力: `portfolios(id,name,type)`、`monthly_returns(portfolio_id,year_month,holding_signal,monthly_return)`。母集団=`expected_names()` の 75 名と一致する PF のみ。展開=`_resolve_weights` と同じ同月 MonthlyReturn 再帰(monthly_return 非 NULL 行のみ、child 欠損/循環は集計失敗=旧結果保持)。出力=(year_month, layer∈L0..L3+ALL, ticker)→weight=Σweight÷pf_count、pf_count=distinct portfolio_id。`is_mtd`=as-of 月(Asia/Tokyo 今日の月)のみ true。書込=新表のみ、同一 transaction で DELETE 全行→INSERT |
| 起動 I/F(固定) | `python -m app.jobs.layer_holdings_batch [--as-of YYYY-MM-DD] [--dry-run] [--input-json <path>]`。`--dry-run` は書かず件数と検証結果を stdout(JSON 1 行)。`--input-json` は DB を読まず固定 JSON(§検算)を入力にする(検算専用。本番 cron/endpoint は使わない) |
| 検算(cmd内) | 固定入力=0f2bfbcd:analysis_runs/cmd_4479_holdings_monthly/input_snapshot_raw.json。99,913,389 bytes、SHA256 729ec9a6117a894ee9f30ea03d77dca8485a43893d89cba420996e9c6827ca2a。R5で全JSON parseとhash一致を確認。トップレベルはportfolios(101行、id/name/type)、monthly(16,298行、portfolio_id/year_month/holding_signal/monthly_return)、signals/display/changes/daily。job入力adapterはportfoliosとmonthlyのみを共通内部形へ渡し、monthly_returnsというJSONキーを期待しない。--input-json時はDB接続0、--dry-run --as-of 2026-09-06で同世代CSV3,525行と全key突合。testsへ巨大JSONを複製せず、常設契約は小さな合成fixture(正/child欠損/循環)を使う |
| AC(二値) | AC1: 突合 3,525 行・key 集合一致・pf_count 一致・is_mtd 一致・weight 差 max ≤1e-9(生出力: `rows=3525 keys_match=true maxdiff=<値>`) / AC2: 各 (year_month, layer) Σweight=1±1e-9 違反 0、pf_count ≤12/21/21/21/75 / AC3: job の SQL log で新表以外への DML 0、同入力で再実行=calculated_at 以外一致、child 欠損 fixture で例外→rollback→旧行残存 / AC6: 契約 test = AC2 と AC3(欠損時 rollback)の 2 本以上、FAIL 0 SKIP 0 / migration: `alembic upgrade head`→`downgrade -1` で新表のみ作成・削除、他表の DDL 差分 0 |
| 見積 | job ≤250 行、migration ≤60 行、models +20 行(上限ではなく見積) |

### §9.2 cmd P2: API+完了証跡の接続(backend)
| 項目 | 値 |
|---|---|
| task_type | implement(DM-Signal backend) |
| 依存 | P1 の表定義(§9.1 は固定なので **P1 と並行可**。P1 branch を base にせず、同じ表定義を前提に書く) |
| planned_paths | backend/app/api/layer_holdings.py、backend/app/main.py、backend/app/api/etl_trigger.py、backend/app/utils/recalc_status.py、backend/app/services/layer_holdings_readiness.py（新規共通関数）、backend/tests/test_layer_holdings_api.py、backend/tests/test_layer_holdings_readiness.py。readiness試験は全PF portfolio/full成功を適格、特定PF full・scope欠落・古いrun・running・後続interruptedを不適格とする。§4.4のcancelled/errors/日付境界/排他も保持。modeだけで拒否しない。sync-statusとPOSTが同じ関数を呼ぶ |
| GET payload(固定) | `ApiResponse.data = {layers:[L0,L1,L2,L3,ALL], months:[...], data:{layer:{ym:{ticker:weight}}}, pf:{layer:{ym:count}}, mtd:[ym...], calculated_at}`。丸めない。表が空なら 503 `{"message":"layer holdings not calculated yet"}` |
| GET の順序(固定) | `limiter` decorator → `require_viewer`(Depends) → `enforce_page_visible(db, "layer-holdings", is_admin, tier_id)` → 読取 → `make_response_with_etag`。If-None-Match でも認可を先に通す(viewer hidden なら 304 ではなく 403) |
| POST /admin/layer-holdings(固定) | require_admin。§4.4/R3共通readinessを使う。対象月初runのsummary.scope=all、必要coverage、completed、cancelled=false、errors=0、start/end時刻と後続未完了runなしを検証。mode fullで全PFと推測せず全PF portfolioを許可。同じ再計算advisory lockを保持して判定・snapshot読取・job commitまで行い、未適格409。成功はrows/calculated_at/source_recalc_idを返す |
| sync-status `L4_recalc`(固定) | 同じreadinessを使用し適格時だけend_timeのUTC日付をlast_success_dateへ。不適格はnull、runningをlockedへ。既存wait scriptのUTC TODAYと一致させる。過去成功だけを検索して後続失敗を隠さない |
| AC(二値) | AC4は§5の認証/global hide/ETag/空表。AC4bは全PF portfolio成功を許可、特定PF full・summary欠落・cancelled/errorsあり・古い成功後の新失敗・runningを409。UTC/JST境界とロック競合も検証。成功時source_recalc_id一致。FAIL0/SKIP0 |

### §9.3 cmd P3: ページ+nav+visibility(frontend)
| 項目 | 値 |
|---|---|
| task_type | implement(DM-Signal frontend) |
| 依存 | §9.2 の payload 形(固定なので **P1/P2 と並行可**。開発中は fixture JSON=`0f2bfbcd` CSV を `scripts/layer_holdings_render.py:48-69` と同じ pivot で作ったもの) |
| planned_paths | `frontend/app/layer-holdings/page.tsx`(新規)、`frontend/components/sidebar.tsx`・`frontend/components/mobile-menu.tsx`(Monthly Returns の直後に id `layer-holdings` label `Layer Holdings` href `/layer-holdings` 各 1 項目)、`frontend/app/admin/visibility/page.tsx:46` 付近に `{ id: "layer-holdings", label: "Layer Holdings", group: "Core" }`、`frontend/lib/api-client.ts`(`getLayerHoldings()` 1 関数、`/api/layer-holdings`)、`frontend/app/__tests__/layer-holdings.test.tsx`(契約 test) |
| 画面(固定) | wireframe gist 6ae60a9c(`docs/dashboard/layer-holdings-monthly.html`、multi-agent-shogun repo)と同じ: layer タブ 5(既定 ALL)+期間 3(12/36/全、既定 12)+積み上げ横棒(ticker 色は既存 palette があればそれ、無ければ HTML の `PALETTE`)+右端 pf_count+直近 3 ヶ月の生表+`is_mtd` 月は薄く MTD バッジ。PF 選択(`useSignals().selectedId`)を参照しない。状態 4 種を区別: 401/403(既存 error 表示)、503(『集計待ち』)、取得失敗(retry)、正常 |
| AC(二値) | AC5: `next build` エラー 0、fixture で描画し各行の weight 合計 100%±0.1(生出力: `rows=<n> sum_violations=0`)、hidden Tier の `hiddenPages` に `layer-holdings` があれば nav に出ない、admin では出る、未選択/選択変更でも表が同じ / AC6: 契約 test = 合計 100% と nav 非表示の 2 本、FAIL 0 SKIP 0 |

### §9.4 cmd P4: 本番投入(家老 lane、殿の明示 OK 後)
| 順序 | 操作 | 確認(二値) |
|---|---|---|
| 1 | 殿 OK(本番 DDL+deploy) | lord_conversation に時刻付き OK |
| 2 | Global hidden_pages に `layer-holdings` を追加(admin visibility UI、Settings と GlobalVisibilitySettings の両方) | `GET /api/admin/...visibility` に id が両保存元で出る |
| 3 | 承認済みP1 migrationを本番へ適用（新BE/FE公開より先） | 新表あり、他表DDL差分0 |
| 4 | 承認済みP1/P2/P3をmain合流しBE/FE配備。Global hideとcron停止を維持 | BE/FE deploy success、参照tableあり |
| 5 | `POST /admin/layer-holdings`(admin) | 200、同世代入力から導出した期待rows、`source_recalc_id` あり。409ならreadiness理由を返し旧結果保持 |
| 6 | `GET /api/layer-holdings`: admin 200 / viewer 403 | AC4 |
| 7 | AC7: 本番 payload と `0f2bfbcd` CSV を同世代で全 key 突合(weight 差 ≤1e-9、2026-08 ALL GLD=0.43944444444444436 / XLU=0.38611111111111107 / TMV=0.17444444444444446 / pf_count 75) | 不一致 0 |
| 8 | render.yaml cron `dm-signal-layer-holdings`(`35 9 1 * *`、`bash scripts/etl_layer_sync_wait.sh L4_recalc layer-holdings`)を有効化 | Render に cron が見える |
| 9 | post_deploy_check を `docs/research/cmd_4416_post_deploy_check.md` の型で記録 | 記録 commit |
| 失敗時 | 公開停止(Global hidden 維持)・cron 停止→FE/BE 旧版へ→新表参照 process 0 を確認→必要時のみ `alembic downgrade -1` | 表を先に落とさない |

### §9.5 家老の配備順(悩まないための固定)
- P1・P2・P3 は **同時に 3 名へ配備可**(依存は本書の固定仕様で切ってある)。空き忍者が 1 名なら P1→P2→P3 の順。
- 各 cmd の `related_lessons`: 契約 test の default-delete、cross_repo deploy_forbidden(F-19 後の gate)、readonly launcher 契約。
- レビュー: 軍師一次→家老。AC の生出力行がない報告は差戻し(1 回で通す型)。
- P4 は cmd ではなく家老 lane の runbook(§9.4)。殿 OK が無い間は着手しない。

§9配備条件（R5確認）: 固定入力の所在・hash・実キーは§9.1で実測済み、共通readiness配置は§9.2で確定。P1/P2/P3は所有pathを分けて並行実装し、統合検証は統合時に1回行う。source_recalc_idは新結果表の監査列で§1/§4.1と一致。input-jsonの巨大fixtureは同世代検算専用、通常の契約テストは合成fixtureで回す。



## §10 殿裁定（22:40記録）

- 2026-09-06 22:30: 初期はL1 Global Page Visibilityで全Tier+Freeをhide。Settings/GlobalVisibilitySettingsのhidden_pages unionにlayer-holdingsを登録、admin閲覧可、viewer403/nav非表示。公開は殿裁定後、Globalの両保存元に当該idが残らないよう1運用操作で解除する。Tier設定は維持する。
- 2026-09-06 22:34受領: wireframeはHTML gistを前提とする。冒頭の旧artifact取得失敗の留保は、発行者のローカルHTML来歴確認とU7解消により更新する。

- ← [[殿指示_LayerHoldingsMonthly本番ページ_20260906_2207]]
- ← [[dm-signal-market-direction-breadth-exposure-asis-tobe_20260905]] v1.1(1 表) ← [[dm-signal-research-data-foundation-asis-tobe_20260905]] F1
- → [[layer_holdings_monthly_本番表]] → [[layer-holdings_page]]
- origin: "[[殿指示_LayerHoldingsMonthly本番ページ_20260906_2207]] -> [[研究1表を本番結果表+API+ページへ]] -> [[p_average_results型の流用]]"
