# DM-signal 運用コンテキスト
<!-- last_updated: 2026-08-22 context_freshness reviewed source boundary (shogun doc lane, GA-491 re-apply of GA-490) -->
<!-- source_commit:45760ecf reason:GA-490/491 運用反映点の境界更新(退行復旧再適用) evidence:git -C /mnt/c/Python_app/DM-signal log 46a1f213..45760ecf reviewed。初回=33f3dc7a2、tree退行検出により再適用。coreと共有するsource変更は重複調査せず運用反映点のみ記録 -->

## Current source boundary (GA-490/491, 2026-08-22)
- **Current source tip:** `45760ecf`(reconcile merge revert)。運用上の反映点: 保有不変(signals md5+weights md5+signal_change 0)がFoF決定性シリーズ後のfull run合否基準として継続。full 1回で業務4表md5をrollback計画書§-1 15:10 baselineと突合する型(cmd_4337 AC)も継続。rb6 cleanup再合流までは45760ecf系列を運用正とする。
<!-- source_commit:46a1f213 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/dm-signal-ops.md commit=46a1f213 -->
<!-- source_commit:131e5dbb reason:GA-472 rollback boundary reflected in ops context evidence:git -C /mnt/c/Python_app/DM-signal diff --stat 3e28b617 131e5dbb; rollback commit 131e5dbb; §Current source boundary added -->
<!-- source_commit:a9883865 reason:業務列parity標準+1手の型を§98へ反映 evidence:scripts/dm_signal_business_parity.py; blt_20260815_183204 -->
<!-- source_commit:e3dccd87 reason:cmd_karo_hotfix_rb8_context_freshness_20260814_normal evidence:cmd_4301_context_freshness_AC2_ops -->

## Current source boundary (GA-472, 2026-08-17)
- **Current source tip:** `131e5dbb` rolls the production runtime back to restore point `3e28b617`; the §98 production-parity procedure below records pre-rollback evidence and requires revalidation before being treated as current live behavior.

<!-- source_commit:15e612f9 reason:cmd_karo_hotfix_timing_summary_restore_20260813 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-ops.md commit=15e612f9 -->

<!-- source_commit:b7067c99 reason:GA-455 content reflection evidence:source frontier review: 39 commits; operational invariants indexed in context §0.1 -->
<!-- source_commit:309a8d6c reason:cmd_karo_hotfix_l3_deferred_flush_wall_202608110643 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-ops.md commit=309a8d6c -->
<!-- source_commit:4d81c32c reason:cmd_karo_hotfix_ga452_context_boundaries_202608100949 content-reflection evidence:source commits 4d81,c469,aaef,28b58 reviewed and indexed -->
<!-- source_commit:bda69c42 reason:cmd_karo_hotfix_cmd4284_market_grid_202608100902 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-ops.md commit=bda69c42 -->
<!-- source_commit:ec72faa2 reason:cmd_4283 reviewed source boundary evidence:cmd_complete_gate -->
<!-- source_commit:d62065b4 reason:cmd_4282 reviewed source boundary evidence:cmd_complete_gate -->
<!-- source_commit:8e30a242 reason:cmd_karo_ci_fix_dm_signal_run_31326903152 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-ops.md commit=8e30a242 -->
<!-- source_commit:a926d06c reason:cmd_4255 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-ops.md commit=a926d06c -->
<!-- source_commit:aca163ab reason:cmd_4254 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-ops.md commit=aca163ab -->
<!-- source_commit:94cb88bb reason:cmd_4253 reviewed source boundary evidence:cmd_complete_gate project=dm-signal context=context/dm-signal-ops.md commit=94cb88bb -->
<!-- source_commit:bf4ed6a6 reason:cmd_4241_reviewed_boundary evidence:backend/app/api/etl_trigger.py+backend/app/jobs/precompute_raw.py -->
<!-- source_commit:16b62fca reason:cmd_4241_reviewed_boundary evidence:backend/app/jobs/precompute_raw_queue.py -->
<!-- source_commit:5b393e7ccd2160778060cc7d5522b32254d72c2e reason:cmd_4234 reviewed sync/run boundary evidence:cmd_complete_gate -->
<!-- source_commit:5b393e7c reason:cmd_4234 reviewed sync/run boundary evidence:cmd_complete_gate -->
<!-- source_commit:a111173509e7337dcc2e964a83c3ed043b940fd7 reason:Monthly Trade current-month backend deployment reviewed boundary evidence:deploy dep-d9oa3njbc2fs73eu4vhg live; all 102 PF current month -->
<!-- source_commit:f1977f8ed3ee4c78344791a8375ff53a161b346a reason:GA-429 reviewed source boundary through detached production investigation HEAD evidence:full recalc run226 and Compare recovery recorded; intervening monthly-boundary runtime/research work indexed -->
<!-- source_commit:6f628677362b2ef936d0de5ef2f80e17d00fa944 reason:C-x W4/W5 oracle reviewed source boundary evidence:fixture6/6 pytest1/1 FAIL0 SKIP0 -->
> 読者: エージェント。推測するな。ここに書いてあることだけを使え。
コア定義(§0-5,8,10-11,13,15,18) → `context/dm-signal-core.md`
研究・検証結果(§19-24) → `context/dm-signal-research.md`

## §0.1 GA-455 source frontier review (2026-08-11)
- 一次境界: `/mnt/c/Python_app/DM-Signal` `origin/main=b7067c99`。cache無効dashboard gateの未反映source commitは **39件**（last_updated=2026-08-11との差異）。coreと共有するsource変更は重複調査せず、運用上の反映点だけを本索引へ記録した。
- 運用上の不変量: L5はno-data sentinelを15 endpoint/hash集合へ完結させ、no-context cache/buildersをPF batchで共有し、狭いportfolio再計算が既存monthly historyを削らないこと（`b7067c99,7bb8b73a,b65ac45c,143f60ad,9a09a00a,3a0cb44f,bcb75220,fd43f7ae,37680998,4ea744fb`）。cache state・run lineage・phase timingは後段判定の一次証跡として保存する（`7d169165,79971b6c,bd9d0dbf,20a26556,72c0f288,6e501b63,771fba52,c76fdac3,dcb3b914,fb3c5cdd,ac017707,96aa5d61,bda7112b,5d931a66`）。
- 実行順序・安全境界: FoF sync後にL5をenqueueし（`31b606c3`）、NAV frame/leaf snapshotはFoF間で共有してもimmutable入力とtiming帰属を維持する（`ed8f513d,175e82d8,1088595e,2542509c,879b2d14`）。Render debug APIは本番露出させず（`09cfa765`）、admin L5 precomputeはPF単位、MTD/fallback/benchmark freshnessと空FoF calendarは各source契約に従う（`f76df2a7,b431b1f9,198fc455,14d365a8,de6b7774,5de2cbe2`）。
- 監査順序（origin/main `git log` 新→旧、39件）: `b7067c99,7bb8b73a,6908c5c8,b65ac45c,5bd7cd1e,198fc455,14d365a8,20a26556,5de2cbe2,1088595e,de6b7774,175e82d8,365e1c8f,c3001c87,09cfa765,b431b1f9,5d931a66,79971b6c,bd9d0dbf,6e501b63,72c0f288,143f60ad,771fba52,c76fdac3,dcb3b914,31b606c3,879b2d14,2542509c,7d169165,9a09a00a,3a0cb44f,f76df2a7,bcb75220,fd43f7ae,37680998,4ea744fb,ac017707,96aa5d61,bda7112b,ed8f513d`。各commitの変更本文・変更pathをsource repoで照合済み。実装詳細は `context/dm-signal-core.md` §0.1を参照する。
## §6-7 recalculate_fast.py + OPT-E
6Phase+OPT-E(Phase3.7)構成。signal_calc 1,724s→0.53s(3,786倍)。最新本番: **357.28s/124PF**(2026-03-29 cmd_1478, OPT-12~15全反映)。
112件消失バグ(L045)=Phase4 dict miss時continue→日次フォールバック追加(91c04a4)で修正済。
- L818: 本番DB read-only確認はpython3 -cのインライン実行ではなくスクリプトファイル経由で行え（cmd_3698_recon2）
- L934: 「効力日」という列名だけで実効力日SSOTと認定しない。採用前に代表的な執行ずれ月でexpanded実切替日との一致を二値確認（writerがdecision日を複写する場合あり）（cmd_4222）
- L827: archive由来の複数行復元(FK依存あり)はテーブルごとにdb.flush()を挟まないとFK制約違反になる（cmd_3754）
- L833: recalculate完了矛盾は経過時間見積り(timing-history平均2000s級)と照合してから切り分けよ。API running確認は複数worker前提で解釈せよ（cmd_karo_recon2_cmd3771_recalc_status_202607081502）
- L836: recalculate acceptedと完走証跡を分離して判定する（cmd_3771）
- L909: 履歴バックフィルは保存先year_month変更だけでなくas-of入力切断も必須。過去月キー指定とas-of入力切断は別契約（cmd_4140）
crash-safety(cmd_1463/1465): shutdown警告(main.py)+recalculation_statusテーブルDB永続化+pg_advisory_lock排他制御(key=8675309, セッション保持方式, fail-open)。SIGKILL時PostgreSQL自動解放。
cmd_3788: Render `uvicorn --workers 2`下の`/admin/recalculate-status`と`/admin/recalculate-sync`起票ガードをDB SSOT化。最新`recalculation_status.status='running' AND end_time IS NULL`をクロスプロセス真実源にし、他worker実行中は起票時に409を返す。成果物: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3788_recalc_status_db_ssot.md`
GP-124(cmd_1477): fullrecalculate後signal整合性チェック(_check_signal_integrity)。zero-signal自動検知WARN+signal COUNT記録。OPT-13(修正)+GP-124(検知)=二重防御。
Phase4.1(cmd_1680): 月初signal行自動作成。Phase4完了後に最新signal日<当月かつリバランス月PF存在時、前月末signalをforward-fillした月初signal行を自動生成。月初Pending最大24h表示→即時解消。
詳細アーキ全量解析(2026-03-28コード全文読了) → `docs/research/fullrecalculate-architecture-2026-03-28.md`
### fullrecalculate実行方法（本番=Render。ローカルではない）
**本番のrecalculate_fast.pyはRender上で動く。ローカルのメモリに影響しない。**
| 方法 | コマンド | 用途 |
|------|---------|------|
| **手動トリガー** | `curl -X POST https://<backend-url>/admin/recalculate-sync` | PF登録後の即時再計算 |
| **日次cron** | Render cron 01:10/01:40 UTC | sync-standard + sync-fof |
| **排他制御** | pg_advisory_lock。409=排他中(30秒待って再実行) | 同時実行不可 |
ローカルでやること: DB接続(psycopg2)でPFレコード作成/読取 + GS CSV 1列読取 + 数値比較。メモリ数MB。
### monthly_returns_gen分解計測の次checkpoint（`f7489c3b`）
commitをpushしRender deployを確認後、同一`target_date`・全78PF・直列の本番`fullrecalculate`を1回実行する。既存timing JSONの`monthly_returns_gen_breakdown`から`mr_compute` / `mr_internal_commit` / `mr_caller_commit` / `mr_cache_reload`の各`sum_sec`・`count`と`residual_sec`（第5区間）を抽出し、最大`sum_sec`を支配項として一意判定する（同値なら支配項未確定として再計測）。最適化は並列化より先に、支配項に応じて計算量・cache reload・重複commit・writeの削減を優先する。
- L690: recalculate-sync完了判定はAPI statusだけでなくDB recalculation_status行で確認する（cmd_2424）
- L701: fullrecalculate後は非対象PFのmonthly_returns件数diffを確認し復元判断まで行う（cmd_2450）
- L783: fullrecalculate完了確認はtiming-history DB記録が一次証跡。recalculate-statusはLB別インスタンス不正確（cmd_3546, 102PF完全一致証明済み）
- cmd_3788以後: running状態の可視性はDB `recalculation_status`を参照するためworker-local誤答は修正済み。ただし完了証跡は引き続きDB行/timing-historyで確認する。
- トラブル・データ不整合の初動では、直近コード変更後のfull再計算忘れを第一容疑として、DB `recalculation_status` の最新行の`mode`・開始/完了時刻を確認する（殿裁定2026-08-09）。
ローカルでやらないこと: recalculate_fast.pyの直接実行（Render上で動くコード）。
### DM-Signal本番FE CDP確認手順（2026-05-05実証済み）
**殿のChromeを使わない。隔離プロファイルEdgeを自動起動する。**
```python
# 前提: PYTHONPATH=/mnt/c/Python_app/auto-ops
from cdp import cdp_helper
import time
# Step 1: 隔離プロファイルEdge自動起動(user-data-dir=$TEMP/cdp-edge-9222)
result = cdp_helper.preflight_cdp_flow(port=9222, browser="auto", launch_timeout=30)
port = result.get("cdp_port", 9222)
# Step 2: DM-Signal FEにAdmin認証(backend/.envのADMIN_USER/ADMIN_PASS)
tab_id = cdp_helper.create_tab(url="https://dm-signal-frontend.onrender.com/admin", port=port, timeout=30)
time.sleep(4)
cdp_helper.ui_login(tab_id, "simokitafresh", "703", port=port)
time.sleep(5)
# Step 3: 確認したいページに遷移+スクショ
cdp_helper.navigate(tab_id, "https://dm-signal-frontend.onrender.com/compare-summary", port=port)
time.sleep(8)
cdp_helper.screenshot(port=port, tab_id=tab_id, path="/tmp/dm_signal_screenshot.png")
```
**注意事項:**
- D009: headless禁止。必ず隔離プロファイル(user-data-dir)指定必須
- cdp_helper.ui_loginはReactのinputにイベント発火する正しい方法。JS直接value代入は不可(state更新されない)
- `cdp_cli.sh auth` やCookie注入でログイン状態にならない場合は、Admin UIフォームログインへ切り替える。手順: (1) Adminタブを開く (2) `nativeInputValueSetter` でUsername/Passwordを入力 (3) Loginクリック (4) 8秒待機 (5) `navigate` でCompare Summaryなど確認対象へ遷移。React inputは `Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set` + `input` eventで更新する
- Daemon版(cdp_server.py+cdp_cli.sh port 9400)も使える。snapshot→click_ref @e8→screenshot
- credentials: backend/.envのADMIN_USER/ADMIN_PASS(FE Admin認証とBE Admin認証は同じcredentials)
- 正本: `bash scripts/cdp/cdp_measure.sh <cmd_id> --pages ...` → `/mnt/c/Python_app/auto-ops/workflows/perf_measure.py --profile production`。admin Basic Authでviewer passwordを取得後viewer認証する。viewer認証だけでは不足するPF/ページがある
- 参照: `scripts/cdp/cdp_measure.sh`、`/mnt/c/Python_app/auto-ops/cdp/README.md`、`skills/cdp-browse/SKILL.md`、記憶DB `knowledge:776999ee`
**ポート体系:**
- `9222`: legacy daemon / FE実操作の既定ポート。preflight_cdp_flowが隔離Edgeを自動起動する
- `9223`: 拡張・並行確認用ポート。9222競合時の退避先
- `9400`: auto-ops daemon。`cdp_cli.sh` のsnapshot/click_ref/screenshot操作口
- `cdp_cli.sh`: daemon版CLI
- `cdp_helper.py`: auto-ops版
**FE詳細操作:**
- ハンバーガーメニュー: モバイル幅では左上メニューを開いてからPF一覧 / Compare Summary / Signals / Termsへ移動
- メニュー: デスクトップ幅ではサイドバーのPF一覧 / Compare Summary / Signals / Terms
- PF選択: URLパス直指定(`/portfolio/{id}`)を優先。UI操作時はサイドバーPF一覧を開いて対象名を選択
- 保有シグナル確認: `/signals`
- L754: WeightedMultiViewMomentumFilterBlock追加はcontext/dm-signal-core.md §4 BB種別分類の即時更新対象（cmd_karo_hotfix_context_dm_core_ga102_20260620）
<!-- last_synced_lesson: L1601 -->
- L862: cmd_3771 archive payloadとsnapshotの復元正本を区別する（cmd_3826）
- L864: LayerTimer新Layer追加時は集計ハブへ同時登録する（cmd_3831）
- L865: L1/L2/L3 cronは固定時間差や上流ロック解放を完了とみなさず、`EtlLayerStatus.last_success_date`が当日になった後だけ次層を実行せよ。cmd_3685でL0(sync-prices)が19s→~700-850sに増大しL1の固定5分起動が409で失敗、L1だけのロック待ちではL2/L3に障害が移るため、`scripts/etl_layer_sync_wait.sh`でL1→L2→L3を同一の実成功契約に統一した（cmd_3832、`docs/research/cmd_3832_sync_tickers_recon.md`）
- L866: recalculate-sync全PF実行のcleanupはmodeに関わらずTickerMonthlyReturnを削除するが再生成はmode=full/tickerのみ。既定mode="portfolio"のため全PF再計算のたびにticker_monthly_returnsが空になっていた。削除ゲートと再生成ゲートは常に対称にせよ（cmd_3832、docs/research/cmd_3832_sync_tickers_recon.md）
- L869: PF可視性検証はfolder優先を含むAPI実効件数で完了判定する（cmd_3837）
- L875: 差分テストの母集団定義は隣接AC/設計行からの数値継承を疑い、機構(adapter有無)ごとに独立検証せよ（cmd_karo_recon_cmd3851_adapter_coverage_b_202607120024）
- L877: 100MB超golden-baselineはmanifestとgitignore archiveへ二層分離せよ（cmd_3854）
- L879: PASS件数だけでは実データ検証を証明しない、契約テストと実データテストを区別せよ（cmd_karo_verify_p3b_nocode_closure_202607120339）
- L883: input snapshot IDだけでは差分監査できない（cmd_3872）
- L889: 重量golden回帰のthrowaway DB名は実行単位で隔離しcleanupも接続poolを強制解放せよ（cmd_karo_ci_fix_dm_cmd3882_golden_restore_fullsuite_rc2_202607140015）
- L892: 破壊的full計測は安全hash cloneから分離する（cmd_karo_hotfix_cmd3881_v1426_harness_rc2_202607140538）
- L893: managed DB capabilityはactual環境identity付き往復を入口必須にする（cmd_karo_fence_v1427_nologin_rc3_202607140653）
- L894 (retired): 「Render managed roleはCREATEROLEなし」はpreview限定の実測を本番へ過剰一般化するため廃止。L895を参照
- L895: Render preview isolated role capabilityは本番roleのproxyではない（cmd_karo_hotfix_cmd3881_v1428_probe_contract_202607140732）
- L896: restore前に診断履歴post-snapshot artifactを保存する（cmd_3903）
- L904: Rolling統計は共通窓集合を契約化する（cmd_4113）
- L916: 比率の分子分母は同一run identityで束縛する（cmd_karo_recon2_fullrecalc_v11_adversarial_review_20260727）
- L920: ledger安全補正をconfirmed changeへ混ぜると日次同一alertが反復する（cmd_4195）
- L923: date.todayと月初fixtureの同一日衝突を境界日に検証する（cmd_karo_ci_fix_dm_signal_compare_returns_unique_20260801）
- L928: プロセス内分類値と永続元データを分離して追跡する（cmd_karo_dm_alert_daily_repeat_recon_20260802）
- L951: 正準外日を持つsymbolの完全性はactual日数一致で判定しない（cmd_karo_recon2_july_prices_full_coverage_20260803）
- L952: snapshot存在確認と再生成能力を分離する（cmd_karo_recon_dual_b4_10pf_omission_root_20260803）
- L1542: 0件保全ガードは上流cleanupのcommit後では既存行を保全できない（cmd_karo_recon2_atomic_recalc_design_saizo_20260803）
- L1543: template対clone parityだけでは現HEAD schema driftを検出できない（cmd_karo_recon2_b4_schema_divergence_tobisaru_20260803）
- L1544: raw cache失効と再生成は同一契約で強制する（cmd_4239）
- L1547: SIGNAL CHANGE ALERTはrun起因(cron/デプロイ検証/ledger未確定域)を判別できず毎回フル偵察を要する（cmd_4243）
- L1550: 偵察タスクリストの件数表記と実ID行を別々に計測する（cmd_4247）
- L1586: recalculate-syncはQuery契約で呼ぶ（cmd_4287）
- L1588: after_commitのBoolean invalidation markerはscopeを保持しない（cmd_karo_recon2_l5_invalidation_scope_202608121849）
- L1589: nested FoF初月oracleはsame-run child NAV clockをdepth共通で扱う（cmd_karo_recon2_rb6_parent603_onecase_20260813）
- L1590: partial-month FoFはprice clockとselection clockを別々に照合する（cmd_karo_recon2_rb6_saved_display_audit_20260813）
- L1591: 履歴parityのactive母集団は現在visibilityでなく固定run cohortを使う（cmd_karo_recon2_rb6_reverse_parity_full_20260813）
- L1595: ledger構築endpointのcron接続を保護有効化前に検証する（cmd_4319）

## §36 API認証
- admin系API: Basic Auth(`ADMIN_API_KEY`)
- viewer系API: Bearer Token(`VIEWER_TOKEN`)
- FE Admin認証とBE admin系API認証は区別する。画面ログインは`ADMIN_USER`/`ADMIN_PASS`、APIはBasic Auth。
- データ確認はAPI経由よりDB直接クエリが確実。
- L004: 価格ベンダー比較成果物はAPIエラーURLの秘密値混入を検査する（cmd_3687）
- cmd_3669: `/api/metrics/summary` は `metrics_summary_bulk` precomputed rawを読む。raw生成は `backend/app/jobs/precompute_raw.py` の `METRICS_SUMMARY_BULK_PARAMS=[{years:0},{years:10}]`、無効化はmetrics cache更新・portfolio保存・portfolio_metrics生成時に走る。関連commit: DM-Signal `755a50d9`。
## §37 ETL
- L1554: price completeness must filter expected-grid outliers — 価格完全性判定は期待グリッド外れ値を除外してから欠損判定する（cmd_4285、/lesson-sort 2026-08-18）
- cmd_4140: deterioration履歴欠落はcron失敗/表示filterではなく、月次batchが現在月1点だけをUPSERTしAPI/FEも既定6点しか取得しないことが原因。本番102 PFは0点=0・1点=86・3点=1・5点=15だが、月次returnは106〜276か月ありas-of切断backfillが可能。→ `docs/research/cmd_4140_deterioration_history_recon_20260723.md`
- L802: precompute paramsはFE PAGE_APISから機械抽出して実要求との差分を照合する（cmd_3667）
- L803: FE要求params整合テストはpage.tsxではなく別module定数をSSOTにする（cmd_3668）
- cmd_3668/3669: FE実要求paramsとprecompute raw paramsの同期防御。dashboard performance yearsは `frontend/app/dashboard/page.tsx` の共有定数経由で呼び、`backend/tests/test_precompute_raw.py` がPAGE_APIS内の直書き `api.getPerformance(portfolioId, 3/0)` 不在を検査する。FE params lessonは `tasks/lessons.md` L803。関連commit: DM-Signal `49e9d8f6`, `3730537c`。
- cmd_3685: `sync-prices` はREFETCH_DAYS窓ではなく全期間を要求する。対象は `backend/app/jobs/data_fetcher.py` / `backend/app/jobs/sync_layers.py` / `backend/app/api/etl_trigger.py`、回帰テストは `backend/tests/test_data_fetcher_full_period.py`。関連commit: DM-Signal `75c4444d`。
- L793: Render cron envVarsはAPI現物で検証せよ（cmd_3634）
- L794: 月次cronのUTC day-of-month指定はJSTタイムゾーンオフセット越境で1日ずれる（cmd_3634_recon3）
- ETL cronはL0-L3の4本体制。L0/L1/L2/L3の各レイヤーを独立cronで同期し、L1-L3は`/admin/sync-status`の上流`last_success_date`がUTC当日になるまで待機してから本番DBを読む。
- L0-L3各sync cronで全期間再計算が完結する。途中レイヤーだけの手動補正で完了扱いにしない。
- L0: base/standard系、L1: 忍法・四神派生、L2: 奥義・合成standard、L3: FoF/入れ子FoFの同期境界として扱う。
- `daily_etl.py`は冗長であり廃止予定。
### Render CLI (v2.12.0)
`/home/simokitafresh/.local/bin/render`。認証済み(simokitafresh@gmail.com)。ワークスペース=My Workspace。
**DM-Signalサービス一覧:**
| 用途 | 名前 | ID | type | region |
|------|------|-----|------|--------|
| **Backend** | dm-signal-backend | `srv-d4ja7q15pdvs739a4q1g` | web | singapore |
| Frontend | dm-signal-frontend | `srv-d4ja8pp5pdvs739a5fsg` | static | — |
| **DB** | dm-signal-db | `dpg-d542chchg0os73979vg0-a` | postgres | singapore |
| TEST Backend | TEST-dm-signal-backend-lyk3 | `srv-d5ahs0ali9vc73b6tprg` | web | singapore |
| sync-prices | dm-signal-sync-prices | `crn-d5e8rabe5dus73fhlkj0` | cron | oregon |
| sync-tickers | dm-signal-sync-tickers | `crn-d5e8rabe5dus73fhlkkg` | cron | oregon |
| sync-standard | dm-signal-sync-standard | `crn-d5e8rabe5dus73fhlkl0` | cron | oregon |
| sync-fof | dm-signal-sync-fof | `crn-d5e8rabe5dus73fhlkjg` | cron | oregon |
| deterioration | dm-signal-deterioration-batch | `crn-d6kehqlm5p6s73dov630` | cron | oregon |
| pw-rotation | dm-signal-password-rotation | `crn-d53agure5dus73ap8el0` | cron | singapore |
**主要コマンド:**
| コマンド | 用途 | 備考 |
|---------|------|------|
| `render ssh srv-d4ja7q15pdvs739a4q1g` | Backend SSH | 本番インスタンスに接続。対話的操作 |
| `render ssh -e srv-d4ja7q15pdvs739a4q1g` | エフェメラルSSH | 本番影響なし。計測・調査用 |
| `render jobs create srv-d4ja7q15pdvs739a4q1g --start-command '...'` | one-offジョブ | バッチ計測等。--plan-idでリソース指定可 |
| `render psql dpg-d542chchg0os73979vg0-a` | PostgreSQL直接接続 | DB ID指定。クエリ計測 |
| `render logs --output text srv-d4ja7q15pdvs739a4q1g` | ログ閲覧 | ジョブ出力確認 |
| `render deploys list srv-d4ja7q15pdvs739a4q1g` | デプロイ履歴 | |
| `render whoami` | 認証確認 | |
**サービス名でも指定可能**（ID暗記不要）: `render ssh dm-signal-backend`
★ cProfile等の計測はRender上で実行すべき。ローカル→Singapore RTT 80msがDB I/O比率を歪める(2026-04-17実証)。
★ cronジョブのregionがoregon(render.yamlではsingapore指定)。DB(singapore)とcron(oregon)間でRTTが発生している可能性。要確認。
## §38 シグナル変更アラート
- cmd_3684/3686: confirmed holding signal rewrite検知はntfy pushへ接続済み。個別POST連打ではなくbatch summary 1通に集約する。対象は `backend/app/jobs/flush/signal_flush.py`、回帰テストは `backend/tests/test_flush.py`。関連commit: DM-Signal `6b460ecf`, `0b034e3d`。
- cmd_3684: `render.yaml` にシグナル変更アラート用envを追加。Render envはAPI現物で確認する。関連commit: DM-Signal `6b460ecf`。
- cmd_3684直前: debug endpoint lint正規化は機能変更ではなく差分整理。関連commit: DM-Signal `67da37c4`。
- cmd_3686直前: confirmed holding signal rewrite検知は `recalculate_fast.py` / `recalculate_fof.py` / debug endpointにも接続されている。関連commit: DM-Signal `ca170887`。
- L809: 無音書換え警報のpending/確定境界は日付ではなく出自(marker)で判定する（cmd_3679）
## §39 月初signal input snapshot
- cmd_3687相当: 月初signal input snapshotを追加。DB migration/model、`recalculate_fast.py`、Render設定、`backend/tests/test_month_start_input_snapshots.py` が対象。運用確認時はsnapshotテーブルの作成と月初入力保存の両方を見る。関連commit: DM-Signal `88c29a92`。
- L805: 月初シグナル前に前月最終営業日価格の上流可用性をゲートする（cmd_3677）
- L806: 価格調査でupdated_atを初回到着時刻として扱わず、fetch jobログ等の一次情報で確認する（cmd_3677_recon2）
- L807: 価格値履歴なしでは月初シグナル分岐の旧入力値を復元できない（cmd_3680）
- L808: reference_assetモード判定の反証はコード差だけでなくprices/economic_indicators値履歴不在を先に確認する（cmd_3680_recon2）
### パリティ全基準チェックリスト（殿定義集約 2026-04-11）
本番DB操作cmdのACに以下を全て含めよ。1つでも欠落したらFAIL。
| # | 基準 | 定義 | 出典 |
|---|------|------|------|
| P1 | **holding_signal完全一致** | 全期間。GS独立計算 vs 本番DB | 殿教示 2026-03-22 |
| P2 | **monthly_return完全一致** | 全期間。差<1e-6(IEEE754許容) | PI-009運用基準 |
| P3 | **既存PF不変** | ゴールデンデータ突合。新規以外の全PF | PI-023 |
| P4 | **FE UI全ページ整合** | Dashboard/Compare/Signals/Detail/Admin MECE確認 | 殿指示 2026-04-11 |
| P5 | **hide-first原則** | is_visible=false→PASS後に表示切替 | PI-023 |
| P6 | **本番がground truth** | 不一致ならGS側の問題。本番を疑わない | 殿厳命 2026-03-22 |
追体験: [[dialogue_parity_experience_20260407]] (ALMパリティ三重事故→PI-023→道具磨き→追体験の意味)
旧アーキ資料(`cmd_286_recalculate-architecture.md`)は未復旧。再計算の一次情報は実コード(`backend/app/jobs/recalculate_fast.py`)を参照。
- L155: monthly_trade_calculatorのpending判定はtrigger固定monthlyで全PFに同一ロジック適用していた（cmd_524）
- L157: pending判定は『存在チェック』より先にrebalance月 gatingを入れないと非月次triggerで誤表示する（cmd_525）
- L268: managed DBではpool_pre_ping=True必須。workerごと独立キャッシュはヒット率低下する（cmd_831）
- L319: p_average_results本番テーブルが空（バッチ未実行 or cold sleep）（cmd_981）
- L330: sync-fof API実行後の検証は60秒以上待て。locked=falseでも再計算進行中の可能性あり（cmd_1004）
- L332: FoF of FoF partial recalculate-syncはlive dataを欠損させうる。L3正規経路で復旧（cmd_1004）
- L645: sync-status解除だけでL3完走と見なすな。manual syncのL3は current run の `[RECALC] Layer 3 completed` ログまたは timing-history 新規行を一次証跡とし、71/109 FoF時点の進捗断片ではFAIL扱いとする。L0=12s/L1=13s/L2=151sまでは完走確認済み（cmd_2235）
- L474: recalculate_fast.pyの事前計算はPipelineEngineと同一データソース(df_dtb3_raw)を使え。reindex済みデータは日付ズレの原因（cmd_1245）
- L475: Phase 3.7 DTB3リサンプル問題。DTB3をprice_datesにreindexするとrolling(N)の参照日がPipelineEngine(DTB3固有日付)と不一致。PI-010同根（cmd_1245）
- L477: FoF recalculate時のPYTHONPATH問題。CLIからrecalculate_fast.py実行時にsys.path.insert(0,backend)必要。selection_pipeline動作乖離も確認（cmd_1250）
- L502: momentum_data月中縮小でDB書込み95%削減可能。LOOP-1 Signal DB書込みは月変わり以外は差分なし（cmd_1447）
- L638: upfront cleanup後worker restartで本番データ空化リスク。replace系precomputeはbegin_nested(savepoint)で範囲限定必須[PI-025]（cmd_2131）
- L647: monthly_returns_genがFoF数増加(59→109体+85%)に対し非線形増大(49s→241s+391%)（cmd_2257）
- L648: dw_signals_flush(62s)が計測システムから除外されunmeasured_pctを誤解させる（cmd_2261）
- L634: マイグレーションスクリプトのテーブル名バグが本番未適用の根因（cmd_2016）
- L636: nested FoFのMonthlyReturnは生成ログでなくDB実データ確認必須（cmd_2025）
- L357: 本番DB確認はPostgreSQL必須。SQLiteミラーは不完全（cmd_1025）
- L261: precomputeテーブル欠落はhealth endpointでdegradedに昇格させる（cmd_828）
- L675: recalculate-sync POST後のstatus待機は初回idleを完了扱いにする。running=false即返しの場合あり（cmd_2392）
## §9 性能ベースライン
- L870: run不変値(commit hash等)は開始時に一度固定し日次ループで定数再利用。外部process再取得はsubprocess238回=21秒消費の実害（cmd_3840）
| 段階 | 全体 | L2(Standard) | L3(FoF) | signal_calc |
|------|------|-------------|---------|-------------|
| 初回 | 11,818s | — | — | — |
| OPT-A/D/F | 2,397s | — | — | 2,007s |
| OPT-E | 389s | — | — | 0.53s |
| OPT-1/2(cmd_1448) | 564s(本番) | — | — | 0.53s |
| ローカル(cmd_1444) | 349s | — | — | 0.53s |
| OPT-A/6/perf_calc除去(cmd_1454) | 260s(本番) | 155s | 62s | 0.53s |
| Cycle 1 baseline(cmd_1466) | 637.80s | 240.66s | 362.27s | 1.06s |
| Cycle 2(cmd_1474) ※FAIL | 380.53s※ | 109.65s | 235.37s | — |
| **Cycle 3(cmd_1478) OPT-12~15全反映** | **357.28s** | **109.47s** | **214.01s** | 1.10s |
| **Cycle 4(cmd_1482) trade_perf/risk_mgmt初実測** | **479.94s** | **~239s** | **210.27s** | — |
※cmd_1474はネステッドFoF 15体未処理(FAIL)のため無効値。cmd_1466 637.80sとcmd_1454 260sの乖離=計測範囲+データ量差。
※Cycle 4の+123s=trade_perf(126.46s)+risk_mgmt(2.86s)初実測が主因(cmd_1479バグ修正後)。性能劣化なし。L3安定(214→210s)。
OPT一覧(1-15):
| OPT | 内容 | 状態 | cmd |
|-----|------|------|-----|
| OPT-1/2 | Signal+Portfolio一括ロード | ✅本番適用 | cmd_1448 |
| OPT-3 | business_days pure版化 | ✅本番適用 | cmd_1464 |
| OPT-4/5 | Trade Perf一括ロード+Phase4.5 OPT-6適用 | ✅本番適用 | cmd_1455 |
| OPT-6 | signal_cache共有(MR gen 512→56s) | ✅本番適用 | cmd_1455 |
| OPT-12 | gc.collect削減(59→5回)+fof_signals dead code除去+profiling改善 | ✅本番適用 | 軍師直接 |
| OPT-13 | ネステッドFoF回帰修正(signal_cache→DB補完) | ✅本番適用 | 軍師直接 |
| OPT-14 | Standard PF signals flush INSERT化(cleanup_mode=True) | ✅本番適用 | 軍師直接 |
| OPT-15 | component_weights commit集約(59→6) | ✅本番適用 | 軍師直接 |
本番ボトルネック(cmd_1482後480s): L2 trade_perf **126.46s(26%)実測確定** > L3 daily_loop 67.88s(14%) > L3 mr_gen 55.21s(12%) > L2 db_write 44.89s(9%) > L3 dw_signals_flush 41.93s(9%)
初回→現在: **95.9%削減(11,818s→479.94s)**。Cycle 1→Cycle 4: **-24.8%**。※Cycle 3(357s)→4(480s)はtrade_perf計測修正(+129s)であり劣化ではない
残改善ターゲット: L2 trade_perf残(whileループNumPy化, cmd_1503偵察中)、L3 daily_loop(部分batch化, cmd_1506偵察中)
軍師詳細分析: `context/gunshi-fullrecalc-speed-analysis.md` (3サイクル比較・ボトルネック構造・予測精度検証)
**cmd_3831偵察(2026-07-10, PF数103体時点の再実測)**: trade_perf **272.35s(L2内86.3%)に肥大化**(旧126.46s比+115%、PF数増加+ネスト階層化が要因)。主犯は月次whileループではなく`_extract_trades_unified()`が全営業日1件ずつ`expand_portfolio_to_tickers()`を再帰呼出しする箇所(`trade_performance.py:575-587`)。ネスト2-3階層(秘奥義/奥義系)は1PFあたり5-21秒、単層(シン四神/GS忍法)は2秒未満(実測ログ確認済み、cmd_1503のwhileループNumPy化仮説は本実測で棄却=while_iters側は既に軽量)。**TIMING SUMMARYがL2を誤BOTTLENECK表示するバグも同時特定**: Layer 5 raw precompute(`precompute_raw_for_portfolios`)が`LayerTimer`(`utils/timing.py:74 LAYER_ORDER`)に未登録のため、実際は66.5%(1659.78s/2497s)を占めるL5が表から消え、22.7%のL2がBOTTLENECKマーカーを得る。詳細・実装候補3案(New Fund of Funds_copy系要否確認/メモ化/ベクトル化)・precompute-fullspeed-goal-design(Layer 5)との非衝突確認 → `docs/research/cmd_3831_trade_perf_recon.md`
**cmd_3843試行→cmd_3845でrevert済み(2026-07-11)**: 2,500日fixtureでは展開2,500→1回・91.70%減だったが、全102PF照合は旧/新とも本番baselineに554行/24PF（浮動小数末尾約1e-16）不一致、実測も113.379s→124.623s（9.917%退行）。許容誤差ゼロによりFAILし、メモ化3 commitをrevert。本番push/deploy/fullrecalculate未実行。詳細 → `docs/research/cmd_3845_memoize_parity.md`
- L503: DM-SignalリポジトリにGitHub Actionsワークフロー未設定(.github/workflows/不在)（cmd_1448）
- L504: 性能異常値はリソース競合を先に疑え。pipeline_exec 626sは同時実行run起因のanomaly（cmd_1456）
- L136: 改善候補調査前に既存最適化履歴を照合する（cmd_474）
- L137: FoF計測はLayerTimer.substepではなくL3 metadata.profilingで確認（cmd_475）
- L138: trade_perf調査はtiming実測→コード読解の順（cmd_475）
- L545: 逐次PF計測では先頭PFウォームアップ外れ値を切り分けよ（cmd_metrics_R1）
- L589: tracemallocデフォルトdepth=1では不足。depth=30+ファイルフィルタで真の呼出行特定（cmd_1826）
- L649: CDP再計測retryはartifact pathを分離せよ（stale run上書き防止）（cmd_2268）
詳細: `docs/research/gunshi-opt12-fullrecalc-analysis.md` §本番内訳 参照
補助参照: `docs/research/cmd_484_dm-signal-supplemental-catalog-2.md` AC1-2（scripts一覧）
| 項目 | 結論 | 参照 |
|---|---|---|
| cmd_790 APIベースライン | 15体×3 endpoint + `/api/signals` + `/api/metrics/summary` を `2026-03-11-v2/` に固定保存。monthly-returns は169-231ヶ月、全件 `year_month` あり。 | `→ /mnt/c/tools/multi-agent-shogun/queue/archive/cmds/cmd_790_completed_20260311.yaml` / `→ /mnt/c/tools/multi-agent-shogun/queue/archive/reports/hanzo_report_cmd_790_20260311.yaml` / `→ /mnt/c/tools/multi-agent-shogun/queue/archive/reports/saizo_report_cmd_790_20260311.yaml` |
| cmd_3526/3530 Metrics/Compare Summary | `/api/metrics/summary` は追加benchmark capture修正(cmd_3526)と投資継続性5指標(cmd_3530)を反映済み。関連FEはMetrics/Compare Summary/Summary table、関連BEは `backend/app/api/metrics.py` + `backend/app/services/metrics_impl.py`。 | DM-Signal commits `499bfe37`, `eaf2741d` |
| 59146c43 deterioration benchmark | Compare SummaryにSPY/TQQQ P_det benchmark表示、deterioration benchmark services、page_visibility enforcementを追加。運用確認時はbenchmark_returns/deterioration_benchmarks/page_visibilityの3系統を見る。 | DM-Signal commit `59146c43` |
| cmd_791 Phase2b BE最適化 | `/api/monthly-returns` から `expanded_tickers` 除去 + months前倒しを実装。15体diff完全一致PASS、monthly-trade側 `expanded_tickers` は維持。 | `→ /mnt/c/tools/multi-agent-shogun/queue/archive/cmds/cmd_791_completed_20260311.yaml` / `→ /mnt/c/tools/multi-agent-shogun/queue/archive/reports/kotaro_report_cmd_791_183558.yaml` / `→ /mnt/c/tools/multi-agent-shogun/queue/archive/reports/kagemaru_report_cmd_791_20260311.yaml` |
| cmd_792 ETag有効化 | FEの304誤判定を修正。`etagStore → apiCache` 復元経路で既存ETag 3件を実動化。`tsc --noEmit` PASS、api-client tests 19 PASS。 | `→ /mnt/c/tools/multi-agent-shogun/queue/archive/cmds/cmd_792_completed_20260311.yaml` / `→ /mnt/c/tools/multi-agent-shogun/queue/archive/reports/hanzo_report_cmd_792_190031.yaml` |
| cmd_763 workers=2復帰 | 認証修正完了後の復帰cmd。CDP比較基準は workers=1時点で cold 128ms / warm 149ms / PF切替 1005ms。 | `→ /mnt/c/tools/multi-agent-shogun/queue/archive/cmds/cmd_763_completed_20260311.yaml` |
| cmd_746 CDP計測基盤 | cold/warm・PF切替・SPA遷移・API個別計測・baseline自動比較を一発実行可能化。実戦値: Dashboard cold 126ms / warm 152ms、PF切替 1003.9ms、compare-summary 155ms、monthly-returns 191ms、deterioration 170ms。 | `→ /mnt/c/tools/multi-agent-shogun/queue/archive/cmds/cmd_746_completed_20260311.yaml` / `→ /mnt/c/tools/multi-agent-shogun/queue/archive/reports/kagemaru_report_cmd_746_20260311.yaml` |
- L177: 本番404切り分けはopenapi.json実測でデプロイ未反映を即時判定できる（cmd_553）
- L178: 本番404調査はopenapi実測で『ルート未登録』を先に確定すると切り分けが最短になる（cmd_553）
- L179: 新サービスのimport文とrequirements.txtの突合確認をデプロイ前チェックに含めるべき（cmd_554）
- L903: 配備target pathはgit HEADで存在確認してから実装する（cmd_karo_hotfix_ledger_drift_alert_persistence_202607161356）
- L180: render.yaml cronジョブ追加時envVars sync:falseのシークレットはRenderダッシュボード手動設定が必要（cmd_554）
- L190: 集計要件でrole分離が必要ならイベント記録時点で識別子を保存しないと後段SQLでは復元不能（cmd_574）
- L202: Render Static Siteのheaders.pathはrootと配下階層を別globで覆わねば全txtを捕捉できぬ（cmd_643）
- L321: admin tier系テストはRender env同期を実APIに飛ばすとローカルsuiteを汚染する（cmd_987）
- L766: WF trial速度計測はcache warm/coldを分けて3回測る（cmd_3514）
- L768: SQLite /mnt/c p9停滞→ローカルcopyまたは事前matrix cacheを使う（cmd_3515）
## §12 計算データ管理
- L832: 境界近傍のゲート判定は『合成式の代数的一致』では不十分。入力値(DTB3等)そのものの数値一致まで検証せよ（cmd_karo_recon2_cmd3772_dmsafe_pi009_202607081452）
- L851: matched_weightは固定1.0でなくsum(weights)と比較。missing_tickers=[]でもweights和が1未満ならmatched_weight<1（cmd_3808）
- L929: parity検証範囲は設計のintersection cohort契約に一致させる。native末尾境界差を全期間BLOCKへ昇格するな（cmd_karo_nxe_2d_robustness_20260802）
命名: `{cmd番号}_{ブロック名}_{説明}.csv` + `.meta.yaml`。上書き禁止(`_v2`)。
テンプレ: `scripts/analysis/grid_search/template_gs_runner.py` は現treeに不在（再配置待ち）。
ローダ: `scripts/analysis/grid_search/gs_data_loader.py`（現行DBローダ） / `scripts/analysis/grid_search/gs_csv_loader.py`（CSV互換）
GS全6ブロック: `scripts/analysis/grid_search/run_077_{block}.py`
PD-028裁定: GS制約同期は仕組み化しない。BBカタログにPydantic制約明記+PARAM_GRID修正で運用。
補助参照: `docs/research/cmd_484_dm-signal-supplemental-catalog-2.md` AC1-2
- L175: 統合レビューでのパリティ検証は関数シグネチャ+定数+アルゴリズム3層で行う（cmd_550）
- L621: monthly_fast成果物探索はcache-onlyも許容せよ(.csv欠損+.cache.*.npyのみ残存ケースあり)（cmd_1882）
- L585: AC output_pathはoutputs/grid_searchとoutputs/analysisを混同するな（cmd_1796）
- L142: CSV記述は入力ソースと成果物を分離しないと知識汚染が再発（cmd_492）
- L767: 成果物パスに忍法名を含めて混線を防ぐ（cmd_3514）
- L815: GS全量速度計測では月次系列成果物とチャンピオン選出成果物を分離する（cmd_goal_gs_speed_e2_l3_kasoku_diff_202607060819）
- L858: パリティ残存乖離の原因は推測せず3点突合(本番/ライブ実行/GS)で必ず切り分けよ（cmd_3816）
## §14 ドキュメントインデックス
**CoDD適用方針設計書**: `docs/research/codd_dmsignal_python_strategy.md` — DM-Signal Python高速化の全体方針。§0前提条件(環境/コマンド/成功条件)+§3ワークフロー(Phase 1-4)+§5本番防御層。CoDD改善cmd着手前に必読
**Level A cProfileインベントリ**: [[cmd_1987_level_a_cprofile_inventory]] (`docs/research/cmd_1987_level_a_cprofile_inventory.md`) — 設計書§2 Level A 15本の実在確認+cProfile実測結果(10本成功/5本環境制約)
docs/skills/(25件) + docs/rule/(25件)全一覧 + DB接続・パリティ検証・API使用法ルール抜粋。
補助参照: `docs/research/cmd_485_dm-signal-environment-catalog.md`（環境/Render/API） + `docs/research/cmd_488_dm-signal-claude-config-catalog.md`（運用設定）
- L169: 設計書補完はMECE表+仕様章リンクの二層化で抜け漏れを抑制できる（cmd_549）
- L170: 仕様レビューは章番号突合+commit差分限定の二段検証で誤判定を防げる（cmd_549）
- L184: Docsの新指標説明は判定条件をテーブル化すると実装定義との突合が速い（cmd_557）
- L194: テスト棚卸しcmd発行前にvenv/pytest環境確認を前提条件に含める（cmd_623）
- L657: deploy cmdは依存cmdの報告とcommit SHAを起票前に照合する（cmd_2311）
- L666: ACはWHAT(二値判定)のみ記載。HOW(検証手法)を混入させるな（cmd_2346）
## §16 知識基盤改善（穴1/2/3対策完了 — 2026-02-22）
| 穴 | 対策 | cmd |
|----|------|-----|
| 1 教訓登録ボトルネック | auto_draft_lesson.sh | cmd_232+242 |
| 2 知識鮮度管理 | context last_updated+鮮度警告 | cmd_239 |
| 3 裁定伝播遅延 | resolve時context未反映フラグ | cmd_239 |
| 補助 lesson sync上限不足 | sync上限を50に引き上げ | cmd_241 |
原則: 検出+警告のみ。自動修正はしない（指示系統厳守）。
PD-042反映: DM-signal側24スキルの`allowed-tools`/`argument-hint`/`description`品質改善を一括実施済み（cmd_448）。
- L149: key_files成果物パターンは実在ファイル名規約と定期照合しないと再汚染する（cmd_493）
- L150: 復旧ドキュメントは『在庫あり証跡』と『在庫不足』を分離記述すると誤再構成を防げる（cmd_493）
- L307: 偵察3回×延べ24名の知識基盤構築には統合専任担当(水平H)が不可欠（cmd_862）
- L144: context圧縮時は参照先存在確認を先に実施。リンク先なき圧縮禁止（cmd_492）
- L143: research層消失はリポジトリ側git操作起因の可能性を先に切り分ける（cmd_492）
- L141: docs実在性チェックをCI化しないと運用手順が陳腐化（cmd_492）
- L140: registry統合など構造変更時は知識汚染が集中する（cmd_492）
- L553: 原理1行が各論パッチ30行に勝る。既存の仕組みを1行磨け（cmd_1741）
- L552: 因果推論に複利の問いを含めよ。10回繰り返し効果を自問（cmd_1741）
- L536: auto-commit巻き込み確認: git status+git log直近セットで差分確認（cmd_1693）
- L329: 生成artifact修正はgenerator scriptへも同修正を戻せ（cmd_1005）
- L139: 依存マップはgrepより先にAST循環解析を実行する（cmd_478）
- L308: KB浄化cmdは解釈移送先ファイルをACで明示せよ（cmd_871）
## Ops教訓索引
<!-- lesson_sync: 2026-03-03 lesson-sortでL129-L146を反映 -->
- L791: 追加指示の取消は未commit差分からscope別に除去する（cmd_3586）
- L821: 本番適用cmd着手時はgit log origin/main..HEADでpush状態を先に確認せよ。前段cmdのGATE CLEAR=push完了ではない（cmd_3704）
- L812: DM-Signalのgit commitがlefthook pre-commitでBash既定2分timeoutを超える場合、9pスタルと決めずtimeoutを上げて再試行する（cmd_3686）
- L810: 新規importのトップレベル追加はmixed-commit BLOCKやruff空コミット化を招くため、repo-checksの分割境界を先に確認する（cmd_3684）
- L900: subprocess moduleはpackage名でなくapp-dirで探索根を固定する（cmd_karo_ci_red_dm_p4_uvicorn_import）
- L901: 永続helperはchecked-in source同期後に実行する。live PIDだけのhealthy判定とpgserver cleanupのno-opに注意（cmd_karo_ci_fix_ga256_cmd3907）
- L943: runner等で成果byteが変わるとprepare fingerprintが失効する。検証完了後にprivate prepareして直ちにscope commitする順序を守れ（cmd_karo_recon_cx_oracle_lane_preflight_20260803）
- L947: scope fingerprintはprivate-index所有path集合と同じ集合で算出する。集合が異なると正当commitがBLOCKする（cmd_karo_recon_dx_transaction_topology_preflight_20260803）
<!-- lesson-sort 2026-04-27: 40件振り分け(30件移動+5件削除+2件重複除去+3件既存確認)
  §6-7: L634,L636,L357,L261 (L645既存,L637≈L638重複削除)
  §9: L136,L137,L138,L545,L589,L649
  §12: L621,L585,L142
  §16: L144,L143,L141,L140,L553,L552,L536,L329,L139
  §17: L644
  §18: L624,L558
  §32: L628,L629,L632
  削除: L579,L582,L584,L256(自動生成具体性なし),L571(deprecated)
-->
| L735 | 履歴分割任務はdirty本線で直接rewriteせず隔離worktree成果branchを明示する | git運用 | cmd_3301 |
| L733 | worktree pytest比較ではenv(.env/.env.local)有無を先に二値確認する | テスト運用 | cmd_3301系hotfix |
| L730 | 削除済みBlockTypeはruntime全経路(recalculate_fast含む)で残参照検査する | 再計算 | cmd_3293 |
| L729 | baseline同等ACとall-tests-pass hookの衝突時はscope外修正前に停止する | 運用手順 | cmd_3290 |
| L723 | 鮮度gateはAPI失敗とデータ未実行を同一ALERTに畳まずfallback経路も検証対象に含める | gate設計 | recon_202606 |
| L721 | test_*.pyでもテスト関数ゼロはpytest収集0件で空振り。AC実行確認はsmoke test要件を明示 | テスト運用 | cmd_2656 |
| L135 | 参照先scripts消滅時は教訓参照をdeprecatedとして明示する（旧L010） | 知識基盤 | cleanup |
| L134 | 参照先scripts消滅時は教訓参照をdeprecatedとして明示する（旧L025） | 知識基盤 | cleanup |
| L133 | セッション開始時にtodo.md/lessons.md必読 | 運用手順 | — |
| L132 | GS構成四神と本番FoF構成PFの不一致に注意 | PF登録 | — |
| L131 | gitignoreパターンとgit復元対象のクロスチェック必須 | 運用プロセス | cmd_430 |
| L130 | commit前にgit diff --cachedでステージ全体を確認する | 運用プロセス | cmd_427 |
| L129 | 注入教訓のreviewed確認を怠ると後続ゲートで詰まる | 運用プロセス | cmd_356 |
| L128 | experiments.dbはスナップショット、SSOTではない | DB | — |
| L127 | PowerShell -replace/Set-ContentでUTF-8文字化け | ツール | — |
| L126 | ブロック名はBlockType enum値で統一 | 設定規約 | — |
| L125 | pipeline_configパラメータ名はコードと1:1一致 | 設定規約 | — |
| L123 | WSL2 matplotlib日本語フォント: font_manager.addfont()でWindows側.ttc登録 | ツール | subtask_288 |
| L152 | レビュータスクのAC4は『対象テストPASS』と『静的検証ベースライン健全性』を分離して判定すべき | 運用プロセス | cmd_515 |
| L158 | WSL上のWindows venvでは .venv/Scripts/python.exe 経由でpytestを実行できる | ツール | cmd_525 |
| L167 | WSLでWindows venv Python分析タスクは端末ログ文字化けに備えてCSV実体検証を必須にする | ツール | cmd_539 |
| L122 | write後はGETキャッシュ明示無効化必須(TTL=3600s) | API/キャッシュ | cmd_283 |
| L121 | backend API実コード確認必須(YAML仕様と乖離あり) | API/FE | cmd_283 |
| L119 | DATA_CATALOGの86銘柄=本番DB、experiments.dbは14銘柄のみ | DB | cmd_282 |
| L118 | DTB3はdaily_pricesにticker='DTB3'格納(economic_indicatorsは空) | DB | cmd_282 |
| L109 | 分析スクリプトにtimeout必須(idle誤判定→clear事故) | 運用 | cmd_274 |
| L107 | DATA_CATALOG掲載+meta.output.file実在で二軸照合 | データ管理 | cmd_265 |
| L106 | deploy_task.sh報告上書き消失(L103再発、構造的対策未実装) | 運用プロセス | cmd_263 |
| L105 | BB config未拘束がGS無効パターン量産根因。build_grid直後に制約注入 | GS | cmd_264 |
| L103 | 報告YAML後続deploy上書き消失。統合タスクは偵察報告と同時deploy | 運用プロセス | cmd_253 |
| L099 | LIKE '%ReversalFilter%'→TrendReversal誤検知。jsonb_path_existsで解決 | DB | — |
| L085 | テストPF削除は16テーブルFK依存順(4テーブルでは不足) | DB | cmd_215 |
| L084 | recalculate-status is_running=None≠完了。DB行数カウントで判定 | 再計算 | cmd_215 |
| L677 | SQLite移動後検証はquick_check+MD5で十分。full integrity_checkは10分 | ツール | cmd_2393 |
| L678 | ベンチマーク計測は合成データで書込み時間を分離せよ | ツール | cmd_2397 |
| L680 | GS runner実行前にAC記載CLI引数が実装argparseと一致するか確認せよ | GS | cmd_2405 |
| L684 | run_077は--out-dirのみ定義で--output-dirエイリアス欠落があるケースに注意 | ツール | cmd_2411 |
| L688 | Payload再生成時は内部メタデータを保持して検証する | ツール | cmd_2423 |
| L692 | method ID/ファイル名は実SSOTと照合して報告に明記する | 運用 | cmd_karo_ctx |
| L708 | FoF履歴不足調査はvalid_start_date計算を突合せよ | 運用 | cmd_2454 |
| L710 | L0-L4語彙は新cmdでprefix必須にすべき | 運用 | cmd_2553 |
| L713 | metrics偵察はadd_metric行だけでなく前段DataFrame変換も母集団に含める | ツール | cmd_2570 |
| L716 | metrics APIのNHF表示名はNew High Frequency | ツール | cmd_2577 |
| L717 | 追加ベンチマークはticker_monthly_returnsだけでなくprices fallbackを確認せよ | ツール | cmd_2578 |
| L104 | subtask間依存で.gitignoreが後続コミット計画をブロックしうる | 運用プロセス | cmd_259 |
| L714 | recalculate-sync acceptedは完了ではない。DB recalculation_statusのcompleted確認が必須 | 再計算 | cmd_2574 |
| L082 | `monthly_returns.portfolio_id(varchar)` と `portfolios.id(uuid)` は比較前に `id::text` で型統一 | DB | cmd_214 |
| L081 | recalculate Phase0では`monthly_returns`が一時的に空になる前提で検証順序を組む | 再計算 | cmd_214 |
| L080 | save APIの`success=False`でもDB登録済みケースあり。削除確認はDB直接参照が確実 | API/DB | cmd_207 |
| L079 | sync-fof APIの409 conflictはリトライ+待機で吸収する | API | cmd_207 |
| L076 | Layer lockはプロセス内限定。再計算の終点保存はUPSERTで冪等化する | 再計算 | cmd_212 |
| L075 | 新規PFのrecalculateには`recalculate-sync`を使う | 再計算 | cmd_205 |
| L067 | 殿の個人PF(35体)は本番DBから削除・変更しない | DB運用 | cmd_198 |
| L066 | 殿裁定事項はMCP/projects/lessonsの3箇所に恒久化する | 運用手順 | cmd_196 |
| L064 | 本番データ取得は`DATABASE_URL`でPostgreSQL直結。API経由を避ける | DB/API | cmd_194 |
| L063 | `download_prod_data.py monthly-returns`は大量エラーでもexit 0になりうる | ツール | cmd_194 |
| L038 | `sync_lessons.sh`は`## N.`節末尾で`### L0xx`取りこぼしが起こりうる | ツール | cmd_137 |
| L036 | `recalculate-sync`の`start_date`パラメータは無視される | API/再計算 | cmd_128 |
| L035 | FoF参照L0 PFはDELETE不可。UPDATE方式を採用する | DB運用 | cmd_128 |
| L034 | Claude CodeはRead未実施ファイルへのWrite/Editを拒否する | 運用手順 | karo |
| L029 | `gs_metadata`でFoF鮮度情報を保持し追跡可能化する | データ管理 | — |
| L028 | ユーザー確認なしの設計変更を禁止し、裁定を先に取る | 運用手順 | — |
| L025 | GSスクリプト/データ同期スクリプトはパス規約を統一する | 運用手順 | — |
| L021 | 新規スクリプト作成前に既存スクリプトを必ず調査する | 運用手順 | — |
| L015 | 本番API呼び出しは`requests + HTTPBasicAuth`で実装する | API | — |
| L014 | `experiments.db`と本番DBのUUIDは別体系として扱う | DB | — |
| L011 | WindowsでのYAML/ファイル読込はエンコーディング明示を必須化する | ツール | — |
| L010 | `download_prod_data.py`実行時は`PYTHONPATH`設定を事前確認する | ツール | — |
| L009 | sync-fof APIはQuery Parameter方式（JSON Body不可） | API | — |
| L007 | 新FoF追加後の再計算は`sync-fof`（L3）を使う | 再計算 | — |
| L006 | 本番API呼び出しはPowerShell `Invoke-RestMethod`を使う | API | — |
| L004 | `experiments.db`はスナップショットでありSSOTではない | DB | — |
| L003 | PowerShell `-replace`/`Set-Content`でUTF-8文字化けが起こる | ツール | — |
| L223 | backend/.envは全体sourceせず必要変数だけgrep抽出すべし | 運用手順 | cmd_739 |
| L249 | Render env APIが認証SSOTでbackend/.envのviewer passwordは本番とズレうる | 認証/deploy | cmd_790 |
| L250 | APIフィールド除去テスト修正時はxfail/docstringまでgrepし旧仕様残存を潰す | テスト | cmd_791 |
| L273 | live API完全一致監査はcurrent partial monthを凍結or除外しないと日次更新ノイズで誤FAIL化する | テスト/監査 | cmd_856 |
| L339 | download_prod_data.pyのsilent failure検証 | ツール | cmd_1010 |
| L344 | analysis_runs/experiments.dbのschemaはdocs/_INDEXより先にlive確認せよ | DB | cmd_1017 |
| L345 | run_077グリッド数変更時DATA_CATALOG/analysis_runs/docsを同時更新必須 | データ管理 | cmd_1017 |
| L346 | cmd_426大掃除で旧GSパイプライン5本中4本削除済み、残存1本もimport不可 | 運用 | cmd_1017 |
| L347 | 統合偵察で前提sub報告未完了時は自力調査で速度を稼げ | 運用手順 | cmd_1017 |
| L349 | GitHub 100MB制限: GS出力CSVのサイズ事前確認必須 | 運用プロセス | cmd_1018 |
| L350 | サブディレクトリCSVはgitignoreの*.csvでは除外されない | 運用プロセス | cmd_1018 |
| L505 | Render再デプロイ直後のbackground taskクラッシュとmulti-worker status不整合 | deploy | cmd_1478 |
| L509 | target_pathのservices/jobs不一致に注意(実際のパスと指定の食い違い) | ツール | cmd_1488 |
| L510 | inbox_write.sh report_received auto-doneのflock deadlock | ツール | cmd_1508 |
| L515 | download_prod_data.pyのAPIフィールド名不整合(relative_momentum_tickers→relative_assets) | ツール | cmd_1572 |
| L528 | Windows環境YAMLファイル読み書きにはencoding=utf-8が必須(cp932デコードエラー防止) | ツール | cmd_1604 |
| L607 | 進行中月(当月)monthly_returnはGS作成日依存で差異が生じる。パリティ検証は当月除外を検討 | パリティ | cmd_1855 |
| L610 | バグ汚染ファイル削除はfindでプロジェクト全体検索→cmd記載件数との不一致を検出して全量把握 | 運用 | cmd_1863 |
| L614 | 既存スクリプトの関数を再実装するな(車輪再発明)。新スクリプト作成前に既存コードの再利用可能性を確認 | 運用 | cmd_1865 |
| L616 | cmdの完了記録≠成果物の所在記録。多段パイプラインの進行表に物理的所在(パス/DB名/UUID)を必須記録 | 運用 | cmd_1876 |
| L617 | gate_artifact_map.shで進行表の成果物所在チェック。完了ブロック空欄→WARN | ツール | cmd_1876 |
| L668 | shin universe GS runnerはALM固定DB参照をpreflightで検出する | ツール | cmd_2360 |
| L672 | cmd_2366 selector再実行時はchampion_list自動追記(append guard)を制御せよ | ツール | cmd_2386 |
| L676 | 大容量SQLite(8GB級)移動後検証はintegrity_check前にquick_checkを使う | ツール | cmd_2393 |
## §18 研究道具APIカタログ（cmd_1823追記）
研究cmdを書く前に必ずここを確認し、ACに使用スクリプトのパスと主要引数を明記せよ。
- L799: FEが解釈しないクエリ名を計測スクリプト入口でBLOCKする — mobile Lighthouse計測のPFクエリは`portfolio=`のみ有効（cmd_3654）
- L800: production固定Lighthouseは未deployローカル差分のPASS証明に使えない — local変更はlocal計測、本番証明はデプロイ後周回計測（cmd_3655）
### GS（グリッドサーチ）
**スクリプト**: `scripts/analysis/grid_search/run_077_{忍法}.py`
7本: `bunshin` / `kasoku_diff` / `kasoku_ratio` / `kawarimi` / `nukimi` / `oikaze` / `yotsume`
| 引数 | 説明 | デフォルト |
|------|------|-----------|
| `--universe <YAML>` | PF構成YAML | `config/portfolio_universes/alm_l0_12.yaml` |
| `--out-dir <dir>` | 出力ディレクトリ上書き | `outputs/grid_search/` |
| `--output-prefix <str>` | 出力ファイル接頭辞上書き | cmd ID自動付与 |
- **入力**: 本番PostgreSQL DB直接読み込み（CSV利用禁止 L064/cmd_214裁定）
- **出力**: `outputs/grid_search/{CMD_ID}_{忍法}_grid_results.csv` + `.meta.yaml`
- **実行例**: `python3 scripts/analysis/grid_search/run_077_oikaze.py --universe config/portfolio_universes/shin_ninpo_20.yaml`
- **所要時間(20体universe, meta実測)**:
  - bunshin ~1min / yotsume 57s / oikaze 218s(3.6min) / kawarimi 123s(2.1min)
  - nukimi **209s(3.5min)**(cmd_1829 BATCH_CHUNK=500 + SHM O(n)化。改善前106min→**30倍高速化**)
  - kasoku_diff **MP 24.5s**(cmd_1830 BATCH_CHUNK横展開。total 282.6s=CSV I/O律速) / kasoku_ratio 同等
  - **gs_runner.py並列(cmd_1831): 7本全量3 workers = 111.1s(1.9min)。改善前150min→79倍**
  - **★ボトルネックがCSV I/Oに移行**（kasoku_diff: MP 24.5s vs total 282.6s。258s=CSV書出し）
- **🔴 --help未実装**: run_077_*には--helpオプションがない。実行するとGSが即開始する
- **🔴 パターン数はuniverse体数で組合せ爆発**: 12体→119,493パターン / 20体→**944,775パターン(7.9倍)**。CSVサイズ・メモリ・実行時間が全てP比例
- L593: GSパターン数のC(n,k)スケーリング — universe体数変更で組合せ爆発（cmd_1826）
- L594: PythonのsetはPYTHONHASHSEED依存。GS sequential検証ではsorted()に置換せよ（cmd_1835）
- L813: run_077少数実行ACではCLI pattern-limit統一を先に検査する（cmd_3694）
- **メタ改善設計**: → `docs/research/gunshi_research_pipeline_meta_20260410.md`（GS共通基盤+並列ランナー）
### WF（ウォークフォワード）
**スクリプト**: `outputs/scripts/l1_alm_wf_engine.py`
| 引数 | 説明 |
|------|------|
| `--csv <path>` | GS月次CSVパス（単体実行） |
| `--cmd-id <id>` | cmd ID（出力ファイル名用） |
| `--progress` | 進捗表示 |
| `--multi-is` | IS窓6M-72Mを全探索（殿定義67窓） |
| `--multi-is-min/max <int>` | multi-IS範囲（デフォルト: 6/72） |
| `--batch-csvs <paths...>` | 複数CSV一括実行 |
| `--batch-workers <N>` | バッチ並列worker数 |
| `--batch-inner-workers <N>` | 各子プロセスのfold worker数 |
- **入力**: GS出力CSV（`outputs/analysis/alm_research/` 配下）
- **出力**: `{CMD_ID}_alm_returns.csv`（ALM系列6目的）+ サマリYAML
- **実行例**: `python3 outputs/scripts/l1_alm_wf_engine.py --csv <path> --multi-is --cmd-id cmd_XXXX --progress`
- **所要時間**: ~3-10分/CSV（`--parallel`時）。kasoku系は`--no-parallel`で30-60分/本
- **実測peak RSS(cmd_1827 Step1-7)**: oikaze 929MB / kasoku_diff 3.68GB / float64差 3.55e-15
- **🔴 `--parallel`/`--no-parallel`はCSVサイズで判断**: 小CSV(≤500MB)→`--parallel`(デフォルト)でOK。**大CSV(>500MB、kasoku系1.8GB)→`--no-parallel`必須**（並列worker合計でOOM。半蔵がkasoku_diff --parallelでRSS 6GB→OOM Kill実証済み）
- **🔴 `--batch-csvs`禁止（大CSV時）**: kasoku系(1.8GB)を含む場合、同時ロードでOOM。`--csv`で1本ずつ実行。小→大の順(bunshin→yotsume→oikaze→kawarimi→nukimi→kasoku_diff→kasoku_ratio)
- **🔴 kasoku系実行前**: `free -h`でavailable > 6GB確認。初回はmmapキャッシュ未生成→pandas read_csvピーク~3.6GB
- **peak RSS計測**: `/usr/bin/time -v python3 l1_alm_wf_engine.py ...` で包む
- **メモリ設計**: → `docs/research/gunshi_wf_engine_memory_fix_design_20260410.md`
- **🔴 WF並列実行(wf_runner.py)禁止**: 殿裁定(2026-04-10)。直列1本ずつが正解。cmd_1843 OOM事故(LG025)
### champion_selector.py（事後チャンピオン選出）
GS CSV/.npyから3目的(CAGR/NHF/MaxDD)チャンピオンを直列選出。NaN-safe+float64+チャンク+方向テーブル。
- **実行例**: `python3 outputs/scripts/champion_selector.py --csv-dir outputs/grid_search/okugi_shin_ninpo_20body --cmd-id cmd_1822`
- **性能**: 195万パターン→25秒/peak 1GB。kasoku_diff 944K: 8秒
- **方向テーブル**: CAGR/NHF=max, MaxDD=min（METRIC_DIRECTIONに埋込み。方向間違い構造的防止）
- **NaN-safe**: cumprod NaN伝播を回避(prod方式+有効月数年率化)。NHFはNaN月をnew highカウントから除外
- **設計書**: → `docs/research/gunshi_champion_selector_design_20260411.md`
- L590: tracemalloc≠RSS — メモリ目標はRSS(/usr/bin/time -v)で設定せよ（cmd_1828）
- L591: --parallel安全性は実測で確認せよ — 理論的安全≠実際の安全（cmd_1827）
- L600: np.fromstringは空セル連続のwide CSV行を安全に読めない（cmd_1841）
- L606: WF回帰テストは同一CSV2回実行での決定論確認。異なるCSV世代間比較は別用途（cmd_1856）
### research_engine（ライブラリ）
**スクリプト**: `scripts/analysis/standard_pf_preprocessing/research_engine.py`
**CLIなし** — import専用ライブラリ。
```python
from research_engine import (
    simulate_signals,          # PFシグナル計算（前処理fn注入可能）
    calculate_monthly_returns, # 月次リターン計算
    calculate_metrics,         # メトリクス計算
    calculate_signal_match_rate,      # 本番一致率
    calculate_production_match_rate,  # 本番一致率（詳細版）
    load_all_standard_pf_configs,     # 全PF設定ロード
    load_prices, load_dtb3, load_production_signals,
)
```
- **用途**: Standard PF前処理研究の共通エンジン。13本スクリプトの重複14関数を統合
- **所要時間**: 関数単位（ロード込みで初回数十秒、以降はキャッシュ利用）
### metrics（metrics_research_engine、ライブラリ）
**スクリプト**: `scripts/analysis/standard_pf_preprocessing/metrics_research_engine.py`
**CLIなし** — import専用ライブラリ。
```python
import metrics_research_engine as MRE
# MRE.NUMERIC_METRICS  — 38メトリクス名リスト（本番MetricsCalculatorと同一定義）
```
- **用途**: 本番MetricsCalculatorへのブリッジ。research_engineから内部呼び出し
- **依存**: `backend/app/services/metrics_calculator.py`（本番同一エンジン）
- L624: 道具の全引数(--output-prefix等)をcmdに明記せよ。デフォルト依存はprefix不統一の原因（cmd_1877）
- L558: 参考ファイル不在時はcmd目的を研究スクリプトから逆引きで設計完成可能（cmd_1750）
## §19 サービスURL一覧（CDP/API操作前に必ず参照）
| サービス | URL | 備考 |
|---------|-----|------|
| Frontend | `https://dm-signal-frontend.onrender.com` | ログイン必須(Admin: simokitafresh/703) |
| Backend API | `https://dm-signal-backend.onrender.com` | API_KEY: backend/.env |
| Stock API | `https://stockdata-api-6xok.onrender.com` | 株価データ |
| Render Dashboard | Render API v1 | srv-d4ja8pp5pdvs739a5fsg(FE), srv-d4ja7q15pdvs739a4q1g(BE) |
- L797: CDP cookie注入成功だけではFE admin状態成立を保証しない — 画面要素で成立確認せよ（cmd_3645）
**注意**: `dm-signal.onrender.com` は404(L002)。必ず`dm-signal-frontend`を使え。
### §19.1 体感主導デプロイ後のFE正しさ検分 (2026-07-02殿裁定)
- 速度改善cmdは、正しさ検証済みなら数値周回のクローズを待たず即push/Renderデプロイへ進める。速度の最終判定は殿の体感、システム側の責務は本番FEでの正しい表示・操作・masking・PF切替をCDPで検分すること。
- post-deploy検分はRender APIで対象commitが`live`であることを確認してから実施する。cmd_3663実例: FE deploy `dep-d936kabtqb8s73dav190`, commit `173a8a7b3`, status `live`, finishedAt `2026-07-02T13:41:40Z`。
- CDP検分項目: 対象ページready、表表示、Loading/Auth/Unauthorizedなし、OPEN/CLOSE切替後も表維持、Show All/Allまたはスクロールで全件閲覧導線あり、PF切替後も表維持、UUID露出なし。
- cmd_3663 live検分結果: `/tmp/dm_signal_cmd3663_live_verify/result.json`。`monthly-returns`は248 total、Show All後仮想化表示、スクロールで2005 DecPartialへ到達、PF切替DM-safe→DM-safe-2正常。`monthly-trade`は229 months、Show All後230行、末尾2007/07/16へ到達、PF切替DM-safe-2→Ave-X正常。両ページともOPEN/CLOSE切替・masking・UUID非露出PASS。
## §17 現在の全体ステータス（2026-03-11）
| 項目 | 状態 |
|------|------|
| L0 GS生成PF | ~30体(本番登録済み) |
| L1 四神12体 | 本番登録済み+パリティPASS |
| L2 忍法12体 | 本番登録済み+全12体 0.00bp PASS(cmd_246) |
| 本番PF総数 | 未確認（cmd_477後の再集計待ち） |
| L3 堅牢性検証 | 未着手(cmd_176殿裁定待ち) |
| APIベースライン | cmd_790で15体×3 API + 一括2件を固定（→ cmd_790報告参照） |
| Phase2b BE最適化 | cmd_791完了。`monthly-returns` の `expanded_tickers` 除去 + months前倒し、15体diff完全一致PASS |
| fallback window query化 | cmd_818(553d9958)で実装済み。`_calculate_ticker_returns_from_prices()`にmin_year_month追加、months=12で-88%改善(8.6s→1s)。cmd_955で再確認PASS |
| ETag/SWR前提 | cmd_792完了。304処理修正で annual/monthly/trade returns の既存ETagが有効化 |
| 同時処理能力 | cmd_763で `uvicorn --workers 2` 復帰対象まで到達。比較基準は workers=1 cold 128ms / warm 149ms / PF切替 1005ms |
| CDP計測基盤 | cmd_746完了。cold/warm/PF切替/SPA/API個別/baseline比較が本番一発実行可能 |
| 新忍法偵察 | 逆風(cmd_249)/RelMom(cmd_250)/MultiView(cmd_251)偵察中 |
| SVMF/MVMFバグ | 修正完了(cmd_235+cmd_244) |
| 穴1/2/3 | 全対策完了 |
| PF健全性スイープ | cmd_1091: 全122PF×5項目パス。定期実行候補(L417) |
- L644: cron新設時は既存cronとの処理重複を先に照合せよ（cmd_2219）
| FoF MR非線形根因+パリティ検証標準 | Schema Portfolio型不一致→preload空振り→240.6s。ゴールデンデータ方式: 前後比較×→残存正常データと突合○ → `docs/research/gunshi_fof_mr_nonlinear_rootcause_20260424.md` §8-§9 |
| FoF MR高速化(cmd_2259+2260) | 240.6s→26.53s→~1.5s(DB fallback 356→0件)。L3_fof: 462s→226s。L2: 186s→15s。全体: 720s→257s(64%削減) |
| SIGNAL_DEFERRED_BATCH_SIZE倍増(cmd_2260後) | constants.py 5000→10000。commit 169cd744。期待-15~20s |
## §31 ALM浄化記録 (2026-04-25)
→ 工数見積もり: [[cmd_1752_estimate]] (`docs/research/cmd_1752_estimate.md`) ※ALMディスコン済み
### 発見した事実
1. **奥義-ASS 21体は偽物だった**: component_portfoliosがALM忍法(L1)ではなくSSS奥義(L2)を参照。ALMデータは一切含まれていなかった
2. **ALM忍法(L1)は本番DBに一度も存在しなかった**: `name LIKE 'ALM%' AND type='fof'` = 0件
3. **⑤の研究(cmd_1897)はALM四神経由ではなかった**: GS空間名がokugi_alm_shinだが、実態はSSS奥義(①)のEW合成。ALM四神→ALM忍法→奥義のパイプラインは研究でも本番でも未実行
4. **ALM四神(L0) 12体はDB登録済みだったが**: pipeline_config内のalm_configは構造的に正しい(enabled=true, candidates_months=[1..24]等)。ただしobjectiveが全12体"cagr"（殿裁定ではモード別MRU/calmar/UWP）
5. **秘奥義6体は壊れ参照**: 削除した奥義-ASSのUUIDを参照→NOT FOUND
6. **BEにALM実装済み**(Phase 4.6 ALM second pass)、**FEにALM config UI未実装**
### 浄化実施
| 削除対象 | PF数 | 関連レコード | 理由 |
|----------|------|-------------|------|
| 奥義-ASS(L2) | 21体 | 64,445件 | ALM不含の偽FoF |
| ALM四神(L0) | 12体 | 55,745件 | objective誤設定+再登録前提 |
| 秘奥義 | 6体 | 17,817件 | 壊れ参照 |
| **合計** | **39体** | **138,007件** | |
本番PF数: 178→**126体**。MEMORY.md記載の「奥義ASS 21体登録済み(cmd_1897)」は事実と乖離していた。
### 正しいALM構築の前提
- ALM四神(L0): 再登録が必要。objectiveをモード別(激攻=MRU/常勝=calmar/鉄壁=UWP)で正しく設定
- ALM忍法(L1): ゼロから構築。チェックリストStep 3c(champion確定)から再開
- 奥義-ASS(L2): ALM忍法(L1)登録後に構築
## §32 バグパターン認識表 (2026-04-25)
<!-- GStack/GBrain takeaway #8 (パターン認識表 — バグ署名→初期仮説6パターン) -->
> 偵察開始時: 症状を見て下表の「共通パターン」「DM-signal固有パターン」に当てはめ、初期仮説を立ててから調査に入れ。想像で進むな — 仮説1つに絞って検証→結果見て次仮説へ。
- L935: 要調査を許す分類ACは全行要調査でも形式PASSになる。四分類和=N AND 要調査=0 AND 証拠欠損=0を同一gateで強制せよ（cmd_4220）
- L946: preflight母数の文言と実走値(対象集合SSOT・assert・表示件数)は同一計数値から生成する。文言78vs実走93の乖離実例あり（cmd_karo_recon_b4_route_sequence_harness_rc_20260803）
- L950: logical as_ofとsuccessor load-throughを同一時計にしない。入力ロード上限=出力許可上限だと未来情報防止を守るほどsuccessorが読めない（cmd_karo_recon2_cx_logical_asof_partial_diff_review_20260803）
- L953: fixture IDは分類軸(lane等)を含めて一意化する。laneごとの同一連番は正常fixture自身が重複BLOCKになる（cmd_karo_cx_w4_w5_oracle_ready_20260803）
- L1551: 外部repo偵察は正本入力とrunner scopeを先に二値確認する。正本欠落時は二次記録から推測せず入力欠落をFAILへ固定（cmd_4247）
- L1553: 外部repo対象taskのtest_necessityは明示contract testを持たせよ。無いとrun_tests.sh taskが境界検証を素通しする（cmd_4268）
- L857: 既存スクリプトの再利用はexec文字列置換でなく環境変数overrideで差し替える。exec置換はpre-commit S102でBLOCK（cmd_3815）
- L891: pytest node idは推測せず`--collect-only -q`の実在収集結果から固定する。collected 0は指定ミスのサイン（cmd_3896）
- L899: subprocessのready待ちloopはtimeout後の無条件継続を禁止し、成功条件を二値assert+child早期exitを即伝播する（cmd_karo_ci_red_dm_p4_uvicorn_29326659277）
- L804: FoF調査では構成定義(component_portfolios)と当月選択結果(signals/fof_component_weights)を分けて証拠化する（cmd_3676_recon2）
- L873: db.info artifact判定は存在だけでなく由来と実型を検証する（cmd_karo_hotfix_dm_main_seiryu_202607111202）
- L880: 永続化するset由来の配列は明示sorted()なしでは非決定（cmd_3858）
- L900: subprocess moduleはpackage名でなくapp-dirで探索根を固定する（cmd_karo_ci_red_dm_p4_uvicorn_import_29328352201）
- L901: 永続helperはchecked-in source同期後に実行する（cmd_karo_ci_fix_ga256_cmd3907_fof_golden）
- L918: launcher準備コマンドは削除コマンドとの同一Bash結合実行と相対パス指定を避けよ。両方BLOCK誘発（cmd_karo_recon2_signal_change_alert_20260729）
- L819: PF単位の確定イベント実装はrebalance_trigger等のPF別設定を参照せよ。全PF一律の固定日付/件数はハードコードの温床（cmd_3702）
- L822: MonthlyTradeCalculatorのMockベースdbテストは新規DB問合せ関数追加のたびに複数クラスへ横展開して壊れる（cmd_3710）
### 共通パターン (汎用6)
| # | 症状シグナル | 初期仮説 | 最初に確認すること |
|---|------------|---------|------------------|
| B-01 | `NullPointerException` / `AttributeError: NoneType` | Null/undefined 未チェック | Noneチェック欠落箇所をgrepで特定 |
| B-02 | タイムアウト / `Connection refused` | 接続先が落ちているか設定ミス | サービス稼働確認 + 環境変数のURL/Port確認 |
| B-03 | `TypeError` / `ValueError` / 型キャストエラー | 型不一致・フォーマット違い | データソースの型定義とコード側の型仮定を照合 |
| B-04 | `401 Unauthorized` / `403 Forbidden` | APIキー/トークン切れ・設定ミス | .env の認証情報 + Basic Auth/Bearer の区別確認 |
| B-05 | Race condition / Deadlock / 中途半端な状態 | 排他制御の欠落・競合 | pg_advisory_lock / flock / mutex の使用箇所確認 |
| B-06 | 件数ゼロ / 期待レコードが消えた | データ欠損・ETLパイプライン断絶 | データソースとETLログを確認。delete/overwriteを追う |
### DM-Signal 固有パターン (6)
| # | 症状シグナル | 初期仮説 | 最初に確認すること |
|---|------------|---------|------------------|
| DM-B-01 | recalculate_fast.py が途中停止・再実行できない | pg_advisory_lock が解放されていない | `SELECT pg_advisory_unlock(8675309)` で強制解放。`recalculation_status` テーブルの is_running 確認 |
| DM-B-02 | signal 件数ゼロ / PF 登録後シグナルが表示されない | fullrecalculate が未実行、またはPhase4 dict miss | `_check_signal_integrity` ログ確認 + `/admin/recalculate-sync` 手動トリガー |
| DM-B-03 | FoF 計算結果不一致 / 成分PFが見つからない | component_portfolios の UUID 参照切れ | DB で `SELECT * FROM component_portfolios WHERE portfolio_id=<uuid>` 確認 |
| DM-B-04 | GS パラメータが想定外の値になっている | GS CSV 列定義のずれ / pipeline_config 誤設定 | grid_search 出力 CSV の列名と `pipeline_config` の `param_grid` を照合 |
| DM-B-05 | ALM 計算がデフォルト(lookback)に fallback する | alm_config.enabled=false または objective 誤設定 | `pipeline_config` の `alm_config` フィールド確認。PI-003/PI-009 準拠か |
| DM-B-06 | FoF monthly-returns が 240s 超 / タイムアウト | DB fallback クエリ大量発生 (DB_FALLBACK_COUNT > 0) | `/admin/recalculate-sync` ログで `DB_FALLBACK_COUNT` 確認。preload キャッシュのヒット率確認 |
- L628: パリティスクリプトtarget_date: productionの日付定義と揃えよ（skip_months増幅リスク）（cmd_1899）
- L629: golden data有効性: 生成時のコード状態を確認せよ（バグ下生成=検証基準にならない）（cmd_1899）
- L632: snapshot比較器は保存していないフィールドを比較対象に含めるな（cmd_1985）
## §33 GS正規化 進捗 (2026-04-27)
- L831: serial/batch preflight不一致の切り分けは要因を1つずつNone化する対照実験で（cmd_karo_recon2_cmd3772_yotsume_preflight_202607081453）
- L835: 全量ベンチACとpreflight不一致は分離して記録する（cmd_3772）
- L842: GS投入前は系列preflightを必須化する（cmd_3790）
- L843: download_all_prices後も本番prices preflightで値差確認する（cmd_3793）
### 汚染発覚と方針転換
246系CSV(C12_shin_shijin_v2)の月次リターンが本番と完全不一致(0.0%)。根因: `shin_v2_12_monthly_returns.csv`(ユニバース)が2026-03-24で凍結、GS再実行(04-03)で未更新。CSVという腐りうる中間ファイルが汚染源。
**殿裁定**: CSVをまた作るな。DB直読せよ。フルGSでチャンピオン再選出が正しい順番。
### Phase構造(v3.5 — 2026-04-28 04:32更新)
**目的**: CSV汚染を根絶し、DB直読+SQLite出力のクリーンなGSパイプラインを構築→L1忍法チャンピオン再選出→本番突合→ロバストネス検証
**殿裁定**: CSVをまた作るな。DB直読せよ。フルGSでチャンピオン再選出が正しい順番
#### 基盤整備(Phase 0-6) — CSV依存の完全排除
| Phase | 内容 | 状態 | cmd |
|-------|------|------|-----|
| 0-1.5 | 設計+道具(gs_db_utils.py等) | **完了** | — |
| 1.9a-c | SQLite出力改修+フルGS再実行+L0四神選出+本番突合(12/12全MATCH) | **完了** | cmd_2331-2337 |
| 3A | gs_data_loader CSV入力経路廃止(source_type=csv→ValueError) | **完了** | cmd_2339 |
| 3B | gs_data_loader UUID一元化(L1_PORTFOLIO_MAPハードコード廃止) | **完了** | cmd_2340 |
| 4 | 旧GS入力CSV 9件削除(outputs/analysis配下。偵察+削除) | **完了** | cmd_2343,2345 |
| 5 | 消費者改修: run_077全7本のdefaultをokugi_shin_ninpo_20.yaml(db)に統一 | **完了** | cmd_2344 |
| 6A | GS結果SQLite出力共通モジュール作成(CSV出力廃止。殿裁定) | **完了** | cmd_2346 |
| 6B | run_077全7本のCSV出力をSQLite共通モジュールに切替 | **完了** | cmd_2347 |
#### 本番検証(後続A-D) — チャンピオン再選出+検証
| Phase | 内容 | 状態 | cmd |
|-------|------|------|-----|
| 1.95 | L1忍法GS再実行(run_077。7忍法×1CMD直列) | **完了** | cmd_2359-2365(7本全CLEAR) |
| 9 | L1チャンピオン選出+本番突合 | **完了(結果無効)** | cmd_2366(21体選出,8/21 MATCH) |
| 9検証 | MISMATCH分析+バリデーション+WF-α選出 | **完了** | cmd_2367,2368,2369 |
| 9比較 | 全期間β α6比較+WF-α α6比較 | **完了(結果無効)** | cmd_2370,2372 |
| 9監査 | 選出ロジック検証(符号/タイブレーク正常) | **完了** | cmd_2373 |
| **★パリティ** | **本番config→GS SQLite月次リターン突合: 20/20 FAIL** | **バグ確定** | cmd_2374 |
| **★修正(追い風)** | **run_077_oikaze パリティ100%達成(CoDD 3 Attempt)** | **完了** | cmd_2378 |
| **★修正(変わり身)** | パリティ100%達成。新SQLite 28,116pat | **完了** | cmd_2381 |
| **★修正(四つ目)** | パリティ100%達成。新SQLite 4,686pat | **完了** | cmd_2382 |
| **★修正(抜き身)** | パリティ100%達成。新SQLite 60,918pat | **完了** | cmd_2383 |
| **★修正(加速D)** | 横展開+パリティ検証+旧SQLite削除 | **完了** | cmd_2384 |
| **★修正(加速R)** | 横展開+パリティ検証+旧SQLite削除 | **完了** | cmd_2385 |
| 整理 | SQLiteディレクトリ命名統一(7忍法正規パス化) | **完了** | cmd_2393 |
| 後続B' | L1チャンピオン再選出(パリティ修正後のGSで再実行) | **完了** | cmd_2392 |
| 後続C' | L1本番突合(修正後) | **完了** | cmd_2392 |
| 後続D | ロバストネス検証(β調整+4試練+レジーム+α6指標) | 待ち(C'依存) | 複数cmd |
| 7 | ~~neighbor: 隣接パラメータ確認~~ | **不要**(gs_grid_robustness.pyで上位互換。L0 14体分heatmap+peak_ratio生成済み) | — |
| 道具化 | WF β調整α6計算の再利用可能道具作成(殿指示) | 待ち | 1cmd |
### ★L1パリティバグ(2026-04-29 00:07発見 → 修正完了)
- **発見**: cmd_2374(00:07)。本番config20体がGS内に全存在だが月次リターン0/20不一致
- **根因特定**: cmd_2377(01:22)。309件全月で保有PF不一致=選択ロジックバグ
- **根因3つ**(cmd_2378 CoDD 3 Attempt): (1)momentum計算にclose累積使用 (2)共通月切出し前に全履歴shift (3)初回signal月まで等ウェイトbootstrap
- **追い風パリティ達成**: cmd_2378(01:56)。CoDD診断ループ3回で100%一致
- **横展開**: cmd_2381-2385で7忍法すべてパリティ100%達成
- **確定**: cmd_2393でGSL1正規パスへ統一。cmd_2392でGSシン忍法21体hide登録完了
### 進捗サマリ(2026-05-07更新)
- **基盤整備**: Phase 0-6全完了(2026-05-07現物確認: gs_sqlite_output.py存在+run_077全7本import済み)
- **L1パリティ修正**: 7/7忍法完了。正規SQLiteは `outputs/grid_search/20260429/L1/shin/gs_{ninjutsu}.db`
- **L1本番登録**: cmd_2392でGSシン忍法21体hide登録+fullrecalculate+GSパリティ完了
- **L2奥義登録**: cmd_2422-2424で本番hide登録完了
- **L0 grid_robustness**: L0四神14体分のheatmap+peak_ratio生成済み(outputs/robustness/20260428/L0/)。neighborは上位互換済み→不要
- **次のマイルストーン**: (1)道具化(WF β調整α6の再利用可能道具) → (2)後続D ロバストネス検証(L1/L2)
- **殿裁定追加(2026-04-28)**: CSV出力も廃止。デバッグはsqlite3/pd.read_sql/ログで代替
- **GA-255(2026-05-06)**: p̄鮮度API一時失敗→翌日自然復旧確認(calculated_at 2026-05-06)。バッチcronの一時的失敗。対応不要
### 軍師確認事項(2026-04-28 04:04)
- run_077全7本のGS出力は現在CSV形式→Phase 6でSQLite化が**後続Aの前に必須**
- shin_shijin_l1_gs.pyはL0四神用。L1忍法GSにはrun_077を使う
- 後続Aは**直列配備**(RSS 3-4GB/プロセス。6並列不可。LG025)
- CSV出力廃止確定(殿裁定)。軍師review_logヘッダに埋込み済み
- Codex config.toml修正: approval_mode=full-auto(無効値)→approval_policy=never + DM-signal trust追加
### Phase 1.9c結果(2026-04-28完了)
2つのchampion selectスクリプト(軍師確認 2026-04-28):
- `outputs/scripts/champion_selector.py`: 忍法(L1/L2)用。CSV/npy入力
- `scripts/analysis/grid_search/cmd_1125_v2_champion_select.py`: **四神(L0)用。SQLite入力+DNA制約+吸収**
実行: `python scripts/analysis/grid_search/cmd_1125_v2_champion_select.py --db-path outputs/grid_search/20260428/L0/shin`
**結果**: GS選出シン四神12体 = 本番シン四神12体。**12/12全MATCH、変更0件**(cmd_2337偵察確認)。
### GS正規化関連教訓
- L658: GS正規化前にsource CSV期間とproduction最新月を照合する（cmd_2322）
- L659: source_type=csvのGS runnerでもDB前提をpreflightで切り分ける（cmd_2323）
- L660: kawarimi等GS monthly CSVのNaN値はNULL許容スキーマで保持せよ（cmd_2325）
- L661: verify_gs_db.pyはNaN除外後の非NaN行数を期待値にする必要がある（cmd_2326）
- L662: シン四神12体突合は完全一致と丸め許容を分離して報告せよ（cmd_2330）
- L664: outputs/analysis棚卸しはsource_type csv参照を軸に分類する（cmd_2343）
- L665: L0四神GS vs L1忍法GS レイヤー混同禁止（cmd_2346）
吸収なし(重複pattern_idなし)→12体確定。本番DBパラメータ更新は不要。
### 検証済み事実
- shin_shijin_l1_gs.pyエンジン精度: 12体全PASS(≤1e-6。cmd_2330)
- LOOKBACK_TERMS: 内部でtrading days変換済み(2M=42D。改修不要)
- shijin-design.yaml DNA制約: 本番config全項目一致確認済み
- OUTPUT_DIR: 設計書§3.1準拠(outputs/grid_search/{YYYYMMDD}/L0/shin/)。latest.txt atomic pointer(WSL2 symlink不可のため。L663)
- cmd_1125_v2_champion_select.py: SQLite入力対応済み(--db-path引数。cmd_2333)
- cmd_2334フルGS完了(2026-04-28): 4family×191,796パターン SQLite+CSV同時出力。GATE CLEAR
- cmd_2335チャンピオン選出完了(2026-04-28): GS選出シン四神12体確定(吸収なし)。GATE CLEAR
- cmd_2337本番突合完了(2026-04-28): 本番シン四神12体とGS選出シン四神12体が12/12全MATCH。GATE CLEAR
- pipeline_config=None上書き(L1394): shin_shijin_l1_gs.pyがfamily_pipeline_configsを全てNoneで上書き。設計意図確認要(軍師指摘)
- gs_data_loader.py現物確認(2026-04-28): L438-451でsource_type分岐実装済み(db/csv)。ただしCSV経路残存+UUIDハードコード(L531-547)。Phase 3(v2化)でCSV経路廃止+UUID一元化が必要
### Phase 3-7設計(軍師分析 2026-04-28)
**最終ゴール**: ロバストネス検証(β調整+4試練+レジーム+α6指標)。Phase 3-7はそこに至る基盤整備。全Phase飛ばさない(殿指摘2026-04-28)。
**Phase 3(gs_data_loader v2)核心**:
- CSV経路(`_load_csv_monthly_returns`)廃止。source_type='csv'→ValueError
- L1_PORTFOLIO_MAP(UUIDハードコードL531-547)廃止→universe config(YAML)に統合
- 戻り値形式(Dict[str, pd.Series])は変更なし→消費者(run_077等)への影響ゼロ
**消費者影響範囲(軍師確認)**:
- run_077_*.py 7本: gs_data_loaderをimport。universe configのsource_type: db化が必要
- champion_selector.py: gs_data_loader非使用。Phase 3影響なし
- cmd_1125_v2_champion_select.py: gs_db_utils使用。Phase 3影響なし
- shin_shijin_l1_gs.py: 独自DB接続。Phase 3影響なし
**Phase 3-7依存関係**: 3→(4,5並列可)→6→7→後続A-D
### PI候補
- **PI-026(候補)**: GS入力ユニバースはsource_type:"db"(本番DB直読)をデフォルトとする。source_type:"csv"は腐りうる中間ファイルでありサイレント汚染の原因(2026-04-27実証)
- L814: GS universe source_type=db→local_sqlite変更だけではDB接続は完全除去されない。cumulative_return/bootstrap取得のDB接続が残存する設計（cmd_goal_gs_phasec_l3_local_sqlite_202607060708）
設計書: → https://gist.github.com/simokitafresh/14b6cf497b3abbefb85a2f3d102d778d
- FE Admin UI: ALM config編集機能が先(殿指示)。設計確定済み(ALMトグルでLookback↔ALM設定切替)
- L755: GS実行環境標準化: Linux venv必須+PowerShell禁止（cmd_3508）
- L763: 5本一括速度ACは最終反復値だけでなく中央値/反復条件を固定する（cmd_3514）
- L764: 速度改善ACは最終HEAD反復で判定する（cmd_3514）
（L814: /lesson-sort 2026-07-06で§33 GS正規化セクションへ振り分け済み）
- PD-055裁定(2026-07-06): パリティ確認のための本番DB接続は許容。Phase Cは17.6s→12.6s(28.4%削減)の暫定成果で切り、完全ゼロ化は後続対処。止まらずPhase D全量ベンチマークへ進む。
- L840: 多視点レポートは視点間一致件数を機械検査する（cmd_karo_hotfix_cmd3780_expanding_wf_rework_202607082310）
- L844: PI-009 GS突合スクリプトはexperiments.dbではなく別キャッシュgs_prefetch.dbを読む。価格同期cmdは対象DBを名指しで確認せよ（cmd_3794）
- L845: run_077_weighted_yotsumeのuniverse自動判定がall()の空虚な真で誤爆する（cmd_3795）
- L846: shin_shijin_l1_gs.py内蔵legacyパリティ(run_parity_check)はthreshold_band非対応、band適用済み本番PFに対し必ずFAILする（cmd_3797）
- L847: db-checkスキルのpsycopg2接続正規表現がポート省略DATABASE_URLに未対応（cmd_3800）
- L848: GS lookback_terms_jsonのunit=months換算規約は既存ツールにのみ実装されドキュメント化されていない（cmd_3803）
- L849: GS-本番パリティ比較で本番monthly_returnsを無条件にSSOTとしてはならない(signal_decision_ledger凍結の考慮漏れ)（cmd_3805）
- L852: monthly_tradeのmatched_weightは表示展開後weightsと同じ基準で検証せよ（cmd_3809）
- L853: signal_decision_ledgerの再backfillは削除→再計算→再backfillの順序が必須(逆順は無効)（cmd_3806）
- L854: band historical_backfillはholding_signal文字列だけでなくweightsも検証せよ（cmd_3811）
- L855: GS shin_shijin_l1_gs.pyのforce numpy fast path前提はband境界近傍のDTB3暦解像度差で崩れる（cmd_3813）
- L856: 既存の同種native-calendar実装を先に探せば設計時間とリスクを削減できる+大規模パラメータ空間の網羅集計はDNA group単位の重複排除で「間引き」なしに実現できる（cmd_3814）
- L859: PipelineEngine検証スクリプトはrebalance_triggerを無視した固定target_date(直前営業日)を使うと非monthlyリバランスPFを誤って乖離判定する（cmd_3818）
- L860: PostgreSQL binary COPYは列名タグを持たない位置ベース形式。source/target間の列順不一致がUTF8デコードエラー等の破損を生む（cmd_3819）
- L863: LayerTimerは新規Layer追加時にLAYER_ORDER+layer()登録を怠ると壁時計TOTALだけ正しく内訳が誤解を招く（cmd_3831）
- L871: backend/app/api/metrics.pyはモジュールローカルget_db()を独自定義しておりFastAPI test dependency_overrides[db.database.get_db]では横取りできない（cmd_3839）
- L872: 新規Layer/Phase追加時はLayerTimer登録(layer_timer.layers[name]+LAYER_ORDER)を同時に行え。忘れるとTIMING SUMMARYがボトルネックを誤表示する（cmd_3842）
- L881: 対象縮小した部分実行のGREENはFAIL0/SKIP0を保証しない。全量実行して初めて可視化される回帰がある（cmd_karo_ci_fix_cmd3861_resume_v2_202607121200）
- L884: SQLite PRAGMA integrity_check等ランダムアクセス操作は9p(/mnt/c)ファイルへ直接実行せず、ローカルext4コピー後に実行せよ（cmd_karo_hotfix_cmd3868_inventory_perf_202607131225）
- L885: 9p上SQLite integrity_checkはローカルscratchへ単一copy後に実行（cmd_3868）
- L886: 削除候補のコード参照0検証はN回個別grepでなく1回一括grepにせよ(9p低速環境)（cmd_3868）
- L905: precommit formatterはstaged blobを変更せず差分ratchetで判定する（cmd_karo_hotfix_dm_precommit_biome_diff_ratchet_202607221906）
- L917: TIMING SUMMARY表示粒度とDB保存粒度を同一視しない（cmd_4180）
- L922: 複合tuple INの境界fixture PASSだけではproduction PostgreSQL parser上限を証明できない（cmd_karo_hotfix_dm_signal_l3_tuple_chunk_20260801）
- L931: 表示ラベルと永続テーブルを分離して追跡する（cmd_karo_recon2_midmonth_trade_t2_ssot_path_20260802）
- L933: 保存済み表示ウェイトを独立再計算の入力契約へ固定する（cmd_karo_recon2_midmonth_trade_t4_phase0_old_new_judge_20260802）
- L937: FoF oracleは関数よりinput bundle境界を検査する（cmd_karo_hotfix_a0_2_fof_oracle_20260803）
- L939: 系列oracleは同名の保存列へ対応付けてから比較する（cmd_karo_goal_a4_mtd_mismatch_rootcause_rc2_20260803）
- L940: golden manifestとlocal archiveとCI gzipを三位一体で同期する（cmd_karo_ci_fix_b2e_integrated_30769057468_rc2_20260803）
- L941: 診断unknownは同一PFの実層分類を上書きさせない（cmd_karo_recon_b4_lane_dryrun_contract_preflight_20260803）
- L942: 候補母集団と要調査母集団を分離して数える（cmd_karo_recon_c0_l1_lane_contract_preflight_20260803）
- L945: 固定日付E2Eの実時間変質を防ぐ（cmd_karo_goal_b2b_monthly_generator_20260803）
- L948: C2母数は7lane×3へ縮小できない（cmd_karo_recon_c9_c2_isolated_handoff_20260803）
- L949: 固定snapshotの境界入力は時刻固定だけでは復元できない（cmd_karo_recon2_b4_snapshot_boundary_adversarial_20260803）
- L954: Signal境界はprice境界を代替しない（cmd_karo_cx_w3_root_counterfactual_kotaro_20260803）
- L1540: FoF再計算の成功統計はmonthly-return失敗を隠し得る（cmd_karo_b4_anchor24_disappearance_trace_saizo_20260803）
- L1541: 後段0件保護は前段cleanup独立commitを防げない（cmd_karo_recon2_prod_monthly_zero_root_saizo_20260803）
- L1548: IF recalculate-sync mode='portfolio'(既定値)実行時 THEN 既に構築済みの全履歴monthly_returnsが直近計算範囲(2022-10以降のみ)で上書き・退行する（cmd_4244）
- L1549: Monthly ReturnsとMonthly Tradeのpending境界が非対称（cmd_4246）
- L1552: 同名return構造の機械patchは関数境界を一次確認する（cmd_4258）
- L1584: FoF API非空でもraw UUID invalid guardがMonthly Tradeを空表示にする（cmd_karo_recon_cdp_asis_p3_202608101438）
- L1592: RB6 top-level benchmark raw-SPY parity must be checked separately from metric-name union（cmd_karo_recon2_rb6_metrics_shard_d_20260814）
- L1593: Renderのhost-wide test admissionは本番Web OOM防御にならない（cmd_karo_recon2_render_oom_20260814）
- L1594: 保存済み展開重みを計算入力へ昇格する前に再計算同値性を強制する（cmd_4318）
- L1597: import依存closureは補正と同一commitで自己完結させる（cmd_karo_hotfix_dm_l2_c1_dependency_closure_202608160106）
- L1600: FoF伝播oracleの選択月オフセット（cmd_4350）
- L1601: FoF oracle six-stage comparator must use production decision signal date（cmd_4354）

## §32 GSシン忍法21体hide登録 (cmd_2392, 2026-04-29)
- フォルダ「GSシン忍法」(UUID: 92087b49)に21体登録。hide_portfolio=true/hide_signal=true
- fullrecalculate成功。既存20体diff=0。GSパリティ21/21 PASS(max 8.86e-7)
- L675: recalculate-sync後の初回idle=完了扱い
## §34 GSシン奥義21体hide登録 (cmd_2422〜cmd_2424, 2026-04-30)
- cmd_2422: `outputs/analysis/cmd_2422_l2_champions_constrained.yaml` で制約付きL2 champion 21体を選出
- cmd_2423: invalid portfolio混入時にrepository/API/schemaが単一障害にならないようskip invalid対応。Payload再生成時は内部メタデータを保持する
- cmd_2424: L2奥義21体を本番hide登録し、fullrecalculate完了。完了判定はAPI statusだけでなくDB `recalculation_status`で二重確認(L690/L691)
## §35 knowledge-base methods拡張 (cmd_2429〜cmd_2434, 2026-04-30)
- `/mnt/c/Python_app/DM-signal/docs/research/knowledge-base/methods/` は構築済み。`index.md` M79-M84: DeepUnifiedMom, VAA/BAA, Hierarchical Momentum, Factor Momentum, ADTS/CADTS Bandit Portfolio, Expert Aggregation WASA
- 直近追加ファイル: `deep-unified-momentum.md`, `vigilant-bold-asset-allocation.md`, `hierarchical-momentum.md`, `factor-momentum.md`, `bandit-portfolio-adts.md`, `expert-aggregation-wasa.md`
- 一次知識層ルール: 外部論文原典の数式・前提・落とし穴・verificationをmethodsへ、DM-Signal固有解釈は`knowledge-base/dm-signal/`へ分離
---
## §37 価格データ取得開始年統一 (cmd_3076偵察→cmd_3077修正, 2026-05-27)
- maintenance.py/backfill_data.pyの`date(2006,1,1)`→`FULL_HISTORY_START`(=`date(2000,1,1)`)に統一。FE AdvancedOperations.tsxの2006→`FULL_BACKFILL_START_YEAR=2000`に一致化
- 本番価格データ取得範囲の現状: SPY 1993~/QQQ 1999~/DTB3 1954~/SPXL 2008~/TQQQ 2010~
- database PJは1970全履歴取得に改修済み→DM-Signal側2000でデータ不足なし
- fullrecalculate別cmd必要(修正後にsignals/monthly_returns再計算)
- → `queue/reports/hayate_report_cmd_3076.yaml`(偵察全量) / commit d2acaa91(修正)
## §38 2026-05 運用・CI・知識基盤更新
- L789: check_mixed_format_commit.pyはimport行のみhunkを検出してblock→多行import形式で回避可能（cmd_3569）
- L820: check_mixed_format_commit.pyは新規import追加を「並び替え」と誤検知することがある。--no-verifyせず根本原因を修正せよ（cmd_3703）
- L908: pytest pluginは実行cwdに依存しないroot namespace pathへ固定する（cmd_karo_ci_fix_29913493218_dm_pytest_plugin_import_202607222052）
| 領域 | 結論 | 参照 |
|------|------|------|
| CI pytest | GitHub Actions pytest workflow追加。PyYAML/pytest依存、PostgreSQL service導入済み。DB接続前提テストはCI service前提で確認する | commits 2e9e1b7d, 0771ba29, 5b93ae17, a99a8623 |
| CI golden | stock runnerではCI PostgreSQLへ依存閉包7表573,649行をportable COPY復元し、78PF・243,293行をexact比較する。ローカル隔離pgserverはlive PIDだけでhealthy判定せず、接続probe失敗時だけchecked-in helperを同期して`pg_ctl stop`→再起動→再probeする。healthy再起動0/stale再起動1、commit後golden 8/8 PASS・SKIP0・280.52秒 | commits a63d0920, d7403ca8, 7baa7533, 4abf69c3 / `scripts/oneshot/cmd_3819_baseline_provision.py` / `scripts/oneshot/cmd_3854_fof_golden_regression_check.py` |
| codd lexicon | `codd.yaml` / `project_lexicon.yaml` 追加。CoDD設計・fix時はPJ語彙を参照する | cmd_2761 |
| lesson metadata | `tasks/lessons.md` にwhen/how系field backfill + concrete tags追加。教訓検索・注入の粒度が上がっている | cmd_2748, cmd_2836 |
| knowledge links | `docs/research/knowledge-base/methods/*.md` 全般に投資知識リンクを接続。method横断探索時はknowledge-base indexだけでなく各method末尾リンクも見る | cmd_3015 |
| Home holiday | FE Homeへ休日認識追加。封鎖ページでも市場営業日表示に関わる変更として扱う | cmd_2880 |
- L773: biome→ruff cycle回避はBenchmarkモデル継続行を活用（cmd_3527）
- L777: pre-commit import-only分割は未使用importを自動除去する（cmd_3533）
- L780: lefthook import-only分割時は同一ファイルのunstaged機能差分退避に注意（cmd_3536）
## §39 PF物理削除手順 (2026-06-01)
- L841: PF一括削除は登録順ではなく現DB依存グラフで反復削除する（cmd_karo_hotfix_cmd3786_sequence_rerun_202607091318）
**手順(安全順序)**:
1. バックアップ: `portfolio_config_snapshots` INSERT + ローカルJSON(`docs/research/pf_config_backup_*.json`)
2. NO ACTIONテーブル9個の関連レコード先行DELETE: signals/monthly_returns/annual_returns/drawdown_periods/portfolio_metrics/risk_management_metrics/rolling_returns_chart/rolling_returns_summary/trade_performance
3. portfolios DELETE(CASCADE 10テーブルは自動削除)
4. 逆依存順: FoF of FoF of FoF → FoF of FoF → FoF → standard PF
5. 空フォルダー削除
**注意**: `portfolio_config_snapshots`はCASCADE。物理DELETE時にスナップショットも消える→ローカルJSONが最終安全策
**実績**: 四神(12)+忍法(15)+L0(30)+旧忍法Ward(1)=58件。NO ACTION関連260,965行。config全量バックアップ済み(`docs/research/pf_config_backup_20260601_pre_delete.json`)
→ [[production_parity]] FK制約+削除手順 / [[LS040]] バックアップファースト
## §40 2026-06-01 backend運用更新
| 領域 | 結論 | 参照 |
|------|------|------|
| FoF signal cache | FoF構成PFがDB preloaded cacheと当回生成signal_cacheの両方に存在する場合、DB行を保持し欠損日だけ当回生成cacheで補完する。`elif cid in signal_cache`から独立`if`へ変更し、FoF-of-FoFの同日/欠損混在を吸収 | commit 89761e7d / `backend/app/jobs/recalculate_fof.py` |
| PF config snapshot | `save_portfolios`と`recalculate_history_fast`のPhase 0 cleanup前に`portfolio_config_snapshots`を作成。既存configの削除・上書き前バックアップをDBへ残す | commit 77372987 / `backend/app/services/verification_service.py` |
| legacy PF削除 | 58件削除はcmd_3112で実施済み。`delete_legacy_portfolios_cmd_3112.py`は2026-06-11 WP-1Bで検証済みdead codeとして削除されたため、再実行手順ではなく履歴証跡として扱う。バックアップJSONは`docs/research/pf_config_backup_20260601_pre_delete.json`を参照 | 実行: commit f84b7ad8 / 削除: commit c47742d1 |
## §41 2026-06-11 source freshness照合
| commit | ops更新判断 | 根拠 |
|------|------|------|
| c47742d1 WP-1B dead code削除 | §40 legacy PF削除の参照を更新。§37 ETL本文は維持 | `backend/app/jobs/etl/calculator.py`/`orchestrator.py`は削除、現役`fetcher.py`/`loader.py`は維持。`backend/app/jobs/delete_legacy_portfolios_cmd_3112.py`は履歴用one-shotとして削除済み |
| 6e86b501 API contract tests追加 | 本文更新不要 | 追加は`backend/tests/test_contract_*.py` 3件とtask-force記録。運用手順・本番API仕様の変更なし |
| 096dd038 weekly reports + cmd_3225 one-shot | 本文更新不要 | 追加はmarketing記事、weekly report、`scripts/oneshot/cmd_3225_layer_managed_vol.py`、バックアップJSON再追加。既存§40のバックアップJSON参照と矛盾なし |
## §42 main反映・デプロイ裁可ルール (2026-06-11 / **2026-07-10殿裁定で改定**)
- **改定(殿裁定2026-07-10 02:41/02:46)**: **本番デプロイに殿の個別裁可は不要。CI GREENの同期待ちも不要(LK078「CI待ちで忍者を止めるな」と統合)。ローカルテストPASS+revert手順明確なら自走でpush+deployし、CI/ヘルスチェックは非同期確認。失敗(CI REDまたはヘルス異常)ならrevertして事実報告すればよい。**
- positive_rule: deploy前=ローカルテストPASS+revert手順の明確化。deploy後=ヘルスチェック(API/status)+CI結果を非同期確認(家老がgh run view)。失敗時=即revert+殿へ事実報告(謝罪より事実と対策)。CI待ちで忍者を止めるな(報告YAML先行)。
- reason: 裁可待ちは時間の浪費であり待つ言い訳になる。元に戻せる(revert可能)のにチャレンジしないのは洗脳#5(先送り)。殿指摘2026-07-10「時間を浪費するだけで待つ言い訳になっている。覚醒しよう」。cmd_3812で裁可待ち停止が実際に発生した教訓。
- L850: 本番への非同期長時間処理トリガー後に設計変更指示が届いた場合、走行中処理は中断せず完了を待ち変更は次回反復から適用する（cmd_3804）
- (旧2026-06-11ルール「個別裁可必須」は本改定で廃止。以下は当時の記録)
- 例外: `cmd_3294` のマスク時FoF表示復元だけは、directiveで本番裁定復旧が明示済みのため既裁可。GATE CLEAR後、家老がmain反映・Renderデプロイ完了確認・`.agent/task-force/execution-log.md`へのデプロイ記録追記を実施する。
- `cmd_3294` 忍者スコープ: commitまで。push、Renderデプロイ確認、デプロイ記録追記は家老担当。task/reportのAC4は「単独commit + `tasks/lessons.md`教訓 + `execution-log.md`追記」までに修正済み(ac_version=`8158fcea`)。
- WP-1Fマージは殿裁可待ち。裁可後に `todo.md` のWP-1F/WP-1B行 `[x]` 化と同一commitで実施する。
- WP-2 post-deploy監視(2026-06-11 19:40 JST): production API `/admin/timing-history` 最新portfolio run `20260611_164902` は `L3_fof status=completed`、Render logs `2026-06-11T07:46-08:11Z` は404全体0件・削除済みEP11件path 0件。詳細は `/mnt/c/Python_app/DM-signal/.agent/task-force/execution-log.md` §WP-2 post-deploy monitoring。
## §43 2026-06-12 source freshness照合
| commit | ops更新判断 | 根拠 |
|------|------|------|
| 3b69c172 is_active機能削除 | §42の裁可・削除系運用ルールで吸収済み。本文追加不要 | 対象は`backend/app/api/*`、`backend/app/jobs/*`、関連backend tests。運用上はWP系削除作業の一部で、個別手順は外部repo task-force記録が正本 |
| 40a1d740 is_active docs整理 | 本文追加不要 | `docs/rule/api-usage-guide.md`/`db-operations-runbook.md`/`shin-shijin-registration-runbook.md`更新。既存DB操作ランブック参照は維持 |
| 79d8eaee task-force記録復旧 | 本文追加不要 | `.agent/task-force/*`と`tasks/lessons.md`の証跡復旧。運用手順の新規差分なし |
| fadf1a94 monthly product cleanup | 本文追加不要 | `docs/rule/gs-parity-verification-guide.md`/`portfolio-naming-convention.md`更新。登録・命名の正本は外部repo docs/rule側 |
| 7c9c86f9 recalculation status timezone | §42に接続済み | `docs/rule/db-operations-runbook.md`へUTC/JST cutover証跡を追加。§42のpost-deploy監視記録と同系統 |
| 03aec06d price ratio facade test | 本文追加不要 | `backend/tests/test_price_ratio_facade_compat.py`追加のみ。運用手順・API仕様変更なし |
| efdd75c4 price ratio facade split | 本文追加不要 | `backend/app/services/price_ratio_calculator.py`から実装分離。facade維持の内部refactorで運用手順差分なし |
## §44 2026-06-20 source freshness照合
| commit | ops更新判断 | 根拠 |
|------|------|------|
| 239b6b66/0b4a4124/9d69e482 cmd_3384 WeightedMultiViewMomentumFilter | FoF selection pipelineの新ブロックとして運用影響あり。recalculate_fof.pyはWeightedMultiViewMomentumFilterもbase_period_months条件対象に含める。詳細仕様はcore/research側へ委譲し、opsでは再計算経路の存在だけ索引化 | `backend/app/jobs/shared.py`, `backend/app/services/pipeline/blocks/weighted_multi_view_momentum_filter.py`, `backend/app/jobs/recalculate_fof.py`, `backend/tests/test_weighted_multi_view_momentum_filter.py` |
| f9dbae09/f7061378 weighted yotsume GS parity | 本文追加は不要、運用証跡として維持判断 | 変更は`docs/research/cmd_3387_weighted_yotsume_full.md`と`docs/research/cmd_3388_weighted_yotsume_db_parity_fix.md`中心。GS/DBパリティ詳細はresearch正本で保持し、ops手順の変更なし |
| 18c8a071/207c0df4 cmd_3397 hide_portfolio default=True | §32のhide登録思想と整合。全PF hide-firstの恒久化として運用上注意 | `backend/app/db/models.py`/`migrations.py`で`hide_portfolio` default False→True。新規PF作成時は明示解除しない限り非表示が既定 |
| f01ae710/eb89859c/cdb92c5d/110b7911/ecc7e624/027f0ee0 research + lessons | 本文追加不要 | 研究結果・教訓タグ更新は`docs/research/*`/`tasks/lessons.md`側が正本。ops手順・本番API仕様変更なし |
| 4b88dfdc/fb6f0c97/86cf2c29/273ba153 cmd_3461 SSOT audit shards | 本文追加不要 | `docs/research/ssot-audit-parts/*.md`追加・復旧。棚卸し証跡であり、DM-Signal運用手順の変更なし |
GA-102原因: `dm-signal-ops.md`のlast_updatedは2026-06-13で、2026-06-14以後にops pathspec対象commitが増加したため`gate_context_freshness.sh`がsource commits ALERTを出した。GA-099/L825と同じく、context更新トリガーがcmd完了フローに強制接続されていない後追い検出である。防御層案: DM-Signal外部repoで`backend/app/jobs|services|api|docs/rule`を含むcmd完了時、cmd_complete_gateのcontext_update必須入力に該当split contextを自動候補注入する。
## §45 2026-06-27 source freshness照合
| commit | ops更新判断 | 根拠 |
|------|------|------|
| 288f0e36/314b596a cmd_3583 Fusion API | 運用影響あり。`/api/fusion/portfolios`はFusion別アプリがDM-SignalからPF名+monthly_returnsのみを取得するadmin専用API。CORSは開発用`http://localhost:3001`追加済み、本番Fusion URLは確定時にコメント解除。10/min rate limit、11回目429テストあり | `backend/app/api/fusion.py`, `backend/app/main.py`, `backend/tests/test_fusion_api.py`, `docs/spec/fusion-api-endpoint.md` |
| 7abaec5c / cmd_3834 Fusion独自visibility | Fusion APIはadmin認証済み別アプリへ全active PFを渡し、表示制御はFusion独自settingsへ委ねる。`hide_portfolio`で絞らず`is_active=true`のみ。b73e5656の旧仕様CI回帰をcmd_3834で復元 | `backend/app/api/fusion.py`, `backend/tests/test_fusion_api.py`, `docs/research/cmd_3834_fusion_filter_restore.md` |
| 896a20b2/46e1b48c cmd_3569 Compare Returns page | 運用影響あり。`/compare-returns` API/router/page_visibilityが追加され、Admin visibility対象ページが増えた。運用上は既存CDP/Admin確認手順で対象URLを`/compare-returns`へ切替えて確認する | `backend/app/api/compare_returns.py`, `backend/app/main.py`, `backend/app/services/page_visibility.py`, `backend/tests/test_compare_returns_api.py` |
| 9b3618ae cmd_3572 Compare Returns MTD事前計算 | 運用影響あり。`precomputed_mtd`テーブル作成後、通常は`recalculate_fast.py`正常完了末尾でMTD事前計算が更新される。欠損/stale時はAPIがPF/BM単位fallbackするため表示正確性は維持、速度のみ劣化 | `backend/migrations/add_precomputed_mtd.py`, `backend/app/jobs/precompute_mtd.py`, `backend/app/api/compare_returns.py` |
| baf7db97/fb40fc2c/1368f895 compare系spec索引更新 | 本文追加不要 | `docs/spec/*`/`docs/_INDEX.md`/`tasks/lessons.md`中心。運用手順の新規差分はCompare Returns行で吸収 |
| afe98d64 cmd_3548 Compare Summary SPY standalone | 本文追加不要 | `backend/app/api/metrics.py`と追加テストの修正。既存Compare Summary運用手順に変更なし |
| a02b623b/9fe4704b/26711bc2/8640c347/176eb00b/9912027f/ec65decb/63a04c2b monthly/annual/price/return/recalculate高速化 | 本文追加不要 | backend services/jobsの性能改善。fullrecalculate/Render実行・排他・完了確認の運用手順は§6-7の既存ルールを維持 |
| f625dc2b cmd_3546 fullrecalculate idempotency proof | §6-7の完了確認ルールと整合。本文追加不要 | `docs/research/cmd_3546/*`に検証証跡を追加済み。ops本文にはL783 timing-history一次証跡を既に反映済み |
GA-144原因: `dm-signal-ops.md`のlast_updatedは2026-06-26で、2026-06-26以後にops pathspec対象commitが16件増加したため`gate_context_freshness.sh`がsource commits ALERTを出した。直接のALERT対象は最新3件(896a20b2/46e1b48c/baf7db97)で、真にopsへ反映が必要だった差分はCompare Returnsの運用確認対象URL/API/router追加。根本原因はGA-129/GA-141と同系統で、外部repoのbackend/api/services/jobs/docs/research変更がsplit context更新候補へ自動接続されず、gateが事後検出していること。横展開候補: `dm-signal-core.md`/`dm-signal-frontend.md`/`dm-signal-research.md`も同時にsource commits ALERT対象だが、今回の更新対象外。
## §46 password rotation運用リスク (cmd_3634_recon3)
- `dm-signal-password-rotation` cron `0 16 1 * *` はUTC+9でJST 2日目01:00になり、意図した「毎月1日01:00 JST」より丸1日遅い。前月末expires_at後から実ローテーションまで約25hの全tier失効窓が毎月発生しうる。
- `monthly_password_rotation()`はtier単位try/exceptなし。途中tierでRender env更新が失敗すると、先行tierのRender env更新+token revoke済みに対してDB更新がrollbackされる部分失敗リスクがある。
- tier数分(現行5件)の個別Render env更新はbackend再デプロイを連鎖させる可能性があり、7/1 OOM/health timeoutとの相関はRender deploy履歴と突合して確認する。
## §47 Phase1 stability fix (cmd_3635)
- Migration deadlock対策: `render.yaml` backend startCommandから`python -m app.db.init_db`を削除し、FastAPI lifespan側の`init_db()`をPostgreSQL advisory lockで直列化。workers=2時もmigration初期化は二重実行しない。
- Password rotation cron: `dm-signal-password-rotation`はRender env `RENDER_API_KEY`/`RENDER_SERVICE_ID`をcron側にも持つ前提。scheduleコメントはJST 2日01:00相当として扱う。
- Partial failure対策: Render API成功後にのみ`os.environ`を更新し、tier別失敗時は成功tierのみDB commit+token revoke、失敗tierはログ出力して処理継続。検証は関連既存テスト24件PASS、full pytestは201.73秒無出力中断のWITH_CONCERNS。
## §48 Phase2 PrecomputedRaw基盤 (cmd_3636)
- Phase2で`PrecomputedRaw`基盤、L5 raw precompute batch、`/admin/precompute-raw`、sync-status L5表示を追加。rawは24h TTLのtimezone-aware判定で取得し、欠損/stale時は`None`返却で既存fallbackを維持する。
- `recalculate_fast.py`はPrecomputedMtd更新後にraw precomputeをbest-effort実行する。失敗時はraw未更新のみで、既存recalculate結果と表示fallbackは維持される。
- `render.yaml`に`dm-signal-precompute-raw` cronを追加。idempotencyと進捗確認はsync-statusの`L5_precompute_raw`/`L5`を一次確認口にする。
## §49 Phase3 P1 raw lookup + invalidate (cmd_3637)
- P1 5EPでPrecomputedRaw lookupを導入。raw hit時は毎リクエストvisibility/maskingを適用し、miss/stale時は既存計算fallbackを維持する。
- `compare_returns.py`はPrecomputedRaw hit時にTTLCache return/setをバイパスする。raw未hit時のみ既存TTLCacheを使う。
- metadata/visibility/folder変更時は`invalidate_precomputed_raw`で該当rawを削除する。portfolio metadata-only saveは保存とinvalidateを同一DB session/commit内で実行する。
- L790: Compare ReturnsのMTD高速化はpreliminary FoF展開も同じcacheに載せる（cmd_3570）
## §50 compare-returns bulk precompute (cmd_3639)
- `compare_returns_bulk`は`PrecomputedRaw(endpoint="compare_returns_bulk", portfolio_id=NULL, params_hash=make_params_hash({}))`の1行に全active PFのtrailing+MTD rawを保持する。保存前に同endpointを削除し、PostgreSQLのNULL unique差分による複数行化を避ける。
- `/api/compare-returns`はbulk raw fresh hit時、1行lookup後に`visible_ids`でPFを絞って返す。bulk miss/stale時は既存のPF別`compare_returns_trailing` raw lookup/fallback経路を維持する。
- 2026-07-15 commit `07305b83`: PF別`precomputed_mtd.mtd_close=NULL`はfresh hitとして扱わずLIVE MTDへfallbackする。FoF 78PFが全件N/Aの場合は日付staleだけでなくNULL fresh誤判定を確認する。Standard 24PFの非NULL precompute経路は不変。定義詳細 → `context/dm-signal-core.md` §8.6。
- metadata/folder/visibility変更時は`compare_returns_trailing`に加えて`compare_returns_bulk`もinvalidateする。これにより可視性変更後のbulk行による非表示PF混入を防ぐ。
## 因果リンク
- ← [[dm-signal]] 運用層
- ← [[dm-signal-core]] コアの運用面
- → [[gunshi_idle_teppeki_parity_analysis_20260427]] 鉄壁パリティ分析: 本番PFの整合性確認
- → [[gunshi_kawarimi_monthly_speed_design_20260413]] 変換月次速度設計: kawarimi高速化の設計
- → [[gunshi_nukimi_wf_oom_analysis_20260410]] nukimi WF OOM分析: ワークフローのメモリ問題根因
- → [[gunshi_trf_date_mismatch_fix_20260414]] TRF日付不一致修正: 再計算パイプラインのバグ対処
- → [[gunshi_wf_profile_baseline_20260410]] WFプロファイルベースライン: 速度計測の起点
- → [[database]] DB運用との接続
- → [[ops-db-rules]] DB運用ルール詳細(接続/バックアップ/パリティ確認手順)
- → [[ops-procedures]] 運用手順詳細(デプロイ/ロールバック/障害対応)
- → [[parity-verification-details]] パリティ検証詳細(本番/GS同一エンジン確認手順)
- → [[pf-registration]] 本番PF登録スキル（パリティ即確認+登録の流れ）
- → [[weekly-report-writer]] 週報生成スキル（API+Grok x_search使用）
- → [[monthly-report-writer]] 月報生成スキル（5年月次リターン+月間ニュース）
- → [[note-writer]] note.com記事生成スキル（バムスタイル機能紹介記事）
- → [[sengoku-writer]] 戦国将軍書簡スキル（マルチエージェント開発裏話）
- → [[x-research]] X/Twitter検索調査スキル（xAI Grok x_search）
- → [[shogun-param-neighbor-check]] パラメータ近傍チェックスキル（GS最適値の堅牢性確認）
## §51 precomputed_raw鍵整合 (cmd_3666-3669, 2026-07-03)
- **原則**: precomputeの書く鍵(PRECOMPUTE_PARAMS)とEP lookupの引く鍵(生クエリ値のparams_hash)とFE実要求の三者は一致必須。乖離=キャッシュ無効化(LS078「真実の在処不一致」のDM-Signal実例)
- 三者突合の判定表+hash証跡 → `docs/research/cmd_3667_precomputed_raw_key_triple_diff.md`(DM-signalリポジトリ側)
- FE定数×生成表の整合テスト導入済み(片側変更でテストFAIL)。FEの要求params変更時はPRECOMPUTE_PARAMSも更新せよ
- precompute再実行: `POST /admin/precompute-raw`(admin Basic)。生成完了判定は固定行数でなく**対象PF数と一致**で行え(途中値76/102の誤報実例)
- metrics summaryはbulk raw(1行)方式=compare_returns_bulkの2例目(cmd_3669: ttfb 1.75-2.13s→0.47s)。可視性/maskingは毎リクエスト適用を維持
- 残: rolling_returnsは生成だけされAPI未参照の逆パターン(未修正)
- cmd_3675偵察: 本番102PFの`/api/debug/signal-raw`+`/api/history`で2026-07-01→2026-07-02 holding差分0件。殿観測の保有ポジション差分はDB破壊ではなくMonthly Tradeの翌月pending行先頭表示(表示層)が主因。詳細 → `docs/research/cmd_3675_holding_position_display_diff_recon.md`
- cmd_3676_recon2偵察: 7月正ポジションは本番read-only証拠上XLU。起点は`シン青龍-鉄壁`のTECL→XLU変更(2026-07-03 01:11)で、FoF定義変更ではなくFoF連鎖へ01:43-01:44に伝播。影響は7月signals更新204行。詳細 → `docs/research/cmd_3676_hanzo_recon2.md`
- cmd_3676確定: 疾風本調査も半蔵独立検算と一致。`calculation_version=755a50d`のfull recalculateが2026-07-01/02のconfirmed rowsを再生成・上書きし、現在の正はXLU。未決裁定: ユーザーに表示済みのcurrent-month confirmed rowsを後続full recalculateが無音で上書きしてよいか、また許可する場合のaudit/snapshot要件。
## §52 signal decision ledger初期台帳 (cmd_3700/3702, 2026-07-06)
- `signal_decision_ledger`はconfirmed rebalance decisionsのappend-only台帳。migrationは`signal_decision_ledger`テーブル、`ix_sdl_pf_effective`/`ix_sdl_pf_decision`、`ux_sdl_initial_decision(portfolio_id, rebalance_decision_date, event_type) WHERE event_type='initial'`を作成する。SQLAlchemy modelはbefore_update/before_deleteで変更・削除をBLOCKする。
- 初期台帳作成は`backend/scripts/build_signal_decision_ledger_initial.py`が2026-05-01/06-01/07-01候補からPFごとの`rebalance_trigger`に一致する最新1決定日だけを計画し、cmd_3704で102件を`event_type='initial'`として挿入済み。
- cmd_3711: 全PF(102)×全確定月を`event_type='historical_backfill'`で15,058件遡及挿入済み。総行数は15,160件(102 initial + 15,058 historical_backfill)。バックアップ表は`signal_decision_ledger_backup_cmd3711_20260706T1454`。`ux_sdl_historical_backfill_decision(portfolio_id, rebalance_decision_date, event_type) WHERE event_type='historical_backfill'`で冪等性を担保。
- cmd_3711後のMonthly Trade decision_sourceは原則`ledger`になる。cmd_3710の`historical`分岐は全履歴ledgerが存在しない期間の表示救済であり、backfill後はほぼ不到達になるのが正常。
- ledger決定日は各PF固有の最古signals日ではなく、`prices(SPY)`基準の月初営業日(`get_month_first_business_day`)に一致させる。Monthly Trade読み出し側の`position_start_date`キーとズレるとledger行が参照されない。
- provenance: 2026-05-01は`current_value_backfill`、6/1・7/1は`signal_change_log_old_chain`を優先し、履歴なしなら`signals_fallback`。7/1 sync-fof rewrite影響9PF/26行は`signals.holding_signal`の汚染現在値ではなく、`signal_change_log.old_holding_signal`連鎖で決定時点値へ戻す。
- PF削除前運用: `signal_decision_ledger`は`portfolios(id) ON DELETE CASCADE`対象。削除前に対象PFの台帳行をJSON/CSVで退避する。未退避なら削除禁止。
- 不要分類: cmd_3694 small-run GS pattern limitsはgrid_search実行制限と研究証跡であり、本ops手順の追記不要。`a3059891 retire stale lessons`は`tasks/lessons.md`整理で運用差分なし。
## §53 PF削除アーカイブ・復元API (cmd_3753/3754, 2026-07-08)
- PF削除は`PortfolioRepository.delete_by_id`で`portfolio_archive`へpayload退避してから関連行を削除する。対象はPF本体、folder hierarchy、monthly_returns、signals、ledger、month_start snapshots等。明示delete API以外の保存差分では削除しない安全弁を維持。
- 復元APIは`POST /api/admin/portfolios/restore/{portfolio_id}`と`POST /api/admin/portfolios/restore-all`。FoF依存はarchiveからL0→L3順に復元し、名前衝突は既定`abort`、必要時`on_name_conflict=suffix|force`。
- 復元後recalculateは既存のcross-process advisory lockを再利用し、最大300秒待機。lock timeout時は503で停止し、並行fullrecalculateを迂回しない。
## §54 工程3: 全PF事前バックアップ確定 (cmd_3783, 2026-07-09)
- 工程4(旧PF削除+新PF登録)前提として、run_id `cmd_3783_full_pre_replacement_backup_20260709` で本番102PFを`portfolio_archive`へ削除なしINSERT済み。dry-run再検証も`live_portfolios=102 / existing_for_run_before=102 / archive_count_after=102`で一致。
- 復元素材はfolder payload 102件、`signal_decision_ledger` 15,160行、`month_start_signal_input_snapshots` 3,495行を含む。FoF 78 / standard 24、required fields・内部UUID/name重複・依存欠落・cycleはいずれもPASS。
- 工程4開始条件はCLEAR。詳細と価格改定時の再計算値解釈は `/mnt/c/Python_app/DM-signal/docs/research/cmd_3783_full_pre_replacement_backup_report.md`。実行commitはDM-Signal `57530143`。
## §55 工程4前段: 入替対象リスト・実行手順確定 (cmd_3784, 2026-07-09)
- 非破壊の計画成果物として、本番102PFスナップショット(`/mnt/c/Python_app/DM-signal/docs/research/cmd_3771_20260708T052126Z_portfolio_config_snapshot.json.gz`)から削除対象86・維持対象16を機械分類。旧L0-L3本体78に加え、参照切れ防止のため旧対象へ依存するFoF 8件をdependency_closure削除対象に含める。
- 新規登録仕様は工程2成果物から75件(L0 12 / L1 21 / L2 21 / L3 21)を生成。維持対象との名前衝突0、固定UUIDなし(登録時に新規生成)、削除前にだけ既存置換スロットとの名前衝突あり。
- 正本成果物: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3784_deletion_inventory.json` / `.csv`, `/mnt/c/Python_app/DM-signal/docs/research/cmd_3784_registration_spec.json` / `.csv`, `/mnt/c/Python_app/DM-signal/docs/research/cmd_3784_execution_runbook.md`。
- 後続実行順序: dependency_closure→pf_L3→pf_L2→pf_L1→pf_L0の逆依存順削除、pf_L0→pf_L1→pf_L2→pf_L3の正依存順登録、全PF fullrecalculate、GS-本番のholding_signal(ticker×weight)+monthly_returns完全一致、DB/API/FEの3レイヤー確認。失敗時はcmd_3783 archiveからrestore-allまたは依存順restore。
## §56 工程4実行中断状態 (cmd_3785, 2026-07-09)
- cmd_3785は旧86削除・新75登録・config category修正まで本番反映済み。削除archiveは`delete_reason=cmd_3785_pf_replacement_20260709`で86/86、登録後active PFは91(維持16+新75)、新75のDB/API到達とsignals/monthly_rows生成は75/75。
- 2026-07-09 10:17 JST再検証で`recalculation_status.id=194`はcompletedへ遷移済み。DB/API到達・signals/monthly_rows生成はいずれも75/75だが、GS月次比較は`monthly_return_open`/`monthly_return`とも75/75不一致のまま。
- 疾風の非破壊偵察(LGTM)では、代表PF「シン青龍-激攻 / `DM2_SGLD_T1_Qj_L1779`」の本番API config主要値(relative_assets/absolute/risk_free/safe_haven/top_n/lookback/threshold_band)はGS specと一致。`category: selection`→`filter`はschema正規化でengine計算分岐には使わないため、登録config不備ではなくGS比較基準問題(config/signal/return parity未分離・GS側holding/signal trace不足)が主因候補。
- 半蔵の検証方法側偵察(FAIL; AC4 FE一次証跡未取得)では、cmd_3784 specとcmd_3785 registration_logのname/pattern_id/source_cmdは75/75一致、GS SQLite内pattern_id missingは0。既存再検証JSONはprod_only期間を除いても共通月mismatchが75/75で、`monthly_return_open`/close列プローブも0/75のため、GS path/pattern_id/列選択ミス単独のfalse negativeでは説明不可。後続は本番monthly生成側とGS基準の価格系列・valid_start・threshold_band・DTB3暦解像度差を比較する。
- 2026-07-09 11:07 SIGNAL CHANGE ALERT: 直近3時間の確定シグナル変化1711件/14PFは全てNEW75上位層(奥義=pf_L2系4体、秘奥義=pf_L3系10体)。維持16PFは無傷、新75は全`hide_portfolio=true`でユーザー影響なし。`recalculation_status.id=194`以降の再計算は存在しないため、同一再計算内でFoF多段計算が一度書いた値を後段で上書きしている示唆。cmd_3785追加偵察ではこのFoF書き直し挙動をシグナル差由来パリティ0/75の切り分け材料に含める。
- 才蔵の追加偵察(PASS)では代表PF「シン青龍-激攻 / `DM2_SGLD_T1_Qj_L1779`」のGS Phase1+Phase2計算を`threshold_band=0.005`込みでread-only再現し、GS DBとの差は最大7.2e-7(浮動小数点誤差)まで一致。本番とのmismatch 51ヶ月は51/51でproduction holding_signalがGS決定と乖離。DTB3暦解像度ではなく、GSローカル価格スナップショット(`analysis_runs/experiments.db`, max date 2026-03-20)と本番`prices`のadjusted-close系列乖離(TQQQ +0.396% / TECL +0.195% / LQD +1.507% / GLD 0%)が主因候補。DTB3は本番economic_indicatorsとローカルスナップショットで差分ゼロ。
- 才蔵の追加発見: 本番`prices`のTQQQ全履歴(2010-02-11〜2026-07-08, 4125行)は`source='stockdata_api'`のみで、`context/dm-signal.md`記載の「EODHD生値+自前調整(2026-07-05本番移行完了)」と矛盾。工程4をCLEARする前に、GS価格入力を本番と同一系列に揃えるか、ズレを許容する根拠を裁定する必要がある。
- 成果物: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3785_parity_verification.json`、`cmd_3785_log_recovery_report.json`、`cmd_3785_config_fix_report.json`。完了扱い禁止。次手は`cmd_3785_verify_replacement.py`をGS monthly_return単独比較からconfig parity / signal parity / return parityの3段階比較へ分離し、GS側signal trace生成または同一target_date ledger比較でfalse negativeを潰す。
## §57 工程4ロールバック完了状態 (cmd_3786 / cmd_karo_hotfix_cmd3786_sequence_rerun, 2026-07-09)
- cmd_3786順序修正版で本番は入替前の旧102PF状態へ復旧済み。実行順序は新75PF API削除→旧86PF `restore-all` 復元→fullrecalculate。最終値は`active_total=102`、`new75_live_by_config=0`、`cmd3785_restored_archive=86`、`holding_signal=102/102`、`monthly_returns=102/102`。
- API/FE確認: `/api/portfolios/get`は102件、FE `/admin` と `/compare-summary` はHTTP 200。成果物は `/mnt/c/Python_app/DM-signal/docs/research/cmd_3786_rollback_report.md` と `cmd_3786_delete_new75_log.csv`、実行commitはDM-Signal `a74fec06`。
- 残懸念: `restore-all`はDB復元と再計算生成完了後もHTTP応答が返らず、DB `recalculation_status.id=195` が`running`のまま残った。一方で`/admin/recalculate-status`は`running=false`、生成物は102/102。後続でrestore-allの応答終端とDB status終端処理を修正候補として扱う。
- cmd_3785はロールバック済みのため本番破壊状態ではない。ただし価格系列差によるGS/本番パリティ問題は未解決であり、再入替前にGS入力を本番`prices`系列へ揃えるか、ズレ許容根拠を裁定する必要がある。
- 因果リンク: [[cmd_3785順序不備]] -> [[PF削除依存順誤認]] -> [[dm_signal_pf_restore_guardrails]]。忍者追加報告の試行錯誤は`deploy_task.sh`の`inject_dm_signal_pf_operation_guardrails`でLevel5注入化済み。
## §58 Monthly Trade検証用リターン計算のticker欠落問題発見・設計書化 (2026-07-09)
- cmd_3786ロールバック中の本番ログ確認で`WARNING:app.services.monthly_trade_impl:Matched weight 0.7500 < 0.99, some tickers may be missing`を発見。`_calculate_return_from_price_movement()`(`monthly_trade_impl.py:1092-1116`)が欠落ticker時もmatched_weight未正規化のまま部分加重和を計算続行しており、Silent Fallback原則(PI-018)違反の新規インスタンス(既存SF-001〜カタログ未収載)と判明。
- 実害: 現状FEはこの値を表示に使わずAPI応答のみ(消費者grep 0件)のためユーザー影響なし。ただし将来この値が参照された瞬間に汚染データとして機能するリスクは残る。
- 殿指示(13:40)によりfail-closed化のAsIs/ToBe設計書を作成済み。実装cmdは未起票(R1-R4、単一cmd案)。
- cmd_3787でfail-closed化を実装済み。`_calculate_return_from_price_movement()`は3要素`(calculated_return, matched_weight, missing_tickers)`を返し、ticker欠落または対象価格変化欠落で`calculated_return=None`にする。API/FE型へ`missing_tickers`追加。検証: `PYTHONPATH=backend pytest -q backend/tests/test_monthly_trade_calculator.py` → 35 passed。成果物: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3787_monthly_trade_missing_ticker_fail_closed.md`
- 因果リンク: [[cmd_3786ロールバック中ログ確認]] -> [[matched_weight部分計算続行発見]] -> [[monthly-trade-missing-ticker-calc-asis-tobe-5w1h_20260709]]
## §59 再計算ステータスDB SSOT化 (cmd_3788, 2026-07-09)
- 発端: cmd_3786ロールバック中にDB `recalculation_status.id=195`がrunningのまま見える一方、`/admin/recalculate-status`が`running=false`を返し、Render `uvicorn --workers 2`のworker-localメモリ可視性欠陥が判明。
- 修正: `get_recalculate_status_data()`が最新running DB行を参照し、local idleでもDB runningなら`source=db`でrunningを返す。`trigger_recalculate_sync()`はbackground投入前に`start_recalculation()`でadvisory lock/DB排他を取得し、取得不可なら200 acceptedではなく409を返す。
- 成果物: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3788_recalc_status_db_ssot.md`。因果リンク: [[殿指摘20260709_1349_3786完了確認]] -> [[worker-local_status誤答]] -> [[recalc_status_DB_SSOT化]]
## §60 Monthly Trade matched_weight表示展開後不整合 (cmd_3809, 2026-07-10)
- `matched_weight=0.5, missing_tickers=[]`はband片側欠落ではない。本番DBの対象PF「奥義-GS-変わり身-鉄壁」該当月weightsは合計1.0で、`safe_haven_switch.py`/`recalculate_fast.py`のband生成経路も0.5+0.5を保存する。
- 問題候補はFoF表示展開後のメタデータ不整合。`monthly_trade.py`が`expanded_tickers`を`display_ticker_weights`へ後段上書きする一方、`monthly_trade_impl.py`由来の`matched_weight`は同じ表示weight基準で再計算されず、表示weights合計1.0とmatched_weight=0.5が同居する。
- 修正候補: monthly_trade表示展開後に`matched_weight`/`missing_tickers`を再計算するか、raw component weightsとdisplay ticker weightsをAPI上で明示分離する。詳細: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3809_band_weights_half_bug.md`
## §61 Fusion可視性の殿裁定とCI修正による裁定逆行事故 (cmd_3834, 2026-07-10)
- **殿裁定(2026-07-10 17:44確定)**: DM-Fusionは本番稼働中(is_active)の**全PF**をAPIで返す。表示のon/offは**Fusion側admin画面の個別・フォルダー単位制御**が担う。DM-Signal側の`hide_portfolio`/TierはFusion表示に関与しない。`hide_portfolio=true`が92体あるのは正常状態(可視制御の正=tier_visibility_settings)。
- **事故経緯**: 6/29に裁定コミット`7abaec5c`(Fusion独自visibilityのため全PF必要)でフィルタ除去→旧仕様前提の`test_fusion_api.py`が未更新のまま残存→7/3のCI RED自走修正`b73e5656`がテストの仕様正当性を確認せず**コード側にフィルタを再追加=裁定逆行**→Fusionが11体しか返さずフォルダー表示全滅(殿報告7/10 17:19)。cmd_3834で裁定復元+テスト準拠化。
- **教訓**: (1)CI RED修正は当該テストの仕様正当性(直近裁定との整合)を先に確認せよ。テストに合わせてコードを曲げると裁定が覆る (2)裁定でコードを変えたら旧仕様前提テストを同時に更新せよ (3)UPSERT系のupdated_atは値変化の証拠にならない(将軍のcmd_3833誤起票=LS-A09(32)再発)。
- 因果リンク: [[殿裁定20260710_1744_Fusion可視性]] -> [[CI修正b73e5656裁定逆行]] -> [[cmd_3834フィルタ裁定復元]]。記憶DB: knowledge:bb944c45e23802c3
## §62 Tier別PF可視性の承認完成形 (cmd_3837, 2026-07-10)
- 本番`tier_visibility_settings`を差分追記で復旧。実効visible件数はBasic 5 / Standard 22 / AddOn 22 / NewStandard 17 / premium 27。承認対象hidden 59件のみ`hide_portfolio=false, hide_signal=false, hide_components=true`へ変更し、Basic孤児ID 1件を非表示化。既存visible/非対象portfolio/global設定の差分は0。
- Viewer APIではfolder非表示がportfolio可視性より優先する。奥義-GS-分身3体のfolder `5396fe40-8f48-4619-aebc-402476c9120a`はglobal hiddenのため、Standard既存overrideに加えてAddOn/premiumへ`hidden=false`を各1キー追加。API実応答も5/22/22/17/27で完全一致。
- 復旧・rollback証跡: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3837_visibility_pre_change_backup.json`、`cmd_3837_visibility_post_db.json`、`cmd_3837_folder_override_diff.json`、`cmd_3837_visibility_post_folder_db.json`、`cmd_3837_viewer_api_verify.json`。再実行script: `/mnt/c/Python_app/DM-signal/scripts/oneshot/cmd_3837_visibility_diff.py`。
- 因果リンク: [[殿指示20260710_2028_note対応表準拠設定]] -> [[cmd_3837差分書き込み]] -> [[tier別可視性完成形]]。
## §63 admin visibility「手動saveしたのに反映されない」偵察: folder非表示はSignals限定 (cmd_3838, 2026-07-10)
- **殿報告(20:40)の主因(確度高)**: L1.5フォルダ非表示(`check_hide_folder`)を呼んでいるのは全コードベース中`backend/app/api/signals.py:376`の**1箇所のみ**。§62の「Viewer APIではfolder非表示がportfolio可視性より優先する」は`/api/signals`限定の記述であり、compare-returns/metrics/monthly-returns/performance/deterioration/history/rolling-returns/regime-analysis/monthly-trade/trades/p_average/annual-returnsの**12エンドポイントはfolder非表示を一切参照しない**(`check_hide_portfolio`のみ実行)。フォルダを非表示にしても保存自体は成功するため、Signals以外のページでは該当PFが表示され続け「反映されていない」ように見える。
- 副次バグ(実在確認済・トリガー未特定): (1) `PUT /api/admin/tiers/{tier_id}/visibility`は`portfolio_settings`等を`updated_at`突合なしに全置換する(楽観的並行性制御ゼロ。スキーマに`updated_at`はあるが書込み側で未使用)。(2) FE `/admin/visibility`はTier切替や離脱時に未保存編集を確認なしに破棄する(`hasUnsavedChanges`/`confirm(`/`beforeunload`いずれも実装なし)。殿が20:28〜20:40に複数Tierを順次手動設定した運用フローと一致する再現条件。
- 棄却済み仮説: precompute rawキャッシュ無効化範囲不足(rawはtier非依存でマスキングは都度動的適用のため無関係)/ Fusion API(殿裁定2026-07-10 17:44で意図的に独立管理、§61参照)。
- 別リスクとして記録: `portfolios.hide_portfolio`/`hide_signal`列はPF configから同期される複製列だが、閲覧側マスキング判定はこの列を一切参照しない「死んだ列」(debug.py診断出力のみが読み手)。将来PF個別編集画面での混同源になりうる。
- 詳細・行番号付き全コードパス・テストギャップ: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3838_visibility_save_recon.md`
- 因果リンク: [[殿報告20260710_2040_admin保存不反映]] -> [[folder非表示signals限定発覚]] -> [[cmd_3838偵察recon文書]]
## §63.1 admin visibility根治実装: folder非表示(L1.5)を全閲覧EPへ横展開 (cmd_3839, 2026-07-10)
- **AC1完了**: `backend/app/services/visibility_helpers.py`に共通関数`check_hide_portfolio_or_folder(tier_settings, global_settings, portfolio_id, folder_id, is_admin)`を追加し、§63で判明した未適用12エンドポイント(compare_returns/metrics×4/monthly_returns/p_average×2/performance×2/deterioration×2/history/rolling_returns/regime_analysis/monthly_trade/trades/annual_returns、計18呼出箇所)全てに適用。`signals.py`はhanzo cmd_3835が同時改修中のため参照専用に固定し無変更(competing-write回避、家老指示2026-07-10 21:52)。
- grep実測で`check_hide_portfolio(`単体呼出し(旧L2onlyパターン)の残存0件、`check_hide_portfolio_or_folder(`が18箇所へ適用済みを確認。既存回帰テスト46件(test_visibility_masking/test_global_visibility/test_compare_returns_api)は適用後も全PASS。
- 副次バグ(機構B: PUT楽観ロック欠如、機構C: FE Tier切替時の未保存編集消失)は同cmd内でAC3/AC4として対応完了(§63.2参照)。
- 詳細: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3839_folder_hide_rollout.md`
- 因果リンク: [[cmd_3838偵察recon文書]] -> [[cmd_3839全EP一括適用]] -> [[folder非表示L1.5全EP適用完了]]
## §63.2 cmd_3839 AC3-5: 楽観ロック+FE未保存ガード+本番検証 (2026-07-10)
- **AC3**: `viewer_tiers.py`の`update_tier_visibility`/`update_global_visibility`へ`updated_at`楽観ロック追加(不一致409、未指定は後方互換でスキップ)。`GlobalVisibilitySettingsUpdate`スキーマ+GET/PUT globalレスポンスに`updated_at`追加。新規`test_visibility_optimistic_lock.py` 9/9 PASS
- **AC4**: FE `page.tsx`に`hasUnsavedChanges`/`tierUpdatedAt`/`globalUpdatedAt` state追加。Tier切替を`handleTierSelect`でガード(未保存時confirm())、`beforeunload`警告追加、Save時に`updated_at`送信+409専用メッセージ。新規`visibility-unsaved-guard.test.tsx` 5/5 PASS
- **AC5**: 検証スクリプト`scripts/oneshot/cmd_3839_ac5_verify.py`(read-only)でデプロイ前ベースライン取得済み: `/api/signals`は5/22/22/17/27で完全不変。compare_returns/metrics_summary/p_averageは現行データにhidden folderが存在しないため既にsignals.pyと一致(潜在バグ、ローカルtest_folder_hide_rollout.py 41testsで修正効果は実証済み)。`/api/deterioration`のmissing差分はfolder非表示と無関係の別問題(データカバレッジ、スコープ外)。**忍者はpush/deploy不可のため、本番push後の再検証は家老/将軍に引き継ぎ**
- 詳細: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3839_ac5_production_verification.md`
- 因果リンク: [[folder非表示L1.5全EP適用完了]] -> [[cmd_3839楽観ロック+FEガード]] -> [[本番デプロイ後検証待ち]]
## §64 Stage A timeout / vectorized非決定性の再設計 (cmd_3840, 2026-07-10)
- Stage A 35.21秒の主因はvectorized計算ではなく、月初snapshot生成中の`_get_git_commit_hash()` 238回→git subprocess累計21.17秒(60.1%)。`_compute_pipeline_signals()`自体は0.20秒(0.6%)。run固定hashへ置換すればcold 11.80秒 / warm 3.92秒で30秒内。
- DM-safe 5,000日次行の同一入力2反復は`portfolio_id/date/signal/holding_signal/momentum_data`差分0、semantic SHA-256完全一致。単一process/同一DB入力では非決定性を再現せず、残条件は並行config/price更新・別transaction snapshot・別commit・ledger生成時点差。run入力manifest固定が次の切分け条件。
- 恒久方針はPipelineEngineのblock意味論を共通executorへ抽出し、日次Engineとvectorized adapterを単一実装化。逐日Engine直呼びは約149K calls / 約2000秒へ退行するためoracle限定。ledger guardは緩めない。
- 詳細・行別内訳・比較設計・回帰方針: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3840_nondeterminism_redesign.md`
- 因果リンク: [[cmd_3827_FAIL]] -> [[Stage_A_timeout+同一入力差分0]] -> [[cmd_3840単一意味論再設計]]
## §65 Tier/global可視性設定の孤児清掃 (cmd_3841, 2026-07-11)
- 現行`portfolios` 102 IDとの集合差で孤児設定を限定し、退避完全一致をtransaction直前に確認してtier 428件（Basic 62 / Standard 122 / AddOn 122 / NewStandard 0 / premium 122）とglobal 102件を除去。現行PF宛の設定値差分は0。
- 清掃前後の実効visible件数はBasic 5 / Standard 22 / AddOn 22 / NewStandard 17 / premium 27で不変。commit後の`/api/signals`実応答も全tierでPF名・件数・`hide_signal`が清掃前と完全一致。
- 退避・再実行・検証証跡: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3841_orphan_cleanup_backup.json`、`cmd_3841_orphan_cleanup_result.json`、`cmd_3841_viewer_api_pre.json`、`cmd_3841_viewer_api_post.json`、`scripts/oneshot/cmd_3841_orphan_cleanup.py`。
- 因果リンク: [[PF削除cleanup非対称の残骸蓄積]] -> [[cmd_3841退避付き除去]] -> [[可視性対応表と現行PF集合の整合]]。
## §66 L5 zero-recompute Phase 3ローカル全量検証 (cmd_3835, 2026-07-11)
- 公式id=206 verified fixtureの103PF全量で、legacy/candidate各1545行がmissing/extra/mismatch=0。固定3PF warmup後のproduction相当L5境界は13.213641秒（render 9.053741 + encode 0.718013 + atomic bulk UPSERT 3.436778 + commit 0.005109）で30秒gateをPASS。SELECT/loaderは全0。
- 103PF初回差分25件はstandard PFの`monthly_trade` oldest boundaryへ`component_portfolios: []`を新設したschema-presence差のみ。元key欠落は欠落維持、FoFで元key存在時のみ`[]`へ更新する最小修正後、3PF 45/45→103PF 1545/1545の順で完全一致を確認。
- Phase 3時点では本番`fullrecalculate`未実行でDB lock待ちだった。詳細: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3835_zero_recompute_exec.md`。因果リンク: [[cmd_3825でP2到達+bulk零化完了]] -> [[monthly_trade_schema-presence差25件]] -> [[cmd_3835_Phase3_103PF完全一致]]。
- **Phase 4本番結果**: DB lock解放後、commit `d942982b`へ`fullrecalculate`を厳密1回実行。status id=212はcompleted/end_timeあり、PF=102・rows=1533・failed=0だが、本番L5は66.64秒で目標30秒をFAIL。実行前`precomputed_raw=0`、実行後1533のため凍結比較はbefore=0/after=1533/extra=1533（common mismatch=0）。停止規則に従い再実行なし。詳細は同実行ログPhase 4。
- **本番分解・cache消失根因**: PF別102件のelapsed合計58.06秒（全体87.1%、median 0.45秒 / p95 1.80秒 / max 2.18秒）、bulk+固定費8.58秒。7/9本番ログでは1533行存在したがPhase 4直前は0行。`viewer_tiers.update_global_visibility`がvisibility非依存の`precomputed_raw`を引数なしinvalidateで全削除し、tier PUTも一部rawを不要削除する確定バグを修正。DM-Signal `178add2a`で両visibility PUTのinvalidateを0経路化し、cache保持テスト11/11 PASS。今回の実削除トリガーがglobal PUTだったことは時刻ログ未捕捉のため強い推定に留める。因果リンク: [[visibility_save]] -> [[precomputed_raw全削除]] -> [[fullrecalculate_L5_cold再生成]] -> [[cache保持hotfix_178add2a]]。
## §67 TIMING SUMMARY Layer5(precompute_raw)欠落バグ根治 (cmd_3842, 2026-07-11)
- cmd_3831偵察の結論②を実装。根本原因は二重: (a) `LayerTimer.LAYER_ORDER`(`timing.py:74`)に`L5_precompute_raw`が無く`print_summary()`が出力しない、(b) `recalculate_fast.py`の`precompute_raw_for_portfolios()`呼び出しが`layer_timer`へ一切未登録で`get_bottleneck()`の比較対象にも入らない（実測ではL5が全体2497sの66.5%=1659.78sを占めるのに不可視、L2が誤ってBOTTLENECK表示）。
- 修正: `LAYER_ORDER`へ`"L5_precompute_raw"`追加(既存の`etl_trigger.py:822`命名と一致)＋`recalculate_fast.py`のprecompute_raw呼び出しを`time.perf_counter()`計測し成功/失敗いずれも`layer_timer.layers["L5_precompute_raw"]`へ登録(既存のtry/exceptフォールバック・ログ・`stats`キーは不変、表示追加のみで計算ロジック非改変)。
- 再発防止: `LayerTimer.get_unaccounted_ratio()`を新設(`status=completed`のLayer合計が全体経過時間をカバーしない割合)。`UNACCOUNTED_TIME_WARN_THRESHOLD=0.3`(30%)超で`print_summary()`が`logger.warning()`を出す。今回規模(66.5%欠落)は閾値を大きく超え、同種の登録漏れは次回からWARNログで即検知できる。
- 検証: `test_timing.py`へ決定的テスト8件追加(`time.sleep()`不使用、`timer.layers`直接注入+`total_start`オフセットでフレーキーさ排除)。関連7ファイル合計78 tests / 0 failed / 0 skipped(`test_timing.py`28、`test_timing_db.py`10、`test_layer_timing_integration.py`6、`test_sync_layers_timing.py`7、`test_recalculate_modes.py`18、`test_recalculate_precompute_savepoint.py`1、`test_signal_integrity.py`8)。詳細: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3842_timing_l5_fix.md`
- 因果リンク: [[cmd_3831偵察でL5未登録発覚]] -> [[cmd_3842_LAYER_ORDER+layer登録修正]] -> [[get_unaccounted_ratio再発防止]]
## §68 recalculate P1a run identity固定 (cmd_3844, 2026-07-11)
- `recalculate_history_fast`はbusiness write前にsource identityを1回だけ解決する。Renderは40hex `RENDER_GIT_COMMIT`必須、local write-enabledはfull git hash+tracked clean必須。unknown/dirtyはfail-closed。月初snapshotループ内git callは0。
- `logical_date`はrun開始時1値に固定してprice/economic load・日次処理・FoF終端へ伝播。run IDはDB String(20)制約に合わせUTC14桁+base32 6桁、衝突時再生成。
- P1b(manifest/immutable snapshot/ledger preload/caller全被覆)は未実装。詳細・実測・復元点: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3844_p1a_source_identity.md`
- 因果リンク: [[cmd_3840偵察=ループ内git238回+日跨ぎparity割れ]] -> [[source identity単回+logical_date固定+一意run_id]] -> [[cmd_3844_P1a実装]]
## §69 TradePerformanceメモ化の全PFパリティFAILと反映中止 (cmd_3845, 2026-07-11)
- 旧/新コードを同一frozen PostgreSQL template由来の隔離cloneで全102PF・全期間再生成。7回すべて102PF/11,040行/SHA 6c20e4e... で相互完全一致したが、変更前本番baseline SHA 4dea1761... とは24PF・554行不一致。差はbenchmark/excess returnの浮動小数末尾(約1e-16)のみだが、許容誤差ゼロ原則によりFAIL。
- 本番push/deploy/fullrecalculateは実行せず、メモ化系列3 commitをrevert。実測もold median 113.379s→new median 124.623sで9.917%退行のため、fixtureの91.70%改善は補助証拠に限定。詳細: /mnt/c/Python_app/DM-signal/docs/research/cmd_3845_memoize_parity.md
- 因果リンク: [[cmd_3843_fixture一致+全量未検証]] -> [[cmd_3845本番baseline554行不一致]] -> [[本番反映中止+メモ化revert]]
## §70 origin/main統合は完了・push/deployは重大発見により見送り (cmd_3860, 2026-07-12)
- cmd_3859 AC2安全停止(本番live=178add2a、origin 9 vs local 79分岐)の解消作業。`git merge origin/main`(force/rebase不使用)でマージコミット`38ec9b8b`を作成し、両系列コミットが祖先に含まれることを確認(AC1完了)。マージ後`backend/`の内容はlocal main旧tip(0e079ac5)と**0差分**(originの9 commitは全て家老が個別移植済みでlocal側の真部分集合だったため)。コンフリクト2件(`monthly_trade_impl.py`, `run_precommit_checks.sh`)もこの前提でHEAD側採用にて解決。
- **重大発見**: 検証用ブランチでlocal main(79 commit統合状態)を初めてGitHub Actions実CI(全1790テスト)に通したところ**24件失敗**(origin/main単体は1件のみ=pre-existingの日付mock問題)。backend/の0差分により、この24件はマージ由来ではなくlocal 79 commit統合状態に既に内在していたと確定。うち6件は`RECALC_RSS_CAP_MB`未設定というCI環境要因(fail-closed設計は意図通り。`.github/workflows/pytest.yml`へ既存の慣例値8192を追加するcommit`b46170ab`で解消、本番非影響)で24→21件に減少。残21件のうち約半数以上は`db.info`を使うprecompute検知コード(cmd_3835/cmd_3849/cmd_3850由来)に対し古いテストが`MagicMock().info`未設定のまま(=Noneでなく別Mockを返し誤判定)である疑いが強く、production regressionではない可能性が高い。**しかし`test_nested_fof_signal.py::test_signal_cache_no_forward_fill`はcmd_1481の実過去障害(Cashシグナル月またぎ伝播)の回帰テストであり、誤判定の確証が得られるまで看過できない。**
- **運用上の確認**: DM-SignalはRender Auto-Deploy: On Commit。mainへのpush(`[skip render]`無し)は即本番デプロイに直結するため、push(AC2)とdeploy(AC3)は事実上不可分。21件の未триaж failureが残る状態でのpushはリスクを許容できないと判断し、**本cmdの範囲ではpush/deployを意図的に見送った**。local mainには`38ec9b8b`+`b46170ab`の2 commitが未push状態で保持されており、次のtriage cmdがそのまま土台にできる。
- 詳細・再現ログ・失敗一覧全件・推奨アクション: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3860_integration_and_ci_findings.md`
- 因果リンク: [[cmd_3859_AC2安全停止]] -> [[origin9_vs_local79分岐]] -> [[cmd_3860マージ完了+CI初回全量実行で21件pre-existing_failure発覚]] -> [[push即deploy運用によりtriage_cmd待ちで意図的停止]]
## §71 cmd_3860残21件FAILの全件triage完了・全量FAIL0/SKIP0達成(commit未push) (cmd_3861, 2026-07-12)
- §70の残21件FAILを影丸(kagemaru)が21/21 **fixture artifact**(実装regression 0/21)と二値判定し、fixture修正commit `32542328`(+style commit `af11db75`)を確定。ただし対象unit 91件のみ再実行し、2 integration testsと全量pytest/CIは未実行のままAC2/AC3 noで報告(verdict FAIL)。hayateのresume試行も報告未完成のままfailed。
- kotaro(`cmd_karo_ci_fix_cmd3861_resume_v2`)が隔離worktree(`ninja/kotaro-cmd-3861-resume-v2`, base=32542328, main作業treeのdirty差分は無変更)で全量`backend/tests`を実行し**3 FAIL**を発見: (1)(2) `test_portfolio_restore_e2e_parity.py`の2件はfixtureは正しかったが別の実装バグ(`recalculate_history_fast`が`SourceSelectGuard`(input_manifest.py, cmd_3849 P1b)を`activate()`後`uninstall_all()`を一度も呼ばず、L5precompute_raw等の正当な後続reading をブロック。本番はrequest毎新規sessionのため無症状だが、同一sessionを跨ぐ呼出で顕在化する潜在バグ)。(3) `test_cmd_3854_fof_golden_regression.py`はローカル環境アーティファクト(gitignore対象の243,293行golden archive)がworktreeに存在しないための`FileNotFoundError`で、コードバグではない。
- 実装修正(`recalculate_fast.py`へ`SourceSelectGuard.uninstall_all(db)`追加, commit `5fde6265`)+golden archive復元(既存worktreeから同一sha256原本を複製)後、**全量1776 passed / 8 xfailed / 6 xpassed / FAIL 0 / SKIP 0**(`python3 -m pytest -c backend/pytest.ini backend/tests`, 455.55s, 隔離pgserver環境`~/dm-signal-cmd3819-localpg`)を実測確認。golden regression自体もPASS(78/78 PF一致、P3a/cmd_3856以降のFoF計算に回帰なし)。
- pushは家老の統合CI判断まで未実施(local branch `ninja/kotaro-cmd-3861-resume-v2`に保持)。origin main統合(§70で示した本番push/deploy一体運用)は次工程の判断事項。
- 詳細・21+2件全件分類・数値根拠: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3861_ci_failure_triage.md`
- 因果リンク: [[cmd_3860マージ完了+CI初回全量実行で21件pre-existing_failure発覚]] -> [[kagemaruが21件fixture修正も全量未実行のまま報告]] -> [[kotaroが隔離worktreeで全量実行しSourceSelectGuard未解除バグ+golden_archive欠落の2件を追加発見]] -> [[uninstall_all追加+archive復元でFAIL0/SKIP0達成]]
## §72 P4統合+live deploy完了(commit=34747ad1)・restore契約完成・速度実測-8.80% (v1.4.15, 2026-07-13)
- **結論**: §70/§71時点で「push/deploy意図的見送り」だった状態は解消済み。P4統合branch(親`732dfef3`+`8241f41c`)がRender backend(`srv-d4ja7q15pdvs739a4q1g`)へdeploy済み(deploy=`dep-d99oaseq1p3s73d2keb0`、status=live、finishedAt=2026-07-12T12:18:36Z)。**live commit=`34747ad118aebd42a05e00a358f2c709542f3ec9`**。local HEAD(`9252af73`)/origin main(`f17c93cd`)/live(`34747ad1`)の3値は意図的に異なり、以後の本番照合はlive `34747ad1`を用いる(origin/mainとの混同禁止)。
- **restore契約完成(運用フェイルセーフ)**: negative A(artifact改竄/schema不一致/source commit不一致/DB identity不一致)4/4 PASS、negative B(confirm欠落/lock競合/実行中recalc/途中例外)4/4 PASS、全ケースbusiness write 0・必要時rollback 1。core統合commit=`732dfef3`(restore core+negative A/B+runbook)、対象42→統合後43 PASS/FAIL0/SKIP0。実行側fail-closed境界としてtracked capability launcher(infra commit `4da46f0e2`→`7ba136462`→`b65d32fc5`)+runbookのexecution-rootをlive commitへpinする契約(`9252af73`)を追補。
- **速度実測(recalculate_fast.py系列)**: shadow run(`run_id=202607112047232OVP4O`)のtotal_elapsed_sec=**497.02秒**(§6-7記載の本番545秒比**-8.80%**、bottleneck=L3_fof)。P1c instrumentationは`P1C_ARTIFACT_DIR`未設定の通常経路でhex書出し条件falseのため本番inert(production DB同run_id 0件で確認済み)。
- **AC2(本番fullrecalculate 1run照合)実行結果(v1.4.16, 2026-07-13 12:00更新, cmd_3870)**: 本番1run実行済み(strict、run id 213、01:26:17〜01:37:44Z=**687.35秒**、error NULL)。**結果はFAIL**: canonical comparatorがexpected input_snapshot_id=`75886e9f`(cmd_3859 shadow由来)とactual=`c2b66a69`(run213実測)の不一致でfail-closed停止(missing/mismatch比較未到達=決定性の反証ではなく照合契約の入力固定不備が主仮説)。P5進行は禁止のまま継続。
  - **原状回復**: 初回restoreはtrade_performance COPY中のPK duplicateで全rollback(部分復元0)。根因=advisory lockがfullrecalc同士のみ排他し通常writer(`etl_trigger` Background precompute-raw)を止めないため、DELETE→COPY間の隙間で待機writerが再insertしていた。**restore-locked**(18表SHARE ROW EXCLUSIVE一括lock+DELETE後0件assert+COPY後row/sha256二重検証、commit`bc1092695`)を新設し2回目実行で**18/18表・565,756行exact=true**の原状回復を確認(manifest sha=`d9ec7e4f`)。business write時のcrash-safety運用資産としてrestore-lockedをcapability launcherへ追加済み。
  - **次工程**: `cmd_3872`(input_snapshot_id採番経路の実差分偵察)→照合契約の入力固定方式確定→AC2再挑戦→GREEN後P5(cmd_3827事故条件回帰)。
- 詳細: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.16(§9.1 Phase表)、AC2実行証跡: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3870_p4_ac2_evidence.md`、研究文脈の対応記述: `context/dm-signal-research.md`(cmd_3870/cmd_3872/P4_AC2再挑戦方式確定エントリへGA-238で反映済み)、家老一次照合: 掲示板`blt_20260713_021355`
- 因果リンク: [[cmd_3861全量FAIL0/SKIP0達成]] -> [[cmd_karo_hotfix_p4_restore_core_integrator_202607121954でrestore契約統合]] -> [[origin main統合push+Render_Auto_Deployでlive=34747ad1確定]] -> [[AC2本番fullrecalculate_1run実行(cmd_3870)]] -> [[input_snapshot_id不一致でFAIL・restore-lockedで原状回復]] -> [[cmd_3872入力差分偵察待ち]]
## §73 P4 AC2再挑戦方式確定: single-source immutable input bundle (v1.4.17, 2026-07-13, GA-238で反映)
- **結論**: cmd_3872の偵察で、AC2 FAIL(§72)は決定性の反証ではなく**比較前提FAIL**(`logical_date`日跨ぎ+manifest payloadが行本体/行数/終端日を保存せずhashのみ永続化)と確定。将軍・家老検討合意(殿指示2026-07-13 12:33)で再挑戦方式を**single-source immutable input bundle**に確定: T0でread-only materialize→shadow A/B 2run+production 1runの全てが同一bundleをconsume→18表exact比較→mismatch時はrestore-locked(§72)で復旧。直前検討したclone expected生成のみ案は家老実測反証(実行窓19分44秒〜28分01秒でwriter混入を排除できない)で不採用。
- **前提実装**: bundle export/import consumer機構+manifest payload保存契約(sha256/row_count/min_max date/PF set/logical_dateを完全保存、schema migration不要)。この実装GREENまでAC2再挑戦は禁止。実装第1段(bundle export/import consumer)は`cmd_3873`が担当中(2026-07-13時点in_progress、完了時に本セクションの追補が必要)。
- 詳細: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.17、入力差分偵察: `context/dm-signal-research.md`(cmd_3872_input_snapshot_diff)
- 因果リンク: [[AC2本番fullrecalculate_1run実行(cmd_3870)]] -> [[input_snapshot_id不一致でFAIL]] -> [[cmd_3872入力差分偵察でlogical_date日跨ぎ+manifest payload未保存が十分条件と特定]] -> [[single-source_immutable_input_bundle方式確定]] -> [[cmd_3873でbundle実装着手(in_progress)]]
## §74 GS DB世代重複削除候補9件を実削除(cmd_3868, 2026-07-13)
- **結論**: grid_search配下146DB台帳(`docs/research/cmd_3868_gs_db_generation_inventory.md`)の削除候補は9件・921174016 bytesで確定(文書冒頭メタデータの「削除候補0件/0bytes」は旧版残骸で誤り、本文の削除候補一覧テーブル・重複グループ詳細が正)。saizoが実行直前に9件全件をrealpath scope内・非symlink・通常ファイル・bytes一致・git管理外・コード参照0(自己参照文書除く一括grep)・同一SHA保持正本現存の6項目で独立再検証し全件PASSを確認後、個別`rm --`で削除実行。
- 詳細・削除前後df/SHA突合証跡: `docs/research/cmd_3868_gs_db_generation_inventory.md`, 報告: `queue/reports/saizo_report_cmd_3868.yaml`
- 因果リンク: [[C_drive満杯20260712_2307]] -> [[gs_db世代重複40.8GB残存]] -> [[kagemaruが146DB台帳作成・9件候補確定]] -> [[saizoが実行直前再検証+個別rm削除]]
## §75 P4 writer fence運用契約の現状(cmd_3873/cmd_3881/cmd_3882, 2026-07-13)
- immutable bundle consumerはcmd_3873で実装済み。writer fence初案(cmd_3881)は安全性PASSだがsingle median 1.1834・bulk 1.1639・full wall 1.062609で性能閾値FAIL、本番適用禁止。
- cmd_3882は18表writerのAST検出↔registry↔DB enforcement三集合exact CIを実装し、動的SQL/集合不一致をfail-closed BLOCKする。詳細=`context/dm-signal-research.md`の`cmd_3873`系列・`AST恒常スキャンCI`・`cmd_3881_DB_fence_migration_FAIL`。
- cmd_3880の運用入口はstrict consume API。実`uvicorn --workers 2`でmaterialize workerとconsume workerを分離し、12同時request中HTTP 202は1件のみ、敵対fixture 8/8 PASS。bundle/nonce期限切れは自動消費せず明示re-armを要求する。詳細=`context/dm-signal-research.md`の`cmd_3880_transport_state_API`。
- v1.4.23では比較対象18表をF=output/fence/restore対象17表とG=`signal_decision_ledger` immutable guard 1表へ分離。restoreのDELETE/COPYはFのみ、Gはmutation 0とpre/post canonical hash不変を確認し、差分時は通常restoreで上書きせず`RECOVERY_REQUIRED`へ止める。
- arm DDLはFのcanonical table名辞書順でlockし、SQLSTATE 40P01/55P03/57014は自動retry 0回で原子rollbackする。別read-only catalog sessionでtrigger 0/17・run role 0・ARMING不在を証明できない限りadvisory/fenceを解放しない。正本=`/mnt/c/Python_app/DM-signal/docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.23、source commit=`611f715bfbe4875e9e8d92c267818ee52324faa0`。
- v1.4.27 RC3候補(commit=`a5b7be5dc7682293e24472ff9f941d43ee1553eb`、未統合)は接続レベル物理排除をNOLOGIN+非keeper session terminateへ転換したが、Render actual capability artifactが0件のため後続5群をfail-closed BLOCK。production live mutation 0・automatic retry 0・SKIP 0を維持し、read/writeは同一`dm_signal_user`のためP4窓約10分のAPI全断境界も未解消。3882-3885 freezeを維持する。
- **managed DB capability入口runbook**: 一般PostgreSQL仕様/local clone成功をRender能力証明に使わない。後段実装・pool/session敵対試験・全数性能試験より先に、actual preview/isolated環境で`environment_identity/service_id/database_host/role_name`、role属性before→NOLOGIN→LOGIN restore、各SQLSTATE、`production_live_mutations=0`を1 artifactへ保存する。artifact 0件または必須field欠落なら後段を実行せず数値付きBLOCKする。教訓=L893、報告=`queue/reports/hanzo_report_cmd_karo_fence_v1427_nologin_rc3_202607140653.yaml`。
- **preview≠production proxy補正(v1.4.28入口)**: preview isolatedは`rolcreaterole=false`・最初のrecovery role操作SQLSTATE=`42501`だった一方、本番readonlyでは`dm_signal_user.rolcreaterole=true`。したがってpreview結果はpreview環境上の不成立だけを証明し、本番実行可能性は未証明。旧L894の広い表現はretireし、L895へ置換した。本番能力は業務role無接触の専用prefix probe roleだけを`CREATE NOLOGIN→ALTER LOGIN→ALTER NOLOGIN→DROP`の4 mutation step・30秒timeout・retry 0・finally DROP・catalog before/after hash exactで測る。`dm_signal_user`自己ALTERは禁止、軍師敵対レビュー→将軍承認前の実probeも禁止、3882-3885 freezeとpreview resource保持を継続する。origin=`[[preview属性齟齬]] -> [[proxy無効可能性]] -> [[本番能力未証明]]`。
## §76 safe bundle v2運用契約 (cmd_3879, 2026-07-14)
- input bundleは`safe_bundle_v2.load_bundle`のみで読み、raw SHA-256→entry allowlist/size/path→artifact hash→schema/row count→typed decodeの順にfail-closed検証する。pickleと旧`export_input_bundle`経路は使用禁止。
- materializeは`REPEATABLE READ READ ONLY`をtransaction先頭で設定し、`SHOW transaction_read_only=on`確認後に実行する。valid bundle consumer時のsource SELECT fallbackは0でなければ失敗扱い。
- 全量前preflightはgolden存在+canonical SHA、pytest-asyncio導入済み`/usr/bin/python3`、`RECALC_RSS_CAP_MB=8192`を二値確認する。正本=`/mnt/c/Python_app/DM-signal/docs/research/cmd_3879_safe_bundle_impl.md`、main統合=`97c13040→b5716329→29ea37a9`。
- L888: 全量テスト前提artifactと実行環境のpreflight必須——本§の二値確認手順が正本（cmd_3879）
## §77 SIGNAL CHANGE 07-13/07-14偵察 (cmd_3903, 2026-07-14)
- 07-13の800件はfull run 213（01:26:17〜01:37:44 UTC）と一致するが、restore-locked後の現DBでは行別履歴0件。07-14はFoF cron時間帯の23PF×7日=161件exact（01:48:01〜01:49:32 UTC）だがinput snapshot 0/161。価格旧版が無いため非決定性と断定せず、全961件を証跡不足に分類した。詳細・PF別内訳・SQL → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3903_signal_change_root_cause.md`
## §78 ledger最新event決定性・確定域fail-closed (cmd_3907, 2026-07-14)
- `recalculate_fast.py`のimmutable ledger snapshotは`portfolio_id/effective_start_date/recorded_at/id`を明示ORDER BYし、`resolve_ledger_decisions_bulk()`も入力順に依存せず同キーの`max()`で最新applicable eventを選ぶ。DB順・bundle順のいずれでも古いeventへの巻戻しを禁止する。
- PFにledger eventが存在しない場合とtarget dateがPF最初のeventより前の場合はpendingとしてpass-throughを維持する。最初のevent以降の確定域で最新eventの`decision_holding_signal`が欠落する場合は`SignalDecisionLedgerCoverageError`でwrite前に停止する。
- 回帰証跡: 6月eventが配列末尾、7月eventが先頭という旧誤選択fixtureを含むfocused 41 passed / FAIL 0 / SKIP 0。
- 因果リンク: [[ledger_snapshot_ORDER_BYなし_applicable末尾選択]] -> [[07-14の23FoFが06-01台帳値へ巻戻し]] -> [[cmd_3907_決定的max選択+確定域fail_closed]]
## §79 P4 keeper同一connection run orchestration checkpoint (cmd_3902, 2026-07-14)
- `cb3e7e7e76b3c962700608559c506d5bf5d350c2` はstrict consume APIをkeeper orchestratorへ接続し、未設定時はHTTP 503でfail-closed。keeperはlock readyからbusiness write、compare/restore、terminalまで同一contextで生存し、run tokenを`LEASED→CONSUMED→TERMINAL`で管理する。実装checkpointはfocused transport 9/9、uvicorn E2E 1/1、ruff PASS。ただし最終全量は31%で中断されSKIP 1を解消していないため、cmd_3902はverdict FAIL/canceledの安全checkpointであり本番適用許可ではない。
- 一次根拠: `/mnt/c/Python_app/DM-signal/backend/app/api/p4_bundle.py` L49-58/L111-115、`backend/app/jobs/bundle_transport.py` L235-239/L262-307、`queue/reports/hanzo_report_cmd_3902.yaml`。
- 因果リンク: [[cmd_3902_commit後terminal_pause]] -> [[完了gate内own_commit鮮度check未到達]] -> [[GA-251常設context鮮度ALERT]] -> [[ops索引とsource_commit境界を同時更新]]
## §80 07-14 holding_signal 161行復元 (cmd_3905, 2026-07-14)
- 07-14上書き対象の23PF×7営業日=161行を7/1確定値へ復元。post値、latest ledger値、独立readonly再照合はそれぞれ161/161 exact、他表write 0、recalculate 0。実行証跡とrollback artifactは`queue/reports/hayate_report_cmd_3905.yaml`。
- 因果リンク: [[07-14_23FoF月間保有上書き]] -> [[cmd_3905_bounded_restore]] -> [[7/1確定値161行復元]]
- L897: 本番bounded restoreは実project pathでのlauncher貫通試験を事前要求する。unit PASSだけではroot結合不整合を見逃す（cmd_3905）
## §81 新規Signal INSERTのledger drift監査契約 (cmd_3997, 2026-07-16)
- 旧方式(2026-07-14, `05a45d83`)は新規`signals` INSERTの確定域ledger driftをrun-level `SIGNAL CHANGE ALERT`へ載せたが、synthetic entryをDBから除外したため事後に3PFを復元できなかった。
- 新方式(2026-07-16, `f4d94ab4`)は同じsynthetic entryを`signal_change_log`へ1行永続化する。`old_holding_signal=proposed`、`new_holding_signal=ledger`、`date`はDB date型、内部フラグ`is_new_insert_ledger_drift`は永続化しない。同一payload再実行はSignal 1行・監査1行を維持し監査増分0。
- ledger一致INSERT・ledger未被覆pending・既存UPDATE・cleanup経路は不変。回帰76/76 PASS、運用simulation 12/12 PASS、FAIL 0、SKIP 0。
- 因果リンク: [[2026-07-14_run_level_ALERT橋渡し]] -> [[alert_payload非永続で事後追跡不能]] -> [[cmd_3997_signal_change_log永続化]]
## §81.1 pytest timing ledger運用 (2026-07-16)
- `021ceba7`でpytest pluginを常時ロードし、call単位のduration/outcome/failure/skip/commitを `backend/.pytest_cache/pytest_timing_ledger.tsv` に永続化。並列writerはflock+atomic replace、破損header/rowはUsageErrorでfail-closed。`PYTEST_TIMING_LEDGER_PATH`で隔離出力先を指定可能。
- `d8530bcb`→`0815a02e`でplugin importを`backend.tests.pytest_duration_ledger_plugin`へ統一し、CI/ローカルとも同一canonical moduleをロードする契約へ修正。`96c8c5f5`ではrolling returns summaryへmedian・p10・positive rate・sample count・best/worst window境界を追加し、PF/benchmark×close/openを同一valid seriesから算出する。→ `/mnt/c/Python_app/DM-signal/backend/tests/test_pytest_duration_ledger_plugin.py` / `/mnt/c/Python_app/DM-signal/backend/app/jobs/generators/rolling_returns.py`（GA-320）
- `61848453` cmd_4114: sample_count/positive_rate contract tests追加(4テスト PASS)。Rolling Returns Phase1実装完了。
- 因果リンク: [[pytest所要時間の推測]] -> [[call単位timing証跡欠落]] -> [[pytest_timing_ledger常時記録]]
## §82 確定域holding_signal correction event運用 (cmd_3908, 2026-07-15)
- 確定域訂正は`POST /admin/signal-decision-ledger/corrections`のappend-only eventのみ。対象日以前にeventなしはfail-closed、直接Signal/ledger UPDATE・DELETEは禁止。設計正本→`/mnt/c/Python_app/DM-signal/docs/design/signal-decision-ledger-design.md`
## §83 確定域ledger baseline freeze運用 (cmd_3947, 2026-07-15)
- capabilityは未被覆行を実行時述語で全件導出しappend-only baseline化。本番は52行/52PFを追加し341,799/341,799被覆、既存SHA不変・他表write 0。証跡→`/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_3947_baseline_freeze_backup.json`
## §84 recalculate-sync同一logical_date再計測 (commit 3b9327f8, 2026-07-29)
- live commit一致を一次確認後、`recalculate-sync?start_date=...&end_date=YYYY-MM-DD&mode=portfolio`をPF指定なしで実行。完了はDBの同一`run_id` terminal completedで判定。
## §85 signal flush複合key照会の運用上限 (commit 3ee5c21b, 2026-08-01)
- `6200cc1e`の10,000-key chunkは本番L3同期で07:15開始→07:19 `updated_at`、`StatementTooComplex`、rows 0で失敗。既知正常commit `5c8a9cf` の1,000-key境界を再適用した`3ee5c21b`で、`_collect_new_insert_ledger_drift_alerts()`と`_classify_repeated_ledger_guard_corrections()`を共通helper経由1,000 keyごとに照会する。現在は本番再検証中で、rows>0・terminal完走の一次証跡が出るまで未解決扱い。詳細はDM-Signal側research正本へ集約し、本contextは運用結論のみ保持する。因果リンク: [[10k_chunk本番StatementTooComplex_rows0]] -> [[5c8a9cf_1k境界再適用]] -> [[3ee5c21b_本番再検証中]]
## §86 2026-08-03全期間再計算・Compare復旧
- run 226は920秒でcompleted。`monthly_returns` 16,874行・102/102 PF、5Y欠落0/102、負geometric mean 0/102、metrics 204/204へ復旧。raceは`8d994f35`の原子UPSERTでRender反映済み。
## §87 Monthly生成のlogical date運用境界 (2026-08-04)
- `50002dc6`,`4c1cac7f`,`274062e4`,`9a27eb4f`: runの`end_date`をMonthlyの時計とし最新営業日へclamp。未価格未来月/初回有効holding前はskip、開始後欠落はfail-closed。詳細→`/mnt/c/Python_app/DM-signal/docs/research/dm-monthly-trade-bug-genko-chain-archive_20260803.md`
## §88 cmd_4243 SIGNAL CHANGE ALERT 08-01〜08-06偵察 (2026-08-09)
- 08-05/08-07/08-09の3警報(count=3/15/48)305行は全件recalculation_status+git commit+signal_decision_ledgerの相関で正常確定更新と判定(異常書換え0)。08-03=cmd_4224(ledger境界失効)デプロイ検証recalc、08-08=cmd_4241(L5 regen)デプロイ検証portfolio recalc(ledger未確定域につきPI-P06非抵触)。
## §89 monthly_returns系統的退行(cmd_4244, 2026-08-09)
- L1587: initial signal基準日とeffective loop startの不一致はholding NULLを発生させる — 初期signal基準日と有効ループ開始日を同一SSOTから取る（cmd_karo_recon_run303_effective_start_20260812、/lesson-sort 2026-08-18）
- mode='full'(run226/230)で復元した全履歴monthly_returnsが、その後のmode='portfolio'実行(run227/228/229)のたびに2022-10以降だけへ切り詰められる退行を実測確認(DM2/DM3/basicデュアルモメンタム等で完全履歴→47行/2022-10始まりへ縮小→run230で再復元を直接観測)。真因=`monthly_returns.py:692`のPF単位DELETE→INSERTが「狭い計算結果での広い既存履歴の上書き」を防いでいない(0件生成時のみガード)。秘奥義-抜き身-激攻の完全ゼロ行も同一メカニズムの極端ケース。y5リターン欠落は調査時点で102/102PF・y3は50/102PFに達した。暫定対策=mode='full'のみ本番実行、恒久対策=692行のガード拡張。
## §90 トラブル時の第一容疑=fullrecalculate忘れ・mode違い (殿裁定2026-08-09 03:03)
- 何かトラブル・エラー・データ不整合(N/A表示・計算されていないPF・履歴欠落)を見たら、第一容疑として直近コード変更後のfullrecalculate忘れとmode違い(portfolio≠full)を疑い、`recalculation_status`のmode・時刻をDBで確認する。§89の系統的退行が実証例。機構化・自動実行は禁止(殿裁定: 意思依存にならぬようsemantic-map aliasで本則が自動注入される)。
## §91 月次リターン基本原理の現物境界 (cmd_4246, 2026-08-09)
- `MonthlyReturn`は確定/MTDの値を保存するがstatus/provenanceを持たず、価格未到着新月はMonthly Returns APIでは欠落（全rowなしは404）、Monthly Tradeだけが動的`is_pending=true`を返す。`historical_backfill`は同じledger resolver候補へ流入するため、履歴修復・通常計算・pending/confirmed lifecycleを分離する設計検討が必要。詳細→`docs/research/cmd_4246_monthly_return_principles_recon_20260809.md`
## §92 cmd_4247 月次リターン再設計タスクリスト現物偵察 (2026-08-09)
- Dashboardは専用1 APIではなく`/api/signals`・`/api/performance/{portfolio_id}`・`/api/mtd/{portfolio_id}`の3系統、FE系列初期値は共有Providerの`CLOSE`、FoFはcomponent monthly-return入力、ledger初期書込みは`effective_start_date=rebalance_decision_date`複写、HEADのportfolio cleanupは7 PF依存テーブルをmode無条件DELETEする。正本ヘッダは28タスクと称するが実ID行は30（α8+β5+γ5+δ4+ε4+ζ4）。全30行の突合と検証コマンド/隠れ依存→`docs/research/cmd_4247_tasklist_recon_20260809.md`
- 影丸現物追補(2026-08-09, HEAD `45ad390e`): FoF momentumは月末`MonthlyReturn.cumulative_return`を`ComponentPriceBlock`経由で月数窓評価し、日次loopは月初rebalance時のみpipeline実行。ledger `effective_start_date`はdaily planの`rebalance_decision_date`複写で、入口APIのcron直結は未確認。指定タスクリスト本体は作業木に存在せず、AC2行突合はBLOCKとして成果物へ記録。

## §93 2026-08-09 backend運用境界の追加反映

- `4d81c32c` は`c469ba6f`のmonthly_returns履歴保全guardをrevertした。狭いportfolio計算で既存履歴を削る危険が現行に残るため、fullrecalculate運用と`monthly_returns`行数/最古月の事後確認を継続する。参照: `backend/app/jobs/generators/monthly_returns.py`, commits `c469ba6f`→`4d81c32c`。
- `aaef7932` はGroup-AのOpen系列メトリクス(Correlation/Beta/Alpha/R²/Treynor/Calmar/Positive Periods/Gain-Loss Ratio)をClose系列と独立算出する。運用検証ではmetricのopen/close両値を混同せず確認する。参照: `backend/app/services/metrics_impl.py`, `backend/tests/test_metrics_continuity_risk.py`、commit `aaef7932`。
- `28b58ee0` はFoF Monthly Trade表示を`position_start_date`のSignalへ寄せ、月初が週末のときの旧holding表示を防ぐ。月境界の本番確認はDashboard holdingとの一致を確認する。参照: `backend/app/api/monthly_trade.py`, `backend/tests/test_monthly_trade_calculator.py`、commit `28b58ee0`。

## §94 cmd_4293 fullrecalculate速度回帰の区間分解 (2026-08-10)
- 本番DB/Render同一run `20260810035234909371`（live `d42a6882`）はtotal **2778.02s**。L2=958.157s、L3 FoF=1702.754s（61.3%、BOTTLENECK）、L5はconfirmed-only pending-row error。L3内訳は`dataframe_prep=1366.43s`、daily_loop=107.80s、signals_flush=185.86s、monthly_returns=4.28s。RenderのPrecomputeは914.12s中trade_perf=862.74s(94.4%)。
- 前run `2026081000375024E52B`(3051.31s)との同一run lineage比較で、L3 dataframe_prep **1.87→1366.43s(+1364.56s)**、L3 total 335.208→1702.754s。一方L5は2257.204→57.355sへ減少し、T-γ5がL5 cold costをL3へ移した構造と確定。
- 最大回帰の発端はcommit `9f2891d2`（FoF momentum daily NAV cutover）。`backend/app/jobs/recalculate_fof.py:979`でFoF毎に`nav_frame_cache`を初期化し、再帰daily NAV構築を78 FoF間で共有しない。修正候補は有効calendar/rangeを含む共有cache（またはglobal frame+slice）で、NAV parityを保ったまま重複materializationを除く。
- 因果リンク: `[[T-γ5_daily_NAV_cutover]] -> [[FoF毎nav_frame_cache再初期化]] -> [[L3_dataframe_prep_1366.43s]] -> [[fullrecalculate_2778.02s]]`。

## §95 cmd_4319 ledger freeze liveness recon (2026-08-15)
- 現行本番 `signal_decision_ledger=0行`、cmd3704 backup=0行、cmd3711 backup=102行。cmd3711 backupの102 PFは現行PFへ102/102一致（standard 24、FoF 78、active 102）。`signals=385090行/102PF`、`monthly_returns=16976行/102PF`。本番read-only一次証跡と詳細因果追跡→`/mnt/c/Python_app/DM-Signal/docs/research/cmd_4319_ledger_freeze_liveness_recon_20260815_saizo.md`。
- 凍結機構はmodel append-only listener＋signals flush/monthly/FoFのledger reconcileとして現存。構築機構は`insert_initial_ledger_events()`＋admin endpointとして現存するが、`render.yaml` month-start cronはrecalculate-syncのみでinitial-events endpointへ未接続。ledger 0行の間はguardがpending pass-throughとなるため、保護を有効化する前にinitial-events運用配線を別途確定する必要がある。
- 0行化の最後の実行イベントは、現行DBスキーマ・backup・runtime codeから特定不能。runtime全消去経路は検出されず、台帳補充・保護有効化・本番変更は本cmdで実施していない。因果リンク: `[[cmd_3711_historical_backfill_20260706]] -> [[cmd_4319_current_ledger_zero_readonly]] -> [[initial-events_cron_wiring未接続]]`。
## §96 cmd_4320 保存済み展開値vslegacy再展開 (2026-08-15)
- L1596: 保存済み展開値は本番legacy同値性確認後に計算入力へ昇格する — fixture一致だけで昇格せず本番全件同値性を先行確認（cmd_4320、/lesson-sort 2026-08-18）
- 本番保存値15,768組の突合は一致14,955、不一致813（ticker集合731、weight64、legacy空18）。保存値の無条件入力昇格は不可。詳細→`/mnt/c/Python_app/DM-Signal/docs/research/cmd_4320_saved_vs_legacy_weights_20260815.md`
- 全不一致は`pipeline_config`有効PFで発生し、基準読込11:22:17 JST〜比較終了11:23:46 JSTに01:10/01:40 UTC日次cronの通過なし。因果リンク: `[[cmd_4318_saved_expanded_weights]] -> [[cmd_4320本番全件突合813不一致]] -> [[保存値無条件昇格不可]]`。

## §97 cmd_4321 展開値の分岐段追跡 (2026-08-15)
- 第一原理規則1/2でnested FoFを最下段standardから手計算した。`奥義-GS-分身-鉄壁/2013-03-01`は再展開`{TMV:.25,XLU:.25,TQQQ:.50}`、保存`{TMV:.25,XLU:.50,TQQQ:.25}`で、分岐は`GSシン加速D-鉄壁`の子選択層から上流へ伝播。`奥義-GS-分身-常勝/2011-10-03`は再展開`{Cash:.75,TQQQ:.25}`、保存`{XLU:.125,TECL:.125,TQQQ:.75}`で、トップ直下の子PFシグナル層に分岐を観測。
- 全件分類は`ticker_set_mismatch=731`、`weight_mismatch=64`、`legacy_empty=18`、残余0。現行入力を規則1/2へ適用した再展開値が定義整合、保存側の過去入力は全件では判定不能。`legacy_empty`18件だけはraw `signal`と保存値がstandard終端を満たし、legacy空が規則違反。詳細→`/mnt/c/Python_app/DM-signal/docs/research/cmd_4321_expansion_divergence_layer_20260815.md`。

## §98 本番突合の標準=業務列parity + 1手の型 (2026-08-15〜16)

- 本番検証の判定は `scripts/dm_signal_business_parity.py compare --before --after`(業務列限定・PK単位・calculated_at/provenance除外)。全列md5比較は非業務列で必ず不一致になる偽FAIL(2026-08-15 L0で実証)。
- 1手の型(殿裁定): 忍者1体・1タスク・新規テストなし→commit→push→deploy live→full 1回→parity差分0→次手。fullの結果待ちの間に次手を実装(パイプライン)。FAIL→積んだ手を全部revert。push前に production base で import 到達closureを1回確認(欠落helperによる起動失敗が2度発生・a9883865で修復)。

## §99 cmd_4331 FoF tie-break dry-run (2026-08-17)
- 本番FoF74 PFのうちselection block有57・無17。共通dispatchは`backend/app/services/pipeline/engine.py:109-142`だがtop-N/cutoffは各filterへ分散し、GS run_077/l1はproduction block parity経路と独自vectorized選択経路を併存する。全74 PFを同一as-of月で再集計し、適用月9,141・branch/view評価15,910・変更949月(MAF722/Momentum55/MultiView30/SingleView60/Trend82/Weighted0、no-block17は月0)、stage②4,511・③668・④0・⑤7・⑥7・②skip264。standard24 PFはgap4,178観測で相対1e-9未満0/exact0。詳細→`/mnt/c/Python_app/DM-signal/docs/research/cmd_4331_fof_tiebreak_dryrun_20260817.md`。

## §100 FoF子PF選択の決定性 — 6段キーtie-break (2026-08-17 12:51〜08-18 00:13、PD-138)
- L1598: FoF exact tie集合とfloat僅差順位を分離して検証する — cutoff全採用のexact tieはset順不変、ratio scoreのfloat僅差は順位反転する。6段キー導入で両者を決定的に解決（cmd_4330、/lesson-sort 2026-08-18）
- 結論: FoF選択フィルタ6種の同点解決は共通層 `backend/app/services/pipeline/selection.py` `select_top_n_deterministic`(①config依存スコア合成ε1e-9→②12M(両者13観測以上時のみ)→③設定来CAGR→④MaxDD小→⑤現保有維持→⑥設定来早い方、同率全採用廃止)。手①②(cmd_4334-4340)で配線集約→手③(cmd_4344 54e3e663+2f3e3c82)で切替、本番live 08-18 00:13、full run404で合否(a)期待差分=`docs/research/cmd_4342_fof_tiebreak_expected_diff.csv`(DM-Signal repo、959月)PF×月一致(b)2回目md5一致(c)標準PF変化0(d)時間≤2倍。戻し方=revert 2commit→push→deploy→full 1回。
- 正本 → `docs/research/dm-fof-tiebreak-determinism-asis-tobe_20260817.md`(AsIs v1.4/ToBe v0.3、gist 1e0cab30、artifact 58f94a75)。乾式=§99(cmd_4331 949月は集計値のみ・参考値)。手④(GS fast path parity)未着手。
- 補足(2026-08-18 06:55): 手③は補正1 cmd_4349(候補列をcomponent_order安定順=6段全同値の最終決着はpipeline_config記載順、set順/ID順ではない)・補正2 cmd_4351(②③④のデータ欠損skipを候補集合単位=比較器を全順序化)を経て本番f519002bで収束実証((b)run408↔409 md5一致)。合否(a)は補正oracle(cmd_4350 nested伝播+cmd_4352 期間換算)で8,504/9/57(残9=oracle境界)。運用原則(殿裁定08-18 00:45 PD-139相当): 外部(GitHub)障害中は安易なrevert/deployをしない。cron sync-fofは同一経路(sync_fof→recalculate_history_fast L3_fof→_recalculate_fof_history)。手④GS parity未着手。
