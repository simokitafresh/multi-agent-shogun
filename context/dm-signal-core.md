# DM-signal コアコンテキスト
<!-- last_updated: 2026-09-01 2026-09-01 将軍doc lane: DOC_LANE_ALERT 4件(偽陽性=marker d87339a4 not ancestor of local clone)。実欠落(showcase API/showcase_events/LP cmd_4431-4437/login minimal/noindex)を追記し境界をorigin/main tipへ -->
<!-- source_commit:172b6d35e7f2 reason:2026-09-01 将軍doc lane: DOC_LANE_ALERT 4件(偽陽性=marker d87339a4 not ancestor of local clone)。実欠落(showcase API/showcase_events/LP cmd_4431-4437/login minimal/noindex)を追記し境界をorigin/main tipへ evidence:git -C /mnt/c/Python_app/DM-signal log d87339a4..origin/main = 88 commits; diff --stat backend/app = 4 files +621; grep反映 showcase_events/api\/public/cmd_4433 各>=1 -->
<!-- source_commit:9734518397066f644bd7c7180bccc276d2bf5947 reason:2026-08-31 06:45 将軍doc lane GA-535: 境界を origin/main tip へ是正(8-hex 旧hotfix markerだと分岐外祖先が非除外で1390/789/1588件の偽ALERT) evidence:git -C /mnt/c/Python_app/DM-signal rev-list --count <tip>..origin/main=0 -->
<!-- source_commit:10d59c8d reason:2026-08-31 将軍doc lane GA-535: §96 contract v3+auth API反映 evidence:grep -c '§96' context/dm-signal-core.md=1(4e705dd2d) -->
<!-- source_commit:d87339a4 reason:T05 shogun doc lane reviewed source boundary (2026-08-26) evidence:git -C /mnt/c/Python_app/DM-signal log <marker>..origin/main: core/ops=研究系(cmd_4372-4376)+記事のみ・core/ops知識変更なし; research=cmd_4372/4374/4376は末尾§へ反映済; frontend=frontend/配下変更は08-17 cmd_4324-4333のみで§28反映済、残りはbackend(ops§100反映済)/記事/研究。ローカルcloneはoriginと履歴分岐(同subject別hash)のためorigin/main tipを境界にする -->
<!-- source_commit:5a5556af reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/dm-signal-core.md commit=5a5556af -->
<!-- source_commit:e7a6c59d reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/dm-signal-core.md commit=e7a6c59d -->
<!-- source_commit:45760ecf reason:GA-490/491 FoF決定性tie-breakシリーズ境界反映(退行復旧再適用) evidence:git -C /mnt/c/Python_app/DM-signal log 46a1f213..45760ecf = 110 commits(source 67件)reviewed。初回=33f3dc7a2、tree退行検出(blt_20260822_144525)により再適用 -->

## Current source boundary (GA-490/491, 2026-08-22)
- **Current source tip:** `45760ecf` = Revert "merge: reconcile rb6 cleanup and cmd_4353/cmd_4354 into main"(reconcile mergeは一旦戻された。rb6 cleanup/cmd_4353-4354の再合流は未了として扱う)。
- durable knowledge(cmd_4334-4356系列): FoF全フィルタの選択部は共通関数 `backend/app/services/pipeline/selection.py::select_top_n_with_ties` へ集約済み(手①/②a/②b/②c)。`include_ties`(既定True=cutoff以上全採用)/`ascending`(既定False)のkeyword-only引数で変わり身(TrendReversalFilter)のtop/bottom両枝も同関数配線(cmd_4337)。6段決定性候補選択(cmd_4339)+tie-break stage availability collection-wide(cmd_4351)+component order安定ソート(cmd_4349)+GS FoF selection parity contract(cmd_4353)。完全同値基準=signals md5+weights md5+signal_change 0(設計書AsIs v1.10、殿裁定2026-08-18 13:02: 保有不変が本質、日々リターンの微小変動は受容)。
<!-- source_commit:46a1f213 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/dm-signal-core.md commit=46a1f213 -->
<!-- source_commit:131e5dbb reason:GA-472 rollback boundary reflected in core context evidence:git -C /mnt/c/Python_app/DM-signal diff --stat 3e28b617 131e5dbb; rollback commit 131e5dbb; §Current source boundary added -->
<!-- source_commit:a9883865 reason:L1分割6手live+L2分割走行中を§94へ反映 evidence:origin/main a9883865 git log; docs/research/dm-l1-split-design_20260815.md AsIs v1.5 -->
<!-- source_commit:3e28b617 reason:cmd_karo_hotfix_rb8_context_freshness_20260814_normal evidence:cmd_4301_context_freshness_AC2_core -->

## Current source boundary (GA-472, 2026-08-17)
- **Current source tip:** `131e5dbb` rolls the production runtime back to restore point `3e28b617`; the §94 L1/L2 live-state notes below are historical pre-rollback evidence and must not be treated as current runtime state until revalidated.

<!-- source_commit:15e612f9 reason:cmd_karo_hotfix_timing_summary_restore_20260813 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-core.md commit=15e612f9 -->

<!-- source_commit:b7067c99 reason:GA-455 content reflection evidence:source frontier review: 40 commits; durable L5/L3/P4/API knowledge indexed in context §0.1 -->
<!-- source_commit:309a8d6c reason:cmd_karo_hotfix_l3_deferred_flush_wall_202608110643 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-core.md commit=309a8d6c -->
<!-- source_commit:4d81c32c reason:cmd_karo_hotfix_ga452_context_boundaries_202608100949 content-reflection evidence:source commits 4d81,c469,aaef,28b58,9f81 reviewed and indexed -->
<!-- source_commit:bda69c42 reason:cmd_karo_hotfix_cmd4284_market_grid_202608100902 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-core.md commit=bda69c42 -->
<!-- source_commit:ec72faa2 reason:cmd_4283 reviewed source boundary evidence:cmd_complete_gate -->
<!-- source_commit:d62065b4 reason:cmd_4282 reviewed source boundary evidence:cmd_complete_gate -->
<!-- source_commit:8e30a242 reason:cmd_karo_ci_fix_dm_signal_run_31326903152 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-core.md commit=8e30a242 -->
<!-- source_commit:a926d06c reason:cmd_4255 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-core.md commit=a926d06c -->
<!-- source_commit:aca163ab reason:cmd_4254 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-core.md commit=aca163ab -->
<!-- source_commit:94cb88bb reason:cmd_4253 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-core.md commit=94cb88bb -->
<!-- source_commit:bf4ed6a6 reason:cmd_4241_reviewed_boundary evidence:backend/app/api/etl_trigger.py+backend/app/jobs/precompute_raw.py -->
<!-- source_commit:16b62fca reason:cmd_4241_reviewed_boundary evidence:backend/app/jobs/precompute_raw_queue.py -->
<!-- source_commit:5b393e7ccd2160778060cc7d5522b32254d72c2e reason:cmd_4234 reviewed no core change evidence:cmd_complete_gate -->
<!-- source_commit:5b393e7c reason:cmd_4234 reviewed no core change evidence:cmd_complete_gate -->
<!-- source_commit:a111173509e7337dcc2e964a83c3ed043b940fd7 reason:Monthly Trade current-month backend row reviewed boundary evidence:43/43 tests; Render live; all 102 PF current month; gunshi APPROVE -->
<!-- source_commit:f1977f8ed3ee4c78344791a8375ff53a161b346a reason:GA-429 reviewed source boundary through detached production investigation HEAD evidence:50 paths reviewed: 4 monthly-boundary runtime paths already indexed, 45 research/evidence paths, 1 restore script; Compare upsert documented separately -->
<!-- source_commit:6f628677362b2ef936d0de5ef2f80e17d00fa944 reason:C-x W4/W5 oracle reviewed source boundary evidence:fixture6/6 pytest1/1 FAIL0 SKIP0 -->
> 読者: エージェント。推測するな。ここに書いてあることだけを使え。
タスクに `project: dm-signal` がある場合このファイルを読め。パス: `/mnt/c/Python_app/DM-signal/`

## 0.1 GA-455 source frontier review (2026-08-11)
- 一次境界: `/mnt/c/Python_app/DM-Signal` `origin/main=b7067c99`。cache無効dashboard gateの未反映source commitは **40件**（last_updated=2026-08-11との差異）。内容確認後、以下の durable knowledge だけを本索引へ反映した。
- L5 cache/data契約: `b7067c99` はcold contextで未初期化cacheを防ぎ、`7bb8b73a` はno-context monthly cache/buildersをPF一括共有、`b65ac45c`/`143f60ad`/`9a09a00a`/`3a0cb44f`/`bcb75220` はno-data `None`をL5 sentinelへ変換してstale rawを残さない。`7d169165` はcache状態を観測可能化、`fd43f7ae` はconfirmed FoF holding_signal cache、`37680998`/`4ea744fb` は狭い再計算で履歴を削らないcleanup guardを追加した。
- L3/P4計測・再利用: `ed8f513d` はFoF間NAV frame cache共有、`2542509c`/`879b2d14` はimmutable snapshotへFoF leaf価格とcontract testを追加、`175e82d8`/`1088595e` はNAV materialization/allocationを最適化。`fb3c5cdd`/`ac017707`/`96aa5d61`/`bda7112b`、`5d931a66`、`72c0f288`/`6e501b63`、`771fba52`/`c76fdac3`/`dcb3b914` はP4/L3/L5の固定phase・subphase・wrapper timingを同一summaryへ帰属する。
- 周辺契約: `09cfa765` はRender debug API露出を閉じ、`31b606c3` はFoF sync後だけL5 enqueue、`f76df2a7` はadmin L5 precomputeをPF単位へ限定、`20a26556` はfull recalculate timing summary schemaを保持、`79971b6c`/`bd9d0dbf` はL5 run lineageを機械結合可能にした。`5de2cbe2` は空FoF monthly calendarを再構築し、`198fc455`/`14d365a8`/`b431b1f9`/`de6b7774` はfallback/MTD/benchmark freshnessを維持する。
- 監査順序（origin/main `git log` 新→旧）: `b7067c99,7bb8b73a,6908c5c8,b65ac45c,5bd7cd1e,198fc455,14d365a8,20a26556,5de2cbe2,1088595e,de6b7774,175e82d8,365e1c8f,c3001c87,09cfa765,b431b1f9,5d931a66,79971b6c,bd9d0dbf,6e501b63,72c0f288,143f60ad,771fba52,c76fdac3,dcb3b914,31b606c3,879b2d14,2542509c,7d169165,9a09a00a,3a0cb44f,f76df2a7,bcb75220,fd43f7ae,37680998,4ea744fb,fb3c5cdd,ac017707,96aa5d61,bda7112b,ed8f513d`。各commitの変更本文・変更pathをsource repoで照合済み。
## 0. 研究レイヤー構造
| Layer | 名前 | 内容 | 状態 |
|-------|------|------|------|
| L0 | 四神 (`pf_L0`) | 個別DM戦略（青龍/朱雀/白虎/玄武）のパラメータGS・検証 | 完了(12体+ノンレバ玄武1=13体) |
| L1 | 忍法 (`pf_L1`) | FoF。L0四神をコンポーネントとし、BB1つで選別→EW。7忍法×3モード=21体 | 完了(21体登録済み) |
| L1+ | 忍法+(構想) | L1のselection blockを複数BB直列に拡張。[BB₁]→[BB₂]→EW。BB₁がL0を絞り、BB₂がその結果をさらに選別。L2チャンピオン21パラメータをBB₂に流用し21×21=441パターンでGSなしにBT検証(殿構想2026-06-22) | 設計中 |
| L2 | 奥義 (`pf_L2`) | 上位構造の堅牢性検証（WF優先。FoFは乗り換え戦略のため時間軸評価が本質。CPCVは補助） | 登録済み(21体) |
| — | 秘奥義 | 激攻/鉄壁/常勝/堅守 | 登録済み(4体) |
| — | DM系 | DM2〜DM7+/DM-safe等 | 9体 |
| — | スタンダード | Ave-X/裏Ave-X/劇薬/basic等 | 7体 |
| — | New FoF | 10D/15D/4M | 3体 |
- **PF総数は変動する。固定値で記憶するな。** 本番DB `SELECT COUNT(*) FROM portfolios` で都度確認（2026-06-08時点: 78体）。接続は [[db-check]] スキル（`create_db_engine()`）を使え。[[psycopg2直接接続禁止]]（DB名不一致エラー実証済み 2026-06-08）。origin: [[殿指摘_PF数変動]] -> [[psycopg2試行錯誤]] -> [[create_db_engine唯一の正解]]
- 2026-04-30: L2奥義21体はcmd_2424で本番hide登録+fullrecalculate完了。登録運用詳細は `context/dm-signal-ops.md` §34。
**Trade-Rule教訓（cmd_766）** — LLMが間違えやすいルール:
- L233: RULE09 Open/Closeは独立計算系列、混在禁止
- L234: RULE10 シグナル判定はClose固定、Openはリターン計算限定
- L235: RULE11 Monthly Trade ReturnとMonthly Returns Returnは完全一致
- L236: 誤解5 リターンは累積インデックス比ではなく価格比×ウェイト
- L237: 誤解6 日次複利積ではなく価格比×ウェイトで月次を出す
- L238: 誤解7 FoFのシグナル参照日は当月初営業日のholding_signal
- L239: 誤解13 Open-to-Openは異なる日のOpen同士を結ぶ
- L240: 誤解14 Open/Closeデフォルト判断はOpen-to-Open
## 1. システム全体像
本番: Render.com — PostgreSQL + FastAPI + Next.js。StockData API毎日01:00 UTC自動同期。viewer/admin認証は in-memory dict ではなく DB-backed token (`viewer_tokens`/`admin_tokens`) + HttpOnly Cookie (`viewer_session`/`admin_session`) が正で、Cookie期限は JST 期限日 23:59:59 を UTC に変換して設定する。参照: `/mnt/c/Python_app/DM-signal/backend/app/auth.py`, `/mnt/c/Python_app/DM-signal/backend/app/api/auth.py`, `/mnt/c/Python_app/DM-signal/backend/app/db/models.py`
2026-05-07: auth token cleanupのcount-based evictionは削除済み。期限切れtokenのみ削除する設計を正とする(cmd_2599, commit 86661769)。
2026-07-02: backend起動時migrationはFastAPI lifespan側の`init_db()`+PostgreSQL advisory lockが正。`render.yaml` startCommandから`python -m app.db.init_db`は削除済み。password rotationはRender env成功tierだけDB commit+token revokeし、tier別失敗で全体rollbackしない。参照: commit `9cc10f27`, `/mnt/c/Python_app/DM-signal/backend/app/main.py`, `/mnt/c/Python_app/DM-signal/backend/app/jobs/password_rotation.py`, `context/dm-signal-ops.md` §46。
ローカル: WSL2 — dm_signal.db(本番ミラー) + experiments.db(分析用ground truth)。
- L500: ガード条件(is_kalman_meta等)除去時は保護していた全変数のスコープと副作用を確認（cmd_1445）
- L501: is_custom_weightガード除去でEqualWeight PFにカスタムweight計算パスが発動する副作用（cmd_1445）
| Layer | 時刻(UTC) | ジョブ | 内容 |
|-------|-----------|--------|------|
| 0 | 01:00 | sync-prices | StockData APIから価格DL |
| 1 | 01:05 | sync-tickers | ティッカーメタデータ同期 |
| 2 | 01:10 | sync-standard | 個別DM戦略シグナル計算 |
| 3 | 01:40 | sync-fof | FoFシグナル計算 |
再計算排他制御: `recalc_status.py`の`threading.Lock`。同時実行不可。409=正常排他(FAILではない)。30秒待って再実行。status timestampはUTC/JST cutoverを明示して書き込む（commit 546565d6）。→ `projects/dm-signal.yaml` (c) recalculate_concurrency
2026-07-09 cmd_3788: Render複数worker下の再計算running判定はDB `recalculation_status`がSSOT。`/admin/recalculate-status`は最新running DB行を見て`source=db`で返し、`/admin/recalculate-sync`はbackground投入前にDB/advisory lock排他を取れない場合409で止める。詳細 → `context/dm-signal-ops.md` §59 / `/mnt/c/Python_app/DM-signal/docs/research/cmd_3788_recalc_status_db_ssot.md`
2026-07-29 commit `3b9327f8`: `POST /admin/recalculate-sync`の任意`end_date`はISO `YYYY-MM-DD`。未指定時は`date.today()`、形式不正・`start_date`以前・未来日はrun予約/lock/business write前に`ValidationError`で停止する。有効値はbackground taskから`recalculate_history_fast(..., end_date=effective_end_date)`へ透過伝播し、accepted responseにも確定`end_date`を返す。運用手順 → `context/dm-signal-ops.md` §84。
p̄バッチ: `p_average_results`テーブルに事前計算結果を格納。バッチ未実行 or cold sleepで空(L319)。p̄ゲート: `gate_p_average_freshness.sh`で鮮度監視。
- L232: recalculate_fast.pyのholding_signal更新は「月変わりANDリバランス月」の2条件で制御される（cmd_764）
### §1.5 Phase間クリティカルデータフロー（OPT変更時必読）
<!-- added: 2026-03-29 cmd_1474/1479のデータフロー依存バグから抽出。検証元: docs/research/fullrecalculate-architecture-2026-03-28.md §2/§6/§7 -->
Phase構成全量 → `docs/research/fullrecalculate-architecture-2026-03-28.md` §2。ここには**OPT変更時に壊れやすい依存**のみ記載。
- 2026-07-29 `f7489c3b`: 既存の`monthly_returns_gen`総時間と返り値を維持したまま、既存JSON timing正本へ`monthly_returns_gen_breakdown`を後方互換追加する。`mr_compute` / `mr_internal_commit` / `mr_caller_commit` / `mr_cache_reload`は各`count`・`sum_sec`・`avg_sec`・`max_sec`を持ち、未計測差分は`residual_sec=max(0, monthly_returns_gen-sum(4区間))`として保存する。
| 上流Phase | 下流Phase | 共有データ | 危険パターン | 事故実績 |
|-----------|-----------|------------|-------------|---------|
| Phase 2 | Phase 3.7/4 | `signal_cache` dict(OPT-6) | in-memory共有。参照のみなら安全 | — |
| Phase 4/4.5 | **Phase 5 FoF** | **DB上のSignalレコード** | flush遅延/deferred→FoF DB queryが空→ゼロ信号 | **cmd_1474**(OPT-13: deferred flush) |
| Phase 2 | **Phase 5 FoF** | `signal_cache`+`holding_signal_raw`(OPT-15) | signal_cacheはbuild_signal_cache_value変換済み(holding_signal or signal)でDB生値と不一致。holding_signal_raw二層cacheが必要(L531) | **cmd_1622**(N+1 query除去) |
| **Phase 5 FoF 1段目** | **Phase 5 FoF 2段目+** | `holding_signal_raw` vs `signal_cache` L519-527 | if/elif排他: preloadでDBの古い日付がholding_signal_rawに入る→cidキー存在→signal_cacheのelif分岐到達不能→2段目ネストFoFが1段目計算結果の新日付を読めない(42件signal未生成) | **cmd_3110**([[LS041]]) |
| Phase 5 FoF | **Phase 5 precompute** | **SQLAlchemy session** | session-bound preload→commit後expire→下流例外→silent skip(PI-018) | **cmd_1479**(portfolio_preload expire) |
| Phase 5 FoF | **monthly_returns** | **momentum_data[weights]** | OPT-A(cmd_1450)で非リバランス日={skipped:true}→weightsキー消失→EWフォールバック(L1067-1070) | **cmd_1568**(Ward/KalmanMeta bimonthly/quarterly。月次FoFは影響なし) |
**原理(PI-019)**: データの見え方(可視性)や生存期間を変える修正では、**全ての下流消費者が新状態を参照できるか**検証せよ。flush/commit/session/cacheの全てに適用。具体例: deferred flush→FoF空(cmd_1474), session expire→precompute失敗(cmd_1479), skipped最適化→weights消失(cmd_1568)
## 2. DB地図
核心ルール(接続先/書込禁止等) → `projects/dm-signal.yaml` (c) database
テーブル詳細(全DB) → `docs/research/core-db-tables.md`
要点: experiments.db=価格ground truth(daily_prices 414K行) | dm_signal.db=本番ミラー(PF設定用) | 本番PostgreSQL=SSOT
- **experiments.db進行中月乖離**(cmd_1567偵察): DL日(3/16)で凍結→本番は日次更新(3/27)。完了月diff=0(計算ロジック同一証明)、進行中月のみ乖離(4.4-7.4%)。Ward FoF+四つ目3PFがexperiments.dbに不在(L512)
### SSOT 3層階層（殿確定 2026-03-11 §25）
| Level | 名前 | 役割 | ファイル |
|-------|------|------|---------|
| L0(データ) | Price table | 全ての原点。営業日=Priceレコード存在日 | — |
| L0(ルール) | trade-rule.md | 理論上の理想形(11絶対ルール定義) | `docs/rule/trade-rule.md` |
| L1a (`calc_L1`) | calculate_monthly_return() | 月次リターンのSSOT関数 | `backend/app/services/return_calculator.py` |
| L1b (`calc_L1`) | calculate_trade_period_return() | Trade期間リターンのSSOT関数（月次複利合成方式 cmd_768） | `backend/app/services/return_calculator.py` |
| L2 (`calc_L2`) | MonthlyReturn table | L1aの事前計算キャッシュ。`recalculate_fast.py`で生成 | — |
| L3 (`calc_L3`) | UI表示層 | L1/L2を使用する派生実装 | — |
→ `projects/dm-signal.yaml` ssot_hierarchy
UUID不一致: DM7+以外は2DB間でUUID異なる（§3参照）
DLコマンド: `download_all_prices.py grid-search`(価格) | `download_prod_data.py monthly-returns`(月次)。`prices`は422エラー(cmd_042)
- L156: pending判定のas_of基準は2系統存在する: DB最新日(signals) vs date.today()(monthly-trade)（cmd_524）
- L171: バッチジョブのUPSERTはdb.merge()パターンが最も簡潔（cmd_550）
- L172: 新規テーブル導入時はインデックス作成をif/else外に置くと自己修復性が上がる（cmd_550）
- L173: パイロット→本番移植ではDB層分離がパリティ検証を容易にする（cmd_550）
- L296: 履歴特徴量系の新手法を入れる前にsnapshot SSOTを埋めよ（cmd_861）
- L420: monthly_returnsテーブルにはmonthly_return(Close)とmonthly_return_open(Open)の2列。GSはOpen-to-Open方式。パリティ検証はmonthly_return_open列を使うこと（cmd_1098）[PI-008]
## 3. 四神（しじん）構成
**★ 設計原理（殿直伝 2026-03-15 — 全エージェント必読、すべての検討の前提条件）**
**L0概念（最重要）**: 単一銘柄=受動的価格系列（判断なし）。DM PF=意思決定が埋め込まれた価格系列（市場+アルゴリズム判断の合成物）。DM-SignalはこのDM PFをL0として扱う。論文手法をそのまま適用できるケースはほぼない——意思決定システムの出力であることを常に意識せよ。モメンタム(二階微分)・相関(時変)・forward-looking(多変数)・最適化(二重化)・性能分解(因果不明)の全てが受動的資産と異なる。
源流はDM2+/DM3/DM6/DM7+の4ファミリー。四神はここから生まれた。
- **absolute assetが戦略のDNA**: ファミリーを定義し、戦略の性格を決定する
- **全パラメータが一体で一つの意味を成す**: lookback/rebalance/relative/safe_havenを個別に見ても本質は掴めない
- **3モード(激攻/鉄壁/常勝)はDNA内の味付け**: absolute+relative+safe_havenは不変。源流の性格は変わらない
| 源流 | Absolute | DNA（不変の性格） | 全パラメータの統一意思 |
|------|----------|-------------------|---------------------|
| DM2+ | LQD(安定債券) | **降りない** | LQD基準で退避ほぼ不発動+XLU退避=株内残留+12M複合窓でノイズ平滑化。常時リスクオン |
| DM3 | TMF(3倍債券) | **債券方向スイッチ** | TMF=ゲートセンサーであり保有しない(本番実測: TMF保有0日、2026-07-06確認)。TMF絶対モメンタム(vs DTB3, 20D)合格=相対選択のTECL/TQQQ保有、失格=TMV保有。実保有の切替はTECL/TQQQ↔TMV。bimonthly_oddが3倍レバの過剰切替を制御。債券でアルファ |
| DM6 | ^VIX(恐怖指数) | **レジーム判定** | VIXで恐怖の上下を検知。15D観測(最速)×quarterly行動(最遅)でノイズ除去。GLD=恐怖時の第三軸 |
| DM7+ | SPXL(3倍S&P) | **構造的逆張り** | 攻守逆転(relative=XLU守り,safe_haven=TQQQ攻め)+24M窓。短期暴落を無視し最攻撃ポジション維持 |
**⚠ よくある誤解（一般常識の暗黙の前提で四神を判断すると全て間違える）**:
- SM01: safe haven=防御的→玄武のTQQQは最大火力。SM02: 3倍レバ=長期不適→四神の核心設計
- SM03: 暴落時=退避→青龍は「降りない」がDNA。SM04: 危機=債券→朱雀はTMV(債券ショート)
- SM05: VIX高=危険→DM6は方向(上昇/下降)を見る。SM07: 短lookback=良→DM7+は鈍さが本質
- SM08: ラベル信頼→玄武「リセッション防御」は実態と真逆。SM09: CAGR最低=劣→低相関が価値
- SM12: SPY/QQQ(非レバ)=安全→DM2+のLQD常時保有でレバが活きる。非レバは設計の無駄遣い
- **思想レベル**: SM13: 動的ウェイト最適化→メタ最適化=過適合。SM14: 10PFを1完璧PFに→過適合(殿明確否定)
- SM15: 好成績に集中/悪成績を外す→低相関を捨てる。SM16: 4神一致で行動→1戦略に縮退
- SM17: 忍法=四神の上位互換→レイヤーが違う。SM18: 神同士のシグナル制御→独立性破壊
- SM19: 動的配分=高度→殿哲学は真逆(不可知→単純保有)。SM20: BB増=精度↑→シンプルBBがGSチャンピオン
- **根源**: SM21: DM PFを単一銘柄と同じに扱える→受動的資産vs意思決定システムの出力。SM13-SM20の全根源
- 全21件の詳細 → `projects/dm-signal.yaml` (e) common_misconceptions_shijin
- **計算と解釈の分離原則（殿裁定 2026-03-16）**: 評価指標（p̄, CPCV等）は全PFに一律で計算し、結果はそのまま記録する。計算結果をどう解釈・運用するかは別レイヤーの人間判断。朱雀がp̄で高く出ても/CPCVで不合格でも、それは「単独システムとしての一貫性がない」という事実であり、素材としての価値否定ではない。四神は素材であり、FoFが動的に組み合わせる完成品。素材レベルで一貫性を要求するのは設計思想と矛盾する。**CPCVやp̄の結果が悪いからFoFに使わない、は誤用。**
- **殿の指標哲学(2026-03-16裁定)**: 体験→指標→道具の順で設計。Sharpe/σ後回し。優先4指標: Max Run-up / Tail Contribution / Left-tail Jumps / NHF。「平均は悪、極値が全て」
- **辞書フィットネス**: ◎M03(Rank Persistence) ○→◎M10(DSR→CAGR/NHR差替) △→○M05(HMM→市場適用) △M09(PSR=Sharpe衝突) ×M08(Meta-Labeling=再訓練なし)
- 詳細 → `projects/dm-signal.yaml` (f) indicator_philosophy + dictionary_fitness
詳細設計・DNA制約・誤解リスト → `projects/dm-signal.yaml` (e) shijin
### 旧四神(v1: cmd_246時代 — FoF構成) ⚠ ディスコン
> **v1(191,796パターン広探索→CPCV→32ユニット方式)は全廃。シン四神v2に移行済み。**
> 以下は記録として残置。新規タスクではシン四神v2を参照せよ。
四神 = 各DMファミリー全パラメータ総当たりGS(172,818パターン) → GFS → チャンピオン戦略均等配分FoF。
| 四神 | 構成 | チャンピオン戦略 | FoF CAGR |
|------|------|----------------|----------|
| 青龍 | DM2 FoF n=3 | Qj_GLD_10D_T1, Qj_XLU_11M_5M_1M_w50_30_20_T1, Be_GLD_18M_7M_1M_w60_30_10_T1 | 59.5% |
| 朱雀 | DM3 FoF n=2 | M_TMV_4M_3M_20D_w50_40_10_T1, Qj_TMV_3M_15D_w50_50_T1 | 40.0% |
| 白虎 | DM6 FoF n=2 | Qj_XLU_15M_3M_w70_30_T2, Qj_GLD_4M_1M_w50_50_T1 | 54.7% |
| 玄武 | DM7+ Prod n=1 | M_SPXL_XLU_24M_T1 | 29.5% |
選定: GFS(CAGR最大化順次追加) | 堅牢性: SUSPECT検出 | 参照: portfolio-research/015→023§2.3
### シン四神v2（cmd_1018-1080: L1 standard PF）— 現行
旧v1を全面廃止。DNA事前制約→データ駆動lookback→3モードチャンピオン直接選出。
**12スロット設計**(4ファミリー×3モード)。GS結果(cmd_1018)では重複吸収後**10体**。
朱雀・玄武は激攻=常勝が同一変種→常勝消滅。
登録形態: **L1 standard PF**（旧四神のFoF構成とは異なる）。
シン忍法v2(21体)はこの10体を材料として構築。
確定パラメータ・DNA制約根拠・データ分析 → `context/dm-signal-research.md` §27
⚠ 登録進捗はチェックリスト参照→`context/checklist-shin-v2-registration.md`
### 命名規則（殿裁定 2026-02-20）
L1四神FoF: {モード}-{四神名}（激攻-青龍等） | L2忍法FoF: {忍法名}-{モード}（加速-激攻等）
モード: 激攻(CAGR) / 鉄壁(MaxDD) / 常勝(NewHigh)。旧サフィックス廃止。同一config→忍法名のみ
※ 智将(Calmar)→鉄壁(MaxDD)変更理由: Spearman相関分析でCalmarはCAGRと高相関(rho=0.86)で冗長。MaxDDはCAGRと低相関(rho=0.49)で独自軸
シン四神v2確定: 4神×3モード=12スロット（吸収後10体）。旧四神(激攻のみ4体FoF)はディスコン
L2忍法FoF: 5忍法×3モード=最大15体。monban除外(ext_pricesのCSV化に追加設計必要)。nukimi_c→nukimiに統合(L054)
cmd_246完了: 12体チャンピオン本番DB登録済み。全0.00bp PASS。PF総数89(上限100)
新忍法候補: 逆風(cmd_249採用決定)/追い越し(cmd_250)/四つ目(cmd_284フルGS完了) → §4新忍法候補参照
⚠ L1/L2混同禁止: L1=神の中身(GSパラメータ) | L2=神の組み合わせ(BB)
- L262: recursive FoF expanderはroute層からrequest-scope cacheを注入しない限りquery storm化する（cmd_830）
- L269: FoF request-scope cacheのkeyはauth→portfolio_id+signal_dateに寄せ、maskingはroute後段に隔離せよ（cmd_834）
### L2忍法チャンピオン（cmd_246完了 — 全12体 0.00bp PASS）
全5忍法ミニパリティ0bp確定(cmd_227)後、4忍法フルGSを実行。
| 忍法 | パターン数 | 備考 |
|------|-----------|------|
| 追い風 | 42,174 | tiebreak修正後コードで再実行 |
| 抜き身 | 152,295 | — |
| 変わり身 | 28,116 | — |
| 加速 | 238,986 | — |
| 分身 | 781 | cmd_214完了済み(EqualWeight) |
合計: 462,352パターン。
| 忍法 | 激攻(CAGR) | 鉄壁(MaxDD) | 常勝(NHR) |
|------|-----------|------------|----------|
| 追い風 | 64.85% / 18M,N1 | -15.87% / 18M,N2 | 64.56% / 9M,N3 |
| 抜き身 | 74.21% / 18M,SK3,N1 | -15.51% / 18M,SK1,N1 | 65.73% / 24M,SK1,N4 |
| 変わり身 | 62.25% / 24M,N1 | -13.51% / 24M,N1 | 65.7% / 24M,N2 |
| 加速 | 76.27% / 10D/4M,ratio,N1 | -14.47% / 9M/10M,diff,N1 | 66.03% / 18M/24M,ratio,N1 |
詳細（UUID・構成四神・パリティ月数）→ `queue/reports/hanzo_report.yaml` (cmd_246 AC5)
### ポートフォリオ一覧
UUID・銘柄構成・リバランス設定 → `projects/dm-signal.yaml` (e) shijin。全銘柄: GLD|LQD|SPXL|SPY|TECL|TMF|TMV|TQQQ|XLU|^VIX
| 四神 | dm_signal.db UUID | experiments.db UUID | 戦略 |
|------|-------------------|---------------------|------|
| 青龍(DM2) | f8d70415 | 4db9a1f5 | ロング株式 |
| 朱雀(DM3) | c55a7f68 | 8300036e | ロングVol/債券 |
| 白虎(DM6) | 212e9eee | a23464f7 | VIXレジーム |
| 玄武(DM7+) | 8650d48d | **8650d48d(同一)** | リセッション防御 |
シグナル生成(例DM2): MomentumFilter(top1) → AbsoluteMomentum(LQD>DTB3?) → SafeHavenSwitch(空→XLU) → EqualWeight → signal
- L325: FoF valid_start_dateとdownstream warm-upは別物。valid_startはselection block lookback考慮、warm-upはcash初期化期間（cmd_1003）
## 4. ビルディングブロック
パス: `backend/app/services/pipeline/blocks/` | BlockType enum: `schemas/pipeline.py` | 登録: `shared.py`
標準パターン → `projects/dm-signal.yaml` (d) pipeline
全14種BBパラメータ詳細・選出方式 → `docs/research/core-param-catalog.md`
### BB種別分類（cmd_247）
| 区分 | BB名(BlockType) | 対応忍法 |
|------|----------------|---------|
| 採用 | MomentumFilter / SingleViewMomentumFilter / TrendReversalFilter / MomentumAccelerationFilter | 追い風 / 抜き身 / 変わり身 / 加速 |
| 採用 | AbsoluteMomentumFilter / EqualWeight | 門番 / 分身(全忍法terminal) |
| 補助 | SafeHavenSwitch | 門番補助 |
| 採用 | ReversalFilter → **逆風**(cmd_249採用決定) / MultiViewMomentumFilter → **四つ目**(cmd_284フルGS完了) | シン忍法v2で7忍法体制確定 |
| 採用 | WeightedMultiViewMomentumFilter → **重み付き四つ目**(cmd_3384) | 4視点投票数比例ウェイト。奥義-GS-新四つ目(激攻/鉄壁/常勝)3体登録(cmd_3389) |
| 採用 | WardTwoStageEW → **Ward二段EW**(cmd_1437/1443/1444) | ネステッドFoF terminal。Ward階層クラスタリング+二段均等加重。本番稼働中(旧忍法-Ward) |
| 未採用/削除済 | MonthlyReturnMomentumFilter / PBarSelectionBlock / RelativeMomentumFilter / KalmanMeta | WP-2でdead endpoints・未使用BBとして削除済み(commit d1bc8b22)。古い調査結果を実装前提にしない |
| 未採用 | ComponentPrice / CashTerminal | インフラ/スケルトン |
- L151: OPEN/CLOSE切替導入時はbenchmark側の*_open適用も同時チェック必須（cmd_507）
- L154: OPEN/CLOSE切替修正ではbenchmark側の*_open参照を全ビューで同時点検する（cmd_522）
- L318: p̄(richmanbtc式)は安定型(青龍)を構造的に優遇し、スイッチ型(朱雀/TMF-TMV)を排除する（cmd_981）
- L320: p̄検定は朱雀(DM3)のDNA「債券方向スイッチ」と構造的に不適合（cmd_981）
- L599: TrendReversalFilterBlockのinsufficient_candidates early returnでcurrent_tickersが残りbatch不一致（cmd_1837）
- 2026-07-06 cmd_3707: AbsoluteMomentumFilter reference_asset modeに`threshold_band`三状態(pass/band/fail)を追加。band内はSafeHavenSwitchで相対選択資産50%+safe_haven_asset50%の`context.final_weights`を設定し、`recalculate_fast.py` vectorized経路も`momentum_data.weights`へ同等payloadを保存。未指定PFは従来二値判定のまま不変。研究根拠: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3705_absolute_momentum_band_study.md`。
### tiebreakルール（cmd_217, L086/L092）
| 方式 | 対象忍法 | 動作 |
|------|---------|------|
| cutoff_score全包含 | 追い風・抜き身・加速(+MultiView/MonthlyReturn) | 境界同点を全採用(top_n超過許容) |
| strict slice | 変わり身・逆風 | 厳密N件切出し |
L092: float64同値タイ→ハイブリッド方式(desc/asc別ソート+重複時desc単一リスト両端スライス)
GS修正経緯(cmd_215→217): cmd_215でtop_n同点パリティ差分検知→cmd_217で方式差(cutoff_score vs strict slice)確定。追い風=commit `9277881`修正済み/加速=cutoff_score適用済み/抜き身=cmd_217 Phase3で修正継続
### GS-本番パリティ統一原則（cmd_229: PD-011/012/013）
- 全4忍法は**cumulative_return→pct_change方式**で統一。旧monthly_return方式禁止(PD-013)
- 504日分の日次データが揃うまでCash扱い(PD-011)。長lookback(12M/24M)で差異顕在化
- モメンタム算出は`cumulative_return`から`pct_change(mc)`。本番同一コードパス優先(PD-012/L076)
- 教訓詳細→§19.3(L086-L092)
### SVMF/MVMFバグ修正（cmd_235 + cmd_244）
| cmd | 問題 | 修正 | commit |
|-----|------|------|--------|
| cmd_235 | `is_monthly_data()`未使用→行数ベース誤判定(L097) | skip前に呼出 | a6ba012 |
| cmd_244 | SVMF fallback `target_date`未フィルタ→将来データ参照(L098) | `index<=target_date`追加 | 2e970ed |
影響PF: MIX2/3/4(SVMF)+bam-2/6(MVMF)。修正後5PF全PASS。
### 新忍法候補（2026-02-22 偵察開始）
| 忍法候補 | BB型 | 状態 | cmd | 主要パラメータ |
|---------|------|------|-----|-------------|
| 逆風(gyakufuu) | ReversalFilterBlock | 採用決定 | cmd_249 | bottom_n(B1-B5), lookback。strict slice |
| 追い越し(oikoshi) | RelativeMomentumFilterBlock | 偵察完了 | cmd_250 | benchmark=SPY固定(殿裁定PD-023: 複数候補不採用), lookback |
| 四つ目(yotsume) | MultiViewMomentumFilterBlock | **フルGS完了** | cmd_284 | base_period(≥4), top_n。SKIP=[0,1,2,3]固定 |
### パイプライン実行・シグナル
`PipelineEngine.execute_pipeline(pipeline_config, target_date, initial_tickers, price_data_cache, momentum_cache)` → `{signal, momentum_data, block_results, weights}`
PipelineContext(黒板): `current_tickers`(絞込) / `momentum_data`(各BB結果) / `final_weights`(Terminal配分)
- **2026-07-12 cmd_3856(P3a共通executor統合)**: 標準PF(非FoF)のselection→terminal決定は`backend/app/services/pipeline/executor.py`の純粋関数`execute_pipeline_semantics()`が新SSOT。Engine adapter(`execute_pipeline_with_blocks`)とvectorized batch adapter(`recalculate_fast.py`)が同一実装を共有し、旧独立実装`_compute_pipeline_signals`はbackend全域で参照0件(全廃)。**射程外**: FoF専用ブロック(ComponentPrice/MultiView/SingleView/TrendReversal/WardTwoStageEW)は`recalculate_fof.py`が呼ぶ上記`PipelineEngine.execute_pipeline`を無変更のまま使用(統合対象外)。P1a〜P2b(source identity/manifest/RSS cap/oracle契約修正)はrecalculate_fast.py内の検証ハーネス・運用robustness改修でありcore不変量への影響なし。詳細 → `context/dm-signal-research.md` §54 + 因果リンク`[[cmd_3856_P3a_common_executor]]`、DM-Signal `docs/research/cmd_3856_p3a_common_executor.md`、設計書`docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.11 §7.5
**signal**: パイプライン生出力 | **holding_signal**: リバランス月でなければ前月維持。MonthlyReturnはholding_signalで計算せよ
- L419: fof_component_weightsフラッシュ未配線(全FoF影響)。flush関数実装済みでもrecalculate_fof.pyのimport+呼出がなければ永久に空（cmd_1096）
- L421: flush関数の実装+exportだけでは不十分。呼出元のimport+呼出コードが存在するか二値チェック必須（cmd_1101）
- L423: FoF BBシミュレーションM-1オフセット必須（cmd_1102）
- L427: resample(ME).last()はカレンダー月末を返す。実取引日との差異がシグナル帰属ズレを引き起こす（cmd_1115）
- L428: valid_start_date計算は全構成シンボル(relative+absolute+safe_haven+DTB3)を含めよ（cmd_1115）
- L429: パリティ検証における非決定的順序とpartial-month初月の扱い（cmd_1116）
- L258/L259: try/exceptフォールバックでbulk preload+mock DB両立（cmd_820）
- L506: OPT変更時は既存preloadのexpunge戦略を確認せよ（cmd_1479）
- L507: lazy-loaded cache forward-fillは危険。OOM/データ汚染の原因（cmd_1481）
- L508: silent fallbackパターン禁止(PI-018)。例外→デフォルト値フォールバックは問題を隠蔽する（cmd_1483）
- L531: build_signal_cache_valueのholding_signal or signalフォールバック注意（cmd_1622）
- L555: load_all_monthly_returnsはholding_signalも取得必須。KeyError防止（cmd_1743）
- L573: FoF月次キャッシュをdictに変えるときもlookupはbisect helper統一（cmd_1787）[PI]
- L574-L578: FoF選択block(**全5種: MVMF/SVMF/MomentumFilter/TrendReversalFilter/MomentumAccelerationFilter**)のmonthly pathでexact dict lookupするとbiz day/月末日ミスマッチでCash全損。Series+bisect必須（cmd_1786。**TRF/MAF追加: cmd_1899で12体Cash100%事故**）[PI:L573同根]
- L627: 横展開漏れ検出: コード修正時にgrep同パターン全ファイル確認必須。TRF/MAFが04f74830 bisect修正で漏れた実例（cmd_1899）
- L630: dict.get(target_date)禁止: blocks/内はbisect helper統一（cmd_1899）[PI:L573同根]
## 4.5 GS用語定義（混同厳禁）
| 用語 | 意味 | 実体 |
|------|------|------|
| 狭義GS（四神作成スクリプト） | パラメータ総当たり→チャンピオン選定 | `shin_shijin_l1_gs.py` |
| 忍法スクリプト（7本） | 四神12体をコンポーネントとしてFoFを構成・計算。1本=1ビルディングブロック | `run_077_*.py` |
| GS（広義） | `scripts/analysis/grid_search/` 全体 | 狭義GS + 忍法スクリプト7本 + 共通ライブラリ |
流れ: 狭義GS → シン四神12体 → 忍法スクリプト7本 → シン忍法v2 21体
スクリプト詳細一覧 → `projects/dm-signal.yaml` key `gs_ninpou_scripts`
## 5. ローカル分析関数
`simulate_strategy_vectorized()`: `grid_search_metrics_v2.py`。MomentumCache必須(渡さないと黙って空リスト)。
月次リターン: 月末シグナル→翌月適用。Return=(月末価格/月初価格)-1。マルチアセット=単純平均。
詳細(全パラメータ・スケジュール) → `docs/research/core-local-analysis.md`
- L260: 上流の件数制限はprecomputed queryとfallback queryの両方へ必ず伝播させる（cmd_829）
- L264: precomputedテーブル存在時はraw再計算APIを残さずfast pathを導入せよ（cmd_830）
- L271: years付きmonthly fast pathは境界月だけdaily fallbackを残すと完全一致と高速化を両立できる（cmd_833）
- L317: MetricsCalculator右尾4指標は実装済みだがFE未露出（cmd_976）
- L497: R2 Ward selection reuse via compute_monthly_selections。存在しない関数をimportするな（cmd_1413）
### §5.5 Robustness / Continuity Metrics (2026-06-25)
| 領域 | 現状 | 根拠 |
|------|------|------|
| alpha6 robustness | `scripts/analysis/grid_search/robustness_common.py` がalpha6/continuity系指標を返す。L0/SPY foundation、L1/L2/L3 trial系CLIは同共通関数を経由 | commits `063e17c9`, `2c7aa1f1`, `2fe6671a`, `46a7aafc` |
| continuity risk API | `backend/app/api/metrics.py` / `backend/app/services/metrics_impl.py` はContinuity Risk指標をmetrics payloadへ追加済み。互換テストは `backend/tests/test_metrics_continuity_risk.py` | commit `eaf2741d` |
| compare benchmark capture | compare summaryのadditional benchmark取得はmetrics API側でSPY/TQQQ等のbenchmark captureを補強済み | commit `499bfe37` |
- L775: monthly_df_cache渡しbenchmarkモードではDrawdownPeriodテーブルをスキップせよ（cmd_3532）
- L781: pd.to_datetimeはリスト内包個別呼出し禁止、リスト一括ベクトル化呼出し（cmd_3539）
## 8. APIエンドポイント概要
FastAPI 22ルーター/84-88EP | Next.js frontend | 共通: `ApiResponse{success,data,error,message}`。FE `api-client.ts` は TTL付きGET (`annual-returns`/`monthly-returns`/`rolling-returns`/`monthly-trade` 等) で auth-scope込み `cacheKey` を生成し、保存済みETagを `If-None-Match` 送信、`304 Not Modified` は成功扱いで保存済みpayloadへ復元する。参照: `/mnt/c/Python_app/DM-signal/frontend/lib/api-client.ts`
主要: `/api/signals` `/api/portfolios/get|save` `/admin/recalculate-sync` `/healthz` | Admin保存バリデーション分析: [[cmd_1753_validation_analysis]]
詳細(全EP・レスポンス構造) → `docs/research/core-api-endpoints.md` | yaml → `projects/dm-signal.yaml` (h) api
- L153: signals APIのpending判定はrebalance_trigger共通化しないとFoF/非月次で表示不整合が起きる（cmd_515）
- L174: 最新+前月比較APIは『前月年月サブクエリ→同テーブル再JOIN』でN+1を回避できる（cmd_550）
- L176: 一覧トレンド判定は前月ラベルだけでなく前月p12をAPIで同時返却しないとB4を満たせない（cmd_552）
- L246: months引数の件数制限は末尾sliceだけでなく下流queryまで通せ（cmd_782）
- L252: PriceCacheパターン横展開がN+1最適化の最安全手法（cmd_806）
- L254: FoF展開共通関数のcache未注入でquery storm化する（cmd_806）
- L255: ticker precompute欠落時のfallbackはmonths windowをPrice queryへ必ず伝播させる（cmd_805）
- L257: Monthly Trade raw payload: Pydantic未宣言fieldもAPI contract（cmd_819）
- 2026-07-09 cmd_3787: Monthly Trade検証用リターン計算はticker/価格欠落時に部分加重和で続行せずfail-closedする。`_calculate_return_from_price_movement()`は`missing_tickers`を返し、欠落時は`calculated_return=None`。FE/API型にも`missing_tickers`追加。詳細 → `context/dm-signal-ops.md` §58 / `/mnt/c/Python_app/DM-signal/docs/research/cmd_3787_monthly_trade_missing_ticker_fail_closed.md`
- L310: apiCache.clear()はETag IDB未削除→304エラーの可能性。汎用clear()は未対応（cmd_962）
- L311: isRetryableError()はHTTP 5xx未対応→Render cold start 502/503で即エラー表示（cmd_962）
- L314: CORS expose_headersなしではFEがカスタムレスポンスヘッダを読めない（cmd_964）
- L315: Payload cache+validator cache分離構成ではinvalidatorが両層同時破棄必須（cmd_964）
- L412: BE定数変更時はFE定数(frontend/lib/constants.ts)も必ず確認・同期せよ（cmd_1079）
- L769: α6キー名はAC文言と実装SSOTを事前照合せよ（cmd_3518）
### §8.5 Deterioration Benchmark Layer (2026-06-25)
`/api/deterioration` はSPY/TQQQ benchmark return、P(det) benchmark表示、page visibility enforcementを追加済み。DB正本は `backend/app/db/models.py` / `backend/app/db/migrations.py`、計算正本は `backend/app/services/benchmark_returns.py` と `backend/app/services/deterioration_benchmarks.py`、batch連携は `backend/app/jobs/deterioration_batch.py`。根拠: commit `59146c43`、spec `docs/spec/deterioration-benchmark-extension.md`。
### §8.6 Compare Returns / MTD SSOT (2026-06-27)
`/api/compare-returns` は全visible PF + standalone benchmark(SPY/TQQQ等)のMTD/1M/3M/6M/1Y/3Y/5Y/ALLをclose/open両系列で返す。PF MTDは`backend/app/services/mtd_returns.py`が`/api/mtd`とCompare Returnsの共通SSOTで、Compare Returnsは`build_compare_mtd_values_batch()`でN+1を避ける。page visibilityは`backend/app/services/page_visibility.py`が`settings.hidden_pages`と`global_visibility_settings.hidden_pages`のunionを正とする。根拠: commits `46e1b48c`, `646216d5`, `09796aee`, specs `docs/spec/compare-returns-page.md`。
cmd_3572でMTD事前計算テーブル`precomputed_mtd`、`backend/app/jobs/precompute_mtd.py`、`recalculate_fast.py`末尾連携、API側fresh判定+PF/BM単位fallbackを実装済み。DB DATE→API ISO境界とprecomputed/fallbackパリティは`backend/tests/test_compare_returns_api.py`で検証。根拠: commit `9b3618ae`, spec `docs/spec/compare-returns-mtd-precompute.md`。
2026-07-15 commit `07305b83`: `precomputed_mtd.current_ym`と価格日が一致しても`mtd_close=NULL`ならfreshではない。NULLは計算済み値ではなくbatch算出不能を表すため、`is_precomputed_fresh()`はfalseを返してLIVE計算へfallbackする。これによりFoF 78PFのCompare Returns MTD N/Aを解消し、非NULLのStandard 24PFは従来経路を維持する。
### §8.7 Fusion API (2026-06-28)
`/api/fusion/portfolios` は外部Fusionアプリ向けのadmin認証専用エンドポイント。`is_active=true`かつ`hide_portfolio=false`のPFだけを対象に、`id/name/type/folder`と確定済み`monthly_returns[{year_month, return}]`のみを返す。当月・null monthly_return・config/holding_signal/ticker/weights/cumulative系は禁止。2026-07-03 `cmd_karo_ci_fix_dm_signal_20260703`で、`hide_portfolio=true`のPFが混入する回帰を修正し、この除外条件を再確定。10/min rate limitと11回目429テストあり。根拠: commits `288f0e36`, `314b596a`, `a3a854ba`, `b73e5656`, spec `docs/spec/fusion-api-endpoint.md`, test `backend/tests/test_fusion_api.py`。
### §8.8 Rolling Returns API/Table (2026-07-01)
Rolling Returns summary tableは`3_months`/`6_months`/`1_year`/`2_years`/`3_years`/`5_years`/`7_years`/`10_years`を返す。3M/6Mは年率換算せず、期間内のraw compound returnを表示する。根拠: commits `86348160`, `5883fb01`, `/mnt/c/Python_app/DM-signal/backend/app/jobs/generators/rolling_returns.py`, `/mnt/c/Python_app/DM-signal/backend/app/services/rolling_returns_calculator.py`, `/mnt/c/Python_app/DM-signal/frontend/components/rolling-returns-summary-table.tsx`。
2026-07-22 `96c8c5f5`: Rolling Returnsに期間別distributionを追加。DB/API生成は`backend/app/jobs/generators/rolling_returns.py`と`backend/app/services/rolling_returns_calculator.py`、表示は`frontend/components/rolling-returns-distribution-table.tsx`が正本。
2026-07-24 `61848453` cmd_4114: sample_count/positive_rate contract tests追加(4テスト PASS)。Rolling Returns Phase1実装完了。
## 10. ディレクトリ構成
詳細ツリー → `docs/research/core-directory-structure.md`
主要: backend/app/(api|services/pipeline|jobs|db|schemas) | frontend/lib/ | scripts/analysis/grid_search/ | analysis_runs/experiments.db
- L168: 未使用判定はimport探索と呼び出し探索を分離すると誤検知が減る（cmd_548）
## 11. Lookback標準グリッド（恒久ルール）
18パターン基本探索範囲。換算: 1M=21営業日。
| # | 値 | 営業日数 | # | 値 | 営業日数 | # | 値 | 営業日数 |
|---|-----|---------|---|-----|---------|---|-----|---------|
| 1 | 10D | 10 | 7 | 4M | 84 | 13 | 10M | 210 |
| 2 | 15D | 15 | 8 | 5M | 105 | 14 | 11M | 231 |
| 3 | 20D | 20 | 9 | 6M | 126 | 15 | 12M | 252 |
| 4 | 1M | 21 | 10 | 7M | 147 | 16 | 15M | 315 |
| 5 | 2M | 42 | 11 | 8M | 168 | 17 | 18M | 378 |
| 6 | 3M | 63 | 12 | 9M | 189 | 18 | 24M | 504 |
既存パラメータがこの18点のどれに該当するか常に明示。カバレッジマップでは探索済み/未探索を示せ。
## 13. StockData API
エンドポイント: `stockdata-api-6xok.onrender.com` | クライアント: `backend/app/client.py`
環境変数: `STOCK_API_BASE_URL` | リトライ3回(指数バックオフ) | タイムアウト60秒 | ローカルDL: `download_all_prices.py grid-search`
- L496: /v1/economic/{symbol}は1リクエスト最大1000件。長期経済データ取得時にページネーション必須（cmd_1412）[PI-017]
## 15. 殿の個人PF保護リスト（絶対ルール — cmd_198）
> DB操作(DELETE/UPDATE)タスクでは以下のPFを**絶対に削除・変更してはならない**。
**Standard PF(21体)**: DM2, DM2-20%/-40%/-60%/-80%/-test/-top, DM3, DM4, DM5, DM5-006, DM6, DM6-5/-20%/-40%/-60%/-80%/-Top, DM7+, DM-safe, DM-safe-2
**FoF PF(13体)**: Ave-X, 裏Ave-X, MIX1-4, bam-2/-6, 劇薬DMオリジナル/スムーズ/bam/bam_guard/bam_solid
~~Ave四神~~: 2026-03-11時点で本番不在（削除済み）
削除許可: L0-*(GS生成) / 四神L0(12体) / 忍法L1(20体) のみ
運用: DB操作タスクのdescriptionに「殿PF除外」明記必須 / dry-runで残存PFリスト確認してから本削除
詳細→`projects/dm-signal.yaml` protected_portfolios
## 18. backend `folder_id` 実態（cmd_269, 2026-02-23）
| 観点 | 内容 |
|------|------|
| カラム | `Portfolio.folder_id`: String, nullable, FK→`portfolio_folders.id`(ON DELETE SET NULL) (`models.py:75`) |
| マイグレーション | Alembicなし。起動時処理(`migrations.py:66-79`作成, `:87`追加) |
| 使用箇所 | 定義: `models.py:75` / 参照+更新: `api/folders.py:77,104,213,251,304` |
| Schema | `Portfolio`スキーマに`folder_id`なし。CRUD未対応。更新は`folders.py:283-309`のみ |
| 本番実値 | 全88PFが`folder_id=NULL` |
## 19. 教訓索引（Lesson Index）
<!-- cmd_286: lessons.yaml 50件から core該当28件を索引化 -->
### 19.1 DB関連
| ID | 結論(1行) | 出典 |
|---|---|---|
| L084 | `recalculate-status`の`is_running=None`は完了ではない。DB行数カウントで判定せよ | cmd_215 |
| L085 | テストPF削除のFK依存は16テーブル。4テーブルだけでは不足 | cmd_215 |
| L099 | `pipeline_config LIKE '%ReversalFilter%'`はTrendReversalFilterを誤検知→`jsonb_path_exists`で解決 | cmd_222 |
| L118 | DTB3は`economic_indicators`ではなく`daily_prices`テーブルに`ticker='DTB3'`として格納 | cmd_282 |
| L119 | DATA_CATALOG 86銘柄は本番PostgreSQL側。`experiments.db`は実際14銘柄のみ(ETF12+DTB3+VIX) | cmd_282 |
| L124 | DB JSONカラムのstr型防御: `isinstance(value, str)+json.loads()`。`or {}`はtruthy文字列で発火しない | cmd_296 |
| L128 | `experiments.db`はスナップショットでありSSOTではない | cmd_222 |
| L511 | fof_component_weightsのactual_weight/driftがNULL(未計算状態)。Admin画面ウェイト未表示の根因 | cmd_1566 |
| L512 | experiments.db進行中月データは日次更新本番と構造的に乖離する(完了月diff=0、進行中月のみ4-7%差) | cmd_1567 |
| L640 | DB経由データのCoDD最適化検証では同一プロセス・同一データで比較せよ | cmd_2152 |
### 19.2 BB仕様・バグ修正
| ID | 結論(1行) | 出典 |
|---|---|---|
| L722 | pipeline_config同期はトップレベル差分とブロック差分を別々に検証(FEはトップレベルのみ更新・BE saveはmodel_dump丸ごと保存) | cmd_3079 |
| L734 | FastAPIテストのget_db overrideだけではauth/get_db_session経路は隔離されない | cmd_3301系hotfix |
| L093 | SVMF月次/日次判定バグ: `is_monthly_data()`未使用で行数ベース判定が月次データを日次と誤判定 | cmd_227 |
| L096 | skip処理のデータ頻度判定は`is_monthly_data()`を使え(行数ヒューリスティック禁止) | cmd_234 |
| L097 | SVMF/MVMFのskip計算に`is_monthly_data()`使え。同一ファイル内に既存実装あり | cmd_233 |
| L098 | SVMF fallbackパスが`price_data_cache`全期間参照し`target_date`未フィルタ→将来データ参照バグ | cmd_227 |
| L100 | MVMF `base_period_months`≥4必須。skip=3で`effective_months`≤0になる | cmd_222 |
| L101 | MVMF Phase3 momentum_cache事前計算はFoF専用でスキップ。Phase5 fallbackで計算 | cmd_222 |
| L102 | MVMF 4視点`SKIP_MONTHS_LIST=[0,1,2,3]`はクラス変数固定。configで変更不可 | cmd_222 |
| L105 | BB config未拘束(`Dict[str,Any]`)がGS無効パターン量産の根因。制約注入は`build_grid`直後が最適 | cmd_264 |
| L126 | ブロック名は`BlockType` enum値で統一する | cmd_222 |
| L438 | MomentumAccelerationFilterのnumerator/denominator_periodはLookbackPeriodスキーマ準拠必須 | cmd_1190 |
| L445 | DTB3を株式用momentum関数で処理してはならない | cmd_1194 |
| L447 | nukimiのみ`_run_mp`関数不在で構造差異 | cmd_1196 |
| L513 | OPT-A(cmd_1450)で非リバランス日momentum_data={skipped:true}→weightsキー消失→EWフォールバック。Ward/KalmanMetaのみ影響 | cmd_1568 |
| L639 | EqualWeight GSにpipeline import guardを混入させるな。本番pipeline lazy importは `blocks/__init__` 副作用を招く | cmd_2142 |
| L631 | TRF insufficient_candidatesパス(len<2)でcurrent_tickers=set()するな。単独ティッカー通過不能バグ。dict.get→bisect修正と同根(cmd_1899) | cmd_1899 |
| L635 | Signal DELETEを外すならFoF deferred flushもUPSERTへ切り替える必要あり | cmd_2021 |
| L669 | GS monthly_returnはopen-to-open系列。本番monthly_return(close)と混同するな | cmd_2376 |
| L921 | open-to-open全月パリティはbootstrap(初月return=0/holding=None)とlive MTD(latest-open)を独立境界として実装する | cmd_4198 |
| L670 | Oikaze GS: production first_signal_monthまで初期EqualWeightを再現する | cmd_2379 |
| L694 | pipeline_config内側top_nとPortfolio直下top_nは別経路。分離検証必須 | cmd_2443 |
| L696 | FoF登録ではPortfolio直下top_nを構成数に使うな(直下top_n=1固定+pipeline_config内側のみ) | cmd_2444 |
| L703 | FoF holding_signal同一判定は展開後ticker×weightで行う | cmd_2452 |
| L671 | Yotsume GS: production close cumulative_return+first_signal bootstrapを使う | cmd_2382 |
### 19.3 GS-本番パリティ
| ID | 結論(1行) | 出典 |
|---|---|---|
| L086 | GS tiebreak本番準拠: `cutoff_score`全包含方式。strict top_nでは短lookbackでFAIL | cmd_217 |
| L087 | kasoku長lookback(12M/24M)でGS-本番初期化期間差異が発生(504日ルール) | cmd_217 |
| L088 | L1パリティPASSはtie処理網羅の証明にならない(構造的にtie不発だっただけ) | cmd_218 |
| L089 | GS-本番パリティはデータソース一致が前提。CSV vs DBでは保証されない | cmd_222 |
| L090 | GS `monthly_return` NaN系 vs 本番 `cumulative_return` 系でコンポーネント選出数が変わる | cmd_225 |
| L091 | GSモメンタムは`cumulative_return` ratio方式を使え。prod方式はタイブレーク不一致を誘発 | cmd_222 |
| L092 | kawarimi float64同値タイ: ハイブリッド方式(desc/asc別ソート+重複時desc単一リスト両端スライス) | cmd_223 |
| L094 | oikaze `cutoff_score` epsilon tolerance(1e-12)が必要。float64精度差~2e-16 | cmd_227 |
| L095 | kasoku `main()`が`cumulative_returns`を未ロード。常にfallback(prod方式)が使用される | cmd_227 |
### 19.4 FoF登録フロー
| ID | 結論(1行) | 出典 |
|---|---|---|
| L129 | FoFパリティ比較は本番の現行パラメータを先に確認する | cmd_222 |
| L131 | 新FoF追加後の再計算は`sync-fof`(L3)を使う。sync-standardでは不足 | cmd_222 |
| L132 | GS構成四神と本番FoF構成PFの不一致に注意。登録前に突合必須 | cmd_222 |
| L135 | FoF作成は12ステップ省略不可。ステップ2-4省略でGS前提崩壊(抜き身3の失敗) | cmd_284 |
| L283 | FoFパイプラインのsnapshot参照はleakage-free設計必須。当月snapshot参照=データリーク | cmd_860 |
| L431 | 既存PF更新時はUUID維持でFoF参照を保護 | cmd_1126 |
| L478 | 吸収(absorption)はGS概念。DB物理では独立PFとして全体が登録される | cmd_1259 |
| L481 | standard PF登録時のmomentum_methodデフォルトはprice_ratio。明示指定必須 | cmd_1272 |
| L709 | FoF weights健全性チェックはconfigではなくfof_component_weightsを正本にせよ [PI] | cmd_2458 |
### 19.5 GS運用・config
| ID | 結論(1行) | 出典 |
|---|---|---|
| L112 | `monthly_returns.signal`がJSON辞書形式(`'{"TECL":1.0}'`)のとき`json.loads`でキー抽出必須 | cmd_274 |
| L125 | `pipeline_config`テンプレートのパラメータ名はコードと1:1一致必須 | cmd_222 |
| L134 | GS結果を利用する際は`DATA_CATALOG.md`と`meta.yaml`を必ず参照する | cmd_222 |
| L642 | champion_selectorの成果物探索は `cmd_id` 直後に `ninjutsu` 名が来る現行命名もglob対象に含めよ | cmd_2177 |
### 19.6 追加統合（cmd_322）
| ID | 結論(1行) | 出典 |
|---|---|---|
| L083 | close_fallback=openは部分欠損closeを補完しない | cmd_215 |
| L078 | PortfolioRepository.load()は1PFバリデーションエラーで全PF読込失敗する単一障害点 | cmd_207 |
| L065 | 本番コードパス統一原則: 数学的等価でも本番と同一コードパスを使え | cmd_196 |
| L056 | wide形式CSV(76万列)の`pd.read_csv`はヘッダー先読み+`usecols`が必須 | cmd_184 |
| L054 | nukimi_c統合可能: PARAM_GRID差分のみで戦略ロジック同一 | cmd_165 |
| L045 | nukimi_c高速化: ロジック共通、差分はパラメータグリッドのみ(T1-T3 vs T1-T5) | cmd_161 |
| L037 | standard PFでpipeline_config未設定だとrecalculate_fastがCashフォールバック | cmd_128 |
| L032 | データ構造変更時は全使用箇所を確認せよ（tuple化後の属性アクセス破綻を防ぐ） | — |
| L030 | Pipelineにmomentum_cache未提供だとsignal_calcが大幅劣化（9s→439s） | — |
| L023 | DTB3経済指標のDB照会はPipelineEngine呼出回数分だけ累積する | — |
| L022 | PipelineEngine統合の偽陽性（0/0=OK）に注意 | — |
| L020 | signal vs holding_signalの差はリバランスタイミング差として扱え | — |
| L018 | RULE10: シグナル判定はClose、リターン記録はOpenを厳守 | — |
| L002 | ブロック名は`BlockType` enum値で統一する | — |
| L001 | `pipeline_config`テンプレートのパラメータ名はコードと1:1一致必須 | — |
| L878 | adapterを跨ぐ純粋関数統合ではdate-like入力の型正規化(pd.Timestamp化)を移植先で再実装せよ | cmd_3856 |
| L003 | 調整済み時系列は全期間再取得必須、複数repo横断で同ロジック全箇所修正 | cmd_3685 |
### 19.7 trade-rule突合・SSOT（cmd_766-770）
| ID | 結論(1行) | 出典 |
|---|---|---|
| L241 | SSOT関数書き換え時、呼び出し元の不要引数計算を残さない | cmd_768 |
| L242 | trade-rule整合レビューでは同一文書内の二次SSOT表もgrepで潰す | cmd_770 |
## 20. Deterioration色丸(ColorDot)マッピング
コンポーネント: `DeteriorationDots` | 定義: `frontend/lib/constants/deterioration-colors.ts`
| 色 | Hex | Label対応 |
|----|-----|----------|
| 緑(good) | #22c55e | GOOD, EARLY_WARNING |
| 黄(caution) | #eab308 | WATCH, MIXED |
| オレンジ(warning) | #f97316 | DETERIORATING |
| 灰(neutral) | #9ca3af | INSUFFICIENT_DATA |
### 指標別→Label変換ロジック
| 指標 | 関数 | 閾値 |
|------|------|------|
| G1(μ_long slope) | `g1ValueToColorLabel` | < -0.0002 → DETERIORATING, < 0 → WATCH, ≥ 0 → GOOD |
| G2(p_erosion) | `g2ValueToColorLabel` | ≥ 0.8 → DETERIORATING, ≥ 0.7 → WATCH, < 0.7 → GOOD |
| P(det) | `pValueToColorLabel` | G2と同一ロジック |
null/NaN → INSUFFICIENT_DATA(灰)。Label→色変換は `labelToColorDot()` で統一。
## GSL1正規パス (cmd_2393, 2026-04-29)
- `outputs/grid_search/20260429/L1/shin/gs_{ninjutsu}.db` (7本: bunshin/oikaze/kawarimi/yotsume/nukimi/kasoku_diff/kasoku_ratio)
- §3.1命名ルール準拠。旧cmd番号付きディレクトリは削除済み
## GSL2正規パス / L2奥義登録 (cmd_2422-2424, 2026-04-30)
- `outputs/analysis/cmd_2422_l2_champions_constrained.yaml` = 制約付きL2 champion 21体SSOT
- cmd_2424でGSシン奥義21体本番hide登録完了。完了判定はAPI status + DB `recalculation_status`二重確認(L690/L691)
- knowledge-base methods SSOT: `/mnt/c/Python_app/DM-signal/docs/research/knowledge-base/index.md`。M79-M84にDeepUnifiedMom/VAA-BAA/Hierarchical Momentum/Factor Momentum/ADTS-CADTS/WASAを追加済み
## §20.5 WP削除後のbackend正本 (2026-06-12)
| 領域 | 現状 | 根拠 |
|------|------|------|
| is_active | backend API/jobs/schema/repositoryのis_active前提は削除済み。PF有効/無効を新規実装前提にしない | commit 3b69c172 |
| momentum method | backend schemaのmomentum method selectorは削除済み。FE側削除は`context/dm-signal-frontend.md` §10に記録 | commit 36e6137a |
| dead endpoints/BB | `api/kalman.py`, `kalman_wf.py`, `services/kalman/*`, KalmanMeta/MonthlyReturnMomentum/PBar/RelativeMomentum blocksは削除済み。`backend/app/main.py`にもKalman routerなし | commit d1bc8b22 |
| verified dead code | legacy削除one-shot、旧ETL calculator/orchestrator、monthly_common、monthly_product_momentum、consistency_checks等は削除済み。履歴はops §40-43とtask-force記録を参照 | commit c47742d1 |
---
## PortfolioEditor UI ↔ pipeline_config 同期欠落 (cmd_3079偵察, 2026-05-28)
- PortfolioEditor.tsx updateFieldはトップレベルPortfolioフィールドのみ更新。pipeline_config内ブロック(AbsoluteMomentumFilter/SafeHavenSwitch)は未操作
- BE POST /api/portfolios/save→_validate_portfolio→Repository.saveもpipeline_configブロック同期なし
- 本番136件中乖離1件: ノンレバ玄武-鉄壁(top SPY/QQQ vs block SPXL/TQQQ)
- 殿裁定待ち: top-level同期 vs pipeline_config SSOT化
- → `queue/reports/hayate_report_cmd_3079.yaml`(偵察全量)
---
## §21 FoF表示・監査系 2026-05更新 (cmd_2451〜2455)
- FoF表示はUUIDではなく`display_ticker_weights`優先。valid_start/lookback、N+1 cache、signal auditは修正済み。設計正本→`/mnt/c/Python_app/DM-signal/docs/design/signal-decision-ledger-design.md`
- 2026-07-06 cmd_3698_recon2: 確定台帳偵察で `signal_change_log` はappend-only実績あり、`month_start_signal_input_snapshots` はUPSERTで過去値が消えるため台帳代替不可と確認。`portfolio_config_snapshots` はholding_signal非保持、`fof_rebalance_decisions` はMAX(date)=2026-02-03で停止。書込みガード候補は `backend/app/jobs/flush/signal_flush.py::_flush_batch()` と `backend/app/jobs/generators/monthly_returns.py::_generate_monthly_returns()` の二層。初期台帳は `signal_change_log` 主ソース、新設台帳が妥当。
- 2026-07-06 cmd_3699: 保有シグナル確定台帳の設計書を作成済み。追記専用 `signal_decision_ledger`、書込みガード3経路(`signal_flush.py::_flush_batch`, `monthly_returns.py::_generate_monthly_returns`, `api/debug.py` fof-profiling)、読み経路4層(signals API/monthly returns/FoF child/trade生成)、初期構築、correction、同日朝夕再計算、UI表示方針を定義。RenderログでSIGNAL CHANGE ALERT発火を確認し、ntfy push成否に依存しない警報設計へ反映。詳細: `/mnt/c/Python_app/DM-signal/docs/design/signal-decision-ledger-design.md`。
- 2026-07-06 cmd_3700: 確定台帳実装第1弾完了。`signal_decision_ledger` DDL/ORM/migration、append-only update/delete guard、partial unique index `ux_sdl_initial_decision`、初期構築dry-runスクリプト、台帳テストを追加。実挿入・書込みガード実装は後続cmd。対象commit: `/mnt/c/Python_app/DM-signal` `5e9ea355`。
- 2026-07-06 cmd_3702: 初期構築dry-runの決定日フィルタを `rebalance_trigger` 対応へ是正。旧306件(102PF×3日)は非リバランス月混入で誤り、新計画は102件(1PF×1決定日)、復元不能0件、provenance内訳=signal_change_log_old_chain 9 + signals_fallback 93。本番trigger分布はmonthly 91 / quarterly_jan 5 / bimonthly_even 3 / bimonthly_odd 3 / quarterly_feb 0 / quarterly_mar 0。2026-07-01遡及書換え9PFは全てold_chainで決定時点値へ解決し、汚染混入0件(3PFは現在値と決定値が実際に異なる巻き戻り、6PFはnet-zero往復)。対象commit: `/mnt/c/Python_app/DM-signal` `e0734172`。
- 2026-07-06 cmd_3704: 本番`signal_decision_ledger`初期構築を実行。バックアップ`signal_decision_ledger_backup_cmd3704_20260706T2018`作成後、102PF分102件を挿入し、sync-standard/sync-fof後もchecksum `36334bde8188c94e7295c69427768f15105522f35c70701babe970311432f241` 不変。CRITICAL drift 2件でガード発火を実証。台帳=決定済みholding_signalのSSOTとして本番稼働。
- 2026-07-07 cmd_3711: `signal_decision_ledger`全履歴バックフィルを本番実行。SPYカレンダー月初営業日キーで2003-2026の確定リバランス月へ`historical_backfill`行を追加し、Monthly Tradeの過去月Pending表示を解消。バックアップ`signal_decision_ledger_backup_cmd3711_20260706T1454`後、dry-run 15,058 planned、実行後15,160 total、API `decision_source` spot check済み。対象commit: `/mnt/c/Python_app/DM-signal` `4b9fae64`。
- 2026-07-08 cmd_3753: PF復元R1完了。`portfolio_archive`(FKなし`portfolio_id`+payload JSON+deleted/restored metadata)を追加し、`PortfolioRepository.delete_by_id`直前でportfolio/folder階層/`signal_decision_ledger`/`month_start_signal_input_snapshots`を同一transaction退避。archive INSERT失敗時は削除rollback。対象commit: `/mnt/c/Python_app/DM-signal` `f6404d70`。
- 2026-07-10 cmd_3810: Monthly Trade FoF表示で`display_ticker_weights`変更時、`calculated_return_open/close`・`matched_weight`・`missing_tickers`を表示weightsと同一基盤で再計算するよう統一(`_sync_entry_calculation_to_display_weights`)。旧実装は表示weightsだけ差し替え、計算returnは別ソースのweightsを参照し不整合だった。`matched_weight`判定も厳密等価(`!= 1.0`)から浮動小数点許容(`abs(matched_weight-1.0)>1e-9`)へ修正。対象commit: `/mnt/c/Python_app/DM-signal` `67bdffc8`。
- 2026-07-10 cmd_3812: `monthly_returns.py::_generate_monthly_returns`に`signal_decision_ledger`のband確定weight(`decision_ticker_weights`)優先ロジックを追加。台帳にband weightがあれば通常計算weightより優先使用し(`_normalize_ledger_ticker_weights`)、価格キャッシュ対象tickerにも台帳weightのtickerを含める。台帳のband weightsがMonthly Returns生成時に上書きされていた問題への対処。対象commit: `/mnt/c/Python_app/DM-signal` `8fc49267`。
- 2026-07-14 cmd_karo_hotfix_signal_insert_ledger_drift_alert_202607141340: 新規`signals` INSERTの確定域ledger driftをrun-level `SIGNAL CHANGE ALERT`へ載せたが、当初は`signal_change_log`から除外していた。この旧方式は事後追跡不能を生んだため、2026-07-16 cmd_3997で廃止。
- 2026-07-16 cmd_3997: 新規INSERTのledger drift synthetic entryも`signal_change_log`へ1行永続化する。`date`はDB投入前に`date`型へ正規化し、内部キー`is_new_insert_ledger_drift`はDB field filterで除去する。同一payload再実行は監査ログ増分0。対象commit: `/mnt/c/Python_app/DM-signal` `f4d94ab4`、回帰76/76 PASS・運用simulation 12/12 PASS・SKIP 0。
## §22 CI/テスト基盤 2026-05更新 (cmd_2652〜2660)
- `.github/workflows/pytest.yml` を追加。PyYAML/pytest依存をCIへ導入し、PostgreSQL service付きpytestへ拡張済み
- `backend/tests/test_pipeline_cache_optimization.py` はCI対象。テスト関数ゼロの空振りを避ける教訓L721を併用する
- 2026-07-16 `021ceba7`: 全pytest call結果を `backend/.pytest_cache/pytest_timing_ledger.tsv` へ記録するpluginを常時ロード。列は timestamp/nodeid/duration_sec/outcome/failures/skips/commit。flock+atomic replaceで並列追記し、既存ledger破損・git不在はfail-closed。
- 2026-07-22 `0815a02e`: duration ledger pluginのcanonical importは`backend.tests.pytest_duration_ledger_plugin`。`backend/tests/conftest.py`とplugin contract testは同じimport pathを使う。
- 2026-07-16 `1bf0eae5`: 新規Signal INSERTのledger driftは複数行でもdrift/alert/永続行を1:1で保存し、同一batch再実行では監査行を重複INSERTしない契約を回帰固定。
- CI失敗調査ではworkflow依存不足とDB service起動を先に確認する
## §23 P4統合期のbackend変更 (cmd_karo_hotfix_p4_restore_core_integrator/cmd_3858/cmd_3861, 2026-07-12、GA-238で反映)
結論: P4 restore・非決定配列・CI fixtureを統合。safe bundleはone-use CAS、writerはAST↔registry↔DB三集合でfail-closed。詳細→`context/dm-signal-ops.md` §71-§76 / `context/dm-signal-research.md`
## §24 signal flushの複合IN照会chunk境界 (cmd_karo_hotfix_dm_signal_l3_tuple_chunk_20260801, 2026-08-01)
- `backend/app/jobs/flush/signal_flush.py` の2列複合key照会は `_query_composite_keys_in_chunks()` に集約する。`6200cc1e`の10,000-key chunkは本番で07:15開始後、07:19の`updated_at`で`StatementTooComplex`・rows 0となり不十分だった。既知正常境界`5c8a9cf`(1,000-key)を再適用した`3ee5c21b`で`COMPOSITE_IN_QUERY_CHUNK_SIZE=1_000`へ修正済み。対象は新規Signal INSERTの既存行照合と反復ledger guard correctionの過去`signal_change_log`照合。現在は本番再検証中であり、完走確認前に解決済みと扱わない。
## 30. Compare metrics同時生成の原子的UPSERT (2026-08-04、本番反映済)
- `backend/app/services/metrics_impl.py`のmetrics保存はSELECT→INSERT/UPDATE分岐を使わず、PostgreSQL/SQLite dialectの`ON CONFLICT DO UPDATE`で原子的に保存する。同一PFへの同時要求で`portfolio_metrics_pkey`競合を起こさない。
- 例外時はrollback前にORM属性へ触れず、事前取得した文字列IDを使い、`rollback → log`順を守る。commit=`8d994f35`、対象テスト15/15 PASS、Render live、軍師事後レビューAPPROVE。
- 因果リンク: [[Compare_Summary同時metrics生成]] -> [[SELECT_INSERT_race_UniqueViolation]] -> [[dialect_upsert_8d994f35]]
## 31. Monthly生成のlogical date・未初期化境界 (2026-08-04)
- `50002dc6`〜`9a27eb4f`: run logical dateを営業日へclamp、未価格未来月/初回有効holding前はskip、開始後欠落はfail-visible。詳細→`/mnt/c/Python_app/DM-signal/docs/research/dm-monthly-trade-bug-genko-chain-archive_20260803.md`
---
## §93 2026-08-09〜10 source boundary反映

- **monthly_returns履歴保全**: `c469ba6f` は新計算範囲が既存履歴を包含しない場合にPF全履歴DELETEを拒否し、計算できた月だけUPSERTするguardと回帰testを追加した。しかし `4d81c32c` がこのguardとtestをrevertしたため、現行は狭い`mode='portfolio'`結果で広い履歴を再び切り詰め得る。運用上は§89の暫定`mode='full'`制限と履歴行数確認を維持する。参照: `backend/app/jobs/generators/monthly_returns.py`、`backend/tests/test_monthly_returns_history_guard.py`、commits `c469ba6f`→`4d81c32c`。
- **Group-A Open metrics**: `aaef7932` はCorrelation/Beta/Alpha/R²/Treynor/Calmar/Positive Periods/Gain-Loss Ratioを`*_open`系列から独立計算し、close/open値を同一metricへ格納する。回帰testはOpen値がClose値の複製でないことを検証する。参照: `backend/app/services/metrics_impl.py`, `backend/tests/test_metrics_continuity_risk.py`、commit `aaef7932`。
- **FoF表示日の正本**: `28b58ee0` はMonthly Trade FoFの表示weights照会候補に`position_start_date`を最優先で加え、月初カレンダー日(週末)の旧holdingではなく実保有開始日のSignalを採用する。参照: `backend/app/api/monthly_trade.py`, `backend/tests/test_monthly_trade_calculator.py`、commit `28b58ee0`。
- **ledger次回rebalance境界**: `9f81c106` はtrigger別の次回rebalance月を判定し、openな旧confirmed eventが次回決定月へ持ち越されるのを止める。非rebalance月はcarry、次回rebalance月は新eventが入るまでpendingとする。参照: `backend/app/services/signal_decision_ledger.py`, `backend/app/jobs/recalculate_fast.py`, `backend/tests/test_signal_decision_ledger_guard.py`、commit `9f81c106`。

## §94 L1分割 全6手 live + L2分割 走行中 (2026-08-15〜16、source=origin/main a9883865)

- **L1分割(全6手 live・各手 full→business parity 差分0)**: L0 config/ledger snapshot(`snapshot_portfolio_configs`/`db.info["portfolio_config_snapshot"]`・f0194282) → L1.1 `resolve_price_consumer_dependencies`→`PriceConsumerDependencySnapshot`(config-only・b3156fb5) → L1 materialize範囲をL1.1出力から(5e307731) → L1.2 `_resolve_fof_dependency_plan`(PFごと最深depth 1値・fail-closed・fbcc8be0) → L1.3 `run_identity` 1つ(2268592d) → 直列固定(925b8338)。設計正本=`docs/research/dm-l1-split-design_20260815.md`(gist 4e64d25b)。
- **L2分割(走行中)**: #1 前回確定成果物 C1 read-once(0f47de79 live)、#2 PF×月現fingerprint produce(3a5ebd05 live)、#1b/#3(judge record-only)はimport closure欠落で2度revert→helper closure修復(a9883865)後に再push。#4 C2合流は未。設計正本=`docs/research/dm-l2-standard-design_20260815.md`(gist b4b31391)。次=継ぎ目設計 `docs/research/dm-l2-l3-seam-design_20260816.md`(gist 4735a7fc)。
- 親ToBe=`docs/research/dm-unified-tobe-flow_20260815.md`(gist 12cb3fc4)。読み方: 行=L・左列=cache・右列=計算・上から下へ戻らない。

## 因果リンク
- **cmd_4296 モメンタム窓調査 (2026-08-13)**: standardは日次close-to-close営業日行数、leaf/nested FoFは子PFの`monthly_returns.cumulative_return`を月末close系列として月数行差分。三系統の独立選抜結果はDB signalと一致したが、`signals.momentum_data`にモメンタム数値は保存されず保存値との数値parityは検証不能。詳細→`/mnt/c/Python_app/DM-signal/docs/research/cmd_4296_momentum-window-recon_20260813.md`
- ← [[dm-signal]] メインPJの核心層
- → [[dm-signal-ops]] コア→運用への接続
- → [[dm_signal_db_schema]] DM-Signal DBスキーマ全文(テーブル構造・カラム定義)
- → [[dm_signal_pi_full]] DM-Signal 本番不変量(PI)全文(全PI一覧・適用ルール)
- → [[dm_signal_trade_rules_full]] DM-Signalトレードルール全文(エントリー/エグジット条件)
- → [[dialogue_preprocessing_research_20260331]] 前処理研究日誌=コア改善の知的基盤

## §95 tier依存endpointのETag/Cache-Controlに主体を含める (cmd_4327, 2026-08-17)
- `backend/app/utils/etag.py` `generate_etag`入力に主体(tier_id/is_admin/visible_ids)を含め、tier依存endpointは`Cache-Control: no-store`。別主体で同一ETag→304が成立しない不変量(`test_etag` PASS)。→ `docs/research/dm-login-boundary-asis-tobe_20260817.md`

## §96 showcase contract v3 + free-coupon の Supabase Auth API 化 (2026-08-31)

- 790c7036(cmd_4425): showcase 契約 v3=mdd 追加・best_name 除去・blackout。GATE CLEAR≠到達の再実装版(4415 偽 CLEAR の是正)。
- 10d59c8d: `_build_hero` に sharpe(close.portfolio)追加+contract test で hero キー集合を固定(キー漏れ再発防止)。
- c72f95e3(cmd_4428): free-coupon 検証を Supabase Auth API(anon key+Bearer)へ=JWT secret 不要。

## §97 public showcase API `/api/public` + showcase_events テーブル (2026-08-30〜31)

- `backend/app/api/public_showcase.py`(+486行, router prefix `/api/public`): 公開 PF 判定 `is_public_signal_portfolio`/hide_signal、metrics 集約(`_aggregate_metrics`、CAGR は total_return+period_months から導出)、tier 設定 `_tier_settings_for_public`、Supabase user 取得 `_fetch_supabase_user`(Bearer)、hero に sharpe(10d59c8d)。LP 側 origin を CORS 許可(2bef946a)。
- `ShowcaseEvent`(models.py)+`showcase_events` テーブル(migrations.py: step/ua_class/lang/occurred_at、index step・occurred_at・複合)。mutation は `_block_showcase_event_mutation` で遮断=追記専用テレメトリ(cmd_4422 5b50424e)。
- 制約: `from __future__ import annotations` を public_showcase.py に置くな(e94cda07: slowapi wrapper 経由で PydanticUndefinedAnnotation→Render deploy 失敗、cmd_4419 5ddd1e96 で文書化)。
- 境界=origin/main 172b6d35e7f2。
