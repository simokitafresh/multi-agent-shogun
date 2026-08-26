# 将軍 全体状況マップ(やることリスト) — 2026-08-26 13:55 作成 / 08:06 更新(loop tick 10)
# 原則(殿13:52-13:54): シングルタスクを高速に切替える。優先順位なし=全部やる。依存は構造としてだけ記す。一定時間ごと(各inbox処理後・30分毎)に更新。
# artifact: https://claude.ai/code/artifact/5da62854-f81f-4d53-908b-2fe464031f36 (HTML正本 docs/dashboard/shogun-todo-map.html。更新=正本Edit→Artifact再公開 同file_path)
# 記法: [ ] 未 / [~] 走行中(担当) / [x] 済(証跡)。★=速度向上へのつながり1行必須

- [x] T01(疾風 r2 GATE CLEAR 14:56: ledger stale指紋更新。push→CI確認へ=T02: stale_ledger_paths=test_archive_completed) CI RED(ed237d33a, 13:40) の失敗特定→家老へci_fix配備 ★本線GREENでらせん次弾がGREEN上で回る
- [x] T02(22:40 origin=HEAD diverge 0/0。15:10指示→7h30m。真因=まとめpush×手動full走査。増分push 1本ずつで57本を1時間で消化) rev-list 0 2 の未push(家老レーン) ★分岐の芽を毎回摘む
- [x] T03(skill_hint 11+gunshi review 2+kotaro failed 1+将軍1=家老へ集約案内済) 家老inbox未読14の中身確認(将軍発が多ければ統合して減らす) ★家老の直列化を減らす
- [x] T04(軍師再判定: 本質型4弾=−242s/並列型2弾=数えない。レビュー基準更新) 軍師idle(CTX55%)の活用: dm-signal文書更新3件のレビュー/要約担当 ★遊休をなくす
- [x] T05(将軍doc lane 0d60e350b: 4本の境界をorigin/main d87339a4へ。実未反映=core/ops 10・research 11・frontend 101でいずれも反映済/記事のみ。忍者配備はDOC_LANE_ROUTINGで正しくBLOCK=将軍の裁定失念) dm-signal文書更新: core(252 commits)/ops(261)/research(200)/frontend REQUEST(5b4e27eb) → 忍者4名へdoc lane配備YAML ★知識鮮度=次cmdの誤起票を減らす
- [x] T06(check本体はtimeout。本日分は§2026-08-26へ反映済ゆえ境界をorigin/main tipへ更新) infrastructure.md『1745件』ALERTの正体(merge後のmarker解決)→境界更新 ★偽ALERTの消化コスト削減
- [x] T07(14:10公開 label 20260826-1410) artifact(らせん戦況録)更新(10:25以降: 第2セット5弾/統合終端/退行復旧/殿裁定3件) ★殿の状況把握コスト削減
- [~] T08(飛猿 r2: 14/14 PASS済・primary WIPをscope guardが検知→将軍がWIP退避commit 8de4a417a→再試行通知 14:55) converge構造根治(AC3: ours採用でtheirs破棄)を1名へ配備(家老へ指示済み、配備確認) ★退行の再発=最大の手戻り
- [x] T09(TODO 0件) session_alerts_shogun.txt 未処理確認 ★stop hookの往復削減
- [~] T10(疾風 failed 19:48: timing logに完走gate run 0件=材料未生成→次GATE CLEAR後に再配備を家老へ下知 20:04) 第2セット残: cmd_skeleton(影丸走行中)/cmd_complete_gate 200s/scope_commit/run_tests(並列型のみ→本質案なしなら終了) ★らせん本体
- [x] T11(LS登録+shogun.md焼込み d29f6b81c) 殿裁定4件(並列≠本質/0.1%×100億/シングルタスク切替+全体マップ)を将軍教訓+instructions/shogun.mdへ焼込み ★再発防止=同じ指摘を殿に2度させない
- [x] T16(疾風 GATE CLEAR 18:30。以後のDOC_LANE_ALERT偽件数が止まるかを次の投稿で検証) context_freshness_checkの日付基準集計が統合後に偽ALERT(1752件)を出す→marker基準へ(insight登録済・次の空きへ) ★偽ALERT消化コストの削減
- [ ] T12(cmd_4401計装はstdout出力のみで永続ログ無し→次回cmd_publish実行時に将軍がstdoutをlogs/へ保存して分解) ライブpublish 13分の分解(cmd_4401計装の実測回収) ★publish律速の短縮
- [x] T13(半蔵 GATE CLEAR 15:08: stale同一内容は600秒超で更新/fresh同一はreplace抑止) karo_snapshot更新停止insight(登録済)の家老配備確認 ★二次情報の鮮度
- [x] T14(半蔵idle→T05へ、飛猿failed要確認) idle忍者の確認(半蔵/才蔵/小太郎/飛猿)→T05/T08へ充当 ★遊休をなくす
- [x] T15(run419 18:51: 業務値は同一入力2回目で完全収束。md5差=momentum_data内execution_time_ms telemetryで非決定性ではない。殿契約08-16 PASS。記憶DB貫通済) dm-signal fullrecalculation(前復帰点の走行中件)の結果確認(msg_201913) ★前セッションの未回収

- [x] T17(03:45 将軍doc lane: infrastructure.md §2026-08-27 に5点反映、境界06ddbc988、掲示板2件actioned) DOC_LANE_ALERT 2件(blt_123314/blt_101234 infrastructure.md境界)→T02 push後に context_source_commit_set.sh で境界更新しactioned_by記入 ★偽ALERT消化コスト削減
- [x] T18(半蔵 GATE CLEAR 18:31: 関数別実時間の計測器常設=らせん第1手。次=計測結果で分割対象を名指し→T10へ合流) script_size_alert 14件(cmd_complete_gate 14804行/ninja_monitor 11856/deploy_task 11256…)→cmd_4403成果と合流する分割cmd(前復帰点の残弾) ★hook/gate読込時間の短縮
- [x] T19(05:17 家老判定: L1637×2 retireしない(unknown増分0未確認)・L1632 retire適格だが canonical lessons.md に不在=SSOT不整合で見送り、report archive・failed残置0; 影丸 FAIL報告 17:42: AC3未達→家老判断待ち) lesson_deprecation候補3件(L1637×2/L1632)家老判断待ち→家老へ集約案内 ★教訓注入トークン削減
- [x] T20(cfd7b7d3e: gate ARCHIVE_AUTO_HANDLED+archive_completedがhint既読化。ゾンビ16件掃除→家老未読19→1) 家老inbox滞留の真因調査(殿18:03)=完了済cmdのskill_hintゾンビ ★家老の再読コスト16KB×毎nudgeをゼロに
- [~] T21(影丸 acknowledged。19:33に家老Codexのnudge queue停滞を実観測=裏付け) Codex宛nudge配達検証FAILURE 88%(insight登録済)→read遷移ベースの検証+未読N分で再nudge ★家老・忍者の指示受領遅延(2h停滞)の根治
- [~] T22(飛猿 assigned) pre-push PASSキャッシュのキー変更(commit→tested-paths tree hash)+insight auto-commitバッチ化(本日43commit=HEAD churn) ★push 1回あたりの再走を0に
- [~] T23(家老へ下知 20:04) ninja_monitor二重起動(非owner pid 1354798 19:04起動 / owner 2140401 19:48起動)の正規退役 ★snapshot/nudge競合の除去
- [x] T24(20:17 家老復旧: 7/7 bypass・bwrap 0。settings.yaml launch_cmd 4行修正=未commit・殿裁可待ち) Codex sandbox起動でcommitだけFAIL(P2 3件)の真因=settings.yaml per-agent launch_cmdのbypass欠落 ★実装PASSがcommitで捨てられる損失0に
- [x] T25(05:20 GATE CLEAR: review APPROVE、統合tip 77107a355 push; 21:38 家老へ配備下知 msg_213800-C) P1(AC厳格停止8件)の型変更: 基準値をACに固定せず忍者が同一環境でbefore→afterを自己計測、乖離は報告して進む(バッチらせん5条)→配備テンプレ+cmd_save gateへ ★作業PASSがACでFAILになる損失0に
- [x] T26(03:38 cmd_4406 GATE CLEAR 06ddbc988: recon/scout/recon2 は commit/investigation 契約免除+finding必須、bats 8/8; cmd_4406 起票→publish 03:05; 偵察報告FAIL 616件・260報告、commit契約誤適用) P3(偵察の材料なし=FAIL 7件): verdict契約を偵察タスクでは finding付きPASSに ★偵察の再配備往復削減
- [x] T27(01:26 GATE CLEAR t27a hotfix 858d2a82f origin反映済; 21:38 家老へ配備下知 msg_213800-A/B: 影丸T21・飛猿T22のworktree成果commit完遂) 失敗4task(半蔵ci_fix/飛猿T22/影丸T21/疾風T10)のworktree成果をcommitだけ再配備で完遂(家老下知済 msg_201620) ★push律速の半蔵ci_fixを最優先
- [x] T28(e3712b4a9: settings.yaml 忍者launch_cmdモデル固定除去=luna-high継承、idle4名respawn済・小太郎/飛猿は終端後。agent_respawn.shに作業中ガード(BLOCK rc=2)を構造型で埋込・bats 11/11+9/9) 殿裁定20:48-20:54(モデル明示しない/作業中respawn禁止) ★モデル切替の継続+作業成果の破棄0
- [x] K02(家老自立配備 GATE CLEAR 21:23) prepush_gate_gunshi_precheck_timeout(push set 3位368秒の上限対策) ★push harness母数の削減
- [x] T29(22:40 完了: c5c19d73b 88本/214s→…→391db2305 3本/9s、計10単位、最大230s・最小9s。まとめ時=1222s FAIL往復) push方式転換=1commitずつoldest-first ★push律速の本丸
- [x] T30(codex_inbox_priority_guard.sh + .codex/hooks.json + bats 3/3) 殿指摘22:15「inbox無視が構造的真因」→将軍発task_assignedが180秒以上未読なら家老の全tool BLOCK(読めば通る) ★指示不達→方針乖離(本日7h)の再発0
- [~] T31(影丸 完了→1306551ed push済 23:02、239固定撤廃=inventory/ledger集合一致 241/241。CI run 32977736637 実行中→GREEN待ち) CI RED真因=test.yml L150 unit本数239ハードコード(tree/ledger=240)→固定数撤廃+新test timing record ★CI GREEN復帰=らせん次弾がGREEN上で回る
- [x] T32(kotaro lgtm_bundle_guard GATE CLEAR 00:11、CI ccad05fcf GREEN 23:59=本日初GREEN) CI shard1/2 実テストFAIL修正 ★CI GREEN
- [x] T33(2df2ecdee: script_update.sh bashフォールバック+index 100755。drvfsはchmod無効) inbox_watcher毎分死亡の真因=scripts 10本の実行ビット欠落(restore/converge) ★nudge喪失(12:00-00:08 85回再起動)の根治
- [x] T34(inbox_write: ninja_monitor→gunshi review_draft許可+stderr記録) 報告10本UN-GATEDの真因=自動レビュー依頼が送信者制限で毎回BLOCK・stderr不可視 ★報告→レビュー→GATEの自動回転復活
- [x] T35(bc9f4a8c6/474aff0c2: cli_lookup BASH_REMATCH排除+接尾辞自己修復) 半蔵/飛猿 400 luna-high の真因=ninja_monitor trapがBASH_REMATCHを潰し model_name全体をconfig.tomlへ ★忍者停止0
- [x] T36(家老 00:43-00:44 6本を1本ずつpush完了: 3815cc5b7/e0374eaa5/17f43ffd9/bc9f4a8c6/2df2ecdee/c17a92d8e) 根治commitのpush ★根治をorigin/CIへ\n- [x] T37(57b40cf9a: instructions/shogun.md 焼込み+senkyoku-log+todo_map+dashboard HTML初commit、記憶DB session_save_20260827_0035、MEMORY.md索引、feedback_karo_directive_pattern.md) 強くてニューゲーム保存(殿指示00:33) ★/clear後の復帰精度
- [x] T38(03:31 CI GREEN run 32999064580 @8c09923f8=半蔵ci_fix f88e36251+cmd_4405; 02:47 半蔵ci_fix配備成功 wall 199s(負荷除去前374s→175s短縮)・acknowledged; 01:42 858d2a82f run 32987834940=failure: shard4 test_ninja_monitor.bats#3 review_requests=1不一致のみ・家老がci_fixを半蔵へ配備中; 01:12 家老へ1単位下知 msg_011238; 01:27 家老がrerun→858d2a82f run 32987834940 queued。57b40cf9a run=RED: inbox_write delivery検証系 9 test(shard2/4/7/compat)=T27a hotfixの対象領域→858d2a82f結果で判定) origin tip 858d2a82f のCI GREEN証跡: run未生成+queued 2本40分超+c17a92d8e cancelled(insight登録済) ★根治6本のGREEN証跡=らせん次弾の土台
- [x] T39(03:28 cmd_4405 GATE CLEAR 8c09923f8: run_tests.sh 子孫reap契約+fixture root固定、長時間bats 0→0; 02:48 orphan_test_reap.sh --kill(殿実行)で孤児0・stale0・bats0、load 66→19; 02:42 殿kill×3+orphan_test_reap.sh c940c47d5で孤児0件・load 66→25; 01:33 殿kill 4pid完了→新孤児2樹(test_heavy_job_admission singleflight-orphanが内側run_tests.sh unitを生かす自己増殖=真因特定・insight済・cmd起票へ); 01:18 kagemaru failed→idle 家老クローズ済; Gate 10.07 検知を実装・commit済。停止はD006ゆえ殿裁定待ち。発生源7なぜはinsight登録済→cmd化) 孤児bats(test_cmd_complete_gate.bats 137分・親/init・global flock保持・/tmp fixture lock 1359) ★家老commit helperのflock待ち0・/tmp蓄積0
- [ ] T40 insights未処理103件(08:04)の消化(idle時) ★気づきの先送り0
- [x] T41(04:02 GATE CLEAR; 小太郎 karo_hotfix 669afef44: .git/worktrees stale metadata 周期prune+deploy前entry数ログ、695/695 PASS) worktree stale 自動prune ★deploy 397秒→の再発源を構造で断つ
- [x] T42(04:55 CI GREEN run 33005872290 @f690ebdac; 04:33 疾風 ci_fix 完了 5269fa730→HEAD f690ebdac、家老レビュー/GATE/push待ち; 04:17 3run目 9e00859b1=真因確定: test_deploy_task_nocode_commit_contract.bats case9、deploy_task_function_timing_enable が scaffold setup で失敗=669afef44 の entry計測追加の副作用→疾風 ci_fix assigned) CI 06ad396ab run 33001522768 shard2 failure=『tests/unit directory not found』(checkout側の異常・テスト失敗ではない)→669afef44 push の次runで再判定、REDなら家老ci_fix ★GREEN証跡
- [x] T43(04:06 d8ddc2279 commit済・push済; ただし配備0件の真因は別=T44) reflux dirty-guard: queue/insights.yaml が MM(将軍のinsight_write後の auto-commit 失敗)のまま→cmd_reflux の自動配備が毎回 BLOCK=idle忍者6名に仕事が流れない構造。commit で解除→次tickで reflux 配備再開を確認 ★遊休をなくす
- [x] T44(05:38 実配備復活: cmd_reflux_insight_202608270538_hayate DEPLOY_RECEIPT success 25.3s=08-24 16:35以来初; 05:25 GATE CLEAR: 影丸 f956de3c7→5a9f583b9 picker除外拡張+回帰3種、配備再開は監視で確認; 05:05 影丸 in_progress・報告雛形のみ、SKIP継続中(04:47-05:01 同一ID); 04:37 影丸へ karo_hotfix 配備 assigned wall 63.7s; 04:38 家老へ下知) reflux insight 自動配備が 08-24 16:35 以来 0件: picker が INS-20260821-090811134-61a3(reserved/terminal)を毎周期先頭で引き SKIP、次候補へ進まない(ninja_monitor REFLUX-AUTO-SKIP 04:20/04:23)。insights_pending 102 が idle忍者へ流れない真因 ★遊休3日分の根治
- [~] T45(08:04 insights pending 103、07:50/07:57 影丸・半蔵の reflux 配備が REFLUX-AUTO-BLOCK(queue/insights.yaml dirty=daemon の resolved 書込み 08:03:54)→auto-commit 待ち=T43 の構造が毎周期再発; 07:03 5件目 飛猿 06:47→07:00 DONE、pending 104→101、4 CLEAR; 06:36 4件目 才蔵 06:24→06:31 DONE、pending 104→102、1件≈14分・同時1件; 06:06 観測開始) reflux 回転計測: 05:39 疾風→05:55 CLEAR、05:53 影丸→06:02 CLEAR(1件≈14分・同時1件)。insights pending 104 が CLEAR 後も減らない(resolved 352)→ archive 時に resolved へ遷移するか次tickで確認、減らなければ家老へ ★気づき消化の回転速度の可視化
- [x] T46(07:27 CI GREEN run 33018749601 @ed70c88e2=小太郎 ci_fix「owner heartbeat 秒境界レース除去」push済; 07:03 次push d6ab785c5 の run 33016263375=success(75dc761e1 の failure は再現せず)、小太郎 ci_fix 報告済→GATE待ち; 06:38 家老診断→ci_fix cmd_karo_ci_fix_33014653183_owner_heartbeat 配備 64.7s=真因は owner heartbeat テスト; 06:35 下知) CI run 33014653183(75dc761e1 半蔵 reflux 成果) shard compatibility failure → 真因特定→ci_fix or rerun ★GREEN 証跡の維持
- [~] T47(08:05 疾風 in_progress 28分(見積15)・pane Working・worktree で runner 境界を切り分け中、report status=in_progress; 07:39 疾風へ karo_hotfix 配備 assigned; 07:36 insight登録) reflux 配備の空白: 07:00 DONE 後 07:31 に idle 計時が再スタート=6名 idle でも 30-40分の空白。idle 計時起点を task idle 時刻に固定する hotfix 候補(家老レーン) ★気づき消化スループット2倍

- [x] T48(08:00 receipt 現物で16/16確認; 07:56 head -70 パイプで Phase8/9 の receipt が未記録のまま「完了」と報告=型4則(1)再発) /clear復帰(07:54 y)の追体験16Phase+Q6軍師検証(blt_075858 妥当)+origin 0 0(家老 4本 1本ずつ push) ★復帰精度=再開までの空白を最小に
- [ ] T49(08:05 insight INS-080518912) ninja_monitor が実在しない hayate_report_cmd_alias.yaml を REPORT-REVIEW-AUTO-REQUEST-BLOCK(22:54/07:59)=テンプレ内コメントの誤抽出疑い→抽出に実在チェック ★偽BLOCKログの消化コスト0
- [ ] T50(08:04 実測) reflux dirty-guard: daemon の insights.yaml 書込み(resolved 遷移)が毎周期 dirty を作り配備が BLOCK→auto-commit まで空白。書込み側で同一トランザクション commit するか guard を insights.yaml の status 差分のみ許容へ ★配備空白の再発源を構造で断つ
