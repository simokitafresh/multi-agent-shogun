# 戦局日誌 (Campaign Log)
<!-- last_updated: 2026-03-20 -->

> cmdの意図・結果・因果を時系列で記録する索引層。
> 詳細は各報告YAML（パス記載）を参照。500行超で日付分割。

---

## 2026-03-27

| cmd | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_1414 | Dream-skill基盤: SKILL.md配置+should_dream.shトリガー+統合テスト | GATE CLEAR。5Phase Memory Consolidation SKILL.md(232行)+should_dream.sh(24hゲート)+統合テスト全PASS。Dream実行でTS正規化43件(0%→100%)+gate/lesson候補各2件抽出 | 疾風AC1+影丸AC2+家老AC3。設計書完全準拠。MCP書込み制限下でPhase1-5完了確認 |
| cmd_1421 | R13 GreedyK5統合検証: R11(Greedy最良)+R12(K=5最適)の2知見を統合 | GATE CLEAR。GreedyK5がSharpe最良(2.19)。5体目=抜き身-激攻(WardK5=抜き身-鉄壁と異なる)。GreedyK4=Calmar最良(7.19) | 半蔵完遂。事後版4手法比較。静的WardK5(2.08)<K4(2.14)=WF方式(K5>K4)と逆転→方式差 |
| cmd_1422 | R14ローリング版4手法比較: 事後版優位がデータスヌーピングでないか検証 | GATE CLEAR。Ward K=5が最良(Sharpe2.18/CAGR91.3%)。事後版減衰-2.7%=堅牢。GreedyK5は-17.1%で不安定 | 才蔵完遂。95ヶ月ローリング(36M lookback)。全手法R1超過。TO≈20%/月で実運用可能 |
| cmd_1423 | R15 Ward K感度分析(K=3-8): 事後版K=5をそのまま持ち込むバイアス排除 | GATE CLEAR。K*=5(Sharpe2.1756)。事後版K=5と一致→バイアスなし。K5/K6プラトー形成 | 疾風完遂。sanity check PASS(K=4/5がcmd_1422一致)。gradual peak=パラメータ感度中程度 |
| cmd_1424 | R16 lookback感度分析(18-60ヶ月): K感度と直交する軸で36ヶ月の妥当性検証 | GATE CLEAR。LB*=36ヶ月(Sharpe2.1756)=cmd_1422一致。broad peak=頑健。データスヌーピング兆候なし | 影丸完遂。共通期間(2020-03~2026-01)でもLB36最適。Calmar6.06最良。LB48のみやや低下 |
| cmd_1425 | R17 2次元グリッド(K×LB=30通り): 十字型では不可視の交互作用を可視化 | GATE CLEAR。最適(K*,LB*)=(5,36) Sharpe=2.133。peak_ratio=1.073=頑健。K=5,LB=36は最適そのもの | 半蔵完遂。交互作用発見: LB短→K=4最適、LB中→K=5最適。R15-R17でパラメータ頑健性完全確認 |
| cmd_1427 | R19 拡張2Dグリッド(K=2-12×LB=12-60、99通り): R17の粗い30通りを密に拡張 | GATE CLEAR。最適(K=4,LB=30) Sharpe=2.1869。K=5,LB=36=97.5%。peak_ratio=1.12=頑健 | 疾風完遂。R17からK=5→K=4に最適移動(2.5%差=プラトー内)。K≥9/LB≥48低下。殿判断用データ完成 |

## 2026-03-26

| cmd | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_1413 | ネステッドFoF R7(逆ボラ)+R8(絶対モメンタム)+R9(VIX連続)+全7ルール横断比較 | GATE CLEAR。R2 CHAMPION堅持。R7がSharpe1.933+MaxDD-20.4%でR2超え=最有望補完候補。R8=R2と実質同一(フィルタ不発)。R9=CAGR壊滅54.9%。L497登録(compute_monthly_selections共通関数) | 疾風AC1+半蔵AC2+小太郎AC3。cmd_1412のR6_extルックアヘッド修正(lag-1)も含む |
| cmd_1412 | ネステッドFoF R4(Half-Kelly)+外部レジーム(R6_ext)+全ルール横断比較 | GATE CLEAR。R4 FAIL(R2劣後)。R6_ext Sharpe2.16→★ルックアヘッドバイアス確定(軍師検証: lag-1補正後CAGR61.2%/Sharpe1.87=R1以下)。**R2がCHAMPION確定** | 疾風+半蔵+小太郎。R4: DeMiguel(2009)整合。R6_ext: 当月末VIX/SPY使用(Faber2007違反)で32.8%の月でレジーム判定変動。軍師deepdive Phase5実践で根因特定 |
| cmd_1411 | ネステッドFoF R2実装: Ward4クラスタ選抜EW+WF検証+R1比較+クラスタ頑健性テスト | GATE CLEAR。R2 CAGR74.5%/Sharpe1.92(R1比+10.7%)。N=3-10全R1超え。ピークN=5(76.4%)だが将軍裁定でN=4維持 | 才蔵AC1+AC2→影丸AC3+AC4。将軍先行値80.8%との差異=WFリクラスタリングの正常差 |
| cmd_1410 | ネステッドFoF Phase1偵察: 21体月次リターン生成→相関分析→R1(EW21)ベースライン→比較→少数精鋭提案 | GATE CLEAR。R1(EW21) CAGR58.6%/Sharpe1.76。5体精鋭Sharpe2.03。blind_spot: 四つ目CAGR差異0.226(L493) | 影丸。将軍独立分析でWard4クラスタ→EW=Sharpe2.06/OOS CAGR92.5%発見。R2はクラスタベースEW最有力 |
| cmd_1406 | gitignore整理(ホワイトリスト導入前のcommit済み運用ファイル追跡解除) | GATE CLEAR。70件追跡解除+9件追加+push | 疾風。ホワイトリスト導入後の残務整理 |
| cmd_1407 | セキュリティバグ修正2件: insight_write.sh入力サニタイズ+deploy_task.sh yaml.dump安全化 | GATE CLEAR。新規テスト14件+既存36件全PASS | 影丸。修行L2で発見された実バグ(LK015)の修正 |
| cmd_1408 | 防御的コーディング4件: エラー握潰し修正+未使用関数接続+grep堅牢化+重複排除 | GATE CLEAR。テスト41件+新規5件全PASS | 才蔵。修行L2で発見された実バグの修正 |
| cmd_1405 | E2Eテスト4件タイムアウト修正+CI緑化 | GATE CLEAR。根本原因=IFS=tab連続タブ圧縮→specials_b64空→clear_command未処理。E2E 18/18+UT 516/516全PASS | 半蔵。L297登録(IFS=tabプレースホルダ必須) |

## 2026-03-25

| cmd | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_1391 | CI RED修正(15テスト5ファイル) | GATE CLEAR。367テスト全PASS。CI 1件(ninja_monitor snapshot)のみCI環境固有で残存 | ←フォーク解除+set-default後の仕上げ。tobisaru(3ファイル)+kotaro(残り全件+push)+hanzo(fixture)+saizo(確認のみ)の4名分担 |
| cmd_1392 | dashboard_auto_section.sh高速化(22.5s→5s目標) | GATE CLEAR。3.3s達成(85%削減)。Python3箇所→gawk/jq化 | ←cmd_1387(cmd_complete_gate高速化)と同パターン。直列Python処理がbash/awk/jqで十分置換可能と実証 |
| GP-072 | report_field_set.sh フィールド値検証+自動変換 | commit 8685dc1。+231行。WA率64.7%→推定11% | ←軍師提案(c2+c3+c4)の実装。3度消失→影丸commitで永続化。_validate_field_value関数+post-write dict→list自動変換 |
| cmd_1398 | チェックリストStep 8a: シン四神v2 12体パリティ検証 | GATE CLEAR。全65PF ALL PASS(hs=100%,ret=100%)。FAIL/SKIP=0 | ←recalculate後の最終確認。12シン四神v2+53既存PFの完全一致を確認。疾風 |
| cmd_1399 | チェックリストStep 8b: シン忍法v2 20体パリティ検証 | GATE CLEAR。PASS=2,FAIL=18(全L485初月パターン)。構造的FAIL=0 | ←recalculate後のFoF検証。18FAILは全て初月hs_cross既知パターン。影丸 |
| GP-084(将軍直接) | lib Python→awk第2波: pane_lookup(bug+perf), cli_lookup(2箇所), karo_workaround_log, gate_karo_startup(3箇所), ralph_loop_metrics cache | pane_lookup: 258ms→30ms(-88%)+パス/キー不一致バグ修正。cli_lookup: 200ms/call→6ms(-97%), 8スクリプト伝播。gate_karo_startup: 306ms→183ms(-40%)+workaround Python障害修正。ralph_loop_metrics: 3.2s→0.32s(warm,-90%) | ←GP-078第1波(agent_config+startup gate)に続くlib Python全廃第2波。新発見: (1)pane_lookup 3重バグ(パス:logs→queue,キー:ninjas→agents,Python不要)で動的マッピング完全死亡 (2)karo_workarounds.yaml混在フォーマットでPython yaml.safe_load失敗→count常に0 |

## 2026-03-24

| cmd | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_1376 | oikaze tolerance=1e-12横展開修正(cmd_1374四つ目修正の水平展開) | GATE CLEAR。小太郎impl。軍師LGTM。WA:0。3箇所修正+28116パターン事前検証PASS。他run_077_*.pyに同パターンなし | ←cmd_1374で四つ目のtolerance根本原因特定→oikazeに同パターン残存を疾風DCで発見→横展開完了。DC: batch vs PE md5不一致残存(スクリプトPASS) |
| cmd_1364 | cmd_save.shにq7_failure_prediction BLOCKチェック追加 | GATE CLEAR。才蔵impl。軍師LGTM。WA:0。autofix 5件自動防御 | 将軍のcmd設計に失敗予測を義務化。q5パターン踏襲で実装品質安定 |

## 2026-03-23

| cmd | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_1353 | ^VIX grid汚染修正+hs sorted比較修正→53/53完全一致 | GATE CLEAR。影丸。AC1:_build_cache_fastで^VIX除外+native日付系列cache追加。AC2:verify_all_portfolios.py L186 sorted比較。AC3:53/53 hs+ret完全一致。L488登録 | ←cmd_1352の2問題(^VIX汚染+hs順序差)を両方解決。numpy快速パス=本番完全一致を達成。GS本番パリティの最終マイルストーン |
| cmd_1352 | 全53体hs+ret独立突合+L0-M_XLU根本原因特定 | GATE CLEAR。影丸。ret52/53、hs43/53(9体順序差ret影響なし)。根本原因=PI-010同一クラス(^VIX grid汚染→lookback日ズレ)。軍師LGTM。GP-047 3連続WA不要 | ←cmd_1351のhs突合曖昧さを解消+L0-M_XLU原因特定。numpy快速パスの信頼性確立(^VIX除外で解決見込み)。decision_candidate: matrix除外+DB直接照会案 |
| cmd_1351 | Step 1補強: 全standard PF numpy快速パスパリティ(65体想定→実際53体) | GATE CLEAR。影丸。52/53 PASS。1 NG: L0-M_XLU 2026-02月(prod=0.095 vs gs=-0.107、符号逆転)。軍師LGTM。WA不要 | ←cmd_1350(4ファミリー代表PASS)を全体に拡大。53体中52体は快速パス=本番一致を証明。1体のみ2026-02月で不一致→将軍判断待ち |
| cmd_1350 | Step 1やり直し: numpy快速パス本番パリティ検証(allow_numpy=True) | GATE CLEAR。才蔵。DM2(179mo)/DM3(190mo)/DM6(191mo)/DM7+(167mo)全完全一致。軍師LGTM。GP-047初戦果(WA不要) | ←cmd_1349でPI-009修正がGS目的を破壊→殿HALT→allow_numpyバイパス方式で再実行。numpy快速パスの本番同一性証明完了。GS探索用パスの正当性確立 |
| cmd_1345 | Phase E1: 加速(ratio) FoF 2体パリティ検証(MomentumAccelerationFilter) | GATE CLEAR。才蔵。激攻171mo/常勝150mo全PASS。WA:yes(summary空+LC形式) | ←Phase D完了に続きE1完了。E2と並列実行 |
| cmd_1346 | Phase E2: 加速(diff) FoF 1体パリティ検証(MomentumAccelerationFilter) | GATE CLEAR。小太郎。鉄壁158mo全PASS。WA:no | ←E1と並列完了。Phase E(加速3体)全PASS。Step 2残: Phase F以降 |
| cmd_1344 | Phase D: 既存変わり身FoF 3体パリティ検証(TrendReversalFilter) | GATE CLEAR。半蔵。常勝144mo/激攻150mo/鉄壁143mo全PASS(初月L485除く)。WA:no | ←Phase A-C完了に続きPhase D(TrendReversalFilter)完了。鉄壁初月のみret不一致(hs=None×非ゼロリターン=初月固有)。Step 2残: Phase E以降 |
| cmd_1342 | Phase B: 既存追い風FoF 3体パリティ検証(MomentumFilter) | GATE CLEAR。3体全月PASS(常勝153mo,激攻150mo,鉄壁156mo)。L485登録。WA:yes(二重配備) | ←Phase A(EqualWeight14体)に続きPhase B(MomentumFilter3体)完了。hs_cross初月FAILは全FoF共通パターン(初期化差異)。Step 2残: Phase C(他selection block) |
| cmd_1341 | dashboard教訓メトリクス直近30cmd列+⚠マーカー | GATE CLEAR。飛猿。WA:binary_checks boolean(GP-040前) | ←dashboard_auto_section.shにPJ別・タスク種別別・モデル別の直近30cmdトレンド列追加。全体値と10pp以上乖離行に⚠マーカー |
| cmd_1338 | GATE autofix統合+verdict/no_lesson_reason自動推定(GP-031+033+034) | GATE CLEAR。AC1:PASS(疾風),AC2:PASS(影丸),AC3:**FAIL**(Fix9 boolバグ)。L294登録 | ←Fix9: YAML `yes`→Python True(bool)→`str(True).upper()='TRUE'`≠`('PASS','YES')`。isinstance(bool)チェック追加要。Fix10正常 |
| cmd_1340 | 偵察教訓全スキップ→偵察固有7教訓のみ注入に変更 | GATE CLEAR。小太郎。WA:no | ←deploy_task.shのrecon/scout/research早期exitをRECON_LESSON_IDS+recon_modeフラグに置換 |
| cmd_1325 | lesson_impact.tsv pending 22,516行バックフィル+照合ロジック修正+verify追加 | GATE CLEAR。小太郎+飛猿。軍師APPROVE。karo_workaround: no | ←cmd_1324でタブバグ修正後も原因2(prefix照合不一致)で97%故障継続。backfillでpending→0、prefix照合でcmd_XXXX_AC1-3形式対応、verify(updated=0→ERROR)で再発検知。第三層学習ループ計測基盤完全復旧 |
| cmd_1324 | lesson_impact.tsvタブ文字エスケープバグ修正+既存データ復旧 | GATE CLEAR。半蔵+軍師APPROVE。L292登録 | ←deploy_task.sh heredoc内\\tが実タブでなくリテラル\tを出力。2026-03-06以降の教訓効果率計測が全壊(84%データ未更新)。sed復旧+再実行で第三層学習ループ計測パイプライン正常化 |
| cmd_1312 | deploy_task.sh report_filename残留値クリア(将軍なぜ6層で特定) | GATE CLEAR。疾風。bats344全PASS。軍師SG0 auto-fix完了、家老WA不要 | ←GP-003未発火の根本原因。前cmdのreport_filenameが冪等性ガードで残留→新cmdで正しいファイル名未生成。鶏と卵問題(自身の報告は旧形式)あり手動解消 |
| cmd_1311 | GP-003正規表現修正(`_report_`→`_report[_.]`) | GATE CLEAR。影丸 | ←pre-write-report-deny.shが`_report.yaml`にマッチしない問題の修正 |
| cmd_1304-1310 | infra各種修正(7cmd) | 全GATE CLEAR。連勝9達成 | ←将軍の深掘りサイクル成果群 |
| cmd_1276 | Step 2 Phase A: 既存EqualWeight FoF 14体パリティ検証 | GATE CLEAR。14/14 PASS(全75ヶ月完全一致)。6忍者並列完了。workaround:hayate報告形式のみ | ←チェックリストPhase A完了。EqualWeight計算パスの正当性証明。Phase B承認待ち。AC1: DB17体とリスト14+3体完全突合 |

## 2026-03-22

| cmd | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_1274 | 汚染シンv2 33体本番DB削除(チェックリストStep 0) | GATE CLEAR。FoF21+standard12=33体DELETE成功。PF124→91。workaround:no。半蔵。連勝39 | ←本番登録前の清掃。FoF先→standard後の順序厳守。L483/L484登録(認証正本=.env) |
| cmd_1273 | ランブックv2本番コード突合+API動作確認+PF枠確認 | GATE CLEAR。全6コード参照一致+PF枠76空き+admin認証OK。疾風 | ←本番登録準備。cosmetic修正1件推奨(admin/ping期待レスポンス記載) |
| cmd_1272 | シン四神L1 12体standard PF登録スクリプト構築+dry-run検証 | GATE CLEAR。pydantic全PASS+CSV二重検証全一致。飛猿 | ←33体登録クリティカルパスのL1部分。PI-003 pipeline_config設定済。LC: momentum_method明示指定推奨 |
| cmd_1271 | FoFパリティバッチ3(7体) | GATE CLEAR。1PASS/6FAIL(init月hs=NULLのみ)。非init月完全一致。小太郎 | ←cmd_1269系列。LC: selection-based FoF初月hs=NULL問題 |
| cmd_1270 | FoFパリティバッチ2(7体) | GATE CLEAR。4PASS/3FAIL(init月hs=Noneのみ)。才蔵 | ←cmd_1269系列。LC: init月hs=Noneで独立検証不可 |
| cmd_1269 | FoFパリティバッチ1(7体) | GATE CLEAR。7/7 PASS。影丸。L482登録 | ←cmd_1251 PoC展開。初回3PASS/4SKIP→将軍裁定:分岐不要→再検証で7/7 PASS。selection-block FoFも本番hs経由で検証成功。DC: 残18体検証方針 |
| cmd_1265 | report_field_set.sh強制PostToolUse WARN hook | GATE CLEAR。半蔵。L282登録(PostToolUse hookはdeny不可) | ←家老自己研鑽GP-003。reports YAML直接書込み検出+WARNING表示 |
| cmd_1268 | CI RED修正(ntfy_ack mock不備+auto_deploy_doneテスト不整合) | GATE CLEAR。workaround:no。飛猿(AC1)+疾風(AC2+AC3)。344テスト全PASS | ←cmd_1263(unpushed commit WARN追加)でninja_monitorに新変数追加→テスト側declare/初期化漏れ+ntfy_listener.shのsource行追加→mock stub漏れ。L280+L281登録 |
| cmd_1264 | inbox_write.sh gate発火100%化(サイレントスキップ→BLOCK) | GATE CLEAR。workaround:yes(report_missing)。影丸。連勝31 | ←家老自己研鑽で発見。gateは存在するがパス解決失敗時サイレントスキップ→忍者の壊れた報告が素通り。3箇所exit 1化。workaround 50%の根本原因修正 |
| cmd_1266 | FoF selection_pipeline動作乖離偵察 | **中止(殿裁定)**。GS FoFは本番と別アプローチで差異は当然。比較方法の前提誤り | ←cmd_1250 FAIL(21/21不一致)起点。殿: FoFはPipelineEngineと別で差異は当然 |
| cmd_1262 | ninja_monitor AUTO-DONE重複書込みバグ修正 | GATE CLEAR。workaround:no。才蔵。連勝30 | ←idle通知嵐(16分20件超)。check_and_update_done_taskがdone済みに毎サイクルwrite→mtime更新→Guard2誤判定→idle重複排除無効化。冪等書込みmtime副作用の再発。軍師S17根因特定 |
| cmd_1261 | 軍師提案パイプライン構造化 | GATE CLEAR。workaround:no。小太郎+飛猿。連勝31 | ←軍師Phase8到達→提案がYAMLコメントに埋もれ死蔵。proposals:構造化フィールド+startup gate表示で自動検出。L274登録 |
| cmd_1260 | deploy_task.sh lessons_useful/binary_checksプリフィル | GATE CLEAR。workaround:yes(commit代行)。L273登録。疾風 | ←軍師S6分析。workaround 44%(8/18件)がFILL_THIS未記入。デフォルト値注入で構造的解決 |
| cmd_1259 | dm-signal.yaml pipeline flow+registration status更新 | GATE CLEAR。workaround:no。L478登録。半蔵 | ←post_mini_parity_flow Step3-5陳腐化。total_pfs 31→33(吸収=GS概念vsDB物理12体)修正 |
| cmd_1258 | dashboard CI status自動反映 | GATE CLEAR。workaround:no。影丸 | ←INS-173303。ninja_monitorにCI状態変化検知追加+dashboard自動更新 |
| cmd_1255 | unit test 44FAIL+338SKIP修正 | GATE CLEAR。344テスト全PASS(FAIL=0,SKIP=0)。才蔵(AC1+AC4)+小太郎(AC2+AC3)。L272登録 | ←CI RED根本対策。archive_completed動的日付化+agent_config.shセットアップ漏れ+gate_metrics fixture修正 |
| cmd_1250 | FoF 21体full recalculate+holding_signalパリティ | GATE CLEAR(verdict=FAIL)。AC1 recalculate PASS。AC2/AC3 FAIL — 21/21体hs不一致(DB 0-1% vs CSV 47-67%)。selection_pipeline動作乖離。L477登録。飛猿 | ←cmd_1249(v2正本更新)後続。selection_blocksが機能していない根本問題発見。次cmdでPI-009準拠のselection_pipeline調査必要 |
| cmd_1252 | ninja_monitor.shパイプライン空チェック追加(idle通知嵐防止) | GATE CLEAR。notify_idle_batch内にpending/new cmd=0ガード条件追加。影丸。workaround:lessons_useful dict形式 | ←パイプライン空時にidle通知が家老を無限wakeup。殿指摘。構造的修正 |
| cmd_1251 | FoF GSパリティPoC(1体独立計算→全期間完全一致) | BLOCKED。signals/monthly_returnsテーブル空。cmd_1250 recalculate中のタイミング問題。再配備予定 | ←L469(GS engine FoF非対応)。standard 65/65達成後のFoFレベル検証。cmd_1250完了後に再実行 |
| cmd_1249 | FoF 21体component+params DB更新(v2正本一致) | GATE CLEAR。21体FoFのcomponent_portfoliosをv2 12体standard PF IDsに更新+selection block paramsをCSV正本値に設定。DB再読込検証21/21一致(不一致0件)。半蔵 | ←cmd_1247偵察でGAP-1(component旧v1)+GAP-2(params全空)発見。standard 12体v2一致(cmd_1245)の後続。33体本番整合の最終ピース |
| cmd_1245 | シン青龍-鉄壁DTB3パリティ修正+65/65達成 | GATE CLEAR。recalculate_fast.py Phase 3.7のDTB3 reindex問題(df_dtb3→df_dtb3_raw)。65/65 standard PF完全パリティ達成。才蔵+小太郎 | ←cmd_1243で露出した残1件。DTB3固有日付vs株式取引日reindexで行数差→rolling(84)参照日ズレ→0.000019差で符号反転。L474+L475登録 |
| cmd_1246 | gate_report_format.shにverdict二値バリデーション追加 | GATE CLEAR。PASS/FAIL以外(CONDITIONAL_PASS等)をgate FAIL化。テスト5件追加。半蔵 | ←cmd_1239/1243でCONDITIONAL_PASS 2件発生→karo workaround。早期フィードバック |
| cmd_1248 | gate_report_format.shバリデーション強化 | GATE CLEAR。lessons_useful(id必須/useful bool型)+binary_checks(各AC list形式)3種追加。テスト6件追加全17PASS。影丸 | ←karo_workarounds形式エラー2件(cmd_1239/1242)の構造的防止 |
| cmd_1247 | 33体本番DB登録前提条件偵察 | GATE CLEAR。**CRITICAL**: FoF 21体component全不一致(MATCH=0/21)+selection params全空。standard 12体はv2一致済。33体は既にDB存在(UPDATE対象)。疾風 | ←v2本番登録準備。DC: FoF更新方針+L0素材30体処理要裁定。cmd_1245(パリティ検証)と並行 |
| cmd_1243 | L0-M_XLU hs不一致根本解決(PI-009最後) | GATE CLEAR。^VIX/DTB3をprice_data_cacheから除外→DB直接照会で本番一致。L0-M_XLU 186/186 PASS。64/65(シン青龍-鉄壁=既存問題露出)。影丸。workaround:verdict形式 | ←cmd_1240後の残1件。stock_trading_mask resampling→pct_change日付ズレ→momentum符号反転。L473登録 |
| cmd_1244 | commit_missing BLOCK化(gate強制) | GATE CLEAR。cmd_complete_gate.shにgit diff検出→BLOCK追加。4パターンテスト全PASS。半蔵 | ←commit漏れ3件(cmd_1218/1228/1232)の構造的防止。Phase 4原則(意志依存→gate強制) |
| cmd_1242 | CI赤修正(shellcheck SC2168+T-012) | GATE CLEAR。local除去+agent_config.shテスト環境対応。root 36/36 PASS。unit 290/333(43件既存FAIL)。疾風。workaround:lessons_useful形式 | ←cmd_1232副作用(shellcheck)+cmd_1136副作用(agent_config導入時テスト未対応)。L270登録 |
| cmd_1241 | startup gateにidle自走トリガー追加 | GATE CLEAR。Gate 10追加。全忍者idle+パイプライン空→自己分析Step 1-5表示。--briefにidle_trigger:ON/OFF。飛猿 | ←Phase 4原則(意志依存=壊れる)。将軍復帰時idle停止の構造的解決 |
| cmd_1240 | PI-009パリティ6件FAIL根本解決 | GATE CLEAR。Group A/C(4件): DTB3計算を本番完全一致化(diff=0)。Group B(2件): experiments.db価格を本番DB同期(diff=5e-11)。64/65 PASS。新1件=holding_signal別種。小太郎 | ←cmd_1238偵察結果+cmd_1233 BLOCK解消。standard PFパリティ実質達成。次=新FAIL 1件(XLU hs不一致)+忍法v2登録 |
| cmd_1239 | シン四神v2 12体本番登録+recalculate+GS突合 | GATE CLEAR。hs 12/12 PASS。ret 9/12 PASS(白虎3体=IEEE754既知L471)。エンジン問題ゼロ。半蔵 | ←Phase 1-2完了+cmd_1125正本。パリティロードマップPhase 4ゴール到達。次=忍法v2(21体)登録 |
| cmd_1238 | Phase 1 FAIL 6件根本原因調査 | GATE CLEAR。4件=filter_init_months(L074)、2件=IEEE754。GS engine修正不要。才蔵 | ←cmd_1233 GATE BLOCK。根本原因判明→BLOCK解除判断材料提供 |
| cmd_1237 | Simple FoF 7体パリティ検証(Phase 2/3) | GATE CLEAR。hs 7/7 PASS、ret 7/7 PASS(max diff 1e-10)。Phase 1 FAIL波及なし。影丸 | ←cmd_1234偵察結果。GS engine FoF非対応→component return平均で独立検証。Phase 3 Nested FoFへ |
| cmd_1236 | ninja_monitorにgate_report_format.sh統合 | GATE CLEAR。done遷移時gate発火+FAIL差し戻し+重複防止。疾風 | ←workaround率76%の根本対策。gate発火タイミング修正(done遷移時)。家老workaround作業→ゼロ化 |
| cmd_1235 | GS側パリティ検証ツール棚卸し | GATE CLEAR。15ファイル25+関数列挙。simulate_strategy_vectorizedはholding_signal不含。飛猿 | ←cmd_1233 REQ_CHANGES(前提崩壊)→事実確認でPhase2/3 cmd設計精度向上 |
| cmd_1234 | 本番FoF/Nested FoF構成マッピング偵察 | GATE CLEAR。PF122(std63+fof59)。Nested FoF22(深度2)。シン四神=standard型。小太郎 | ←Phase2/3計画基礎データ。旧四神=fof型/シン四神=standard型の構造差発見 |
| cmd_1233 | GS engine standard PFパリティ検証(Phase 1/3) | GATE BLOCK。AC2(hs)63/63 PASS。AC3(ret)57/63 PASS 6FAIL(精度)。半蔵 | ←PI-009/PI-007。holding_signalは100%正確。monthly_return 6PFは浮動小数点精度差(ロジックエラーなし) |

## 2026-03-21

| cmd | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_1232 | cmd_quality_log.shにnotes引数追加+BLOCK理由記録 | GATE CLEAR。commit 68d8cb9。karo_workaround: yes(半蔵commit漏れ→疾風再配備)。軍師REQUEST_CHANGES的中 | ←cmd_1227(Gate 9)のBLOCK理由分析可能化。品質計測パイプ強化。LG003パターン8回目 |
| cmd_1231 | 教訓LG010正式登録(lesson_write.sh) | GATE CLEAR(連勝30)。karo_workaround: yes(lessons_useful dict→list)。軍師LGTM | ←deepdive_karo_study発見→教訓基盤に登録。LK010と同パターン |
| cmd_1230 | cmd_save.shにgunshi直近指摘表示追加 | GATE CLEAR。commit 2efcc94(+46行)。karo_workaround: no。軍師LGTM | ←第二層学習ループ接続。将軍がcmd起票時に軍師の直近指摘を確認可能に |
| cmd_1229 | cmd_save.shにq4_depth WARNING段階的導入 | GATE CLEAR。karo_workaround: no。軍師LGTM | ←q4_depth品質チェック基盤。段階的WARNING→将来BLOCK化 |
| cmd_1228 | shogun.md Idle時自己分析手順commit | GATE CLEAR(再配備)。commit a392c2f。karo_workaround: yes(commit漏れ再配備)。軍師LGTM | ←影丸commit漏れ→LG003パターン。軍師draft REQUEST_CHANGES予測的中 |
| cmd_1227 | gate_shogun_startup.sh Gate 9(rework率+workaround表示) | GATE CLEAR。karo_workaround: yes(報告YAML修正)。軍師LGTM | ←将軍起動時にパフォーマンスフィードバック自動表示。自走基盤強化 |
| cmd_1224 | gunshi.md Identity書換(助言者→パートナー)+成功指標impact化+karo_workarounds読込手順 | GATE CLEAR(連勝23)。karo_workaround: no。軍師APPROVE+LGTM | ←殿診断「軍師は本質を誤解」→第二層学習ループ双方向化。cmd_1225(家老側)とセット |
| cmd_1225 | karo.md軍師関係性更新(委任→パートナー)+workaround還流手順追加 | GATE CLEAR(連勝25)。karo_workaround: no。軍師APPROVE+LGTM | ←cmd_1224(軍師側)とセットで第二層学習ループ完成。家老→軍師のworkaround feedbackパイプ構築 |
| cmd_1226 | cmd_save.sh Check 5非ブロッキング化(cmd_1223 AC2違反修正) | GATE CLEAR(連勝24)。karo_workaround: yes(lessons_useful形式修正)。WARN_COUNT加算削除 | ←cmd_1223のAC2違反→1行修正で設計意図通りの非ブロッキング動作に復帰 |
| cmd_1221 | sync_lessons.shにreference_count同期追加 | GATE CLEAR(連勝20)。injection_countと同一パターンでreferenced=yes集計→lessons.yaml同期。infra44件/dm-signal15件ref>0確認。karo_workaround: yes(commit代行) | ←第三層パイプ(reference_count)断絶→SSOT精度向上→教訓取捨選択の判断精度向上 |
| cmd_1220 | dm-signal.yamlシン四神v2陳腐化2件更新 | GATE CLEAR。v2_pattern_count実数値361603+data_sourceパリティ検証済み。karo_workaround: no。軍師FAIL→家老PASSオーバーライド(AC要件にcommitなし) | ←cmd_1200(GS再実行)+cmd_1191/1194(パリティ検証)→知識基盤鮮度維持 |
| cmd_1219 | gate_report_format.sh FAILメッセージに修復ガイダンス追加 | GATE CLEAR。3種(lessons_useful dict/binary_checks string/lesson_candidate string)にFIX例出力。bats 6 PASS。karo_workaround: no | ←cmd_1212(gate検出力強化)→忍者の自己修正加速 |
| cmd_1215 | report_field_set.sh配列インデックス[N]対応 | GATE CLEAR。Pythonフォールバックに正規表現ベースの配列パターン認識追加。karo_workaround 7/9件の根本原因修正。L307登録 | ←karo_workarounds報告YAMLフォーマット問題(7/9件)→裸配列[0]未対応は残課題 |
| cmd_1216 | cmd_save.sh grepコメント行誤検出修正 | GATE CLEAR。grep -v '^\s*#'前段追加。疾風cmd_1214作業中の自己発見 | ←cmd_1214疾風所見→gate精度向上 |
| cmd_1213 | inbox_write.shのgate無音スキップ根絶(fallback検索+WARN) | GATE CLEAR。report_path未設定時のfallback検索+WARNING出力追加。gate実行率100%化の基盤 | ←cmd_1212(gate検出力強化)の前提条件。cmd_1187(BLOCKING化)の完成形 |
| cmd_1212 | gate_report_format.shのbinary_checks string未検出修正 | GATE CLEAR。string型検出+修正ガイダンス付きFAIL出力。家老workaround最頻出パターン構造解消 | ←karo_workarounds cmd_1205/1207(同一クラス7件)→cmd_1213(gate実行保証) |
| cmd_1196 | GS実行時pipeline_config必須化(PI-009構造的保証) | GATE CLEAR。core+10本修正完了。L448: PI-009チェックはsimulate_strategy_vectorized経由のみ有効、各run_077の独自パスは迂回 | ←cmd_1194偵察(3パス判明)→後続cmd(PipelineEngine統合)必要 |
| cmd_1197 | 報告YAML消失の根本原因偵察(infra) | GATE CLEAR。根本原因=deploy_task.sh L2608-2614実行順序バグ(テンプレート生成→preflight→archive即移動)。全環境再現の構造的バグ。L294登録 | ←cmd_1187(消失事象)←cmd_1192(gate側防御済)→後続cmd(修正実装)必要 |
| cmd_1199 | PI-009対応。run_077全体のsimulate_patternをPipelineEngine経由に統合 | GATE CLEAR。v2対象7本PE統合+v2外3本revert。L455(to_timestamp bug)/L456(PE速度77倍)/L457(oikaze md5不一致) | ←cmd_1196(pipeline_config必須化)。影丸kawarimi AC2/AC3(DB接続検証)は別cmd化予定 |

## 2026-03-20

### Chain A: shutsujin HC事故 → 構造改革4件

**起点**: cmd_1139でshutsujin_departure.shのハードコードレイアウト文字列がターミナルサイズ不一致で失敗 → set -e即死 → ペイン変数ゼロ → デーモン連鎖死。殿との対話で「事故を機に構造を根本から直せ」と4件の改革cmdが派生。

**成果サマリー**: HC事故1件から動的レイアウト・教訓同期・将軍ルール・品質管理ユニットの4構造改革を完了。ラルフループの穴を4箇所同時に塞いだ。

| cmd | 意図 | 結果 | 因果 | 報告 |
|-----|------|------|------|------|
| cmd_1141 | shutsujinの動的3列レイアウト構築（HC排除） | 3列動的レイアウト実装完了。settings.yaml+agent_config.sh+shutsujin連携。commit d36945e | ←cmd_1139(HC事故の直接修正) | `queue/reports/hanzo_report_cmd_1141.yaml` `queue/reports/tobisaru_report_cmd_1141.yaml` `queue/reports/saizo_report_cmd_1141.yaml` |
| cmd_1142 | MCP教訓L-ShutsuinHardcodeをlessons.yamlに正式登録 | L265としてinfra lessons.yaml登録完了。忍者の知識基盤に到達 | ←cmd_1139(事故教訓の知識降下) | `queue/reports/hayate_report_cmd_1142.yaml` |
| cmd_1143 | 将軍の殿への質問に推薦先行+WHYを構造的に強制 | shogun.mdに二値チェック2件追加（推薦先行+MCP教訓同期）。commit d941ccd | ←cmd_1139(殿との対話で判明した将軍の行動パターン改善) | — |
| cmd_1144 | 家老+軍師を品質管理ユニット化、全cmd軍師レビュー必須化 | karo.md/gunshi.md/infrastructure.md 3ファイル編集。commit ffd29f0 | ←cmd_1139(殿指示: 家老が軍師を使い倒す体制) | `queue/reports/kagemaru_report_cmd_1144.yaml` |

### Chain B: 報告3層解像度の整備

**起点**: 殿の指摘「どのような意図で何をやってどういう結果になったのかがわからない。コマンドの時系列も見えない」。Chain Aの改革と並行して報告体制自体を改善。

**成果サマリー**: ntfy(低)・dashboard(中)・戦局日誌(高)の3層で殿の時間ゼロ把握を実現する仕組みを構築中。

| cmd | 意図 | 結果 | 因果 | 報告 |
|-----|------|------|------|------|
| cmd_1145 | 報告3層解像度整備（戦局日誌新設+ntfy強化+フロー追加） | GATE CLEAR。senkyoku-log.md新設+CLAUDE.mdフロー追加+ntfy_cmd.sh強化(purpose/streak/軍師verdict)。commit 2729275 | ←cmd_1144(品質ユニット化の次段: 結果の可視化) / ←殿の直接指摘 | `queue/reports/hayate_report_cmd_1145.yaml` `queue/reports/kagemaru_report_cmd_1145.yaml` `queue/reports/hanzo_report_cmd_1145.yaml` `queue/reports/saizo_report_cmd_1145.yaml` |

### Chain C: 3層学習ループ構築 + インフラ強化

**起点**: 殿の学習ループ原則「全作業に学習ループを回せ。計測だけでは品質管理。還流して初めて成長」。忍者・家老・軍師・将軍の全層で学習ループを閉じる。

| cmd | 意図 | 結果 | 因果 | 報告 |
|-----|------|------|------|------|
| cmd_1146 | 軍師に学習ループ構築(GATEフィードバック+accuracy計測) | GATE CLEAR。gunshi.mdにフィードバック処理+レビューログ構造+accuracy計測。karo.mdにreview_feedback通知フロー追加。commit e96457c | ←学習ループ原則(軍師レビュー精度の自己改善) | `queue/reports/kotaro_report_cmd_1146.yaml` `queue/reports/tobisaru_report_cmd_1146.yaml` `queue/reports/saizo_report_cmd_1146.yaml` |
| cmd_1147 | cmd起票の「書く」と「保存」の分離 | GATE CLEAR。cmd_save.sh新設(重複+flock+安全チェック)。shogun.mdに3段階手順記載。 | ←殿の教え「自動化で学習機会を奪うな」 | `queue/reports/kotaro_report_cmd_1147.yaml` `queue/reports/tobisaru_report_cmd_1147.yaml` |
| cmd_1148 | 全スクリプトMECE偵察(A/B/C/D分類) | GATE CLEAR。136本を2名並列で全量分類。A:74 B:34 C:15 D:7。判断代行(C)+自動消火(D)の特定完了 | ←構造可視化(どこに判断代行が隠れているか) | `queue/reports/kagemaru_report_cmd_1148.yaml` `queue/reports/saizo_report_cmd_1148.yaml` |
| cmd_1149 | 家老workaroundログ構築(殿直接指示) | GATE CLEAR。karo_workaround_log.sh新設(flock+4カテゴリ自動分類+累積カウント)。commit 3ed163f | ←cmd_1145のkaro_workaround: yes多発(構造的対策) | `queue/reports/hayate_report_cmd_1149.yaml` `queue/reports/kagemaru_report_cmd_1149.yaml` `queue/reports/hanzo_report_cmd_1149.yaml` |
| cmd_1150 | STALL Ghost Filter(偽陽性排除) | GATE CLEAR。ninja_monitor.shのcheck_stall()にtask_id空チェック追加。commit 6aac8fc | ←STALL誤検知の構造修正 | `queue/reports/saizo_report_cmd_1150.yaml` |
| cmd_1151 | 軍師レビュー並列化(直列→並列方式) | GATE CLEAR。karo.md/karo-operations.md/gunshi.md改訂。並行方式+severity分類+12ファイルcommit(0feeb95) | ←cmd_1144(品質管理ユニット化)の次段: レビューボトルネック解消 | `queue/reports/hanzo_report_cmd_1151.yaml` `queue/reports/kotaro_report_cmd_1151.yaml` `queue/reports/kagemaru_report_cmd_1151.yaml` |
| cmd_1152 | 将軍cmd設計品質計測(cmd_quality_log.sh+計測基盤) | GATE CLEAR。logs/cmd_design_quality.yaml新設+scripts/cmd_quality_log.sh作成。commit 530bb56 | ←3層学習ループPhase1完結: 将軍の設計品質の構造的計測 | — |
| cmd_1153 | Phase2-A 家老→忍者セットループ(workaroundパターン検出→通知) | GATE CLEAR。workaround_pattern_check.sh新設+ninja_monitor統合(10分間隔) | ←cmd_1149(workaroundログ)のデータ活用 | — |
| cmd_1154 | Phase2-B 軍師→忍者還流(REQUEST_CHANGES→教訓変換) | GATE CLEAR。gunshi.mdにlesson_candidate送信手順+karo-operations.md§13にgunshi_lesson_candidate処理フロー | ←cmd_1146(軍師学習ループ)の知見を忍者に降ろす | — |
| cmd_1155 | Phase2-C 家老↔軍師双方向(review_hint+decomposition_feedback) | GATE CLEAR。karo-operations.md§3にreview_hint送信手順+gunshi.mdにdecomposition_feedback手順。連勝106 | ←cmd_1153+cmd_1146完了で依存解消。双方向学習チャネル開通 | — |
| cmd_1156 | ninja_monitor flat YAMLフォールバック+STAGE1-SKIPタイマー(critical) | GATE CLEAR。check_and_update_done_taskにgrep+sedフォールバック。STAGE1-SKIP 900s/1800sタイマー。L270教訓登録 | ←flat YAML(task:ブロックなし)でyaml_field_set FATAL→忍者/clear永久抑制の即効修正 | `queue/reports/hayate_report_cmd_1156.yaml` |
| cmd_1162 | 軍師レビュー主体移管(gunshi.md+karo.md+karo-operations.md+cmd_quality_log.sh) | GATE CLEAR。軍師一次レビュー→家老スタンプ方式確立。半蔵+小太郎完遂 | ←cmd_1144(品質管理ユニット)の実運用開始。家老レビュー負荷→0 | `queue/reports/hanzo_report_cmd_1162.yaml` `queue/reports/kotaro_report_cmd_1162.yaml` |
| cmd_1163 | 段取りパターン標準化(checklist_update/progress.sh+karo.md+ashigaru.md) | GATE CLEAR。飛猿+疾風完遂 | ←10件以上cmdの配備品質向上 | `queue/reports/tobisaru_report_cmd_1163.yaml` `queue/reports/hayate_report_cmd_1163.yaml` |
| cmd_1164 | 軍師教訓ループ閉鎖(lessons_gunshi.yaml+gunshi.md+/clear Recovery) | GATE CLEAR。才蔵完遂 | ←cmd_1146(軍師学習ループ)の教訓保存先を正式構築 | `queue/reports/saizo_report_cmd_1164.yaml` |
| cmd_1165 | 教訓注入率73.1%精査(recon) | GATE CLEAR。impl/review=100%、recon/scout=意図的スキップが分母膨張。detect_task_typeに_recon欠如→unknown55.7%。DC2件将軍上申 | ←ダッシュボード注入率73.1%の実態把握 | `queue/reports/kagemaru_report_cmd_1165.yaml` |
| cmd_1167 | report_field_set.sh→yaml_field_set.sh統合(2系統→1系統) | GATE CLEAR。独自Python書込み除去。awk共通関数主経路化。lessons_useful正常YAML出力確認 | ←cmd_1162/1163のGATE BLOCK根本原因(構造体文字列書込み)の恒久修正 | `queue/reports/hayate_report_cmd_1167.yaml` |
| cmd_1168 | 教訓注入率計測精度修正(recon/scout除外+detect_task_type修正) | GATE CLEAR。半蔵(AC1)+才蔵(AC2+AC3)+疾風(reflux修復)。L276教訓→PI-INFRA-002+ランブック§2反映 | ←cmd_1165 DC2件の実装 | `queue/reports/hanzo_report_cmd_1168.yaml` `queue/reports/saizo_report_cmd_1168.yaml` |
| cmd_1170 | cmd_save.shで将軍3問検証強制(quality_gate BLOCK) | GATE CLEAR。shogun.md手順追記。cmd_save.sh quality_gate検査追加 | ←cmd_1166で3問を飛ばして消火cmd起票した実績への構造対策 | `queue/reports/hanzo_report_cmd_1170.yaml` |
| cmd_1171 | gate/BLOCK消火パターン偵察(21本段取りリスト) | GATE CLEAR。消火1件(gate_auto_respond.sh L115自動委任)。グレー15件(閾値)。段取りパターン実戦テスト100%完了 | ←自動消火禁止原則の実態調査 | `queue/reports/saizo_report_cmd_1171.yaml` `queue/reports/tobisaru_report_cmd_1171.yaml` |
| cmd_1172 | 全142本消火スクリーニング+偵察スコープ検証ルール恒久化 | GATE CLEAR。新規消火0件。グレー22ファイル(デーモン再起動/通知抑制)。shogun.mdにRecon Scope Verification追記 | ←cmd_1171の85%未検証盲点補完 | `queue/reports/hanzo_report_cmd_1172.yaml` `queue/reports/kotaro_report_cmd_1172.yaml` |
| cmd_1174 | 軍師独自判断基準整備(Review Criteria+Report Review全面刷新+5段階思考プロトコル) | GATE CLEAR。旧6観点→独自6観点(前提検証/数値再計算/時系列シミュレーション/事前検死/確信度/NorthStar)。実例3件付記 | ←cmd_1144(品質管理ユニット)の軍師側独自化 | `queue/reports/hayate_report_cmd_1174.yaml` |
| cmd_1175 | gate_auto_respond.sh自動委任削除→ntfy通知のみ | GATE CLEAR。handle_cmd_stateからcmd_delegate.sh forループ削除。学習機会復元 | ←cmd_1171+1172偵察で特定された唯一の消火パターン修正 | `queue/reports/kotaro_report_cmd_1175.yaml` |
| cmd_1178 | lesson_candidate空検証+binary_checks検証をcmd_complete_gate.shに追加 | GATE CLEAR。疾風完遂。binary_checks8項全PASS | ←cmd_1173偵察AC3の未実装項目をgate実装 | `queue/reports/hayate_report_cmd_1178.yaml` |
| cmd_1180 | cmd_complete_gate.shのSTK trim量計測+改善 | GATE CLEAR。才蔵完遂 | ←STK trim gap教訓の実装 | — |
| cmd_1181 | 軍師ドラフトレビュー誤判定防止(git show HEAD検証+証拠提示必須化) | GATE CLEAR。gunshi.md §1前提検証にルール追加 | ←cmd_1178-1180で軍師誤判定3/6件発生→構造対策 | — |
| cmd_1159 | workaroundパターン修正追跡(check.sh拡張+resolve.sh新設) | GATE CLEAR。才蔵完遂。REGRESSION/EFFECTIVE判定。L074参照有効 | ←学習ループ効果計測の穴2閉鎖 | `queue/reports/saizo_report_cmd_1159.yaml` |
| cmd_1179 | gate_dc_duplicate.sh(DC裁定重複チェック)新規作成+cmd_complete_gate.sh統合 | GATE CLEAR。影丸完遂。gitignore未登録で軍師FAIL→再配備→commit修正→CLEAR | ←cmd_1173偵察AC3のgate未実装項目(DC重複チェック) | `queue/reports/kagemaru_report_cmd_1179.yaml` |
| cmd_1182 | shogun.md cmd起票手順に現物確認ステップ追加 | GATE CLEAR。疾風完遂。L285登録 | ←将軍5件連続前提崩壊→起票前現物確認の構造強制 | `queue/reports/hayate_report_cmd_1182.yaml` |
| cmd_1183 | infrastructure.md軍師品質管理+gate強化の索引還流 | GATE CLEAR。影丸完遂。6cmd分索引追記。L286登録(570行>500行制限) | ←今セッション成果のcontext未反映防止 | `queue/reports/kagemaru_report_cmd_1183.yaml` |
| cmd_1184 | report_field_set.sh YAML構造体破壊バグ修正(CRITICAL) | GATE CLEAR。疾風完遂。L46-55のjson.dumps→USE_PYTHON=1。L287登録 | ←多数のlessons_useful BLOCK根本原因。忍者は正しく書くがツールが壊す | `queue/reports/hayate_report_cmd_1184.yaml` |
| cmd_1185 | ninja_monitor /clear判定バグの3層修正(field_get最浅マッチ+TIMEOUT自己無効化+sed精密化) | GATE CLEAR。疾風完遂(d3540ab)。field_get.sh awk最浅インデント+TIMEOUT→maybe_idle直接追加+sed 2sp固定。L288登録 | ←field_get.sh head-1がACのstatus:pendingをtask-levelと誤認→/clear永久スキップ。35+スクリプト利用の基盤修正 | `queue/reports/hayate_report_cmd_1185.yaml` |

## 2026-03-21

| cmd | 意図 | 結果 | 因果 | 報告 |
|-----|------|------|------|------|
| cmd_1187 | gate_report_format.sh WARNING→BLOCKING昇格。忍者の報告品質を自動強制 | GATE CLEAR。影丸完遂(b3cdcfb)。inbox_write.sh type=report_received時FAIL→exit 1。scope外pre-action capture混入(軽微) | ←karo_workarounds 5件連続(報告フォーマット修正)の根本対策。意志依存→自動化×強制 | (報告YAML消失) |
| cmd_1188 | REFLUX WARN教訓3件(L285/L286/L433)のcontext/dm-signal.md索引還流 | GATE CLEAR。才蔵完遂。L285→§22、L286/L433→§28テーブル追記 | ←dashboardのREFLUX WARN解消。知識サイクル末端接続 | `queue/reports/saizo_report_cmd_1188.yaml` |
| cmd_1189 | 古いシンPF33体を本番DBから全削除(v2登録用の枠確保) | GATE CLEAR。疾風完遂。FoF21→Standard12順で全削除。PF総数91、空き109。報告YAML消失→家老代筆(L293) | ←シン四神v2+シン忍法v2本番登録パイプラインの第1段 | `queue/reports/hayate_report_cmd_1189.yaml` |
| cmd_1190 | シン四神v2(10体)+シン忍法v2(FoF21体)=31体を本番DB登録+recalculate | GATE CLEAR。才蔵完遂(02b4c72b)。kasoku系weight欠落500エラー→修正再save成功。PF91→122。L438登録 | ←パイプライン第2段。cmd_1189で枠確保後の登録 | `queue/reports/saizo_report_cmd_1190.yaml` |
| cmd_1191 | パリティ検証(GS vs 本番DB、standard 10体+FoF 21体) | GATE CLEAR。小太郎完遂。Standard 10体PE再シミュ100%一致(1e-4)、FoF 21体内部整合性100%一致(1e-8)。GS CSVはnon-PE生成のため直接1e-12不可(既知)。L439登録。DC: GS CSV再生成要否 | ←パイプライン第3段(最終)。31体の本番DB計算正当性を確認 | `queue/reports/kotaro_report_cmd_1191.yaml` |
| cmd_1192 | cmd_complete_gate.shに報告YAML存在チェック追加 | GATE CLEAR。半蔵完遂(8d357ef)。タスク>=1/報告==0→BLOCK、一部不在→WARNING | ←報告YAML消失でGATE素通りの穴塞ぎ | `queue/reports/hanzo_report_cmd_1192.yaml` |
| cmd_1193 | gate_report_format.shにno_lesson_reason+binary_checks検証追加 | GATE CLEAR。飛猿完遂(5e77f6c) | ←報告フォーマット検証の漏れ項目追加 | `queue/reports/tobisaru_report_cmd_1193.yaml` |
| cmd_1194 | GS-本番パリティ差異の万全偵察(水平3+垂直3=6名)。PI-009発動 | GATE CLEAR。6名全LGTM。コアアルゴリズム等価。差異源=データソース+Signalパス分岐。pipeline_config必須化が最優先修正(全員合意)。実データtop_n=1: signal完全一致、return max_diff 6.15e-07。教訓L440-L446 | ←cmd_1191でGS CSVがnon-PE生成と判明→パリティ差異の根本原因調査 | 6報告: `queue/reports/{hayate,kagemaru,hanzo,saizo,kotaro,tobisaru}_report_cmd_1194.yaml` |
- cmd_1201 GATE CLEAR (17:37): シン四神v2ドキュメント矛盾一掃。12スロット設計とGS結果10体の分離。疾風+飛猿。L462登録
| cmd_1211 | karo_workaround_log.shにカテゴリ別ALERT+分類改善+resolved_by_cmd除外 | GATE CLEAR。半蔵完遂。2件WARN/3件ALERT+ntfy+insight。9件全正分類。bats11テスト全PASS | ←LK008/LK010(消火体質構造対策)の実装。workaround蓄積→自動ALERT→構造cmd起票を強制 | `queue/reports/hanzo_report_cmd_1211.yaml` |
| cmd_1212 | gate_report_format.shにbinary_checks string型検出追加 | GATE CLEAR。影丸完遂(23096ff)。3行追加。karo_workaround:yes(報告YAML消失→再作成) | ←karo_workarounds 7/9件がbinary_checks関連→gateの検出パターン拡大で根絶 | `queue/reports/kagemaru_report_cmd_1212.yaml` |
| cmd_1213 | inbox_write.shにreport_path未設定時fallback検索+WARNING追加 | GATE CLEAR。疾風完遂(bebb181)。gate実行率100%化 | ←gate_report_format.sh未実行問題の根絶 | `queue/reports/hayate_report_cmd_1213.yaml` |
| cmd_1214 | cmd_save.shのquality_gate BLOCKメッセージにテンプレート出力追加 | GATE CLEAR。疾風完遂(72d2760)。+20行。L306登録。karo_workaround:no | ←BLOCK率44%の構造的対策。Phase4原則(意志依存→環境埋込) | `queue/reports/hayate_report_cmd_1214.yaml` |
| cmd_1253 | 0%有用率教訓6件deprecated/限定 | GATE CLEAR。影丸完遂。L016,L024,L103→deprecated。L090,L117,L060→implement限定。workaround:yes(dict→list) | ←軍師効果率分析→不要教訓の注入停止 | `queue/reports/kagemaru_report_cmd_1253.yaml` |
| cmd_1254 | gate-deployレースコンディション修正 | GATE CLEAR。半蔵完遂(093eebb)。gate FAIL→auto_deployスキップ+ninja_done.shにgate検証追加。workaround47%根因対策 | ←軍師S5分析でrace condition発見→全経路BLOCK | `queue/reports/hanzo_report_cmd_1254.yaml` |
| cmd_1256 | lesson_candidate消失+PROPOSAL見落とし防止 | GATE CLEAR。影丸+半蔵完遂。cmd_complete_gate.shにLC WARN+gate_shogun_startup.shにPROPOSAL表示。workaround:yes(dict→list) | ←LC77%消失問題+軍師提案見落とし→gate/hookで自動化×強制 | 2報告 |
| cmd_1251 | FoF GSパリティPoC(1体) | GATE CLEAR。疾風完遂。シン分身-激攻(2comp EqualWeight)全期間完全一致。hs1637/mr75。L476登録 | ←FoF GS独立計算確立→v2移行の信頼基盤 | `queue/reports/hayate_report_cmd_1251.yaml` |
| cmd_1257 | ランブックv1→v2更新(61→33体) | GATE CLEAR。半蔵完遂(3572ab1)。v2設計書§11完全整合。PI参照追加 | ←cmd_1247偵察GAP-3→本番登録前提条件整備 | `queue/reports/hanzo_report_cmd_1257.yaml` |

## 2026-03-23

| cmd | 意図 | 結果 | 因果 | 報告 |
|-----|------|------|------|------|
| cmd_1275 | GS混乱候補スクリプト7本削除(誤用防止) | GATE CLEAR。影丸完遂(74c071bf)。7本削除+正式8本健在+参照27件報告。DC:27件整理要否 | ←殿裁定:正式7忍法+狭義GS以外は削除→Step 2 FoF登録の誤用リスク排除 | `queue/reports/kagemaru_report_cmd_1275.yaml` |
- **07:22 cmd_1321 GATE CLEAR**: deploy_task.sh冪等性ガード8箇所横展開。飛猿完遂。連勝17
- **07:18 cmd_1320再配備**: 影丸STALL(settings.local.jsonパーミッション制限)→半蔵に再配備。target_pathをtest_result_guard.shに修正
- **07:24 3cmd一斉配備**: cmd_1278(hayate GP-032)、cmd_1287(kagemaru GP-012)、cmd_1288(saizo GP-004)
- **2026-03-23 07:45** cmd_1278/1287/1288/1320 4件一括GATE CLEAR。連勝21達成。cmd_1320でSTALL時の空報告テンプレート残存によるGATE BLOCK→手動archive→workaround 1件。cmd_1287は半蔵commit済みへの影丸重複配備。全軍idle、次cmd待ち

- 2026-03-23 13:50 cmd_1336 GATE CLEAR: GP-031+033+034合体。autofix→format check順序race根絶+Fix9(verdict推定)+Fix10(no_lesson_reason fill)。WA: lessons_useful混在parse error
- 2026-03-23 13:50 cmd_1337 GATE CLEAR: dashboard自動更新イベント駆動化(GATE CLEAR時+配備完了時)。WA: binary_checks散文string
- 2026-03-23 13:50 cmd_1338 void: cmd_1336と同一内容(将軍が重複起票)。半蔵停止済み

## 2026-03-24

- 2026-03-24 02:09 cmd_1356 GATE CLEAR: archive_completed.sh flock全8箇所を/tmp/mas-*.lock移行(WSL2 NTFS flock no-op根治)。chronicle欠落11件(cmd_1336-1343,1351-1353)手動復旧。半蔵実施。WA: なし
- 2026-03-24 02:09 cmd_1354 archive完了: PI-010 implication原則ベース化+L488 summary完全版更新。半蔵実施。前セッションでGATE CLEAR済み

- **cmd_1374** (2026-03-24): 四つ目GS serial/batch md5不一致の根本原因特定+修正。batch precomputed_picksのtolerance=1e-12が本番exact比較と不一致(2ULP差)。tolerance=0.0+float_format統一で500パターン4方式全一致。疾風完遂。→cmd_1372(四つ目3体GS)が unblock
- **cmd_1372** (2026-03-24): シン忍法v2 Step 4 Phase G — シン四つ目3体作成(MultiViewMomentumFilter)。4686パターンGS正常終了。常勝(Calmar2.94)、激攻(CAGR72.9%)、鉄壁=常勝同一。半蔵完遂。**Step 4全7Phase完了 — シン忍法v2 21体GS完了**
- **cmd_1378** (2026-03-24): oikaze フルGS再実行(NaN修正済み28116パターン)。新旧チャンピオン同一(差分ゼロ)。NaN修正はoikaze固有でGS結果影響なし。疾風完遂。WA: yes(double_deploy→cmd_1382で構造的根絶予定)
- **cmd_1379** (2026-03-24): NaN→0.0横展開調査(kasoku_diff/bunshin/yotsume/nukimi/kawarimi/kasoku_ratio)。6スクリプト全て影響なし。oikazeのcomposite_momentum.add(fill_value=0.0)パターンが他に不在。影丸+半蔵完遂
- **cmd_1380** (2026-03-24): GP-071 quality_fix_request race condition修正。inbox_write.shにテンプレート状態検出追加(FILL_THIS残存/verdict空→スキップ)。飛猿完遂。WA: no。連勝19(cmd_1363-1380)

### 2026-03-25 将軍自走最適化サイクル
- **意図**: deepdive原則「自動化×強制」に基づく、殿指示による5秒未満スクリプト改良の連続実行
- **成果**: 8スクリプト最適化(Python→awk/grep,git status -uno,archive titleキャッシュ), 3バグ修正(gate9a/9b/loop_health), 1autofix追加(Fix18)
- **定量**: gate_startup 3.8→1.3s(-66%), cmd_save 4.8→1.3s(-73%), dashboard_auto 10.5→3.0s(-71%), agent_config 200→10ms(-95%/13スクリプト波及)。日次~23分節約
- **根因**: WSL2 /mnt/cのPython起動コスト(200-300ms/回)とgit status全ファイルstat(5.7s)が主犯。awk/grepへの置換とキャッシュが定型解
- cmd_1390: GATE CLEAR(05:30)。inbox_write WARN→BLOCK昇格。WA率根因対策。小太郎完遂。+自走改善L296/L297/L298タスク化→全忍者配備
