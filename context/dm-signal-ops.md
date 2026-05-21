# DM-signal 運用コンテキスト
<!-- last_updated: 2026-04-30 cmd_karo_ctx_freshness_ops L2奥義登録完了+GS/KB更新反映 -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。

コア定義(§0-5,8,10-11,13,15,18) → `context/dm-signal-core.md`
研究・検証結果(§19-24) → `context/dm-signal-research.md`

## §6-7 recalculate_fast.py + OPT-E

6Phase+OPT-E(Phase3.7)構成。signal_calc 1,724s→0.53s(3,786倍)。最新本番: **357.28s/124PF**(2026-03-29 cmd_1478, OPT-12~15全反映)。
112件消失バグ(L045)=Phase4 dict miss時continue→日次フォールバック追加(91c04a4)で修正済。
crash-safety(cmd_1463/1465): shutdown警告(main.py)+recalculation_statusテーブルDB永続化+pg_advisory_lock排他制御(key=8675309, セッション保持方式, fail-open)。SIGKILL時PostgreSQL自動解放。
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

- L690: recalculate-sync完了判定はAPI statusだけでなくDB recalculation_status行で確認する（cmd_2424）
- L701: fullrecalculate後は非対象PFのmonthly_returns件数diffを確認し復元判断まで行う（cmd_2450）
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
- 参照: cdp_measure.sh L80-120, auto-ops/cdp/README.md, memory/cdp-browser-automation.md

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

## §36 API認証

- admin系API: Basic Auth(`ADMIN_API_KEY`)
- viewer系API: Bearer Token(`VIEWER_TOKEN`)
- FE Admin認証とBE admin系API認証は区別する。画面ログインは`ADMIN_USER`/`ADMIN_PASS`、APIはBasic Auth。
- データ確認はAPI経由よりDB直接クエリが確実。

## §37 ETL

- ETL cronはL0-L3の4本体制。L0/L1/L2/L3の各レイヤーを独立cronで同期し、上位レイヤーは下位レイヤー完了後の本番DBを読む。
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
| cmd_791 Phase2b BE最適化 | `/api/monthly-returns` から `expanded_tickers` 除去 + months前倒しを実装。15体diff完全一致PASS、monthly-trade側 `expanded_tickers` は維持。 | `→ /mnt/c/tools/multi-agent-shogun/queue/archive/cmds/cmd_791_completed_20260311.yaml` / `→ /mnt/c/tools/multi-agent-shogun/queue/archive/reports/kotaro_report_cmd_791_183558.yaml` / `→ /mnt/c/tools/multi-agent-shogun/queue/archive/reports/kagemaru_report_cmd_791_20260311.yaml` |
| cmd_792 ETag有効化 | FEの304誤判定を修正。`etagStore → apiCache` 復元経路で既存ETag 3件を実動化。`tsc --noEmit` PASS、api-client tests 19 PASS。 | `→ /mnt/c/tools/multi-agent-shogun/queue/archive/cmds/cmd_792_completed_20260311.yaml` / `→ /mnt/c/tools/multi-agent-shogun/queue/archive/reports/hanzo_report_cmd_792_190031.yaml` |
| cmd_763 workers=2復帰 | 認証修正完了後の復帰cmd。CDP比較基準は workers=1時点で cold 128ms / warm 149ms / PF切替 1005ms。 | `→ /mnt/c/tools/multi-agent-shogun/queue/archive/cmds/cmd_763_completed_20260311.yaml` |
| cmd_746 CDP計測基盤 | cold/warm・PF切替・SPA遷移・API個別計測・baseline自動比較を一発実行可能化。実戦値: Dashboard cold 126ms / warm 152ms、PF切替 1003.9ms、compare-summary 155ms、monthly-returns 191ms、deterioration 170ms。 | `→ /mnt/c/tools/multi-agent-shogun/queue/archive/cmds/cmd_746_completed_20260311.yaml` / `→ /mnt/c/tools/multi-agent-shogun/queue/archive/reports/kagemaru_report_cmd_746_20260311.yaml` |
- L177: 本番404切り分けはopenapi.json実測でデプロイ未反映を即時判定できる（cmd_553）
- L178: 本番404調査はopenapi実測で『ルート未登録』を先に確定すると切り分けが最短になる（cmd_553）
- L179: 新サービスのimport文とrequirements.txtの突合確認をデプロイ前チェックに含めるべき（cmd_554）
- L180: render.yaml cronジョブ追加時envVars sync:falseのシークレットはRenderダッシュボード手動設定が必要（cmd_554）
- L190: 集計要件でrole分離が必要ならイベント記録時点で識別子を保存しないと後段SQLでは復元不能（cmd_574）
- L202: Render Static Siteのheaders.pathはrootと配下階層を別globで覆わねば全txtを捕捉できぬ（cmd_643）
- L321: admin tier系テストはRender env同期を実APIに飛ばすとローカルsuiteを汚染する（cmd_987）

## §12 計算データ管理

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

## §14 ドキュメントインデックス

**CoDD適用方針設計書**: `docs/research/codd_dmsignal_python_strategy.md` — DM-Signal Python高速化の全体方針。§0前提条件(環境/コマンド/成功条件)+§3ワークフロー(Phase 1-4)+§5本番防御層。CoDD改善cmd着手前に必読

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

**注意**: `dm-signal.onrender.com` は404(L002)。必ず`dm-signal-frontend`を使え。

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

設計書: → https://gist.github.com/simokitafresh/14b6cf497b3abbefb85a2f3d102d778d
- FE Admin UI: ALM config編集機能が先(殿指示)。設計確定済み(ALMトグルでLookback↔ALM設定切替)

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

## 因果リンク

- ← [[dm-signal]] 運用層
- ← [[dm-signal-core]] コアの運用面
- → [[database]] DB運用との接続
