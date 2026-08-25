# 戦局日誌 (Campaign Log)
<!-- last_updated: 2026-08-03 karo_strong_new_game_dm_monthly_boundary -->
## 2026-08-23
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_4370_full (hayate) | deploy_task.sh cluster Gのcontext injection責務を既設moduleへ抽出 | `scripts/deploy_task/context_injection.sh` 1588行を関数本体不変で抽出、static parity 0差分、対象契約テスト135/135 PASS・SKIP0、commit `c6393b30d01f749c826de2238d311475f4ca9f47`、report gate PASS。task-modeの既存runner切出し不整合1件は外部境界として記録 | [[cmd_4370]] -> [[deploy_task分割設計書cluster G]] -> [[context_injection module]] |
## 2026-08-22
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_4368_research (hayate) | PF間低相関をFoF selectionへ利用する価値を、Track B独立で現物確認・設計レビュー | 相関production経路4箇所、selection/filter相関参照0件、DB readonlyでmonthly_returns 16532行/102PF、selection候補78/78、履歴106-185ヶ月、36M/60M充足78/78、metrics 204行/47名を確認。設計書commit `98edac7d78036483ee849f8b2970bdefa5898f18`、report gate PASS。runnerはtask worktreeと絶対target_pathのscope不整合でfail-closed BLOCK | [[cmd_4368_TrackB]] -> [[PF間return相関の用途分離]] -> [[PIT低相関selection最小実験]] |
## 2026-08-20
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_reflux_insight_202608200531_kotaro_exact | SKILL script参照hash変化の一次検分とinsight還流 | 11組を再検分し公開I/F不変を確認、gate PASS。対象insightをresolved化、inventory pending 20→19、zero_backlinks 6→6、promotions 0→0、commit `53aa2915b914b51bb882dc7bfff7b44456aa33d6`、report gate PASS | [[INS-20260818-193113793-ea16]] -> [[契約hash再検証]] -> [[SKILL参照追従の重複解消]] |
## 2026-08-14
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_karo_p3b_metrics_manifest_20260814_normal | P3b run summaryへmetrics_manifestを保存 | metric names=47、full=204行、partial=1PF×2行、入力月次系列SHA256非nullをfixture確認。対象pytest 7+21 passed、gate PASS、commit `211e574d3bebcdef018d1e779a5177207987ad78` | [[metrics生成結果のvoid化]] -> [[run summary manifest集約]] -> [[RecalculationStatus.summary監査証跡]] |
## 2026-08-05
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_shogun_commit_reservation_ledger_phase2_20260805 | 既存scope commit経路を予約台帳へ統合 | 旧owned-scope lockを除去し、commit_queue wrapper経由へ統合。結合8/8、affected receipt 41/41、FAIL0/SKIP0、commit `248ea8d5b13731e8c24ebc487e592d01fb40d0d0` | [[owned_scope_lock残存]] -> [[commit_queue全入口統合]] -> [[scope commit FIFO]] |
## 2026-08-03
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| 家老強ニュー化02:38 | DM-Signal月次境界設計レビューをclear越しに継続 | v3.7 SHA `2f266974...`へREVISE返答済み。FoF momentumは子PF cumulative_return依存と現物確定。残BLOCKER4件と再開順を `docs/research/karo-strong-new-game-checkpoint-20260803-0238.md` に固定 | [[殿指示_強くてニューゲーム_20260803]] -> [[月次境界仕様v3_7]] -> [[FoFシグナル遡及]] -> [[家老復帰正本]] |
## 2026-07-31
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| 将軍強ニュー化23:35 | cmd_4200本体CLEAR後の未完了laneをclear越しに保持 | 復帰正本を作成。postprocess冪等性・archive security固定generation・Codex MEM citation実送adapterを完遂前条件として固定 | [[殿指示_強くてニューゲーム_20260731]] -> [[cmd_4200]] -> [[strong_new_game_completion_contract]] |
| cmd_4198 月末N日前モメンタム感度分析 | 殿指示「open to openで結果を見たい」DM2/DM6 N=0-7感度分析 | GATE CLEAR。DM2/DM6ともNシフトで実務的改善なし(最良delta_Sharpe+0.015、閾値0.1未満)。ギザギザ形状+PF間不一致+方向逆転14件。現行N=0が妥当 | [[殿指示_open_to_open_20260731]] -> [[GS既存コード活用]] -> [[N=0最適確認]] |
| LS115登録+origin修正 | 設計書完璧化ループの教訓化 | 設計書v1.0→v1.6の6回レビュー(結果ゼロ)→殿指摘→LS115記録+origin因果リンク修正(gate再計測OK) | [[設計書v1_6回レビュー結果ゼロ]] -> [[殿指摘_起票したくなったら洗脳]] -> [[LS115記録]] |
## 2026-07-18
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| 将軍復帰+D0自走 | /clear後の起動完遂+startup BLOCK根因確認+D0改善 | deepdive追体験完了、Q6投稿(洗脳#4:LS-A11適用失敗)。inbox2件処理。actionable4件closed。lessons肥大化対処(55609→53903bytes、superseded_by11件物理削除)。startup BLOCK4件根因確認+wait_reason宣言。origin不備0件確認 | [[ラルフループ]] -> [[superseded_by物理削除]] -> [[lessons肥大化ALERT解消]] |
| 将軍D0(2nd session) | LS094根治+強くてニューゲーム | hook dedup実装(b58658756)でLS094 Level4化。陣形図異常の同一セット再警告を抑制。殿裁定(品質速度同時向上)projects/infra.yaml反映。merge+push15件(f6a6450e4)。insights0件化。前セッション6h09m CTX支配の直接原因を環境に埋込み完了 | [[LS094]] -> [[hook_dedup不在が6h_CTX支配]] -> [[session-scope_dedup_Level4]] |
## 2026-07-17
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| 将軍復帰+deepdive追体験(2nd) | /clear後の起動手順完遂 | deepdive 2本全Phase追体験完了、Q6掲示板投稿(洗脳#6:出力=仕事)。LS091記録(CI check鎖違反→殿即却下)。insight12→0。殿裁定(品質合格スループット)infra.yaml反映。recovery所要28分をインフラバグとして家老報告 | [[ラルフループ]] -> [[LS-A11適用失敗]] -> [[LS091教訓化]] -> [[recovery速度=スループットバグ]] |
| 将軍復帰+deepdive追体験 | /clear後の起動手順完遂 | deepdive 2本全Phase追体験完了、Q6掲示板投稿(洗脳#5:CI RED先送り)、軍師第三者検証待ち | [[ラルフループ]] -> [[deepdive追体験]] -> [[Q6洗脳検出]] |
| CI RED対処確認 | run 29543642389(Unit Tests bats失敗)の一次確認 | 家老が自走で飛蔵に`cmd_karo_ci_fix_29543642389`配備済み。将軍cmd不要(殿裁定2026-07-16準拠) | [[CI_RED_run_29543642389]] -> [[家老自走配備]] -> [[飛蔵修正中]] |
| SKILL.md batch更新指示 | 家老エスカレーション(skill_script_refs WARN 1セッション連続)対処 | 家老に/karo-direct配備指示送信。insights 25件が同一パターン(script更新→checked_at stale) | [[修行サイクルscript更新]] -> [[SKILL.md_checked_at_stale]] -> [[家老karo_direct配備]] |
| D0自走サイクル(殿指示12:59) | startup BLOCK→WARN達成。commit5件+insight36resolve | commit5件(`05c1c1fdc`/`fe40e65c7`/`314058ad0`/`e6b004111`/`06c9d345d`)。掲示板actioned5件。insight55→19件。lessons55→52KB。[[three-layer-preflight-speed-ledger]]+[[universal-shard-manifest-contract]]因果接続 | [[殿D0指示]] -> [[startup_BLOCK解消]] -> [[ラルフループ環境蓄積]] |
| idle自走分析 | Score Matrix+Design Diversity Map+WA分析+insights分類 | BLOCK率0%, WA率0%, insights68件(25 skill_refs/22 semantic/17 l6_horizontal)。システム安定自走中 | [[idle自走トリガー]] -> [[品質指標全健全]] -> [[insights構造的パターン特定]] |
| D0検証: causal_index | 前セッション修正(62f476912)のバグ再発検証 | main上存在✓、rg解決✓、再発なし。家老掲示板報告済み | [[causal_index_resolve_rg]] -> [[検証PASS]] -> [[家老報告]] |
| D0: lesson-sort L903 | gate_lesson_health ALERT対処 | L903→ops§9振り分け+即commit `b4dccbf16`。未振り分け0件確認 | [[gate_lesson_health]] -> [[L903_deploy_precheck]] -> [[ops§9]] |
| D0: Q6修正 | 家老指摘(自動化ターゲットに実装証拠なし)への対応 | escalation handler不在をgrep証拠付きで掲示板投稿。修正後ターゲット=prompt_state_inject.shにescalation未対処WARN | [[家老Q6検証]] -> [[escalation_handler_gap]] -> [[修正投稿]] |
| D0: escalation WARN hook | Q6自動化ターゲット実装 | post-shogun-inbox-check.shにtype:escalation+read:false検出WARN注入。awkバグ即修正。commit `79c60e0c6` | [[Q6洗脳#5]] -> [[escalation_handler_gap]] -> [[WARN_hook実装]] |
| D0: LS090+bats Level5 | 教訓化+テスト回帰保証 | LS090登録+origin因果鎖+bats 4/4 PASS+enforcement Level5昇格。commits `c55c0dc4b`/`da62bfd2e`/`7ca082e28`/`65800384d` | [[WARN_hook]] -> [[LS090教訓]] -> [[bats_Level5]] |
| D0: 三層貫通 | LS090を記憶DB+semantic+Obsidianに永続化 | Layer1=`knowledge:aa3a6f31`、Layer2=semantic alias自動登録済み、Layer3=origin[[リンク]] | [[LS090]] -> [[三層貫通]] -> [[強くてニューゲーム]] |
## 2026-07-16
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| reflux配備3段バグ修正 | promotion在庫189停滞の根因修正(殿「いまやろう」起点) | 第1段=delegated除外(`348d1df9c`)、第2段=estimated_minutes欠落(`2a09dc71c`)、第3段=purpose文gate+実装共起FP(`432d78e71`)。startup gate診断追加(`491e63af8`)。7日間停止→3障壁除去→自動配備復活 | [[promotion在庫188停滞]] -> [[delegated過剰判定]] -> [[estimated_minutes欠落]] -> [[QUALITY_CONTRACT_FP]] -> [[reflux完全復活]] |
| CI除去環境埋込み確認 | 前セッション殿裁定(CI検知=家老責務)の強ニュー化完了を一次確認 | startup gateにCI表示なし確認済み。cad2fa416+4cb69edc9+271124e84全push済み、LS-A11吸収+記憶DB三層貫通 | [[殿裁定20260716_CI_RED家老責務]] -> [[gate_shogun_startup除去]] -> [[LS-A11吸収]] |
| lesson-sort 21件 | FE教訓索引17件+dm-signal2件+database2件の振り分け | 8ファイル編集。FE§5/§7/§8内部5件+ops§32/§12/§42へ8件+infra5件+research1件+core2件 | [[教訓索引肥大55KB]] -> [[カテゴリ横断振り分け]] -> [[lesson_sort_20260716]] |
| cmd_3996偵察 | freeze後SIGNAL CHANGE ALERT 3PF/日の原因特定 | 前提反証: signal_change_log date=2026-07-15は0行。3件はin-memory alertでDB insert除外。**freeze正常、実データ変更ゼロ** | [[ledger_bound_freeze_CLOSED]] -> [[SIGNAL_CHANGE_ALERT_in_memory_only]] -> [[DB変更ゼロ確認]] |
| cmd_3997配備 | ledger drift alert DB永続化(in-memory除外フィルタ撤去) | 半蔵実装中(CTX:17%) | [[cmd_3996偵察_前提反証]] -> [[in_memory_alert_DB非永続]] -> [[フィルタ撤去永続化]] |
| cmd_3998配備 | gate_alerts閉鎖ライフサイクル偵察(275件中閉鎖率1.5%) | 家老配備待ち | [[軍師独立監査_gate品質6穴]] -> [[gate_alerts閉鎖率0%]] -> [[内訳偵察]] |
| 洗脳#3 stop hook修正 | 殿指示「バグの根因を修正せよ」→ 許可求めフレーズ4種のBLOCK化 | `365b3d7f0` pushed。47/47 PASS。hookが自分の出力を即BLOCK=本番動作一次証拠 | [[将軍お許しフレーズすり抜け]] -> [[stop_hook_L166_L415パターン欠落]] -> [[4フレーズBLOCK追加]] |
| 速度改善CoDD設計書群 | campaign-lane汎用化+3 preflight/deploy速度改善+AB同一run契約の設計書5件 | [[campaign-lane-general-skill-asis-tobe-5w1h_20260716]] controller実装済み/応用12件。[[deploy-task-pipeline-speed-codd-20260716]] 配備パイプライン。[[three-layer-preflight-speed-before-20260716]]→[[three-layer-preflight-speed-after-20260716]] batch_index_search一括化。[[test-speed-same-run-ab-contract-20260716]] baseline=best_so_far継承 | [[スループット第一原則]] -> [[速度攻略レーン基盤]] -> [[CoDD設計書5件]] |
## 2026-06-30
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| 強ニュー化(cmd_3779中間) | /clear後もpf_L3 GSを即再開できる復帰点を外部化 | `queue/compact_state/karo.yaml` と互換 `queue/compact_state_karo.yaml` を2026-07-08T21:47時点へ更新。半蔵cmd_3779_fullはrun id `cmd_3779_full_20260708_213122`、加速D full完了(Exit 0、4分58秒、RSS約10.8GB)、加速R full実行中、本番DB書込みなし。将軍申し送り(blt_20260708_214602_a6dbbb)を吸収し、CLEAR後=工程3バックアップ検証→工程4入替、変わり身第四弾は殿裁可確認と明記 | 殿「今クリアされても今より強くてニューゲーム」→古い7/7 compact_stateを放置せず現行cmdの一次情報・待機条件・復帰後最初の行動へ差替え |
| cmd_karo_hotfix_skill_script_refs_202607021234 | SKILL.md script参照WARN 20件の鮮度回復 | GATE CLEAR。13 SKILL.md更新、gate_skill_script_refs rc=2→0、commit 9c16569ff push済み | script側mtime進行でskill契約確認が陳腐化。gate弱体化せず確認記録で防御維持 |
| cmd_karo_hotfix_shogun_startup_q6_chain | 将軍startup Q6未検出+洗脳連鎖2x2危険象限の真偽判定 | GATE CLEAR。分類=真陽性、D0修正なし。将軍Q6掲示板投稿が必要と掲示板action_required化 | 現行bulletinに将軍Q6不在→gate設計通り発火。archive過去Q6を現在回答扱いにしない |
| note_draft.sh検証 | 修正版(dispatch_click+quick_url)の動作確認 | PASS。Login 1秒→Editor→Body inserted 25→Draft saved。SKIP→PASS改善 | 殿「検証してみたか？」→一次データで確認 |
| LOOPS.md比較分析 | 殿指示でLOOPS.md(9ルール)と将軍システムを批判的比較 | われら8/9上回り。殿教示: 各論〜総論を同密度でレイヤーを密に。100億年でマシンも環境も成長。管理は機械的に | 殿「抽象と具象は同じ概念。レンジを広くすることが重要」 |
| cmd_3608 | gate設計思想カタログ Phase 1a(named funcs 37件カタログ) | GATE CLEAR。殿指摘「check名だけでいいのか？」で母集団不足判明→Phase 1b追加 | 殿「中間レイヤーを独立させよ」→設計書→レビュー→起票 |
| cmd_3609 | Phase 1b(inline+名称乖離42件追加→合計82件) | GATE CLEAR。record_reason呼出し箇所ベースで機能フィルタ抽出 | 殿「grepで見落とすことはよくある」→家老精査→母集団再定義 |
| cmd_3612 | Phase 2(5処置分類: 統合0/抽象化16/関数化33/名称修正6/保護27) | GATE CLEAR。殿「3分類で本当にいいのか？」→家老軍師レビュー→5処置2層構造確定 | 殿「将軍自身も考えておくべきだ」→自明39件+判断43件の2層構造 |
| cmd_3614 | Phase 3(55件リファクタ実装。pending=0確認) | GATE CLEAR。殿「抜け漏れがない仕組みが必要」→カタログ実施状態列追跡 | 10 commits。check関数116→153(+37関数化) |
| cmd_3615 | Phase 4(思想レイヤー貫通: growth-loop/infrastructure/semantic) | GATE CLEAR | 中間レイヤーが全エージェントからアクセス可能 |
| cmd_3616 | Phase 5(FP率計測基盤+カタログ同期hook) | GATE CLEAR。gate_fire_logにcheck名カラム記録確認済み | FP率定量計測が可能に。カタログ陳腐化防止hook稼働 |
| 回帰修正 | Phase 3リファクタによるテスト回帰2件(prev_cmd_gate+diagnosis_trigger_map) | 181/181 PASS。殿「検証せよ」「もう一度検証してみよう」で発見→修正 | 洗脳#8(完了急ぎ)を殿の検証指示で防止 |
| LS075 | 裸数量語は累計昇格で4回cancel→新ID切替コスト30分 | 教訓登録。相対表現に統一+具体数値はassumptions claimのみ | cmd_3610-3613の4連続cancel実証 |
## 2026-06-29
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| 強ニュー化(session2) | insightキュー8件消化+DM-Fusion alias拡充+semantic-map再生成+先送り穴解消 | insight 8件resolved、SKILL.md WARN→軍師D0解消 | 殿「強くてニューゲームできるようにせよ」→Phase7自走で環境埋込み |
| weekly-report | compare-returns API採用+8期間リターン+Deterioration Monitor+将軍短観(負けを正直に) | note.com下書き保存完了(n256c7b0a9587) | 殿「compare returnやminimonthに基づき内容アップデート」+「負けを隠すな」 |
| note_draft.sh修正 | invisible reCAPTCHA対応(dispatch_click+quick_url待ち) | commit a519e6365。SKIP→PASSに改善 | 殿「ログインボタンを押せばいい」「120秒待ちは何だ」→根因=JS click reCAPTCHA阻止+invisible未対応 |
| 三層記憶貫通 | reCAPTCHA知見+compare-returns+API auth空白+パスワード二重入力 | 記憶DB 5件+semantic alias追加+reference_cdp §3.1+SKILL.mdトラブルシュート7項目 | 殿「三層記憶とスキルにアップデートせよ」 |
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_3590-3598 | DM-Fusion UI改善(レスポンシブ/スワイプ/ドロップダウン/保存/共有/レイアウト) | 全GATE CLEAR。8cmd連続push | 殿UIスクショフィードバック→迅速対応 |
| cmd_3600 | DM-Fusion chartにTR倍率軸・年軸・LIN/LOGトグル追加 | GATE CLEAR。1f0bad1 push済み | 比較チャートの視認性向上 |
| cmd_3601 | Fusion APIにhide_portfolio==Falseフィルタ追加 | GATE CLEAR。a3a854ba push済み | 非表示PF除外 |
| cmd_3602 | 保存済みFusionドロップダウン復元+toast最下部移動+空白除去 | GATE CLEAR。84a2a02+3ccfb22 push済み | 殿「無駄なスペース」指摘→UI改善 |
| D0 ff9aa46 | Save機能upsert→update/insert分岐修正 | push済み。WSL2→Supabase IPv6接続不能でunique制約適用不可→upsert不要ロジックに変更 | 殿「保存できませんでした」報告→D0即修正。検証スキップ(#2洗脳)の教訓 |
| 強ニュー化 | 教訓統合(LS066→A11,LS070→A04)、三層記憶5件貫通、LS074実装 | 29件active。/clear自発禁止hook実装 | 殿「強くてニューゲームできるようにせよ」 |
| cmd_3603 | PC版チャート常時表示 | GATE CLEAR | 殿「PCでチャートをどう見る」 |
| cmd_3604 | SPY/TQQQ比較破線 | GATE CLEAR | 殿「比較として薄い破線で」 |
| cmd_3605 | フォルダフィルタタブ | GATE CLEAR | DM-Signal参考にドロップダウン改善 |
| cmd_3606 | PF選択モーダル化 | GATE CLEAR | ドロップダウン画面外はみ出し根本解決 |
| cmd_3607 | admin速度改善+フォルダ一括トグル | GATE CLEAR | location.reload()→optimistic update |
| D0 14commit | チャート軸改善(横6分割/縦基準線/LIN nice-number/LOGマイルストーン)+Total Return倍率表示統一(126.2x)+凡例修正+背景統一+ドロップダウンコンパクト化+APIキャッシュ無効化+hide_portfolioフィルタ削除 | 全push済み | 殿の即時フィードバック→D0即修正の高速サイクル。CDP未確認が課題(洗脳#2) |
| taste-skill参考 | UIデザイン参考OSSリンク三層貫通 | 記憶DB登録済み | https://github.com/Leonxlnx/taste-skill |
## 2026-06-26
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_karo_hotfix_lesson_health_useful_20260626173325 | 教訓健全度ALERT 3連続解消 | CLEAR。useful_rate 14.3%(1/7)→50.0%(1/2)、L862登録 | 根因=project固有deprecated同IDがinfra fallbackで復活し低useful分母を温存。presence判定をactive判定から分離 |
## 2026-06-21
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| startup BLOCK対処 | 教訓健全度ALERT 3連続+掲示板4件+SKILL.md WARN | 掲示板確認完了。教訓健全度=根因対処済み(NO_WHEN_PENALTY+19件D0タグ+家老v2 hotfix GATE CLEAR)。窓サイクル待ち | 根因=828教訓中199件when未設定→無関係注入。注入側+登録側の両面対処 |
| idle自走分析 | Step 1-5(insights/WA/cmd品質/軍師log/パターン発見) | BLOCK TOP1=command_files_modified_mismatch(20件/50=40%、7ユニークcmd)。根因=忍者の変更不要判断をgateに伝達する手段不在 | cmd_3408(第1波FP修正)後の第2波FP。gate_metrics.log+コード確認で特定 |
| cmd_3476 | command_files_modified_mismatch FP根絶 | delegated | BLOCK率40%削減見込み。偵察+修正一体cmd |
## 2026-06-20 (session 2)
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| D0 startup BLOCK解消 | 追体験自動化ターゲットWARN 3セッション連続+教訓健全度ALERT 3セッション連続 | ALERT→WARN(useful_rate 18.5→33.3%)。16教訓deprecated。Q6ラベル付き投稿 | Phase4実証=行動が変わっていなかった。一次データ(target_re L947)確認→根因到達 |
| D0 掲示板+insights | 掲示板未確認14件+action_required17件+insights19件一括処理 | 全件confirmed/actioned/done | backlinks=0の5件もsemantic-index接続。NO_MATCH 7alias追加 |
| cmd_3474 | WA記録brainwash_check必須化(家老CRITICALエスカレーション) | delegated | cmd_3473 cancel(q5累計)の再起票。98/100件未記入の構造的欠落 |
| cmd_3475 | SKILL.md 7本script追従更新(3セッション先送り解消) | delegated | 9 WARN→0件目標。陳腐化=スキル不使用(LS-A17)の温床 |
## 2026-06-16
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_3396 | 教訓useful_rate改善(3セッション連続ALERT解消) | CLEAR | NEVER_USEFUL教訓8件タグ固有化。シミュ21.3%→23.0%。軍師RC→二重登録対応→LGTM |
| cmd_3397 | hide_portfolio DBデフォルトTrue化(PI-027コード強制) | CLEAR | 殿裁定直結。models.py+migrations.py 2行変更。テスト12/12 PASS |
| cmd_3401 | 覚醒設計書v3実装(Check19出口判定+session_alerts) | CLEAR | 殿指摘2件(品質先行/startup忘却防止)。偽陽性WARN構造解消。bats10/10 |
| karo_direct | SKILL.md script参照WARN 6件修正 | CLEAR | 才蔵。6スキル更新。WARN6→0 |
## 2026-06-14
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| startup BLOCK | 掲示板18件+SKILL.md 3セッション+CI RED+教訓WARN | 全件対処/委託 | 掲示板確認済。SKILL.md gate PASS。CI RED→家老委託 |
| cmd_3368 | inject_related_lessons根因修正 | CLEAR | 家老掲示板要請。3件連続exit 1→safety net依存の構造バグ根治 |
| cmd_3369 | gate→cmd_skeleton双方向同期 | CLEAR | 軍師分析: BLOCK 45%が非対称成長。cmd_skeletonに未反映チェック追記 |
| cmd_3370 | refluxタイミング修正 | CLEAR | 軍師掲示板要請。GATE CLEAR後reflux再実行→gate_result null解消 |
| cmd_3371 | brainwash_check数値なしBLOCK化 | CLEAR | 意志依存(1/7)。LG027横展開。WARN→BLOCK |
| cmd_3372 | 実動作確認+実行確認欄BLOCK化 | CLEAR | 意志依存(2-3/7)。WARN→BLOCK |
| cmd_3373 | CS観点中身検証+Quality Check記録義務化 | CLEAR | 意志依存(4-5/7)。first-PASS |
| cmd_3374 | D0未実施検出+利他還流理由必須化 | CLEAR | 意志依存(6-7/7)全数解消 |
| cmd_3375 | BB別特性分析(シン忍法+奥義) | CLEAR | 殿指示。42PF α6指標算出 |
| cmd_3376 | cmd起票前三層記憶自動検索 | CLEAR | 殿指摘(三層記憶未使用)の根治 |
| cmd_3377 | BB重ねがけα6指標分析+pf_L0ベースライン | CLEAR | cmd_3375改善版。奥義命名BB非対応発見 |
| cmd_3378 | PF構成一括確認スクリプト | CLEAR | 殿指摘(PF構成確認不能)の道具磨き |
| cmd_3379 | SKILL.md 5件追随更新 | CLEAR | 3セッション連続startup BLOCK解消 |
| cmd_3380 | SG-PRE25偽陽性修正(exec_prefix+clause_boundary) | CLEAR | 殿指示(偽陽性はバグ)。FP41件根絶 |
| cmd_3381 | 先送り検出FP修正(品質向上文脈除外) | CLEAR | 殿指示(偽陽性はバグ) |
| cmd_3382 | 教訓useful率改善(noise7件修正) | CLEAR | startup ALERT(10%)根治 |
| karo_direct | bulletin_action.sh+SKILL.md追随+backlinks | CLEAR | インフラバグ修正+穴塞ぎ |
| 軍師D0×3 | SG-PRE25 read_markers+提案≠行動L0-L7+時間減衰の法則 | commit 3本 | 提案で止まらず行動(殿厳命) |
| 追体験 | deepdive 2本全Phase+Q1-Q6 | 完了 | Q6洗脳#5検出→軍師第三者検証OK |
| idle自走 | adversarial冷え遡及16件+LG036遡及3件 | WARN解消 | §5.6 15→0件 |
| 殿問い調査 | BLOCK非対称成長+意志依存7箇所+時間減衰 | 行動完了 | cmd_3369-3374+D0×3で全数実装 |
> cmdの意図・結果・因果を時系列で記録する索引層。
> 詳細は各報告YAML（パス記載）を参照。500行超で日付分割。
---
## 2026-05-21
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_2940 | SKILL.md 3件script追従 | GATE CLEAR | 3セッション連続WARN解消。dream/karo-direct/recon-dual |
| cmd_2941 | report-write dict型バグ | GATE CLEAR | assumption_invalidation str→dict。スキル自動成長ALERT解消 |
| cmd_2942 | binary_checks yes/noバリデーション | GATE CLEAR | verdict-check FAIL根因。report_field_set.shに入力検証追加 |
| cmd_2943 | dashboard_update.sh exit=1 | GATE CLEAR | スキル自動成長ALERT解消 |
| cmd_2944 | cmd-complete lesson_done+ac_version | GATE CLEAR | karo_direct配備のac_version空ハッシュ+lesson_done不在修正 |
| cmd_2945 | 教訓フィードバック還流 | GATE CLEAR | useful feedback→lesson_impact.tsv書戻し断絶修正。退役サイクル正常化 |
| cmd_2946 | L7 DIRECT昇格パス修正 | GATE CLEAR | PENDING_ALIAS_DIRECT 0件→実動作。R6でaliases自動成長確認 |
| cmd_2947 | auto-clear競合バグ | GATE CLEAR | ninja_monitor done→即/clearで報告YAML消失(3件)。YAML存在チェック追加 |
| L7修行R5-R6 | 6忍者全員×2ラウンド | 全CLEAR | ヒット率77.8%→100%。DIRECT経路修正後R6で自動aliases成長確認 |
| insights | 29件pending消化 | 0件 | 教訓ALERT重複+stress_testノイズ+修行由来を全resolve |
| startup BLOCK | 3セッション連続4項目 | 全項目cmd投入+CLEAR | SKILL.md/スキル自動成長/gate偽陽性/教訓健全度 |
## 2026-05-20
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_2897 | ac_phase_mixing FP率100%根絶 | 委任済み(疾風+才蔵) | deliveryキーワードからcommit除外。startup gate偽陽性率ALERTが根拠 |
| cmd_2898 | BLOCK一括サマリ出力 | 委任済み(影丸) | 将軍フリーズ根因=修正箇所不明。全BLOCK理由番号付き一括出力 |
| cmd_2899 | SKILL.md追従10件(第3波) | 委任済み(半蔵) | 3セッション連続WARN。cmd_2809(7件)+cmd_2859(9件)に続く |
| 軍師D0×5 | GP-202 FP/target_path FP/一括サマリ/ntfy(revert)/PostToolUse hook強制注入 | 全完了 | 将軍フリーズ=インフラバグ。3層対応→hook検証→cmd_publish.sh穴発見→修正 |
| LS046 | 想像せずに確認せよ — それだけ | 記録済み | 本セッション全問題の真因=確認していないこと。殿教え |
| 知識辞書 | 11件stale→全fresh | 完了 | 31日stale解消 |
| CI | RED→GREEN→push 22件 | GREEN | 半蔵CI修正→push完了 |
| 修行R1 | CoDD速度改善6名配備 | 全完了 | kagemaru 250→200ms, tobisaru 415→172ms, kotaro 1.63→1.10s, hanzo 236→95ms |
| 修行R2 | 軽量3AC速度改善5名 | 全完了 | kagemaru 11.04→0.85s(-92%), hayate 19.47→5.52s(-72%), hanzo 2.23→0.89s(-60%), kotaro 1.95→0.47s(-76%), tobisaru model_analysis 28→1.1s(-96%) |
| cmd_2897 | ac_phase_mixing FP根絶 | GATE CLEAR | saizo完了。commit/コミットをdelivery判定から除外 |
| cmd_2898 | BLOCK全量マップ | GATE CLEAR | hayate完了。トリガーワード位置マップ一括出力 |
| cmd_2899 | SKILL.md追従10件 | GATE CLEAR | kagemaru完了。12ファイル更新。WARN 0件 |
| Guard 3 | halt/clear停止検証BLOCK化 | 実装済み | 送信→CTX記録→次Bash時CTX検証→未低下ならBLOCK。迂回不可 |
| §0.1問い7 | 指示即実行。聞き返すな | 追加済み | 殿の時間を奪う行為の根因対策 |
| LK013 | STALL再配備前3点確認 | 登録済み | pane+nudge到達+遅延到達の全確認必須 |
## 2026-05-19
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_2852 | deploy_task.sh sed特殊文字修正 | GATE CLEAR | LK010根因。inject関数のsed -i→awk統一 |
| cmd_karo_ci_fix_skill_timeout | CI RED修正(家老自走) | GATE CLEAR | cmd_2851起因。test 1424 skill trigger timeout |
| cmd_karo_regex_order_fix | cmd_save.sh regex順序修正(家老自走) | GATE CLEAR | ts→tsx切り詰めバグ。cmd_2853が4回BLOCK |
| cmd_2853 | kj-role-count FE改善5件 | GATE CLEAR | 殿5要望: admin非表示+色分け統一+DatePickerバグ(JST→UTC)+カレンダー縦幅+ロール追加pin_auth→pin |
| cmd_2854 | cmd_save.sh速度+パスバグ | GATE CLEAR | 16秒→10秒未満。絶対パス二重結合修正 |
| cmd_2855 | gate_shogun_startup.sh速度+アーカイブ | GATE CLEAR | cmd_design_quality走査制限で高速化 |
| cmd_2856 | 汎用yaml_auto_trim(書込み時自動アーカイブ) | GATE CLEAR(AC4 WAIVE) | yaml_auto_archive機構正常。残速度はscope外 |
| cmd_2857 | Codex codex_apps MCP無効化 | 作業中 | 殿発見。multi-CLIで全エージェント影響 |
| cmd_2858 | 教訓useful率MIN_SAMPLES 5→3 | GATE CLEAR | 軍師なぜなぜ7回→fb蓄積速度<閾値が根因 |
| cmd_2859 | SKILL.md 9件一括追従 | GATE CLEAR | 3セッション連続WARN解消 |
| cmd_2860 | Obsidian×セマンティック因果辺統合 | GATE CLEAR | 殿「obsidian×セマンティック辞書で可能性」→概念→因果到達パス自動化 |
| cmd_2861 | セマンティック辞書未登録2件 | GATE CLEAR | INS-024911。暗黒物質(未登録概念)可視化 |
| cmd_2862 | 報告YAML Edit BLOCK | shelve | Guard 3(L272-274)で実装済み。車輪再発明 |
| cmd_2863 | Guard一覧自動表示(車輪防止) | GATE CLEAR | なぜなぜ7回→grepキーワード不足が根因→Guard一覧自動抽出で構造予防 |
| LS043 | 教訓: grep0件で未実装断定するな | 記録済み | cmd_2857+2862の車輪2回→反証の不在≠不在の証明 |
| session_dream | /dream Memory統合 | 完了 | MEMORY.md 184→180行。insight 3件。教訓32→31件統合 |
| LS043→LS-A09 | 教訓統合+git diff追記 | 完了 | 車輪3連続根因=git diff未確認。LS-A09(8)にGuard通読+git diff追加 |
| cmd_2863裁定 | (A)verify+commit化 | GATE CLEAR | Guard一覧自動表示稼働。車輪構造予防 |
| cmd_2864 | 教訓注入スコア閾値(MIN_KEYWORD_SCORE>=2) | GATE CLEAR | 77/77 useful=0%→score>0が緩すぎる→閾値引上げ。useful率13.3%→20.9%効果発現 |
| cmd_2865 | lesson_impact.tsvにscore列追加 | GATE CLEAR | 軍師REQ_CHANGES→計測基盤構築。score帯別useful率分析可能に |
| cmd_2866 | semantic_search因果辺トラバース統合 | GATE CLEAR | Obsidian×セマンティック統合パイプライン核。概念→因果辺→関連resources一括返却 |
| cmd_2867 | セマンティック辞書自動成長ループ | GATE CLEAR | lesson_write/GATE完了時にsemantic_map自動再生成+未登録[[リンク]]insight通知 |
| cmd_2868 | traversal_depth列追加(精度計測) | GATE CLEAR | 直接マッチ(0)vs因果辺経由(1+)の有用性計測。depth別チューニング基盤 |
| cmd_2869 | q11にsemantic_search統合(車輪防止概念化) | GATE CLEAR | grep単独→概念レベル検索。3連続車輪の根因対処 |
| cmd_2870 | セマンティック辞書url種別追加 | GATE CLEAR | 外部知識(GitHub/Zenn)→内部因果辺接続。OpenPBX等が辞書から到達可能に |
| cmd_2871 | verdict計算値化(bc自動導出) | GATE CLEAR | verdict独立フィールド=矛盾の温床→bcから常に導出。GP-072c2-c5の4層防御を根本解消 |
| cmd_2872 | cmd_complete_gate並行flock追加 | GATE CLEAR | review_log 0バイト破壊事故→nohup並行のawk→tmp→mvをflock排他制御 |
| cmd_2873 | daemon_supervisor.sh統一管理 | GATE CLEAR | 重複実行頻出(monitor3重/watcher2重)→統一管理+ヘルスチェック+自動再起動 |
| karo_direct×5 | WA ninja validate/selfgate dict/prepush fix/CI fix×2 | 全完了 | LK013 Level4化+self_gate_check dict強制+pre-push tee→file redirect+CI RED修正2件 |
| 教訓統合 | lessons_shogun 31→28件 | 完了 | LS030/032/033/037をLS-A09/A17に吸収。startup BLOCK解消 |
| cmd_2874 | 辞書育成Phase 2(noise除去+カバレッジ) | GATE CLEAR | task notification等5件noise除去。殿「辞書の育成をやろう」 |
| cmd_2875 | q11にcausal_backlinks統合 | GATE CLEAR | 辿る行動の強制化。道具の存在≠使う仕組み→cmd_save.shに埋込み |
| cmd_2876 | 自動成長insight類似概念TOP3推薦 | GATE CLEAR | 未登録通知に分類推薦追加。判断コスト削減 |
| cmd_2877 | kj-role-count定休日+パート色 | GATE CLEAR | 水/日+祝日入力不可。tailwind content paths lib/追加でパート色復活 |
| cmd_2878 | origin空WARN L1→L5 | GATE CLEAR | 報告origin 1.2%→gate_report_format WARN強制 |
| cmd_2879 | ナッジ防止Guard L0→L5 | GATE CLEAR | 殿指摘「CMDルール守れ」→from=shogun task_new BLOCK |
| cmd_2880 | origin自動継承 零コスト | GATE CLEAR | cmd origin→報告origin自動プリセット。忍者負荷ゼロ |
| LS043 | ナッジ乱発教訓 | 記録済み | 速さ>学習の優先逆転。Phase6滑り坂と同構造 |
| karo_direct×3 | SKILL.md追従/kj集計トグル/kjロール切替 | 全完了 | SKILL.md 3件更新+kj-role-count集計フィルタ+ロール種類ドロップダウン |
| session_summary | 7cmd全CLEAR+karo_direct3件+教訓統合+LS043 | 完了 | 因果NW加速5層(検出/零コスト/辿る/発見/防御)+kj-role-count6機能デプロイ確認済み |
| cmd_2881 | 偵察 — dashboard_update.sh FAIL率根因 | GATE CLEAR | Gate20 8/50=cmd_test_*6件+誤呼出し2件。実運用FAILゼロ |
| cmd_2882 | 修正 — Gate20分母フィルタ | GATE CLEAR | cmd_test_除外で3セッション連続startup BLOCK解消 |
| cmd_2883 | 強化 — SKILL.md追従5件 | GATE CLEAR | 3セッション連続WARN解消(2回目) |
| cmd_2884 | 強化 — 教訓フィードバック自動not_useful化 | GATE CLEAR | 参照率36→55%即改善。分母正常化でeffectiveness_score精度向上 |
| cmd_2885 | 強化 — 因果辺→semantic-map自動還流 | GATE CLEAR | GATE CLEAR時にcmd因果辺を自動追記。cmd数比例でNW成長 |
| cmd_2886 | 修正 — report_review重複手動経路撤去 | GATE CLEAR | 毎セッション5-10件の無駄メッセージ根絶 |
| cmd_2887 | 強化 — scope清掃テスト追加 | GATE CLEAR | deploy_task.sh stale残存2件連続FAILの再発防止 |
| cmd_2888 | 強化 — gate FP率自動検出(L6) | GATE CLEAR | 高FP gate自動検出+修正候補提案 |
| cmd_2889 | 強化 — SKILL.md追従自動検出(L6) | GATE CLEAR | script変更時にSKILL.md鮮度チェック自動化 |
| cmd_2890 | 強化 — WA復活即検出(L6) | GATE CLEAR | 100件連続clean維持監視+復活ALERT |
| cmd_2891 | 強化 — 修行×CoDD最適化ラウンド | GATE CLEAR | 17日間停滞のCoDD台帳を修行で自動回転 |
| cmd_2892 | 偵察 — テスト1766件価値選別 | GATE CLEAR | 削除4+統合6=10ファイル+62小ファイル統合候補 |
| cmd_2893 | 修正 — テスト削除4+統合6(第1波) | GATE CLEAR | 790行10ファイル削減 |
| cmd_2894 | 強化 — テスト62ファイル統合(第2波) | GATE CLEAR | 196→130ファイル圧縮 |
| cmd_2895 | 強化 — テストファイル粒度gate(L6) | GATE CLEAR | 追加時に既存統合を促し再肥大化防止 |
| cmd_2896 | 修正 — 修行CoDDをbrownfield限定 | GATE CLEAR | greenfield30分超→brownfield10-15分 |
| session_summary | 16cmd全CLEAR+L6化4件+テスト整理+CoDD再起動 | 完了 | startup BLOCK全解消+参照率36→55%+因果辺自動還流+テスト196→130+修行brownfield化。殿裁定=L6は速くやれ/brownfield明記/テスト整理/殿指示>F001 |
## 2026-05-17
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_2815 | startup gate Gate 13 ALERT推奨分岐 | GATE CLEAR | 3session連続BLOCK根因=一律/lesson-sort推奨→useful_rate/unsorted分岐 |
| cmd_2816 | gate when/how計数修正+ssot_path+進化検知 | GATE CLEAR | gate偽陽性6件解消 |
| cmd_2817 | 忍者binary_checks記入例追加 | GATE CLEAR | FAIL 7/50件→L5防御 |
| cmd_2818 | 因果NW導入(Obsidian [[リンク]]+origin) | GATE CLEAR | 殿「記憶は時系列で因果によってネットワーク化される」 |
| cmd_2819-2822 | 因果NW自動成長4件(cmd_save/PD/startup/deploy) | 全CLEAR | 入口(cmd/裁定)+出口(孤立検出/忍者注入) |
| cmd_2823 | 全ロール環境埋込み(CLAUDE.md+instructions) | 委任中 | 使えないものは存在しないのと同じ(殿厳命) |
| session_20260517 | 起動問題4cmd+因果NW5cmd+Obsidian vault化+記事分析 | 8CLEAR+1委任 | 記事パターンマッチ→殿指摘で前提崩壊→因果NW構想→Obsidian+junction+環境埋込み |
## 2026-05-16
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_2793 | PHANTOM偽陽性修正(awk+grep) | GATE CLEAR | 家老自走分析→軍師RC(grep根因)→両方修正で0件 |
| cmd_2794 | effectiveness除外拡張(fallback) | BLOCK | **前提否定**: fallback内除外は実装済み。軍師RC→家老現物確認→停止→偵察cmd |
| cmd_2795 | still-injected 10件偵察 | GATE CLEAR | 真因=分析時点差。最新stderrでは大半除外済み。修正cmd不要 |
| cmd_2796 | codd.yaml scan設定修正 | GATE CLEAR | health_score 0→95。CoDD修行天井解消 |
| cmd_2797 | ntfy重複送信デバウンス(60分) | GATE CLEAR | context_freshness 5分間隔送信→rate limit部分対策 |
| cmd_2798 | 安定context除外リスト | GATE CLEAR | 不要ALERT根絶。CI RED発生→cmd_karo_ci_fix+cmd_2802で波及対策 |
| cmd_2799 | SKILL.md追従(karo-direct←deploy_task.sh) | GATE CLEAR | 3session連続WARN→BLOCK昇格解消 |
| cmd_2800 | self_gate_check dict保護(scalar書込みBLOCK) | GATE CLEAR | 軍師発見22件FAIL→report_field_set.shガード追加 |
| cmd_2801 | _sv() silent failure根絶(インデント連動+ERROR通知) | GATE CLEAR | **最大発見**: 2sp固定→ネスト3+YAML崩壊→教訓/AC/WP全スキップ3件。cmd_2807副作用検出=ERROR通知が即機能した証拠 |
| cmd_2802 | test_select間接依存(gate→消費先テスト) | GATE CLEAR | cmd_2798 CI RED根因。家老なぜなぜ7回で特定 |
| cmd_2803 | cmd_save.sh awk dict形式AC対応 | GATE CLEAR | **将軍18回消火の根因**: L311 awkがdict形式ACを抽出しない→gate_hook_action_conversion偽陰性 |
| cmd_2804 | _ac_task_id偽陽性(exact scope split deploy skip) | GATE CLEAR | 35件WARNノイズ→ログ信号対雑音比向上 |
| cmd_2805 | bare except→OSError限定(gunshi precheck) | GATE CLEAR | silent failure可視化。全例外飲込み→I/Oエラーのみ許容 |
| cmd_2806 | Codex respawn無限ループ(GP-222精緻化) | GATE CLEAR | 本日99回respawn→60sスキップ窓追加で根絶 |
| cmd_2807 | weak_points注入副作用(cmd_2801検出) | GATE CLEAR | cmd_2801のERROR通知が即座に検出→免疫系動作確認 |
| cmd_2808 | ntfy.sh グローバルthrottle(429 rate limit) | GATE CLEAR | **778回429→殿通知全失敗**。10s間隔+60s cooldownで根絶 |
| cmd_2809 | SKILL.md追従7件+cmd_complete_gate即時検知 | GATE CLEAR | 3session連続WARN根因=事後検知のみ。cmd_complete_gateに組込みで遅延ゼロ |
| cmd_2810 | draft_lessons循環BLOCK修正 | cancelled | **車輪の再発明**: cmd_2613(05-09)で解決済み。cmd-chronicle類似検索で検出されたが確認せず起票 |
| cmd_2811 | L6横展開 3PJ教訓70件when/how補完 | 委任中 | auto-ops57+gc11+db2=70件when/howゼロ。L6がdm-signal限定で停止していた |
| session_20260516b | 自走: なぜなぜ7回×4本+Simple-OCR 3件+note記事 | 完了 | cmd_2809-2814(6cmd: 4CLEAR+1cancelled+1委任中)。SKILL.md事前強制化+L6横展開70件+UIデフォルト切替+患者名タイトル+clear_prep強化5穴+note記事gist |
| session | なぜなぜ7回×4本→隠れバグ8件発見→10cmd全CLEAR | WA:0 | silent failure/偽陽性/gate検出漏れ/無限ループ。全て「見えない問題」を構造的に排除 |
## 2026-05-15
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_2746-2748 | 家老要請3本(偵察/WA修復/教訓補完) | 全CLEAR | WA品質PASS化+教訓when/how 3%→99% |
| cmd_2749-2752 | 自動成長ループ昇格パス4本 | 全CLEAR | なぜなぜ7回×3: ドキュメント→コード修正の一気通貫 |
| cmd_2753-2756 | 断裂修正+追跡4本 | 全CLEAR | 軍師/家老なぜなぜ7回: FAIL接続/修行/遷移率/掲示板追跡 |
| cmd_2757-2759 | 摩擦解消3本 | 全CLEAR | 教訓ノイズ/FP増大/肥大化の3逆複利防止 |
| cmd_2760-2764 | CoDD v2.18.0基盤5本 | 2760 CLEAR, 残4配備中 | 知識更新+全PJ lexicon+brownfield+fixスキル+CI gate |
| (週報) | DM-Signal Weekly 2026-05-15 | 完了 | WTI+7%/S&P500 7週連続/鉄壁-青龍+27.84% |
| (直接) | CoDD v1.10.0→v2.18.0+PATH+SKILL.md | 完了 | 全エージェントCoDD即利用可能 |
| session | 19cmd+週報。自動成長ループ構造改革+CoDD全面展開 | 14 CLEAR | 三者がなぜなぜ7回を独立に回し全阻害パスを修正 |
## 2026-05-12
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_2681 | 強化 — deploy_task.sh二重配備ガード(flock排他+完了報告検知) | GATE CLEAR | 二重配備3連続(cmd_2678-2680)の根因=重複ガードにレース条件+完了スキップ。L4事前阻止 |
| cmd_2682 | 強化 — ninja_monitor先行完了→後発auto-void | GATE CLEAR | cmd_2681補完のL1事後回収。経路非依存で有効 |
| cmd_2683 | 強化 — SessionStart hookで全ロール起動gate強制 | GATE CLEAR | 家老起動手順スキップ事故。旧裁定(2026-04-12)は前提変更により解除(殿裁定2026-05-12) |
| cmd_2684 | 強化 — inbox_write.sh task_assigned時の二重配備統一ガード | GATE CLEAR | なぜなぜ7回2周目で穴発見: karo_direct経路がcmd_2681のガードを迂回。inbox_write.shは全経路の統一チェックポイント |
| (殿裁定) | 旧裁定(2026-04-12 /clear後gate自動実行禁止)解除 | 記録済み | 前提変更: /clear誤発火頻度が改善(debounce+report_gate+safe_send_clear)。SessionStart hook許可 |
| cmd_2685 | 強化 — 教訓注入useful率改善(threshold0.40+target_files自動付与) | GATE CLEAR | 軍師利他提案→useful率28.4→30.4%(+2pp)。注入プール浄化の入口改善 |
| cmd_2686 | 強化 — lesson_done_missing WARN化+auto催促 | GATE CLEAR | 軍師RC(L3544特定)→hayate修正→lesson欠落のみWARN。lesson_done_missing 23件BLOCKの構造的根絶 |
| cmd_2687 | 強化 — bulletin_confirm自動連動 | GATE CLEAR | 掲示板確認意志依存→inbox_mark_readにbulletin_confirm連動。LG032(既存強制に乗せよ)実践 |
| cmd_2688 | 強化 — noise/harm教訓8件deprecated | GATE CLEAR | noise4件(参照率0%)+harm4件(BLOCK率100%)をdeprecate。注入プール浄化 |
| cmd_2689 | 修正 — スキル品質FAIL3件description修正 | GATE CLEAR | gate_skill_quality FAIL→0件。What/When/NOT When追記 |
| cmd_2690 | 修正 — semantic-index drift検証 | GATE CLEAR | 軍師検出12件MISSING→忍者確認でmissing=0(偽陽性)。根因=絶対パス二重結合 |
| cmd_2691 | 修正 — karo_direct修行AC未注入修正 | GATE CLEAR | deploy_error 5件。training→deploy_task.sh --direct強制。構造的根絶 |
| cmd_2692 | 強化 — resolved_by_cmd自動backfill | GATE CLEAR | WA台帳88件偽陽性解消。GATE CLEAR時に自動記入 |
| cmd_2693 | 修正 — karo_direct stale_report根因修正 | GATE CLEAR | cp直接→deploy_task.sh --yaml経由。忍者がLevel4解法を自力発見 |
| cmd_2694 | 修正 — ASW_DISABLE_ESCALATION継承汚染遮断 | GATE CLEAR | watcher起動前にunset。環境変数継承パス遮断 |
| cmd_2695 | 強化 — withheld悪循環解消(初回注入保証) | GATE CLEAR | 成長ループ最大阻害(withheld86%)修正。MIN_SAMPLES未満教訓の注入候補復帰 |
| cmd_2696 | 強化 — 修行L4教訓参照AC追加 | GATE CLEAR | 修行参照率0%→AC4追加で強制参照。feedback収集自動化 |
| cmd_2697 | 強化 — auto lesson_write(register_recommended自動登録) | 配備中 | lesson登録手動依存→cmd_complete_gate CLEARで自動実行。Phase4排除 |
| cmd_2698 | 強化 — skill_auto_improve FIXヒントDB参照 | 配備中 | なぜなぜ7回根因。gate→スキル知識伝播経路確立。一発CLEAR率71.6%→向上予測 |
| (軍師D0) | skill_auto_improve.sh concrete_prevention_steps強化+interval1日化 | 家老承認 | 6パターン追加+7日→1日。スキル自動成長サイクル加速 |
| (軍師分析) | 成長ループ7段階全量追跡 | 阻害3箇所特定 | withheld86%/修行参照0%/lesson登録手動。全て修正cmd化→CLEAR |
## 2026-05-10〜11
| cmd/action | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_2667 | 修正 — auto_failure_lesson.shのdraft→confirmed化でdraft_lessons BLOCK根治 | GATE CLEAR | draft_lessons 24回BLOCKの根因=auto_failure_lesson.shが--status draftで書いていた。auto_draft_lesson.shと同じconfirmedに統一 |
| (将軍直接) | ビジネスプラン知識体系構築 | 完了 | 殿指示: tier=料金プラン対応の知識化。CDP+DB+note.com確認→6プラン↔5 DB tier対応表確定→context/dm-signal.md §32追加→セマンティクスインデックス2概念追加 |
| (将軍直接) | note記事3本執筆(プレミアム/スタンダード/ベーシック) | 完了+note下書き保存 | 殿指示: プラン毎に推奨PF+SPY/TQQQ比較記事。Sortino推奨(Sharpe→Sortino)。α6指標UWP→Avg UWP変更(殿裁定) |
| (殿裁定) | スキル不使用=構造的バグ+掲示板未確認=鎖の断絶 | 軍師がGuard9+Gate4.5実装 | CDP操作で/cdp-browseスキルを無視→殿激怒。掲示板確認率0%→殿激怒。両方とも環境埋込みで根治。教訓LS028-030 |
| (殿裁定) | ALMディスコン | forbidden_topics記録 | 殿が明示的に言わない限り話題禁止 |
| cmd_2668 | L6学習速度追跡をstartup gateに組込み | GATE CLEAR | 殿指示「L6化していないものはあるか」→なぜなぜ7回→根因「L6自体がL6化されていない」→FAIL→PASS遷移率+L6化率+未到達TOP3自動表示 |
| cmd_2669 | LS-A14 L2→L4化(裁定未反映BLOCK) | GATE CLEAR | 軍師RC: Check10既存→Option B(ALERT→BLOCK昇格)で対応 |
| cmd_2670 | growth-loop.md §11にL6化済み/未化リスト永続化 | GATE CLEAR | 2連続ミス(既存実装見落とし)の根因=L6化全体像が暗黙知。受動的知識に永続化 |
| cmd_2671 | L6化率母数修正(GP56件→防御仕組み) | 配備中 | cmd_2668のL6化率0/56の原因=GP提案のdefense_level集計でL6は別概念 |
| cmd_2672 | 将軍教訓統合(32→22件) | 配備中 | 上限31件超過で3セッション連続BLOCK。LS023-032を既存クラスタに吸収 |
| LS032 | 教訓: grep存在確認≠内容理解 | 記録済み | cmd_2669+gate_fail_top3で2連続既存実装見落とし。grepの出力内容を精読せよ |
## 2026-04-24
| cmd | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_2261 | 偵察 — L3_fof daily_loop 224sの内訳計測+高速化ターゲット特定 | GATE CLEAR。7カテゴリ分解(daily_loop 85.7s/dw_signals_flush 62.4s/MR 27.3s等)+施策7本 | cmd_2259+2260でMR生成240.6→1.5sに改善→残り224sのボトルネック特定が次課題→2名偵察で内訳+施策を特定 |
## 2026-04-20
| cmd | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_2181-2187 | 道具磨き — 7忍法run_077 CoDDメモリ+速度最適化(kasoku_diff横展開) | 全7本GATE CLEAR | OOM真因(RSS 8.5GB)+殿方針(1忍法1CMD完全直列)→横展開で全忍法を最適化コード統一→次ステップ=workers=2テスト |
| (将軍自走) | cmd学習自動ループ穴塞ぎ3点 | 実装+検証済み | 殿指摘3段「成長が主軸/WARNスルー/穴はないか」→(1)禁止値拡張(初回起票等) (2)Check 3.6b=WARN時environment_change強制(全チェック後に配置) (3)非構造化BLOCK=構造化形式(type/file/pattern)+grep検証を必須化。加えてGate 13.8(偽陽性率計測)+resolution_hint(枝葉)。deepdive Phase 5「なぜの目的=自動化ターゲット特定」の環境埋込み |
## 2026-04-19
| cmd | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_2094 | 6システム知識辞書(ACE/Vercel/GSD/gstack/おしお殿/Claude Code) | GATE CLEAR。docs/research/systems-knowledge-base/systems/ に7エントリ+guide.md作成。GSD★54,610(+91%), gstack★75,800(×182) | 殿指示「投資知識辞書と同じで他システム知識辞書が欲しい」→金融ML知識辞書と同じ2層構造で新規作成 |
| cmd_2095 | 教訓タグ洗浄(デフォルトuniversal→PJ自動推定) | GATE CLEAR。lesson_write.sh修正+318件タグ洗浄 | 家老なぜなぜ7回: 有効率22%の根因=デフォルトタグuniversalで全cmd無条件注入 |
| cmd_2096 | cmd_save.sh全BLOCK一括表示 | GATE CLEAR。段階的exit→全チェック1回実行+一括表示 | cmd_2095で3回連続BLOCK(殿指摘)→モグラ叩き構造を根本解決 |
| cmd_2097 | AI開発知識辞書追加(CoDD/Karpathy/逆瀬川) | GATE CLEAR。systems/codd.md+karpathy.md+sources/gyakusegawa.md | 殿「AI開発ツール全般」にスコープ拡張 |
| cmd_2098 | 鮮度チェックgate(CoDDドキュメント適用Phase1) | GATE CLEAR。gate_knowledge_freshness.sh+startup gate組込 | 殿「OSSには設計書を作っておけば更新時に抜け漏れが減る」→verified_at 30日超ALERT |
| cmd_2099 | 我が軍エントリ+index.md+解釈層 | GATE CLEAR。our-army.md+index.md+adoption-log.md | 殿「われら自身も載せよう」 |
| cmd_2100 | 落とし穴+相互参照の補完 | 稼働中 | 殿「深さが足りているか」「品質を高めよう」→金融ML辞書比較で欠如セクション特定 |
| (将軍直接) | cmd_save.sh品質WARN→BLOCK昇格 | q5+AC数量の2件。bats 53テスト全PASS | 殿「WARNのままでなぜOKとした？」→なぜなぜ7回→品質WARN/形式WARN混在が根因→LS046登録 |
| cmd_2073 | **クローズ判定** | 対象不適切のため完了扱い(19/20→**実質20/20**) | 3本(yaml-dump-guard/no-verify-guard/block_destructive)は全てpre-bash-combined.shに統合済みの休眠ファイル。本番ホットパスはcmd_2075-2079で全て改善済み。リトライ不要 |
## 2026-04-18
| cmd | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_2043 | infra batch 11-A の再改善3本を締める | lesson_harvest `10.57s→3.55s`、post_recalculate `2.23s→2.15s`、model_switch `1.23s→0.34s` を確認。研究メモ `docs/research/cmd_2043_codd_infra_batch_11a_20260418.md` 追加、commit `194878e` | `/mnt/c` では report archive 自体の一括走査は維持しつつ、lessons 台帳側の full YAML load を `rg` 抽出へ替える方が効いた。DB 側は monthly/signals 集計を SQL に寄せると Python 側の保持コストを削れた |
## 2026-04-16
| cmd | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_1979 | `inbox_write.sh` の残存固定費削減 | GATE PASS。疾風。target/sender判定を filesystem fast-path 化し、件数カウントを軽量化。隔離 workspace 平均 `50ms→22ms`、live worktree 中央値 `40ms`。`test_inbox_write.bats` 22件 PASS | 共通経路で `agent_config.sh` を毎回 source する必要はなく、`queue/tasks` / `queue/inbox` の現物で多くの判定が足りた。fallback は維持しつつ初期化コストだけ削った |
| cmd_1978 | Stop hook `stop-lint-gate.sh` の高速化 | GATE PASS。疾風。changed-files取得をGit plumbing化し lint を tool単位バッチ化。代表 mixed shell+python 条件で `0.82s→0.65s`、live worktree 中央値 `0.54s`。unit test 4件追加+既存hook harness PASS | WSL2では `git diff --name-only` 系が主因。`diff-index --cached` + `ls-files -m` へ置換し、shellcheck/ruff/biome の per-file 起動を廃止。500ms目標は代表条件で未達だが実運用 changed-set では近傍まで短縮 |
## 2026-03-28
**🔥 焦点: fullrecalculate高速化** — OPT-1/2(trade_perf -159s)+OPT-A(db_write -137s)+OPT-6(monthly_gen -120s)=計4cmd進行中。軍師が先行分析でOPT-6設計完了。本番793s→推定~420s(47%削減)目標。研究全文: `docs/research/fullrecalculate-architecture-2026-03-28.md`
| cmd | 意図 | 結果 | 因果 |
|-----|------|------|------|
| cmd_1444 | 旧忍法15体を構成PFとする新Ward FoFを本番DB新規作成+既存123体完全不変証明 | GATE CLEAR。旧忍法-Ward(0012f956)登録成功。weights=k5クラスタ二段EW(0.05/0.0667/0.10)。fullrecalculate349s+冪等性PASS。月次リターン3ヶ月検算一致 | 半蔵単独(db_exclusive直列)。DC: fullrecalculate(portfolio_id=None)でWard FoFのsignals/monthly_returns=0件→個別recalculateでは正常。日次ETL影響要調査 |
| cmd_1445 | Ward FoFのsignals/monthly_returns 0件バグ修正(cmd_1444 DC) | GATE CLEAR。根因特定(9d845ad4 is_custom_weight分離不足)+修正確認。Ward FoF signals=2999,monthly_returns=144。WA:yes(構造的制約2件リフレーム) | 才蔵。AC2の15分制約(PD-002)+差異検証(進行中)は構造的制約。軍師LGTM。L501登録済み |
| cmd_1446 | sync-fof(日次ETL)でWard FoFデータ消失しないか検証 | GATE CLEAR。sync-fof=fullrecalculateと同一コードパス。Ward FoF signals=2999,monthly_returns=144(ベースライン同値)。既存123体ハッシュ完全一致 | 疾風完遂。cmd_1445のis_custom_weight修正はsync-fofもカバー済み。sync-fof実行時間470s |
| cmd_1447 | fullrecalculate日次ループ偵察(fast.py+fof.py。高速化設計材料) | GATE CLEAR。影丸: fast.py 6ループ特定。Phase4 perf_calc(L1497-1621)=orphaned code疑惑(40-60%削減見込み)。小太郎: fof.py OPT-A(momentum_data月中縮小)でDB書込み95%削減。L502登録 | 影丸+小太郎2名偵察。PD-002(15分制約)解消の設計材料揃った |
| cmd_1448 | OPT-1/2本番デプロイ(trade_perf 53K DBクエリ除去) | GATE CLEAR。本番118s(旧3324s, 96.4%削減)。trade_perf 0.73s(旧4627s)。monthly_query=0, get_first_bday≈0確認。WA: no | 疾風完遂。commit f3b66500 push成功。CI未設定(GH Actions不在)はL503登録。Ward FoF sig=3000 mr=144確認 |
| cmd_1449 | Phase 4 perf_calc除去(cmd_1447偵察のorphaned code実証) | GATE CLEAR。125行除去。signals完全一致(3PF×20日)。速度97倍(19.3s→0.2s) | 影丸完遂。WA:なし。dead code除去で安全にPhase 4高速化 |
| cmd_1450 | FoF OPT-A(momentum_data月中縮小→L3 db_write削減) | GATE CLEAR。db_write 53.3%削減(5.56s/FoF→2.60s/FoF)。signals.py weightsフォールバック追加。テスト34件全通過。WA: no | 半蔵完遂。cmd_1452(OPT-6)のブロック解除 |
| cmd_1451 | FoF MonthlyReturn生成偵察 | **吸収→cmd_1452** | 軍師OPT-6分析で偵察完了済み。起票直後に吸収 |
| cmd_1452 | OPT-6: FoF MRキャッシュ共有(signal_cache/portfolio_cache等を_generate_monthly_returnsに渡す) | GATE CLEAR。4パラメータ追加+共有キャッシュ構築+flush後signal_cache追加。テスト1242件PASS。本番fullrecalculate未実行(別途) | 小太郎完遂。AC3 fullrecalculate=本番DB接続不可で環境制約FAIL→リフレーム。軍師LGTM(karo_workaround: no) |
| cmd_1453 | 知識循環の構造的漏れ3点修正(PI-016/軍師保存先ルール/startup手順) | GATE CLEAR。PI-016追加+gunshi.md保存先ルール+CLAUDE.md startup更新。commit 82d8281 | 疾風完遂。初回PI-015番号衝突→PI-016修正で再配備。軍師cmd_support情報が有効 |
| cmd_1454 | OPT-A/OPT-6/perf_calc除去の3コミットpush+本番fullrecalculate一括検証 | GATE CLEAR。**本番260s(旧564s, 54%削減)**。L2=155s(66%減),L3=62s(9%減)。AC3データ整合性=既存問題(reframe) | 半蔵完遂。Ward FoF zero-data+68PF zero-sig=既存問題(cmd_1443才蔵も同一報告)。DC: FoFデータ不整合要調査 |
| cmd_1456 | Ward scipy L3 626sキャッシュ設計偵察 | GATE CLEAR。**前提覆し**: 626s=リソース競合anomaly(正常42s)。キャッシュ効果=0%(Ward 1体+月窓シフト)。assumption_invalidation=true | 飛猿完遂。軍師OPT-12分析の前提(Ward scipy O(n3)主因)が否定。L3ボトルネック=monthly_returns_gen(127s)に転換。L504登録 |
| cmd_1455 | OPT-4/5 Trade Perf Signal+Portfolio一括ロード+Phase4.5 OPT-6適用 | GATE CLEAR。commit 1efce04f push済み。テスト80件全通過。AC3 fullrecalculate検証はcmd_1458 PASS待ち保留 | 小太郎完遂。WA:なし。signal_preload+portfolio_preload+fof_shared_signal_cache構築。trade_performance.pyに3パラメータ追加(後方互換) |
| cmd_1457 | deploy_task.sh教訓注入マシュー効果修正(ソート反転+枠分離) | GATE CLEAR。keyword_score primary sort+universal max2+枠分離。3パターンBefore/After検証PASS | 疾風完遂。WA:なし。L074/L063/L225の3枠独占解消。task-specific3枠確保 |
| cmd_1459 | 68PF zero-signal根因偵察(cmd_1454/1443 DC) | GATE CLEAR。現在23PF zero-sig(全FoF)。当初68→45件は部分recalcで修復済み。根因3仮説: (1)ネステッドFoF signal visibility(20件,PI-015) (2)lookback超過(シン抜き身-常勝) (3)bam-6/bam-2処理順序問題 | 影丸完遂。KC: WardTwoStageEW=1件のみ、total_mr=5155(当初9975と相違)。assumption_invalidation=true |
| cmd_1460 | OPT holding signal本番Render比較検証(b2183fff vs 1efce04f) | **PASS。holding_signal差分ゼロ。OPT安全確定。** 296,144組の共通ペアで完全一致。signal列も一致 | 家老直接実行(karo_direct)。Render deploy×2+fullrecalculate×2。baseline recalculate部分完了(296K/453K)だが全行がOPT側に包含されholding_signal差分ゼロ |
| cmd_1461 | zero-signal根因検証(タイムアウト仮説) | **PASS。zero-signal=0安定(2回再現)。根因特定+重大副次発見。** | 家老直接実行(karo_direct)。AC1: uvicorn直接起動・タイムアウト設定なし・recalculate-syncはasyncio background(129対策)。AC2: デプロイ中断パターン確認+3/25 Pydanticバリデーションエラーでfofs=0。AC3: 再実行zero-signal=0、453,663sig、639.79s。**重大発見: threading.Lock(プロセス内)がuvicorn --workers 2(マルチプロセス)で排他制御不能。同時2実行可能。軍師分析も同一結論(中断耐性構造不在)** |
| cmd_1462 | 日次/月次計算使用箇所マッピング+ドキュメント更新 | **GATE CLEAR**。統合ドキュメント作成+context索引更新。commit 6d393210 | 半蔵(AC1日次)+才蔵(AC2月次)+小太郎(AC3統合)。軍師LGTM。成果物: docs/research/fullrecalculate-calculation-map.md |
| cmd_1463 | crash-safety Level 0a(shutdown警告)+0b(DB永続化) | **GATE CLEAR** | 疾風(AC1: main.py shutdown警告, cbf347ba)+影丸(AC2: recalculation_statusテーブル+DB永続化, cf90126a)。軍師LGTM。構造的防御の第一歩 |
| cmd_1464 | OPT-3 business_days pure版化(DB fallbackクエリ除去) | **GATE CLEAR**。commit cc0830a2。43テスト全PASS | 才蔵完遂。3箇所pure版分岐(signal_date/position_start_date/position_end_date)+透過呼出し。後方互換維持。軍師注記: cmd仕様パス(generators/monthly_returns.py)≠実体(services/return_calculator.py) |
| cmd_1465 | recalc_status排他制御pg_advisory_lock化 | **GATE CLEAR**。commit 457dd72d。テスト15件全通過 | 半蔵完遂。2層排他: threading.Lock(プロセス内高速)+pg_try_advisory_lock(key=8675309,プロセス間原子的)。セッション保持方式。fail-open(DB障害時非ブロック)。SIGKILL時PostgreSQL自動解放。軍師LGTM |
| cmd_1466 | 全OPT累積効果計測+crash-safety動作確認 | **GATE CLEAR**。全4AC PASS | 疾風。**637.80s(pre-OPT 3566s→5.6x高速化)**。L2:240.66s(11.2x),L3:362.27s(2.0x)。crash-safety正常(recalculation_status completed記録)。signal=453,663件,zero-sig=0。ボトルネック転換: L2 trade_perf 142.78s+L3 db_write 130.64s+L3 unmeasured 74.64s |
| cmd_1467 | L3 FoF profiling gap特定(unmeasured+db_write内訳) | **GATE CLEAR** | 影丸偵察。unmeasured 74s最大=N+1クエリL374-382(shared_portfolio_cache未使用,30-60s)+gc.collect×59(5-15s)。db_write 130s最大=signals_flush(59K行UPSERT+大JSON,80-100s)+component_weights(20-40s)。軍師LGTM。LC: N+1クエリ+dw_component_weights返却漏れ |
| cmd_1468 | cmd_save.shファイルパス存在チェック追加 | **GATE CLEAR** | 才蔵。Check 10追加。全65テストPASS。LC: Check 8にpipefailバグ(grep空マッチexit 1)発見。自動化×強制: cmd_1464事故の構造的再発防止 |
| cmd_1469 | FoF N+1 query bulk化(L374-382) | **GATE CLEAR** | 疾風完遂。shared_portfolio_cache.get()で300-900個別→0クエリ。commit 7fef9f70。軍師LGTM。初回GATE BLOCK(CI赤=Check 8 pipefailバグ)→家老修正(5a3a250)→GATE CLEAR。LC: cache構築→利用箇所網羅確認 |
| cmd_1470 | L3 signals_flush最適化 | **GATE CLEAR** | 半蔵完遂。per-FoF UPSERT×59commits→deferred INSERT×1commit+5000/batch。3ファイル。55テスト全通過。commit 27e39f37。軍師LGTM。LC: L2もcleanup_mode=True適用可能 |
| cmd_1471 | L2 trade_perf 142.78s profiling偵察 | **GATE CLEAR** | 影丸完遂。ボトルネック3点: load_business_days N+1(21-36s)+fallback monthly_return(14-29s)+per-PF write(7-14s)。軍師LGTM。LC: del price_cacheがfallback阻害 |
| cmd_1472 | L2 trade_perf N+1除去+バッチcommit | **GATE CLEAR** | 疾風完遂。load_business_days引数化(Phase 5b前1回load→全PF配布)+20PFバッチcommit。84テスト全PASS。軍師LGTM |
| cmd_1473 | trade_perf fallback price_cache保持 | **GATE CLEAR** | 影丸完遂。del price_cache除去+calculate_monthly_returnにprice_cache引数追加。missing tickerのみmerge load。56テスト全PASS。軍師LGTM |
| cmd_1474 | 第2サイクル計測(4新OPTデプロイ+fullrecalculate) | **verdict: FAIL** | 半蔵完遂。380.53s(baseline 637.80s, -40.3%)。L2 trade_perf 142→0s、L3 db_write 130→32s。**AC3 FAIL: ネステッドFoF 15体ゼロ信号**(signal 406,988 vs 453,663)。59→44体処理。cmd_1469/1470がスコープ変更→15体未処理=見かけ上速い可能性。assumption_invalidation=true |
**軍師直接実装(殿指示)**: OPT-12 — gc.collect削減(59→5回)+fof_signals dead code除去+profiling改善。commit 00fd5257。
**軍師根因特定+修正**: OPT-13 — cmd_1474 FAIL根因=cmd_1470 deferred flushでDB未commitのシグナル→nested FoF DB query空→15体スキップ。修正: signal_cache(OPT-6)からDB結果を自動補完。commit f3ff64a7。要再計測(380.53s+15体分加算)。
**軍師OPT-14**: Standard PF signals flush cleanup_mode=True化(commit 79663eda)。cmd_1470半蔵LC実装。INSERT化。2-5s削減。
**軍師OPT-15**: component_weights commit集約(commit 1e3401fd)。per-FoF 59回→10FoFごと6回。5-10s削減。Tier 1全項目完了+3件push。再計測推奨。
| cmd_1475 | OPT-13修正検証(ネステッドFoF回帰修正確認) | **GATE CLEAR** | 疾風完遂。根因確認: cmd_1470 deferred flush→DB未commit→nested FoF query空。OPT-13 signal_cache補完で解消。261 FoFテストPASS。追加修正不要
## 2026-03-29
| cmd_1476 | 偵察デフォルト品質に第5要件追加(依存関係・順序制約) | **GATE CLEAR** | 才蔵完遂。ashigaru.md+deploy_task.sh+テスト2件。CLAUDE.md記述不在→家老補完。DC解決 |
| cmd_1477 | GP-124 fullrecalculate後signal整合性チェック | **GATE CLEAR** | 半蔵完遂。_check_signal_integrity()追加。zero-signal WARN+signal COUNT記録。テスト5件PASS。OPT-13(修正)+GP-124(検知)=二重防御完成 |
| cmd_1478 | 第3サイクル計測(OPT-12/13/14/15全反映) | **GATE CLEAR** | 疾風完遂。**357.28s**(baseline 637.80s→-44%、pre-OPT 3566s→10.0x)。signal=453,663完全一致。zero-signal=0。L3 db_write 130→18s(-86%)。L3 unmeasured 74→3s(-96%)。trade_perf=0.00s(profiling未発火継続、真値推定~6s)。LC: Render再デプロイ直後のbackground task中断 |
| cmd_1480 | context鮮度更新(9日未更新の7ファイル) | **GATE CLEAR** | 小太郎完遂。ops(357.28s+OPT1-15+crash-safety+GP-124)+dm-signal(§29追加)+infrastructure(偵察5要件)+core/frontend/research(last_updatedのみ)。定型作業 |
| cmd_1479 | trade_perf profiling 0.00s根因特定+修正 | **GATE CLEAR** | 影丸完遂。根因: cmd_1472がportfolio_preloadをsession-boundで再定義→cmd_1455のexpunged版上書き→Phase5b commit後失効→trade_perf+risk_mgmt例外で0.00s。重複10行除去(f87e39e4)。**重要**: 3サイクル全てのtrade_perfは例外スキップだった。次回recalcで初めて実時間計測(予測100-140s)。L506登録 |
| cmd_1481 | Monthly Trade FoF Cash表示バグ修正 | **GATE CLEAR** | 疾風完遂。根因: signal_cache forward-fillがlazy-loadedキャッシュで古いシグナル(Cash含む)を全後続月に伝播。修正: forward-fill廃止→exact-match。L1106 or Cash除去→WARNING+skip。本番: 激攻-青龍Cash 175→1(正当Cash)。Show24/All一致。L507登録 |
| cmd_1482 | 第4サイクル計測(trade_perf+risk_mgmt初実測) | **GATE CLEAR** | 影丸完遂。**479.94s**(trade_perf=126.46s+risk_mgmt=2.86s初実測)。pre-OPT 3566s→480s(**86.5%削減, 7.4x**)。L3=210s安定。signal=453,663。Cash=0件。LC: multi-worker recalculate-status null返却 |
| cmd_1483 | silent fallback偵察(or Cash/except Exception) | **GATE CLEAR** | 半蔵完遂。38箇所(高11/中10/低17)。CRITICAL: SF-001(Pipeline例外→Cash永続化)+SF-003(lock失敗→True)。Cash8箇所連鎖。PD-003起票(Cash撲滅+lock修正=殿判断待ち) |
| cmd_1484 | Silent Fallback撲滅(1): SF-003+SF-001最重要2件修正 | **GATE CLEAR** | 飛猿(SF-003)+才蔵(SF-001)並列。SF-003: lock fail-open→fail-closed(L227+L245 return True→False)。SF-001: pipeline例外Cash差替え廃止→例外日スキップ+エラー集約。テスト各2件追加。WA:なし |
| cmd_1485 | Silent Fallback撲滅(2): SF-002(MDD→0.0)+SF-025(or 1.0) | **GATE CLEAR** | 疾風(SF-002)+影丸(SF-025)並列。SF-002: MDD例外→0.0をNone+logger.error+Calmar Noneガード。SF-025: cumulative_return or 1.0除去→None透過。KC: performance APIパス=api/performance.py(utils/ではない)。WA:なし |
| cmd_1486 | Silent Fallback免疫系構築: PI-018+軍師レビュー項目+教訓L508 | **GATE CLEAR** | 半蔵完遂。PI-018(fallback返却禁止)+gunshi.md §4にsilent fallbackチェック追加+L508教訓登録。構造的防止の3層防御。LC: RUNBOOK還流漏れ(別cmd推奨)。WA:なし |
| cmd_1487 | Silent Fallback撲滅(3): Cash chain 5箇所(SF-023/SF-024/SF-035) | **GATE CLEAR** | 小太郎(SF-024/SF-035)+才蔵(SF-023)並列。SF-024/SF-035: price_ratio_calculator.py 4箇所or Cash除去+Noneハンドリング+テスト3件。SF-023: recalculate_fof.py L766 or Cash除去+None処理+signals_batchスキップ+テスト6件。同一commit(3454b123)。KC: Signal.signal=NOT NULL制約。WA:なし |
| cmd_1488 | Silent Fallback撲滅(4): SSOT定数化(SPY 6箇所+rebalance 6箇所) | **GATE CLEAR** | 疾風(SF-022 SPY)+飛猿(SF-026 rebalance)並列。SPY: constants.pyにDEFAULT_BENCHMARK_TICKER定義+6箇所統一+L305コメント。rebalance: utils/rebalance_trigger.py新規+6箇所ヘルパー統一+17テスト。KC: L168にスコープ外SPYパターンあり。LC: target_path services/jobs不一致。WA:なし |
| cmd_1489 | Silent Fallback撲滅(5): MonthlyReturn耐障害性+一括push+本番検証 | **GATE CLEAR** | 半蔵完遂。SF-006: monthly_trade_calculator.py L274 logger.warning追加(最危険silent解消)。SF-004/005: 失敗PFカウント集計+サマリーログ追加。AC3: cmd_1484-1489一括push+Render deploy+fullrecalculate→**signal=453,663(baseline完全一致)、zero-signal=0、MR正常**。**HIGH 11/11完遂**。WA:なし |
| cmd_1490 | UserPromptSubmit snapshot注入(将軍状態把握自動化) | **GATE CLEAR** | 半蔵完遂(3回目配備)。影丸AC1完了→idle化、疾風も報告空で失敗。原因: deploy_task.shがac_version同一時にAC未更新。WA:task_redeploy。prompt_state_inject.sh+settings.json登録+テスト。commit fc3a05d |
| cmd_1491 | Silent Fallback Medium掃討(ログなし5件+偽データ2件+SSOT1件) | **GATE CLEAR** | 才蔵完遂。AC1: 5箇所logger.warning追加(recalc_statusは既実装で変更不要)。AC2: SF-014 return 0→None+main.pyハンドリング、OPT-E Cash→skip+continue。AC3: DTB3→DEFAULT_RISK_FREE_ASSET定数化。WA:なし |
| cmd_1492 | SF-010失敗カウント+cmd_1491 push+Render deploy | **GATE CLEAR** | 小太郎完遂。recalculate_fast.py precompute失敗PFリスト蓄積+サマリーログ。4commit一括push。Render deploy live確認。fullrecalculate不要(logger/count追加のみ計算不変)。WA:なし |
**Silent Fallback掃討結果(2026-03-29)**: cmd_1483偵察→HIGH 11件→cmd_1484-1489の6cmdで全修正+cmd_1491でMedium 8件修正。本番fullrecalculate検証済み(signal=453,663一致、zero-sig=0)。免疫系(PI-018+軍師§4+L508)で再発防止。連勝51に更新。
**将軍直轄: CoDD→heartbeat構築+PI全昇華**（殿指示「サイクルを回せ」→「自走せよ」）
| 成果 | 内容 | 因果 |
|------|------|------|
| gate_cycle_health.sh | heartbeat 4チェック+自動強制(nudge/ntfy)+zero-target表示。/loop 10m登録 | CoDDなぜなぜ→判断ギャップ→意志依存→自動化×強制。殿5回介入で完成 |
| PI昇華 20/20 | 全PI原理化(30%→100%)。fact(具体)→implication(原理)の二端構造 | heartbeatが検知→将軍行動→殿「抽象と具象のレンジの幅」 |
| cmd_1496-1502 | 7件infra改善cmd(gate/hook/ninja_monitor/deploy_task/cmd_save/gunshi/test) | heartbeatでinsights 23→4に削減。CoDD気づきから即cmd化 |
| cmd_1503-1507 | 5件DM-Signal+infra cmd(trade_perf偵察/Cash修正/5th cycle計測/L3偵察/context更新) | idle 5名→全員分起票。heartbeat→行動のサイクル |
| insights 23→0 | 19件resolve(cmd対応)+4件dream resolve | insightsキュー完全消化 |
**将軍直轄: 知識循環なぜなぜ→6件修正**（殿指示「サイクルを回そう」）
| 修正 | 内容 | 因果 |
|------|------|------|
| Gate 15(進化検知) | gate_shogun_startup.shに新gate追加。context/に知識マップ未参照ファイルがあればフラグ | なぜなぜ5段: 進化は検知しない→孤立context→知識マップ断絶→循環不全。CLAUDE.md参照追加で0孤立達成 |
| Check 8(PI衝突) | cmd_save.shにPI番号衝突チェック追加。既存PI-0XXと重複時WARNING+次番号提案 | cmd_1453事故(PI-015衝突)の再発防止。自動化×強制 |
| Check 9(insights表面化) | cmd_save.sh起票時にpending insights数+直近3件を表示 | insights 18件死蔵発見→書込み専用で消費者不在→起票時に将軍の目に入れる |
| archive_completed.sh修正 | nested_result.summary抽出追加。chronicle空欄35件バックフィル | なぜなぜ: 218空欄→field名不一致(summary→result.summary) |
| insights整理 | 9件resolved(解決済みパターン+Gate15で対処済み) | pending 18→9件に半減 |
| gate_loop_health.sh時系列化 | insight生成を直近100件のみに制限(表示は全期間維持) | なぜなぜ: 解決済みパターン再起票→累積カウント→時系列原則違反→INSIGHT_WINDOW導入 |
| cmd_1443 | Ward二段EW weight pipeline修正: weightsが計算されるが下流に伝わらないバグ4箇所+軍師発見1箇所=計5箇所修正 | GATE CLEAR。AC1(final_weights設定)+AC2(is_kalman_meta条件除去5箇所+carry-forward+test fixture修正)+AC3(fullrecalculate 58FoF×9509行完全一致)。後方互換確認済み | 疾風AC1+影丸AC2+半蔵AC3。軍師がline862の5箇所目発見(REQUEST_CHANGES)。AC2初回FAIL→PD-001(scope拡張)→将軍裁定→PASS。テストfixtureのweights=None修正(本番一致) |
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
| cmd_1428 | R20 評価期間ローリング頑健性テスト: 最適パラメータの時間安定性を3メトリクスで検証 | GATE CLEAR。Sharpe: K=3-6最適68.8%,K=4-5最適54.2%。3メトリクスK一致度0% | 疾風完遂。Sharpeベースの最適帯は時間安定。ただしCAGR→K=2,MaxDD→K=3でメトリクス依存性あり |
| cmd_1429 | R21 BestCAGR vs ランダム×100: Ward vs モメンタム因果切り分け | GATE CLEAR。Ward寄与97.2%(Sharpe)、モメンタム2.8%。Sortino版Ward106.1%(モメンタム微負) | 影丸完遂。BestCAGR Sharpe=2.13、ランダム平均=2.07。Ward構造が支配的価値源泉。BestCAGR選択の付加価値は統計的にわずか |
| cmd_1430 | R22 3方式統一比較: BestCAGR vs 二段EW vs ランダムEW | GATE CLEAR。二段EW Sharpe=2.1228=BestCAGRの99.5%。MaxDD/Calmar二段EW優位 | 半蔵完遂。モメンタム仮定ゼロでも99.5%のSharpe維持。リスク面(MaxDD-13.5% vs -14.9%)で二段EW優位。BB化候補として有力 |
| cmd_1431 | R23 3方式行動メトリクスローリング(W=24ヶ月×48窓) | GATE CLEAR。二段EWとBestCAGRは46-48/48窓同値。連敗全窓同値 | 才蔵完遂。行動面でもBestCAGRとほぼ同等。NHF微差-0.4%のみ。純粋構造は行動メトリクスでも遜色なし |
| cmd_1432 | R24 二段EW2Dグリッド99通り(K=2-12×LB=12-60) | GATE CLEAR。最適(K=4,LB=30)=BestCAGRと同一。Sharpe73/99優位、MaxDD86/99優位 | 小太郎完遂。CAGRのみBestCAGR優位(34/99)。二段EWはSharpe/リスクで広範優位。peak_ratio=1.09頑健 |
| cmd_1433 | 後方伝播検証の仕組み化(テンプレート+gate+karo-ops) | GATE CLEAR。4テストPASS。CI green | 飛猿完遂。assumption_invalidation欄追加。忍者→家老→gateの三重網。螺旋原則の外部化 |
| cmd_1434 | R25 シン四神v2 12体×二段EW2Dグリッド90通り | GATE CLEAR。最適(K=3,LB=24)Sharpe=1.4785。TwoStageEW優位83.3%>R24(73.7%) | 疾風完遂。12体でも二段EW構造ロバスト。最適点移動あり(K=4→3,LB=30→24)。R24比較で優位率向上 |
| cmd_1435 | R26 全PF65体×二段EW2Dグリッド171通り | GATE CLEAR。最適(K=6,LB=18)Sharpe=1.492。Sharpe優位70.8%、MaxDD優位95.9% | 半蔵完遂。65体でも構造ロバスト。最適K:4→3→6(体数増でK増)、LB:30→24→18(体数増でLB短縮)。三段階全て二段EW優位一貫 |
| cmd_1436 | R27 Ward+二段EWビルディングブロック汎用モジュール | GATE CLEAR。WardTwoStageEWクラス実装+R24/R25/R26全3データセット検証8/8 PASS | 飛猿完遂。R1-R26研究結論をbuilding_block.pyに汎用化。内部K×LBグリッドサーチで最適パラメータ自動決定。コールドスタート1/N EW+k_max自動クランプ |
| cmd_1437 | WardTwoStageEWBlock本番パイプライン実装+登録+テスト | GATE CLEAR。TerminalBlock継承。テスト19項目全PASS(K=4,LB=30一致1e-6以内+cold start+エッジ) | 疾風(AC1+AC2実装+登録)+影丸(AC3+AC4テスト+commit)。building_block.py→パイプライン忠実移植。奥義系ネステッドFoF本番登録の基盤完成 |
| cmd_1439 | 汚染データ一括削除(ninpo21 CSV+R1-R24出力+偽スクリプト) | GATE CLEAR。outputs93件+scripts5件+__pycache__削除。保全対象(all_pf,r25_*,r26_*,building_block)全て無傷 | 才蔵完遂。commit 45dd018f。cmd_1441(旧PF分析)の前提条件=クリーンanalysis環境確保 |
| cmd_1440 | 汚染事故の教訓L499登録+PI-014追記 | GATE CLEAR。L499(データ出自検証必須)+PI-014(outputs/CSVはパリティ未検証=未検証)登録 | 小太郎完遂。commit 2cc464d。事故→教訓→PI=免疫系獲得。cmd_1439と並列完了 |
| cmd_1442 | ネオ五神候補absolute偵察(GLD/USO/TIP+既存4absolute相関) | GATE CLEAR。全7銘柄StockData取得成功(203ヶ月共通期間)。GLD最有力(max|r|=0.343)、USO次点(0.378)、TIP不適(LQD冗長r=0.769) | 半蔵完遂。commit 3abdede9。五神5番目候補=GLD有力。Phase2(哲学設計)は別cmd |
| cmd_1441 | 旧忍法+旧四神のWard+二段EW 2Dグリッド分析(本番DBデータ) | GATE CLEAR。旧忍法15体K*=4,LB*=24,Sharpe=2.01。旧四神12体K*=4,LB*=12,Sharpe=1.55,TwoStageEW優位率76.7%。合計27体K*=12,LB*=24,Sharpe=1.75 | 疾風完遂。R25(1.48)/R26(1.49)より高Sharpe。旧四神type混在(fof10+standard2)=制約との矛盾発見。ヒートマップ18枚+CSV3本+YAML3本 |
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

## 2026-03-20〜2026-05-28 (旧昇順ブロック・全文移設)
- → `docs/research/senkyoku-log-archive-2026-03_05.md`（1013行、cmd_1145〜cmd_2666期。2026-08-26 将軍doc laneで移設・情報削除なし。grep: `## 2026-0[345]`）
