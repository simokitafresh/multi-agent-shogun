# インフラコンテキスト
<!-- last_updated: 2026-08-30 cmd_karo_hotfix_gate_alert_identity_envelope_20260830(DOC_LANE_REQUEST blt_20260830_093831_327430) -->
<!-- source_commit:ce69ed97490e reason:cmd_karo_hotfix_gate_alert_identity_envelope_20260830(DOC_LANE_REQUEST blt_20260830_093831_327430) evidence:gate_improvement.log BLOCK 0, GATE-IMPROVEMENT-DONE 09:32, gate CLEAR 09:36:10 -->
<!-- source_commit:b132118b472d reason:cmd_karo_hotfix_tmux_live_sendkeys_guard(DOC_LANE_REQUEST blt_074928) evidence:git show --stat b132118b472d -->
<!-- source_commit:869e6ad792cf reason:cmd_karo_hotfix_run_tests_test_necessity_selector(DOC_LANE_REQUEST blt_074340) evidence:git show --stat 869e6ad792cf -->
<!-- source_commit:851d5611b7ff reason:T190 push lane 自動化 unit1-3(DOC_LANE_REQUEST blt_041119) evidence:git show --stat 851d5611b7ff -->
<!-- source_commit:08ce18ac79a8 reason:cmd_karo_hotfix_backup_cron_gws_path(origin 到達後) evidence:git show --stat 08ce18ac79a8 -->
<!-- source_commit:788139722e44 reason:cmd_karo_hotfix_lifecycle_worker_singleton_unit4(DOC_LANE_REQUEST blt_212507) evidence:git show --stat 788139722e44 -->
<!-- source_commit:32612a1f1480 reason:cmd_karo_hotfix_command_scope_directory_prefix(DOC_LANE_REQUEST blt_210808) evidence:git show --stat 32612a1f1480 -->
<!-- source_commit:bb409ad39caf reason:cmd_4411 オフサイト退避+隔離復元(DOC_LANE_REQUEST blt_182710、origin 到達後) evidence:git show --stat bb409ad39caf -->
<!-- source_commit:a8055a18b03286a55414e90582ec96990e9ff9ab reason:doc lane: 2026-08-28 節追記(T151/T157/T159/T160/T161/T162/T158/artifact)。a3e312e2a は origin 未到達ゆえ origin tip を境界、到達後に再設定 evidence:grep -c '2026-08-28 追加' context/infrastructure.md=1; commit f6af51645 -->
<!-- source_commit:0f843cab57d5 reason:DOC_LANE_REQUEST blt_123333 approved_source_commit build_cache ci_fix を T107 行へ追記 evidence:git merge-base --is-ancestor 0f843cab5 origin/main = yes; grep -c '0f843cab5 で cache 3 本を refresh' context/infrastructure.md = 1 -->
<!-- source_commit:49e32bd31d44 reason:DOC_LANE_REQUEST blt_112753 approved_source_commit T107 第 1 弾+shebang ci_fix を §2026-08-27 ext4 節へ反映 evidence:git merge-base --is-ancestor 49e32bd31 origin/main = yes; grep -c 'T107、飛猿 c15453e33 + 半蔵 49e32bd31' context/infrastructure.md = 1 -->
<!-- source_commit:c092febfceca reason:DOC_LANE_REQUEST blt_073452 approved_source_commit T108 source_equivalent 自動終端を §2026-08-27 ext4 節へ反映 evidence:git merge-base --is-ancestor c092febfc origin/main = yes; grep -c 'T108、小太郎 c092febfc' context/infrastructure.md = 1 -->
<!-- source_commit:88969097a185 reason:DOC_LANE_REQUEST blt_070809 approved_source_commit T100 runtime lane 直 push 廃止を §2026-08-27 ext4 節へ反映 evidence:git merge-base --is-ancestor 88969097a origin/main = yes; grep -c 'T100、半蔵 88969097a' context/infrastructure.md = 1 -->
<!-- source_commit:b5f586933959 reason:T70 影丸 hotfix(task worktree root→ext4) を §2026-08-27 へ反映(DOC_LANE_REQUEST blt_20260827_231110) evidence:context/infrastructure.md §2026-08-27 T70 行; commit b5f586933959 scripts/deploy_task.sh scripts/deploy_task/preflight.sh -->
<!-- source_commit:c6e8231816ab reason:2026-08-27 将軍doc lane: ext4 移設(cutover/効果/副作用/T70/T83)を §2026-08-27 追加(DOC_LANE_ALERT blt_20260827_230132 実消化) evidence:context/infrastructure.md §2026-08-27 追加(ext4); commits 5f8aea006 e644881f5 c6e823181 -->
<!-- source_commit:06ddbc988 reason:2026-08-27 将軍doc lane: 孤児テスト根治5点を反映(DOC_LANE_ALERT blt_20260826_123314/101234 実消化) evidence:context/infrastructure.md §2026-08-27 追加; commits 3fa443c11 c940c47d5 8c09923f8 06ddbc988 -->
<!-- source_commit:ed237d33a reason:context_freshness reviewed source boundary (post-integration: 本日分は§2026-08-26に反映済) evidence:context_freshness_check context=context/infrastructure.md commit=ed237d33a -->
<!-- source_commit:f5c19317d reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=f5c19317d -->
<!-- source_commit:ae9609fe8 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=ae9609fe8 -->
<!-- source_commit:ec3e50f4f reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=ec3e50f4f -->
<!-- source_commit:024dce221 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=024dce221 -->
<!-- source_commit:7d9532b12 reason:context updated for report scope SSOT + merge-commit ownership gate evidence:doc_lane_request blt_20260826_101234_f3d396 -->
<!-- source_commit:4dde551de reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=4dde551de -->
<!-- source_commit:b7ad89d5c reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=b7ad89d5c -->
<!-- source_commit:464c833c1 reason:context updated for ghost tmux AC2/AC3b + session_alerts runtime preservation evidence:doc_lane_request blt_20260826_062930_e5aabe -->
<!-- source_commit:e06c2f9dc reason:context updated for ghost tmux AC1 implementation evidence:doc_lane_request blt_20260826_040416_c55741 -->
<!-- source_commit:46d568a53 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=46d568a53 -->
<!-- source_commit:a4930e9ce reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=a4930e9ce -->
<!-- source_commit:60537d6fb reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=60537d6fb -->
<!-- source_commit:626640662 reason:context updated for cmd_4403 batch spiral evidence:doc_lane_request blt_20260825_200004_961db6 -->
<!-- source_commit:1131863bc reason:context updated for ci green + receipt harness evidence:doc_lane_request blt_20260825_192810_979cd7 -->
<!-- source_commit:464d5ddf7 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=464d5ddf7 -->
<!-- source_commit:0225c9501 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=0225c9501 -->
<!-- source_commit:3f1ad1f8b reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=3f1ad1f8b -->
<!-- source_commit:076dc99cd reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=076dc99cd -->
<!-- source_commit:4e0287e1e reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=4e0287e1e -->
<!-- source_commit:8a5a9d9f3 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=8a5a9d9f3 -->
<!-- source_commit:26d7b5580 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=26d7b5580 -->
<!-- source_commit:cbc14955f reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=cbc14955f -->
<!-- source_commit:760485841 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=760485841 -->
<!-- source_commit:3b283e4b0 reason:context updated for cmd_4400 shard parallelization evidence:doc_lane_request blt_20260825_131907_154d6a -->
<!-- source_commit:712934f22 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=712934f22 -->
<!-- source_commit:74161aece reason:context updated for cmd_4401 instrumentation evidence:doc_lane_request blt_20260825_114142_f45408 -->
<!-- source_commit:75dd7ec83 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=75dd7ec83 -->
<!-- source_commit:5c1c7fed3 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=5c1c7fed3 -->
<!-- source_commit:9ceb1502d reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=9ceb1502d -->
<!-- source_commit:513513851 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=513513851 -->
<!-- source_commit:d9121144b reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=d9121144b -->
<!-- source_commit:dcae274d5 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=dcae274d5 -->
<!-- source_commit:d47b745c1 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=d47b745c1 -->
<!-- source_commit:0a8ae32a8 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=0a8ae32a8 -->
<!-- source_commit:7391258b6 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=7391258b6 -->
<!-- source_commit:1ca192e3a reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=1ca192e3a -->
<!-- source_commit:8c3f0dc53 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=8c3f0dc53 -->
<!-- source_commit:2beeceebd reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=2beeceebd -->
<!-- source_commit:3f4befacb reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=3f4befacb -->
<!-- source_commit:cca367e80 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=cca367e80 -->
<!-- source_commit:80daf0ee7 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=80daf0ee7 -->
<!-- source_commit:0d401214f reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=0d401214f -->
<!-- source_commit:afd8ac69b reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=afd8ac69b -->
<!-- source_commit:67c51dfcb reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=67c51dfcb -->
<!-- source_commit:dcb23224e reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=dcb23224e -->
<!-- source_commit:8e39543de reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=8e39543de -->
<!-- source_commit:165c35355 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=165c35355 -->
<!-- source_commit:c22305f0b reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=c22305f0b -->
<!-- source_commit:ddeb06b19 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=ddeb06b19 -->
<!-- source_commit:e39daca71 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=e39daca71 -->
<!-- source_commit:1ba43779d reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=1ba43779d -->
<!-- source_commit:ebeaeffba reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=ebeaeffba -->
<!-- source_commit:aae314f84 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=aae314f84 -->
<!-- source_commit:b86369d29 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=b86369d29 -->
<!-- source_commit:6000227f3 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=6000227f3 -->
<!-- source_commit:309d651fe reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=309d651fe -->
<!-- source_commit:fe9e3ba4a reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=fe9e3ba4a -->
<!-- source_commit:f9234698a reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=f9234698a -->
<!-- source_commit:7972b7fd2 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=7972b7fd2 -->
<!-- source_commit:6cfbf1361 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=6cfbf1361 -->
<!-- source_commit:324bdb414 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=324bdb414 -->
<!-- source_commit:5f7cbb7be reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=5f7cbb7be -->
<!-- source_commit:2fee986d0 reason:GA-492 context update request consumer接続の反映 evidence:gate_context_freshness.shが承認済みcontext update requestを消費するconsumer接続(+51-18、cmd_karo_hotfix_ga492) -->
<!-- source_commit:2da7e1e05 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=2da7e1e05 -->
<!-- source_commit:95184ce75 reason:context_freshness reviewed source boundary evidence:context_freshness_check context=context/infrastructure.md commit=95184ce75 -->
<!-- source_commit:8fed7e2df reason:GA-491 terminal blob parity反映 evidence:cmd_karo_hotfix_ga491_terminal_blob_parity: cmd_complete_gateが終端で成果commitの祖先化に加えpath blob一致(report対象pathのHEAD blob=成果commit blob)を強制(+205行、test +57行)。tree退行4/4事象(GA-491)の構造根治=本日4クラス目クローズ -->
<!-- source_commit:962b0f2bc reason:GA-490/491 UPDATE_REQUEST反映(退行復旧再適用) evidence:cmd_4360-4365でdeploy_task.shをscripts/deploy_task/{bootstrap,state,transaction,delivery,resolve,task_contract,report}.shへ抽出(挙動不変、A-Eは移動+static互換stub、Fはif-false static互換様式=L1630契約)。優先度台帳=docs/research/script_refactor_priority_20260821.md、分割設計書=docs/research/deploy_task_split_design_20260821.md。残cluster G-J継続中 -->
<!-- source_commit:5a073b2ec reason:stale ALERT再送防止の反映(退行復旧再適用) evidence:gate_context_freshness.shが通知直前にraw ALERT metadataを現物last_updatedと再突合し、alert基準日より新しければ通知破棄(+39行、test +30行)。stale再送3件(core/ops/research 2026-08-22実証)の構造根治 -->
<!-- source_commit:3ddbbdce8 reason:GA-490 raw ALERT doc-lane永続通知契約の反映(退行復旧再適用) evidence:gate_context_freshness.shがraw ALERTを掲示板可読契約で永続通知。test +88行で契約固定。doc lane受信経路=掲示板DOC_LANE_WARNING投稿。併せてcmd_complete_gateへreport commit main祖先化終端検査(merge 3a16cfde)とinsight ID-monotonic merge(gold_missing=0不変量)を2026-08-22恒久化 -->
<!-- GA-483: infra-platform freshness uses explicit source pathspecs; operational records and project research remain outside this owner boundary. -->
<!-- source_commit:253afbb2c reason:inbox_write guard/pre-commit guard/契約を追記 evidence:commit 75ffff697 ae52b3129 cc13a69cb -->
<!-- source_commit:9f39c1a071cf4c0f6cc1afbdad39a295ff29cc2a reason:cmd_karo_hotfix_review_quality_warn_20260814_normal reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=9f39c1a071cf4c0f6cc1afbdad39a295ff29cc2a -->
<!-- source_commit:e8cbaf7eb5fbd1a907f06d75240d609ef316700c reason:cmd_karo_hotfix_review_quality_warn_20260814_normal reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=e8cbaf7eb5fbd1a907f06d75240d609ef316700c -->
<!-- source_commit:66c9455ae reason:cmd_karo_hotfix_ga457_context_update_autowire_20260812 reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=66c9455ae -->
<!-- source_commit:4848ca902 reason:cmd_karo_hotfix_speed_deploy_task_r1b_20260809 reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=4848ca902 -->
<!-- source_commit:ce4ba6d2b reason:reviewed_source_boundary evidence:cmd_karo_hotfix_insights_rotation_archive_gate_20260808 -->
<!-- source_commit:b35dc70be reason:reviewed_source_boundary evidence:cmd_karo_hotfix_insights_concurrent_dirty_gate_20260808 -->
<!-- source_commit:6ab875128 reason:reviewed_source_boundary evidence:cmd_karo_hotfix_guard14_launcher_operand_20260808 -->
<!-- source_commit:27299673b reason:cmd_karo_hotfix_gate_report_cross_repo_cwd_20260808 reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=27299673b -->
<!-- source_commit:51a7acee8 reason:cmd_karo_hotfix_ci_reviewed_at_direct_20260808 reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=51a7acee8 -->
<!-- source_commit:5e57ee7df37d02135910876cc431cf36ed400411 reason:GA-446 context freshness update evidence:gate_alert GA-446 -->
<!-- source_commit:63a42ced1 reason:cmd_karo_ci_fix_31076764177_scope_commit_race reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=63a42ced1 -->
<!-- source_commit:b303051f0 reason:cmd_karo_hotfix_uncommitted_scripts_20260806 reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=b303051f0 -->
<!-- source_commit:df400ee75 reason:cmd_karo_round10_lane2 reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=df400ee75 -->
<!-- source_commit:a44de3202 reason:cmd_karo_round10_lane2 reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=a44de3202 -->
<!-- source_commit:180a3894a reason:cmd_karo_round10_lane2 reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=180a3894a -->
<!-- source_commit:4875ea831 reason:cmd_karo_round10_lane1_refresh_window_impl_20260805 reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=4875ea831 -->
<!-- source_commit:7c461e2a0 reason:cmd_karo_round10_lane1_refresh_window_impl_20260805 reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=7c461e2a0 -->
<!-- source_commit:ef7e4188f reason:cmd_karo_hotfix_completion_notify_gap_draft_ja_20260805 reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=ef7e4188f -->
<!-- source_commit:3d56941d7 reason:reviewed source boundary evidence:cmd_karo_round9_lane0pp_impl_common_20260805 gate evidence -->
<!-- source_commit:8e6527a3c reason:reviewed source boundary evidence:cmd_karo_round9_lane0pp_impl_common_20260805 gate evidence -->
<!-- source_commit:8b80cb4a4 reason:cmd_karo_t5_ac12_consumer_regression_20260805 reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=8b80cb4a4 -->
<!-- source_commit:77f7e1a77 reason:cmd_karo_t5_ac10_idempotency_root_20260805 reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=77f7e1a77 -->
<!-- source_commit:248ea8d5b reason:cmd_shogun_commit_reservation_ledger_phase2_20260805 evidence:reviewed -->
<!-- source_commit:f8c49cbd7 reason:cmd_shogun_commit_reservation_ledger_phase1_20260805 evidence:reviewed -->
<!-- source_commit:515f0214e reason:cmd_karo_hotfix_ga432_context_freshness reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=515f0214e -->
<!-- source_commit:23a1ce61205ce4496ab11570583e8e8adcaeac4e reason:reflux backlink SSOT update reviewed evidence:incoming 0 to 1; runner69/69; target doc diff0 -->
<!-- last_synced_lesson: L1675 -->

結論: 本ファイルは検索起点となる索引層。運用詳細・経緯・教訓本文は7つの詳細正本へ移設した。
source boundary一致taskはregistryのowner/update_triggerからcontext_update_candidatesを自動注入し、未処理候補はcmd_complete_gateがBLOCK、明示処理済み/無関係はCLEAR。
参照: 見出し名を `rg` し、該当する詳細ファイルを読む。全見出し対応は `docs/research/infrastructure-section-manifest-20260801.yaml` が正本。

## コンテキスト・記憶・品質基盤

結論: 詳細は `docs/research/infrastructure-context-memory.md` に保存。原文を省略せず移設済み。
見出し: インフラコンテキスト / コンテキスト管理 / 2026-07-24インフラ修正バッチ(cmd_4154-4164) / lord_conversation / 記憶DBデータフロー（cmd_2963〜cmd_3032） / 三層記憶×学習ループ接続（cmd_3116〜cmd_3128, 2026-06-02） / 直近改善（cmd_181〜cmd_541） / 直近改善（cmd_602〜cmd_612） / 直近改善（cmd_875〜cmd_878） / 直近改善（cmd_1039〜cmd_1120） / 直近改善（cmd_3300〜GA-050） / 軍師品質管理ユニット（cmd_1144〜cmd_1181） / 偵察デフォルト品質5要件（cmd_754+cmd_1476） / 直近改善（cmd_1532〜cmd_1543） / 直近改善（2026-04-16〜2026-04-30 CoDD波 / GP-198〜240）

## 配備・CLI・自動化基盤

結論: 詳細は `docs/research/infrastructure-agents-delivery.md` に保存。原文を省略せず移設済み。
見出し: deploy_task.sh --direct mode（cmd_1672） / /henseiスキル（cmd_1673） / Claude CLIモデル指定とコンテキスト（ci_fix_200k） / Codex multi-CLI統合(2026-05-11確立) / 直近24日間の主要裁定/実装（2026-05-01〜2026-05-24） / Claude Code バージョン固定と復帰 / 忍者個別弱点自動注入（cmd_1307） / gate強化（cmd_1178〜cmd_1180） / 知識サイクル現状（cmd_531/533/541/1111/1113/1117 反映） / 稼働中の仕組み / 現行メトリクス（2026-03-30時点） / 設計思想 / SessionStart hook — startup gate自動実行（cmd_2683） / 二重配備防止3層防御（cmd_2681/2682/2684） / 暗黒物質Phase 2: 高優先度60関数（cmd_2777） / ninja_monitor.sh: 状態管理・配備・監視・自動化（26件） / deploy_task.sh: 注入・ゲート・配備制御（20件） / inbox_write.sh: メッセージ管理・重複検出（9件） / cmd_save.sh: 品質ゲート補助（5件） / ninja_monitor.sh / inbox_watcher.sh / ntfy.sh / ログローテーション / field_deps.tsv
- 作業中忍者clear不変量: `safe_send_clear`は`assigned|acknowledged|in_progress`を既定BLOCKし、停止を計測したDEPLOY-STALLだけ明示許可する。即時clear指示を恒久設定変更へ一般化せず、task statusをidleへ改変して適格化しない。`clear_debounce`は再送抑制であり完了待ちではない。origin: [[殿指示_即時auto_clear_20260809]] -> [[safe_send_clear直呼びと恒久設定化の穴]] -> [[active_task_clear_fail_closed]]
- cmd_4248現物走査: `gate_shogun_startup.sh` の機械検知は `gate_karo_startup`/idle自走/CI RED忍者修正/`ninja_monitor` へ移管候補、殿への回答・追体験・裁定・cmd起票判断は将軍固有、状態遷移のない要約表示は削除候補。移管順序は `session_alerts生成 → stop hook → 先送りBLOCK/dedup → escalation` を維持する（詳細: `docs/research/cmd_4248_shogun_gate_triage_20260809.md`）。
- publish経路の段別計装（cmd_4401, 2026-08-25）: `scripts/cmd_publish.sh` に段別wall時間計装(preflight/save_gate/promotion/delegate)+missing defaults二重setterのbatch統合(-8.3%)。隔離fixture実測=publish_total 3770ms（timing正本: `scripts/cdp/cmd_4401_publish_timing.md`）。★ライブpublish実測約13分との乖離が未説明=LS-A24計測代表性。次弾=ライブ1回のphase log一次取得(INS-20260825-111719094)。origin: [[cmd_4399_preflight本体無罪確定]] -> [[cmd_4401_publish外側経路計装]]
- CI shard並列化+状態依存compatibility shard（cmd_4400+stateful_shards hotfix, 2026-08-25）: `.github/workflows/test.yml` をunit単一job→8 shard並列(実測タイミングLPT割当・欠落0重複0)+状態依存testを除外せず依存順で束ねるcompatibility shard+run固有namespace隔離(3b283e4b0)。unitテストwall-clock 2885秒→最長shard 303秒(compatibility)/通常最長183秒=約89.5%減。**GREEN確定済み**(run 32828851180、全14 job success、2026-08-25 17:59)。ローカル検証harness常設: 固定SHAで8 shard+compatibilityのreceipt FAIL0(9/9 PASS・計3523テスト・SKIP0)をpush前提とするci_push_receipt_contract。origin: [[cmd_4392_CI分解_テスト実行90.7%支配]] -> [[cmd_4400_shard並列化]] -> [[CI_GREEN_20260825_1759]]
- 個別テスト単体短縮バッチらせん（cmd_4403〜, 2026-08-25）: 殿裁定の型=忍者並列×バッチ計測選別(機械選別・個別before/after・バッチ境界で全体分布確認・ファイル排他・当面10個)。第1バッチ=最重量test_cmd_complete_gate.bats 912→298秒(67.3%減)・281/281 PASS・検証削除ゼロ(626640662、成果物正本=docs/research/cmd_4403_slowest_tests_speedup_20260825.md)。origin: [[殿の教え_個別最適化は単体高速化_20260825_1524]] -> [[cmd_4403_slowest_tests単体短縮]]
- **オフサイト退避+隔離復元(cmd_4411, 2026-08-29)**: 殿下問 16:37『PC 故障時に GitHub/zip で即時移行できる方法は確立されているか』→git 外の状態(記憶DB gzip・projects・queue・logs/gate_metrics.log、DM-signal env 系は対称暗号化)を `python3 scripts/shogun_backup.py` で Drive `shogun-offsite-backups`(id 1EOqd51NF4ZplAJrJrhhLQWXoPGCnumgI)へ退避(鍵=`~/.config/shogun/backup.key` mode 600、Drive へ送らない)、Drive 一覧 6 件・再 download sha256 5/5 一致。隔離復元(mktemp clone→`first_setup.sh --dry-run`→展開→記憶DB `integrity_check=ok`→bats 2/2 FAIL0 SKIP0)を実走証明。cron `0 3 * * *`(marker `# shogun-drive-backup`、flock)。復元 runbook → `docs/research/cmd_4411_offsite_restore_runbook_20260829.md`。DM-signal 側は疾風 push unit(origin..HEAD 0/0、backup/<branch> 新 ref)で GitHub 復元可。outputs は本番 PF 作成根拠のみ保持(T189、`context/dm-signal-research.md`)。
- **attached 本番 tmux への無許可 send-keys guard T191(半蔵 b132118b, 2026-08-30 家老自走 hotfix)**: cmd_4407(08-27)の『クリーン clone で shutsujin 完走』が本番 8 pane へ send-keys した事故(型三弾-3)の構造型根治=INS-20260827-152607。`scripts/lib/tmux_live_send_guard.sh`(新設 45 行)+`reset_layout.sh` の送出 6 箇所直前に guard: attached の本番 shogun session へは `SHOGUN_ALLOW_LIVE_SENDKEYS` 明示許可なしで BLOCK、隔離 session は PASS。契約 bats 4/4(無許可 BLOCK/隔離 PASS/明示許可 PASS/6/6 直前 guard)。
- **gate_improvement_trigger の gate_alert に commander 封筒(疾風 ce69ed974, 2026-08-30 家老 hotfix)**: 08:04 の task_supplement_identity hotfix で家老 inbox の指示 type に `task_id=commander_directive subject_task_id=… parent_cmd=…` 封筒が必須化された結果、daemon 発 gate_alert が毎周期 BLOCK(rc=2、07:49〜09:09 GATE-IMPROVEMENT-FAIL)。`gate_alert_identity()` が `subject_task_id=gate_alert_<gate>_<alert_id>`/`parent_cmd=cmd_gate_improvement_<gate>` を先頭行に付与 → gate_improvement.log BLOCK 0・DONE 09:32。教訓: 封筒必須化は人発だけでなく daemon 発 inbox_write 全経路(gate_improvement/ninja_monitor)を grep してから入れよ。bats tests/unit/test_gate_improvement_trigger.bats
- **run_tests の test_necessity 誤認除去(疾風 869e6ad7, 2026-08-30 家老自走 hotfix)**: `scripts/run_tests.sh` が自然言語 task の文言を test_necessity 宣言と誤認して test 選択を誤っていた→自然言語 task は rc=0、明示 test_path は direct=1 で選択。契約テスト 73/73 SKIP0。default-delete test policy(CLAUDE.md §Test Rules)の運用上の穴。
- **push lane 自動化 T190(影丸 unit1〜3, 2026-08-30 01:51〜04:09)**: 08-29 は CI GREEN でも未 push commit が 26〜38 分滞留し将軍の 1 通で解消(23:10/00:10/00:41 の 3 回、`WAIT:report_commit_main_ancestry` 16:00 以降 47 行)=push lane が人手依存。unit1=`ninja_monitor.sh` lifecycle worker `push_lane`(oldest first-parent 単 commit・force なし・pre-push 維持・CI RED 停止・WAIT ancestry 再 GATE、150/150)。unit2=timeout を固定 120s から pre-push 実測由来へ+PUSH/TIMEOUT を `push_lane.log`(STATE_DIR)へ 1 行記録(153/153)→live で 6s に縮み毎 cycle rc=124(導出式に下限なし)。unit3=`max(60s, ceil((3×pre_push_wall+push_wall)/1000))`+push 実測記録(154/154、851d5611)→live で timeout=186s・TIMEOUT 0 行。proof=unit3 live 後 24h で WAIT/BLOCK ancestry 0 行∧将軍 push 1 通 0(`queue/shogun_todo_map.md` T190)。
- **オフサイト退避 cron の daemon 環境差(小太郎 08ce18ac, 2026-08-30)**: 08-30 03:00 の初回 cron run が『BACKUP_FAIL: gws CLI is unavailable』(`shogun_backup.py` が `shutil.which("gws")` 依存、cron PATH に nvm 無し=型八弾-2)。`--install-cron` が crontab 行に `SHOGUN_GWS_BIN=<絶対 path>` を exact 1 件注入(bats 3/3)。将軍は同日 03:05 に手動 run で当日分を担保(backup_id shogun-20260829T180517Z、Drive 18 ファイル)。本番 proof=08-31 03:00 の成功 JSON。
- **cmd_complete_gate の command/files_modified 照合をディレクトリ境界対応(才蔵 32612a1f1, 2026-08-29)**: cmd_4411 が 18:32 に `command_files_modified_mismatch` で BLOCK(command 欄の `scripts` 等ディレクトリ指定と files_modified の個別 path が不一致扱い)→`scripts/cmd_complete_gate.sh` に directory-boundary coverage 2 行+bats 41 行。修正前 297/298(回帰 1 FAIL)→修正後 477/477 SKIP 0。
- **review-pending nudge 三状態の unit4=lifecycle worker singleton 早期終了の除外(半蔵 788139722, 2026-08-29)**: T184 三者合意(A/B/C 状態+durable ledger)の実装後、lifecycle worker の singleton 早期終了で『formal LGTM 済(状態 B)』の家老宛 nudge が 0 回だった→除外して 1 回だけ送信、再実行重複 0(ledger/nudge 0→1、bats +18 行)。unit1〜4 の全体像 → T184(`queue/shogun_todo_map.md`)。

## プラットフォーム運用

結論: 詳細は `docs/research/infrastructure-platforms-operations.md` に保存。原文を省略せず移設済み。
見出し: tmux設定 / Claude Code マルチアカウント管理（cmd_313偵察） / Google Workspace CLI (gws) — 全PJ共通ツール / Render運用（cmd_2824, 2026-05-17） / プラン別挙動 / 障害切り分け手順 / 全サービス一覧 / WSL2固有 / 競合調査 / Android App / 記憶DBバックアップ棚卸し（cmd_3869） / DM-Signal outputs陳腐化中間成果物削除（cmd_3871） / `/mnt/c`残量の事前検知（cmd_3875） / 防御機構スループット棚卸し（cmd_4059） / 外れ値型防御checkの発生条件（cmd_4185） / DM-signal outputs陳腐化成果物削除（cmd_3871, 2026-07-24）

## 教訓索引 A（配備・gate）
- L1599: verification taskにはno-code identityとrunner契約を同時注入する — 検証のみのtaskはcommit契約required=false(task_type=verification/read-only字句)と選択実行runner契約を配備時に同時に持たせる（cmd_4340、/lesson-sort 2026-08-18）

結論: 詳細は `docs/research/infrastructure-lessons-deploy-gates.md` に保存。原文を省略せず移設済み。
見出し: テスト方針（全PJ共通・殿裁定2026-07-19） / Infra教訓索引 / カテゴリ別索引（L051-L466）

## 教訓索引 B（git・test）

結論: 詳細は `docs/research/infrastructure-lessons-git-testing.md` に保存。原文を省略せず移設済み。
見出し: 前節「Infra教訓索引」の連続本文（source lines 1301-1700）。

## 教訓索引 C（review・operations）

結論: 詳細は `docs/research/infrastructure-lessons-reviews-operations.md` に保存。原文を省略せず移設済み。
見出し: 前節「Infra教訓索引」の連続本文（source lines 1701-2123）。
- L1503: 既存legacy欠損は不変multisetで隔離せよ（cmd_karo_hotfix_shared_operational_log_ownership_20260801）
<!-- last_synced_lesson: L1675 -->
- L1504: appendとarchiveはreaderを含むgeneration transactionにせよ（cmd_karo_hotfix_gunshi_cs_remediation_generation_20260801）
- L1505: 永続test宣言はtask正本に置く（cmd_4206）
- L1506: active context DEFERはowner存在だけでなくdirty・baseline変化・fresh leaseの全ANDにせよ（cmd_karo_hotfix_active_context_gate_transient_20260801）
- L1507: chunk値の安全性はcommit・unit PASSでなく本番rows>0・terminal完走で確定する（cmd_karo_hotfix_ga422_context_freshness_20260801）
- L1508: prepared publication key（cmd_4205）
- L1509: 実装前review receiptはtask identityとAC fingerprintの双方へ結合する（cmd_karo_hotfix_bugfix_dual_review_enforcement_20260801）
- L1510: field存在率100%とcanonical pair成立を分離計測せよ（cmd_4210）
- L1511: 未読0は任務なしの証拠ではない（cmd_karo_hotfix_tobisaru_failed_recovery_20260802）
- L1512: 同期fallback前に親lockを解放せよ（cmd_karo_hotfix_completion_workers_tmux_detach_20260802）
- L1513: writer rc=0は成果receiptではない（cmd_4214）
- L1514: 進捗freshnessとSTALL閾値を直列加算するな（cmd_4213）
- L1515: 高価なcache整合処理は書込ごとのpushではなく読取stale検知で需要駆動せよ（cmd_4212）
- L1516: 削除必須一時testをtask selector planned pathへ残すと最終receiptが自己矛盾する（cmd_karo_hotfix_viewer_rotation_recovery_20260802）
- 共有bounded queueのtask-owned recordがliveから消えた場合、archive内の同ID・完全一致・一意を満たす時だけ正規evictionとして許可し、それ以外はBLOCKする（cmd_karo_hotfix_gate_shared_insight_semantic_20260802）
- L1517: 自動配備inventoryは分析helper出力をGit追跡境界で再検証する（cmd_reflux_backlink_202608020948_kotaro）
- L1518: terminal report fixtureはtask side effectも隔離する（cmd_karo_hotfix_fail_close_truthful_terminal_20260802）
- L1519: canonical receiptへidentityを追記せずsidecarで厳密再利用する（cmd_karo_hotfix_precommit_receipt_index_latency_20260802）
- L1520: task runner終端receiptを明示パスで検証する（cmd_4215）
- L1521: shared-file帰属はpath/blob全体でなくtask-owned normalized hunkで判定する（cmd_karo_hotfix_report_shared_provenance_fp_20260802）
- L1522: async送達の最終判定は同一tickの複合証拠で行う（cmd_karo_hotfix_async_delivery_verify_20260802）
- L1523: CDP target closeはbrowser cleanupではない（cmd_4218）
- L1524: 再検証対象は固定archive pathとSHAを対で注入する（cmd_karo_verify_fixed_infra_bugs_20260802）
- L1525: 外部repo鮮度判定は既存commit receiptを消費せよ（cmd_karo_hotfix_context_freshness_ga425_20260802）
- L1526: 並列runnerはfail-fastとselection receipt完全性を両立できない（cmd_karo_hotfix_run_tests_terminal_receipt_partial_exit_20260802）
- L1527: 完了後source commitにも行動receiptを提示せよ（cmd_karo_hotfix_context_freshness_ga426_20260802）
- L1528: deployed_at graceだけではgate中task差替え競合を防げない（cmd_karo_hotfix_stall_transition_fp_20260802）
- L1529: 不適格な占有endpointを空portと同一視しない（cmd_karo_cdp_t5_endpoint_qualification_20260802）
- L1530: task runnerはplanned test pathを直接選択しない場合がある（cmd_karo_cdp_t5_auth_dom_probe_20260802）
- L1531: 大規模DB出力は母集団を縮めずhash chunk化する（cmd_4221）
- L1532: 外部repo taskのrun_tests ownership mapping欠落（cmd_karo_goal_w0_b1）
- L1533: 外部source鮮度は検出だけでなく承認receiptを更新要求へ接続する（cmd_karo_hotfix_context_freshness_ga427_20260803）
- L1534: refluxはcommit専用index scopeでfingerprint生成（cmd_karo_goal_a1_l0_boundary_reverify_commit_rc3_20260803）
- L1535: cross-repo git判定はtask project working treeをSSOTにする（cmd_karo_hotfix_sgpre35_cross_repo_head_20260803）
- L1536: task runnerの外部repo contract選択を配備時に注入する（cmd_karo_goal_b3_fallback_remove_rc_20260803）
- L1537: 不可逆境界の前で候補object全体をscope検査する（cmd_karo_hotfix_scope_commit_cross_path_contamination_rc_20260803）
- L1538: atomic renameだけでは共有markerのlost updateを防げない（cmd_karo_context_source_marker_concurrency_tobisaru_20260803）
- L1539: 子PFreturnは親境界oracleにならない（cmd_karo_cx_fail9_oracle_semantics_hanzo_20260803）
- L1540: append型receiptは集合として全件照合する（cmd_karo_direct_ga428_context_freshness_fix_20260803）
- L1541: 既存tracked test内の新関数はtask-level test_necessity path宣言とcommit helperが衝突する（cmd_4225_backend_impl）
- L1542: dependency lock変更のtask test selectorはファイル名filterにしてはならない（cmd_karo_ci_fix_rebalancer_30841850798）
- L1543: full-corpus testはtracked境界を固定せよ（cmd_karo_ci_fix_30844464109_yaml_injection）
- L1544: binary存在とdaemon稼働を同一視しない（cmd_karo_ci_fix_30844464109_wrapper_run_tests）
- L1545: 共有運用YAMLはcommit前にID集合scopeを二値検査する（cmd_reflux_insight_202608040505_kagemaru）
- L1546: 複数source markerは行順でなくcommit ancestryから単調境界を選べ（cmd_karo_hotfix_ga432_context_freshness）
- L1547: 同一cmd再配備時のreport snapshot世代一致を報告前に検査する（cmd_karo_hotfix_review_bundle_split_subtask）
- L1548: 新規daemon境界では親のlock FD継承を二値検査する（cmd_karo_ci_fix_30852904481_completion_tail_race）
- L1549: 永続contract testはコメントだけでなくtask.test_necessity構造宣言が必要（cmd_karo_hotfix_gist_index_redesign_20260804）
- L1550: 新規tracked hook初回導入はHEAD不存在よりindex所有を先に判定する（cmd_karo_hotfix_gist_post_commit_trigger_20260804）
- L1551: DrvFS frontend fallbackは依存もext4でなければworker stallを防げない（cmd_4228）
- L1552: 成果物commit repoとproject repoの分離をtask契約へ反映する（cmd_4232）
- L1553: Bash caseのYAML tildeは引用して全表現を個別計測する（cmd_karo_hotfix_acknowledged_at_null_20260804）
- L1554: reflux insight生成は注入判定対象のpurpose scalar形式を保持する（cmd_karo_fix_reflux_insight_scope_20260804）
- L1555: RCとarchiveはreport pathの世代transactionとして直列化する（cmd_karo_fix_rc_archive_report_race_20260804）
- L1556: same-cmd pending report symlinkはformal RCと同じreport-unit境界で再生成する（cmd_karo_fix_same_cmd_pending_symlink_20260804）
- L1557: 親子計測は同一event_groupをdurableに持たせる（cmd_karo_round9_lane3_deploy_total_recon_20260804）
- L1558: 明示成果再利用は成果物と最新終端証跡を対で検証する（cmd_karo_fix_scout_report_reuse_gate_20260804）
- L1559: Bats固定抽出はsetup_fileへ分離する（cmd_karo_round8_speed_gate_startup_20260805）
- L1560: commit予約識別子はUSERでなくtmux agent_idを使う（cmd_shogun_commit_reservation_ledger_phase1_20260805）
- L1561: restricted PATH下の既存writer計装はPATH復元をfixtureで守る（cmd_karo_round9_lane0pp_impl_common_20260805）
- L1562: private cache公開前のWAL統合とappend判定snapshot（cmd_karo_round10_lane2_refresh_copy_impl_20260805）
- L1563: context reflux後に到着する外部source commitの自動task化（cmd_karo_recon_context_freshness_ga437）
- L1564: context freshnessはsource path一致だけでなく本文反映要否を分類する（cmd_karo_recon2_ga438_ga439_context_freshness）
- L1565: WARN/BLOCKエスカレーション前に一次情報を再確認し、解消済みなら過去断面のまま裁定要求しない（cmd_karo_recon2_disk_recovery_20260806）
- L1566: reflux inventoryのpromotions指標はledger-reconciliation短絡経路で実値と大きく乖離しうる（cmd_reflux_backlink_202608061239_hayate）
- L1567: reflux_inventory(insights_pending/zero_backlinks/promotions/total)のうちzero_backlinks以外は並行稼働中の他忍者churnが支配的で単体タスクの効果測定に使えない（cmd_reflux_backlink_202608061316_kagemaru）
- L1568: task_type=recon2の commit_contract.required=false 既定分類は、AC自体がcommitを要求する'hotfix型recon2'では実態と乖離する（cmd_karo_hotfix_uncommitted_scripts_20260806）
- L1569: commitタイムアウト時にbypass/他者委任するな（cmd_gunshi_d0_20260807）
- L1570: commit_queue.sh Phase2の全体直列化導入時、既存のwait-based race dedup機構(flock)が黙って機能不全化した（cmd_karo_ci_fix_31076764177_scope_commit_race）
- L1571: reflux inventory事後計測でninja_monitor.sh内部関数を呼ぶ安全な手段が未整備（cmd_reflux_insight_202608071301_hayate）
- L1572: GPトラッカーのdefense_level記載は実装の後発強化を自動追従しない（cmd_reflux_insight_202608071332_tobisaru）
- L1573: insight_write.shのdedupはsource完全一致のため、followup writerがsourceへ内容依存digestを埋め込むと重複insightが際限なく積み上がる（cmd_reflux_insight_202608071355_hanzo）
- L1574: reflux_insight task(AC2:reflux_inventory計測)のrelated_lessons injectionにL968/L134が含まれていない（cmd_reflux_insight_202608071447_kagemaru）
- L1575: GitHub Gists APIの一覧はupdated_at順を提供しない（cmd_karo_gist_reorder_20260807）
- L1576: 偵察専用AC(報告のみ)にtask_type=fullを使うとcommit_contract.required=trueが実態と乖離する（cmd_4240）
- L1577: recalculation_status.modeをSSOT突合せずfull完了と表記しない（cmd_karo_retro_cmd4242_recalc_label_20260809）
- L1578: startup gate移管はalert連鎖の受け皿を先に固定する（cmd_4248）
- L1579: 同一意味論のBLOCKチェックがスクリプト内に独立して複数箇所存在しうる。1箇所の修正だけでは不十分（cmd_karo_hotfix_speed_ninja_scope_commit_r2_20260809）
- L1580: pre-commit全量timeout時のscope commit再開経路（cmd_4250）
- L1581: typed escalationは本文語彙でなくtype境界を正本にする（cmd_4251）
- L1582: reflux判定ではdeploy_taskの実lock pathを現物確認する（cmd_reflux_insight_202608100629_saizo）
- L1583: signal_change_log.dateは対象signal日でありdecision_dateではない（cmd_karo_recon_signal_flush_date_semantics_202608101453）
- L1584: report_publicationは子process合計と未計測残差を分離してから最適化候補を選ぶ（cmd_karo_recon_report_publication_latency_202608101813）
- L1585: helper抽出fixtureと静的契約は実装refactorと同一commit波で同期する（cmd_karo_ci_fix_31431140453_completion_archive）
- L1586: 共有insight YAMLのsafe helperにも世代競合防御が必要（cmd_reflux_insight_202608110625_hanzo）
- L1587: source context update triggerを完了経路へ自動接続する（cmd_karo_hotfix_ga457_context_update_autowire_20260812）
- L1588: RB6配備前提カードはcohort・定義・入力coverageの3項目に固定する（cmd_karo_recon2_ninja_prerequisite_audit_20260814）
- L1589: レビュー品質WARN率は同一cmd_idの終端結果を実装cmd単位で集計し、証拠付き別件FAILを偽陽性としてWARN分子から分離、未終端draftは終端report/verifyまで分母から除外する（cmd_karo_hotfix_review_quality_warn_20260814_normal; source=e8cbaf7eb/9f39c1a07）
- L1590: 外部repo鮮度検査のlesson-only除外と本文cmd ID照合をroot fallbackと共通化する（cmd_karo_recon2_ga463_context_freshness_20260814）
- L1591: 世代境界のtest lifecycle契約をSTALE_FIELDSへ登録する（cmd_karo_hotfix_deploy_stale_test_lifecycle_20260815）
- L1592: context source registryをfreshness detectorのpathspec SSOTにする（cmd_karo_hotfix_ga466_context_freshness_20260815）
- L1593: context freshness起票cmdはregistry owner route update_triggerを保持せよ（cmd_karo_hotfix_ga470_infrastructure_freshness_202608170147）
- L1594: context freshness候補をTOP3で切らず全件をLevel5入力へ保持（cmd_karo_hotfix_ga471_context_freshness_202608170345）
- L1595: rollback後はsource commit境界とlive記述を同時検証する（cmd_karo_hotfix_ga472_context_freshness_202608170955）
- L1596: freshness detectorは全registered ownerの承認receiptを更新要求へ接続する（cmd_karo_hotfix_ga475_context_freshness_20260818）
- L1600: singleflight failure terminalは承認状態世代へ結合する（cmd_karo_hotfix_review_singleflight_rootfix_20260818）
- L1601: Bounded lock rollover preserves active guards and old inode rollback（cmd_karo_hotfix_ninja_monitor_hot_reload_generation_20260818）
- L1602: Freshness cmd checks must resolve the active task before archive publication（cmd_karo_hotfix_ga477_context_freshness_trigger_20260818）
- L1603: 完了境界後のtracked writerは同一publication checkpointへ収束させる（cmd_karo_hotfix_postclear_runtime_publish_202608182010）
- L1604: detached tracked writerはgeneration-bound receipt完了後にterminal snapshotせよ（cmd_karo_hotfix_postclear_runtime_publish_202608182010）
- L1605: 単一target配備CLIでは候補fallback入口を先に定義する（cmd_karo_hotfix_release_ninja_on_done_unarchived_20260818）
- L1606: AC列契約とランキング列契約を同時検証せよ（cmd_4356）
- L1607: source-only三者mergeのbaseはgraph共通祖先でなくsource世代親に結合する（cmd_karo_hotfix_source_only_remote_new_id_202608190023）
- L1608: 実行中に自己更新するshellは入口でsource世代を固定する（cmd_karo_hotfix_gate_self_update_race_202608190202）
- L1609: 収束前にruntime状態をcheckpointし、再試行履歴はlogical identityで畳む（cmd_karo_hotfix_gate_self_update_race_202608190202）
- L1610: 機械可読出力はconsumer接続まで二値検証する（cmd_karo_hotfix_ga479_infrastructure_freshness_202608190450）
- L1611: 入口許容契約を終端publishまで貫通させる（cmd_karo_hotfix_direct_cmd_status_publish_202608190530）
- L1612: 依存閉包refactorでは削除対象のcontract testを同一差分で実走する（cmd_karo_hotfix_inject_seam_contract_missing_202608190548）
- L1613: path prefix除去にlstripを使わない（cmd_karo_hotfix_dotpath_worktree_projection_202608190635）
- L1614: task worktree生成時にscripts/run_tests.shの実行ビットが失われ、run_tests.sh task modeが構造的にBLOCKする（cmd_karo_hotfix_prepush_runtime_speed_202608190621）
- L1615: 共有Git収束はrepo flockと変更予定path限定untracked検査を一体化する（cmd_karo_hotfix_safe_shared_convergence_202608191137）
- L1616: AC前提件数は対応IDで照合してから実装開始する（cmd_karo_hotfix_gate_busy_not_block_202608190642）
- L1617: 共有repo publicationは検査前にsingleflight admissionする（cmd_karo_hotfix_runtime_writer_singleflight_202608191225）
- L1618: run_tests.sh taskモードはtask_worktree_pathがscripts/run_tests.shの実行ビットを保持していないとexternal_scope_no_mapped_testsで誤BLOCKする（cmd_karo_hotfix_git_index_singleflight_202608191445）
- L1619: 生成cacheのSSOT pathは移設可能な相対契約にする（cmd_karo_hotfix_ga484_lesson_health_202608200754）
- L1620: bash経由scriptの能力判定はinvocationに合わせreadable regular fileへ揃える（cmd_karo_hotfix_ga486_bulletin_readability_202608201431）
- L1621: 隔離worktree解決前のstable_id claim/lease照合（cmd_reflux_insight_202608201515_tobisaru）
- L1622: ignored runtime projectionのtracked復活を事前BLOCKするcheck（cmd_reflux_backlink_202608201539_kagemaru）
- L1623: task worktree配備時のshared dirty bytes注入（cmd_karo_hotfix_skill_auto_improve_dirty_202608201637）
- L1624: affected非空選択はengine dispatcherへ接続する（cmd_karo_hotfix_affected_mixed_engine_202608201740）
- L1625: zero-backlink同一targetの重複配備をpre-deployで拒否する（cmd_reflux_backlink_202608201630_saizo）
- L1626: gitignored semantic SSOTをtask worktreeへ注入する（cmd_reflux_backlink_202608201818_kagemaru）
- L1627: gitignored semantic SSOTをtask worktreeへ再現する（cmd_reflux_backlink_202608201856_saizo）
- L1628: context freshness warning must publish the complete candidate set（cmd_karo_hotfix_ga487_context_freshness_20260821）
- L1629: AC成果物とplanned_pathsの不一致を配備時に検出する（cmd_4359）
- L1630: module抽出時の静的抽出互換を維持する（cmd_4364）
- L1631: task-modeは隔離worktreeへabsolute target_pathを射影すること（cmd_karo_hotfix_source_publish_single_truth）
- L1632: External task scope exclusion must be surfaced as a test-run boundary（cmd_4373）
- L1633: Source-equivalent revertは本文差分とboundary更新を分離して自動要求化する（cmd_karo_hotfix_ga493_context_freshness_trigger）
- L1634: behavior不変cmdの業務parity証跡を完了gateで強制する（cmd_karo_hotfix_lsa04_behavior_invariant_full_parity）
- L1635: runtime publishの共有ledger lockはroot mutation区間へ限定する（cmd_karo_hotfix_commit_ledger_single_lock）
- L1636: 分割境界のsource-only定義比較はruntime補助関数まで含める（cmd_4377）
- L1637: gate_metrics model attribution owner fallback（cmd_karo_hotfix_p2_gate_model_attribution）
- L1638: GA-496: 定義済みLevel5 detectorは最終判定callerまで接続する（cmd_karo_hotfix_ga496_context_freshness）
- L1639: CI FAIL artifactはparallel-onlyとstandaloneを直列比較で分離する（cmd_karo_hotfix_cmd4400_stateful_shards）
- L1640: Source boundary classification must remain explicit across ledger producer and gate post-processing（cmd_karo_hotfix_ga498_context_freshness_source_timeout）
- L1641: Race contracts must hold partial records across the observation boundary（cmd_karo_ci_fix_32810257392_compatibility_isolation）
- L1642: FAIL_CLOSEはstale CLEARより先に判定しgeneration一致を要求する（cmd_karo_hotfix_fail_close_worktree_cleanup_20260826）
- L1643: 通知成功とdoc内容反映を同一のdurable receipt契約へ結ぶ（cmd_karo_hotfix_ga499_doc_lane_setter_20260826）
- L1644: CI共有資源fixtureはprotected full-budget境界へ即時反映する（cmd_karo_ci_fix_admission_pending_20260826）
- L1645: 独立Batsセルはbounded parallel化し、空値軸は明示sentinelで結果集約する（cmd_karo_hotfix_cmd4403_batch2set_test_auto_deploy_next_r2_20260826）
- L1646: 非git fixtureのTMPDIRをrepo配下へ置かない（cmd_karo_hotfix_archive_nocode_receipt_r2_20260826）
- L1647: diverged mergeのpath/blob一括検証（cmd_karo_hotfix_converge_no_remote_loss_r2_20260826）
- L1648: 一時repo fixtureはproduction side effectを明示無効化する（cmd_karo_hotfix_t02_insight_prepush_blocker_20260826）
- L1649: 収束時は対象pathをoursとして再適用しremote-only inventoryを検証する（cmd_karo_hotfix_t08_converge_ours_r3_20260827）
- L1650: monitor跨ぎのidle時計はprocess memoryへ置かない（cmd_karo_hotfix_reflux_idle_anchor_20260827）
- L1651: 共有台帳writerは対象path由来の同一lockを使う（cmd_karo_hotfix_rework_capture_gap_20260827）
- L1652: 隔離tmux検証ではTMUX解除と全target変数化が必要（cmd_4407）
- L1653: WSL再起動後のtask_worktree_path staleを正本で検知する（cmd_4408）
- L1654: runtime source chainを含む既定値全数確認（cmd_karo_hotfix_t70_ext4_worktree_root_20260827）
- L1655: 実行bit非依存のreport gate呼出し（cmd_karo_hotfix_report_gate_exec_mode_20260828）
- L1656: 全terminal report publisherへ提出前precheckを接続する（cmd_karo_hotfix_t99_report_precheck_20260828）
- L1657: git-ignore正本を含むtask selectorはmarker-safe一時fixtureで分離検証する（cmd_karo_hotfix_t102_t91_ext4_cutover_complete_20260828）
- L1658: 開始nudgeは初回・再送・直送の全callerを同一task identityへ結ぶ（cmd_karo_hotfix_t114_reflux_task_id_nudge_20260828）
- L1659: 非同期fixtureは最終ログ行でなく子process終了と回収境界を待つ（cmd_karo_ci_fix_33120834061_inbox_delivery_cleanup_20260828）
- L1660: CI並列shardの語彙判定はgrep/localeから分離する（cmd_karo_ci_fix_33122914110_shard_inventory_ledger_r2_20260828）
- L1661: shell unit抽出時はowner testの関数抽出元もmodule正本へ同期する（cmd_karo_hotfix_t107_cmd_complete_split_unit1_20260828）
- L1662: unit分割時はowner testの抽出源もcanonical moduleへ同期する（cmd_karo_hotfix_t107_r2_pre_push_helper_20260828）
- L1663: single wrapperはbatch itemの任意メタデータを明示伝播する（cmd_karo_hotfix_review_bundle_single_precheck_na_20260828）
- L1664: DEBUG計測器は既存trapへ一行counterをinlineする（cmd_karo_hotfix_function_coverage_20260828）
- L1665: inner runner receipt欠落は原因付きterminal FAIL evidenceへ変換する（cmd_karo_ci_fix_33147256383_compat_receipt）
- L1666: source-equivalent回帰fixtureは実repo履歴から分離する（cmd_karo_ci_fix_33156085995_ga505_source_equivalent_20260828）
- L1667: producer接続とFP観測は同一contractで検証する（cmd_karo_hotfix_pending_decision_infra_bundle_20260828）
- L1668: set -e下の任意ログ欠損は明示的に0件扱いする（cmd_karo_ci_fix_33176429634_startup_owner_20260828）
- L1669: Failure detailのbyte capはUTF-8境界安全decodeを必須とする（cmd_karo_hotfix_hook_failure_utf8_boundary_20260829）
- L1670: 9p履歴証跡はsubject/pathを単一git showへ統合する（cmd_karo_hotfix_context_freshness_runtime_speed_v2_20260829）
- L1671: pipefail下のheadはidentity producerの後続出力を失わせる（cmd_karo_ci_fix_33253680471_commander_identity）
- L1672: task runnerの外部worktree dispatchは実行境界を明示する（cmd_karo_hotfix_tmux_live_sendkeys_guard_20260830）
- L1673: doc_no_changelogは一般設計語と履歴語を分離せよ（cmd_karo_hotfix_ga527_doc_no_changelog_20260830）
- L1674: hook_failure改善トリガーはartifact意味分類で意図的安全BLOCKを除外する（cmd_karo_hotfix_ga530_expected_pre_push_block_20260830）
- L1675: CI契約変更時は互換性fixtureの旧期待値を同一commitで同期する（cmd_karo_ci_fix_33298405219_two_shards_20260830）

## 設計標準・テスト・因果

結論: 詳細は `docs/research/infrastructure-design-standards.md` に保存。原文を省略せず移設済み。
見出し: 軍師レビュー効果計測（cmd_1144導入） / ベースライン（導入前） / 導入後計測 / 判定基準（30cmd後） / PD裁定反映（cmd_354同期） / skill_gate_feedback.sh 最適化パターン（cmd_2589, 2026-05-06） / SKILL.md品質基準（7項目チェックリスト） / フロントマター必須フィールド / オプションフィールド / North Star / Diff-aware Testing 方針（GStack/GBrain #26） / 適用判断フロー / CI固有FAIL切り分け手順(ローカル未再現時) / WSL2固有の注意点 / 変更ファイルに関連するテスト特定方法 / 変更ファイルのテストを特定 / 制約（SKIP=FAILルール、Test Rules §1） / DB guard = 語彙一致ではなく操作意図×信頼境界で判定せよ（cmd_karo_hotfix_guard14_db_trust_boundary_202607120854） / 重量テストジョブのhost-wide admission契約（cmd_karo_hotfix_heavy_job_admission_202607121348） / 因果リンク

## 2026-08-26 追加(source=b065d7fc7〜aa9a28e02・夜間ghost陣+承認欠落の根治)

- **tmux二重サーバ(ghost陣)**: WSL再起動後、`/init`直下で自動起動されたtmuxサーバ(826)が、`shutsujin_departure.sh` の後発サーバにsocket(`/tmp/tmux-1000/default`)を奪われ**到達不能のまま生存**。配下ghost家老(codex)がkaro inboxを共有処理し「inboxが届かない/家老が止まっている/影丸の所在不明」の見え方を作った。撤収STEPは `tmux kill-session -t shogun` =socket所有者にしか届かず、**出陣を繰り返すほどghostが積む**。一次確認= `ss -xlp | grep tmux`(サーバPIDが2本=異常)。根治=家老hotfix `queue/handoff/karo_hotfix_ghost_tmux_20260826.md`(AC1 撤収工程の多重サーバ検知+撤収 / AC2 daemon_watchdog ALERT / AC3 826の起動元特定 / AC4 幻スキル参照差替え)。insight INS-20260826-020217534。**AC1実装済(影丸 `e06c2f9dc`, GATE CLEAR 03:57)**: `shutsujin_departure.sh`/`scripts/reset_layout.sh` の撤収工程が同一socket pathの全tmuxサーバを `ss` で列挙し、現owner以外の旧サーバと配下agentを一覧表示。**停止は自動化しない**(D006整合・停止プリミティブ全除去 rg exact=0): 重複検知時は **fail-closed rc=1 で出陣を止め**、停止操作は殿の操作境界に残す。検知0件時は無音。**AC2実装済(疾風 `46d2b8783`)**: `scripts/daemon_watchdog.sh` が同一socket pathのtmuxサーバ重複を検知し、owner照合+dedupe通知でALERT(fixture 9/9)。**AC3真因(将軍一次確認 05:05)**: 外部自動起動は存在せず(影丸偵察: Scheduler/Run/Startup/wsl.conf/systemd unit全て陰性)、WSL再起動直後の `systemd-tmpfiles-setup.service`(21:57:08→22:00:29、`tmp.conf: D /tmp`=boot時削除)が殿の出陣(21:58)で作られた `/tmp/tmux-1000/default` を削除→826到達不能→22:06の `shutsujin -s` が新サーバを作りghost化(物証: `/tmp/tmux-1000` birth=22:00:22、watchdog 22:01〜list-sessions failed)。`/init`が親なのはデーモン再親付けで起動者の証拠ではない。**AC3b実装済(飛猿 `f13550126`)**: 出陣/reset_layout前に tmpfiles-setup がactivating中なら完了を待つガード(fixture 14/14、非systemdは無音rc=0)。**関連(疾風 `464c833c1`)**: `archive_completed.sh` のtracked runtime allowlistへ `queue/session_alerts_shogun.txt` を追加(cmd完了archiveで将軍session_alertsが消えない)。
- `shutsujin_departure.sh`: `log_warn` が2026-03-23から未定義(`log_war`のみ)で、ntfyスモーク失敗/ntfy_inbox_archive失敗の分岐だけ `command not found` になっていた → `b065d7fc7` で定義追加。ntfyスモーク失敗自体はWSL起動直後の一過性。
- `scripts/gates/gate_shogun_startup.sh` 「■ スキル参照実在」新設(`1136fefab`): CLAUDE.md/instructions/*.md の `/skill` 参照に対し `skills/<name>/SKILL.md` 実在をALERT(初回検出= `CLAUDE.md:/reset-layout`、skills削除efc8e016e後の幻参照。deepdive Phase 9「参照パスと実体不一致」同型)。
- `scripts/review_bundle.py`(`2dd1d2a21`): `generate` を単独CLIで `--verdict APPROVE` 実行しただけでは承認(gunshi LGTM=`review_approvals/reports/<key>/gunshi.yaml`)にならない。batch4/5r/6r/7r/8rで軍師がgenerateのみ実行→承認欠落→家老gate5件が `review_two_phase_pending` でBLOCKした実証。以後、直接CLIのAPPROVEでLGTM未記録なら **rc=3 fail-closed+NEXT(`review_bundle.py single`)を名指し**。正規入口は `/review-bundle`(Step 1=`single`)。`review_approval.sh gunshi LGTM` 直接実行は構造的拒否(rc=2)。
- `scripts/review_bundle.py`(`aa9a28e02`): 忍者taskがidle化した後の報告身元照合は家老inboxの受領receiptで行うが、報告timestampが**UTC(`...Z`)**だと探索日が**JST命名の `archive/inbox/karo_YYYYMMDD.yaml`** と1日ずれてreceiptを見失う(batch6r saizo実証: ts=08-25T16:43Z→karo_20260825を探すがreceiptはkaro_20260826)。receipt探索を全日付archive(新しい順)へ拡張。fingerprint/report_id/path完全一致は維持。
- バッチらせん#2〜#8実績(一次実測・`docs/research/cmd_4403_slowest_tests_speedup_20260825.md`): #2 79.9→67.6s / #3 87.5→72.6s(AC2 timeout BLOCK) / #4 20.1→9.2s / #5r 87.6→48.8s / #6r 630→586s+phase receipt常設(支配=checks_main.quality_gate) / #7r 142.7→61.3s / #8r 169.2→76.9s。初回#5/#7/#8は**timing正本≠live実測(−44〜−50%)でAC1どおり実装せず停止**→次セット選別は各弾後に正本を再計測してから行う。
- 報告scopeの正本=source-generation SSOT(飛猿 `7d9532b12`, `scripts/lib/review_source_context.py`+`gate_report_format.sh`): 報告の変更scopeはisolated worktreeの生成源で検証し、primary(共有main)のdirty混入を排除する。**merge commit注意(将軍 `64025b9d4`)**: 所有パス検査の `git diff-tree` に `-m --first-parent` が無いとmerge commit(親2+)は変更0件扱いになり、履歴分岐統合taskが構造的にFAILする(実証0→15 files)。全repo target(`target_path: <repo root>`)のtaskは知識/台帳の恒常dirty(lessons/insights/semantic-index等)が『未commit変更あり』BLOCKになるため、統合前にscope commitで退避する。
- 報告timestampはJST(`+09:00`)で書け(UTC `Z` は上記の日付ずれの発生源)。恒久解はreport-writeテンプレのtimestamp生成側で統一する(未実装=次ターゲット)。

## 2026-08-15 追加ガード(source=253afbb2c以降)

- `scripts/inbox_write.sh` speed_guard(将軍→家老委任に一括実装命令/層ごとGATE・報告YAML・レビュー/新規テスト・contract test・fixture・pytest全量があればBLOCK)+three_layer_guard(将軍→家老task_assignedに`[MEM:`引用なければBLOCK)。
- `scripts/hooks/git-pre-commit.sh` に `tobe_no_line_numbers`(WARN)と `doc_no_changelog`(BLOCK: docs/research/*.md の見出し/行頭に変更履歴)。
- 契約: 小さく1手・儀式なし・パイプライン(instructions/shogun.md・karo.md・generated同期)。

## 2026-08-27 追加(source=57b40cf9a〜06ddbc988・孤児テスト増殖の根治+偵察報告契約の分離)

- **孤児テスト増殖(00:50-02:48実測)**: `tests/unit/test_heavy_job_admission.bats` の singleflight-orphan ケースが内側 `run_tests.sh unit` を生かしたまま終了し、古い task worktree(seed 未是正版)から実 suite を再帰起動→root 27・bats-exec-suite 32本・load 66・`/tmp` fixture lock 1359個・global flock 競合(家老 commit helper 待ち・deploy 397秒 timeout・三層preflight timeout→将軍封鎖)。停止は D006 ゆえ殿が実行 → `docs/research` 相当の経緯は `queue/shogun_todo_map.md` T39
- **検知**: `scripts/gates/gate_shogun_startup.sh` Gate 10.07 長時間bats検知(etimes>1800 の bats-exec-suite/file を WARN 列挙、3fa443c11)
- **回収**: `scripts/orphan_test_reap.sh`(ps 1回スナップショットで親=/init のテスト樹を再帰展開、dry-run 既定、`--kill` は殿実行、`EXTRA_PATTERN` で古 worktree 由来も対象。pgid 単位 kill では `heavy_job_admission.sh` が新 pgid を切り子孫が残る)
- **発生側根治(cmd_4405 8c09923f8)**: `scripts/run_tests.sh` に `trap run_tests_cleanup_children EXIT`(子孫回収)+fixture suite root 固定(fixture 起動が実 suite へ再帰しない)。回帰 bats あり
- **偵察報告契約の分離(cmd_4406 06ddbc988)**: `scripts/gates/gate_report_format_main.py` で task_type recon/scout/recon2 は commit/investigation 契約を免除し finding(観測・結果・根拠パス)必須。監査=`scripts/gates/recon_report_contract_audit.md`(FAIL 557件/240報告の理由別内訳)。実装報告は従来契約維持
- **deploy 遅延の隠れ要因**: `.git/worktrees` stale metadata(実体不在 624/724)で `git worktree add` が全走査→deploy 397秒。`git worktree prune` で 724→103(deploy 199秒)。自動化=小太郎 karo_hotfix(ninja_monitor 周期 prune+deploy 前件数ログ)で走行中
- **GitHub Actions 補足**: queued 40分超・cancel-in-progress の想定と逆の cancel が発生。家老が exact-sha `workflow_dispatch`(ff0f95ad1)で突破。CI GREEN 復帰=run 32999064580 @8c09923f8


## 2026-08-27 追加(source=5f8aea006〜c6e823181・リポジトリ本体を 9p(/mnt/c)から ext4(/home)へ移設)

- **正本パス変更(cutover 22:00:15)**: `/mnt/c/tools/multi-agent-shogun`(drvfs/9p)→ **`/home/simokitafresh/multi-agent-shogun`**(ext4)。旧ツリーは印 `MIGRATED_TO_EXT4.txt`(READ_ONLY=true、chmod は行わない marker 方式)。crontab・auto-memory 鍵ディレクトリ(`~/.claude/projects/-home-simokitafresh-multi-agent-shogun/`)・tmux 全 pane cwd は新パス。Windows からは `\\wsl$\Ubuntu\home\simokitafresh\multi-agent-shogun`、Android は Project Path を新パスへ。手順・欠陥2件(rsync が clone commit を巻き戻す/pane 判定が CLI 末尾形状で BLOCK)の正本 → `docs/research/9p_root_fix_runbook_20260827.md` §3/§4.2。script=`scripts/migrate_to_ext4_{relocate,cutover,rollback}.sh`(cmd_4408 b487c998f、hotfix f6348f9fa/5f8aea006、置換 commit e644881f5)
- **根拠(殿下問 13:50)**: D-state p9_client_rpc 9 プロセス、`git status` 60-120s、push timeout 3回/日、compat bats TAP 0行/30分=9p RPC が git/flock/stat の律速。
- **効果(半蔵 T87 実測、各3回)**: publish_total 3770→227ms(−94%)、ninja_scope_commit git_commit 9487→173ms(−98%)/scope_sync 5846→73ms、`git status` 84ms、実 push 1.1s、deploy_task 配備 wall 199-397s→22s。残る律速=実 push 1132ms/publish 外側 604ms → `docs/research/ext4_speed_rebaseline_20260827.md`。旧 T60/T12(9p 上の値)は前提消失で終了。
- **移設で顕在化した副作用**: (1)旧ツリーの stale `_cmd_*_ready.yaml` が最終 rsync で復活(退避は rsync 後に再適用、T86/T90) (2)CI shard7 quality-lock test がパス依存で receipt 欠損 → 小太郎 ci_fix c6e823181「path independent」 (3)`config/cli_events.yaml` 旧パス 8 件(消費者 0)・`~/.codex/config.toml` hooks.state 旧キー 7 件(新 path trust :23 実在)=無害、掃除+起動 gate に旧パス残存 grep を追加予定(T91) (4)`/mnt/c/Python_app/DM-signal` は 9p のまま=次の移設候補(同手順)。
- **task worktree の永続化(T70、影丸 hotfix b5f586933)**: `scripts/deploy_task.sh` と `scripts/deploy_task/preflight.sh` の `DEPLOY_TASK_WORKTREE_ROOT` 既定 `/tmp/shogun-task-worktrees` → `/home/simokitafresh/shogun-task-worktrees`(env 明示時は尊重)。回帰=`tests/unit/test_task_worktree_lifecycle.bats`。理由: WSL 再起動で /tmp が消え 14:54 に task worktree 11 本が消失(未 commit 作業の再実装リスク)。
- **cmd_complete_gate.sh 分割設計(T83、才蔵抽出)**: 15,030 行→17 lib unit・契約 test 43 の所有表 → `docs/design/cmd_complete_gate_split_design_20260827.md`(実装は次 cmd、deploy_task 分割 J と同型)。
- **first_setup.sh の初回認証案内+安全 dry-run(T109、才蔵 991343278)**: `bash first_setup.sh --dry-run` は副作用なしで Codex 認証手順(`codex login --device-auth`/`codex login status`)を表示し、repo が `/mnt/c`(9p)配下なら ext4 配置を警告(runbook `docs/research/9p_root_fix_runbook_20260827.md`)。README/README_ja Quick Start に同行を追記(18ec6721f)。将軍の下知誤り(target を `scripts/first_setup.sh` と誤記→才蔵が前提差異で正しく停止→r2)=型4弾-1「書いたら grep」は下知本文の path にも適用
- **runtime lane の origin 直 push 廃止(T100、半蔵 88969097a)**: `cmd_complete_gate.sh` の runtime publish(postclear field-aware/insights auto-commit/autopush)は origin へ直接 push せず shared main の field-aware commit のみ(直 push 実体 L3166 の caller 0、postclear log に rev-list 観測点)。push は家老の first-parent 1 本ずつ経路へ一本化。根拠=08-27 再分岐 6 回・08-28 2 回(毎回 converge)。本番 proof=以後の postclear で `git rev-list --left-right --count origin/main...HEAD` の左辺 0。★注意: postclear field-aware publish(e8ed1e8f0)が本節の T109 行を一度消した=将軍 doc lane の書換えが runtime 書換えで失われる型(型4弾-1 の原因)
- **DOC_LANE_REQUEST source_equivalent の自動終端(T108、小太郎 c092febfc)**: `gate_context_freshness.sh` が reason=source_equivalent を将軍へ通知せず、source_commit が対象 repo で rev-parse 可能かつ origin/main 祖先なら gate 内で `context_source_commit_set.sh` を実行し掲示板 `DOC_LANE_INFO` 1 行で閉じる。非祖先/不在 commit は WARN のみ(request を出さない)。approved_source_commit(内容反映が要るもの)のみ将軍通知を維持。根拠=本日 04:24-05:45 に旧 commit 4 件+不在 1 件の request を将軍が手回し(INS-054618999/055343134/062706432)。本番 proof=次周期以降の将軍 inbox への source_equivalent 到達 0
- **cmd_complete_gate.sh 分割の第 1 弾(T107、飛猿 c15453e33 + 半蔵 49e32bd31)**: `scripts/lib/cmd_complete_gate_ci.sh` へ CI unit を抽出(15023→14522 行、−501)。抽出 unit に bash shebang が無く CI `Shell Script Linting` のみ RED(run 33132419327)→半蔵 ci_fix で shebang 追加(49e32bd31)。教訓: `scripts/lib/*.sh` 新設時は shebang+shellcheck を所有 test に含める。分割設計=`docs/design/cmd_complete_gate_split_design_20260827.md`(17 unit)、次弾は unit 2〜17 を 1 unit ずつ家老自立 hotfix。★後続: shebang ci_fix の push 後 `Build Instructions Check` のみ RED(4 回目の別根)=instructions/generated/.build_cache/*.cache が CLAUDE.md/AGENTS.md 変更(89510dbaa)後に未再生成→疾風 ci_fix 0f843cab5 で cache 3 本を refresh。教訓: CLAUDE.md/AGENTS.md/instructions を編集した commit は同一 commit で generated cache を再生成する(`bash scripts/ninja_scope_commit.sh` の対象に .build_cache を含める)

## 2026-08-28 追加(source=091981ab5〜a3e312e2a・便停止の根治群+本番 queue 汚染+gate 構造バグ 2 件の着手)

- **ninja_monitor 入口ガード反転(T151、将軍 D0 091981ab5)**: 825ceeaa7 で L46 の否定 `!` が欠落し `--lifecycle-worker`/`--check-and-update-done-task` を usage+exit 64 で拒否(19:26-19:41 rc=64 171 行、AUTO-DONE/check_stall 全滅)。修正後 0 行。hot script は temp→`bash -n`→mv。
- **lifecycle worker の argv 欠落(T159、影丸 885c739b0)**: `repair_terminal_report_outboxes` の background 化(009ecdd87)で callsite が key のみを渡し worker 関数名が空→毎 cycle rc=64。REASON 計装(b8b9439a0)が 1 cycle で `args=--lifecycle-worker <空> argc=2` を名指し→1 token 修正。手動再現 4 通り(通常/daemon PATH/daemon env/exported 関数)は全て rc=0=daemon の**呼出形(argv)**まで再現しないと出ない(型八弾-2『環境+trap』に argv を追加)。
- **忍者 bats の本番 root 実行で本番 queue が消える(T157、半蔵 c02ca5426+a2bd411ea)**: 半蔵 ci_fix が `REPO_ROOT="$PWD"` で bats を走らせ fixture report(cmd_bounded_done_check)が本番 queue/reports に現れ、20:43 影丸 task YAML 消失(便欠落 3 例目、`.pre_rc_snapshot` から復元)。根治=fixture root 隔離(tests/unit 5 本)+`scripts/run_tests.sh` の `run_tests_queue_root_guard()`(fixture root が本番 queue を解決したら exit 2)。将軍側=`gate_shogun_startup.sh`『■ 本番 queue 汚染(fixture 由来)』節(c54380824/faae86e02: fixture id の report/task 件数+直近 2h『task file missing』行数)。**注意**: `set -e` script 内の `$(… | grep -c)` は 0 件で exit 1→gate 全体が黙って死ぬ=必ず `|| true`。
- **待ちを BLOCK で表現する gate 構造(T160、半蔵 gate_wait_state 走行中)**: 本日 GATE BLOCK 49 件中 39(80%)が `report_commit_main_ancestry` 25/`review_two_phase_pending` 10/`throughput_segment_invalid` 4=忍者の品質と無関係な順序・到達待ち。設計=WAIT 状態+自動再 GATE、BLOCK は契約違反(report_format/files_modified/ac_version)のみ。殿裁定 22:31『バグは即時根治せよ』。
- **実装 AC と本番 proof の分離(T161、小太郎へ予約)**: 本番 push/live 後でしか計測できない AC(1h 窓/CTX-RESET/FALLBACK 0)を task AC に混ぜると人質化(T140)・RC 中 auto clear で成果消失(T152)・live 後失敗の取りこぼし(T159)。設計=task YAML `production_proof:` 節を deploy_task が分離格納、GATE は実装 AC のみ、monitor が窓満了で PROOF-PASS/FAIL 行(FAIL は将軍 inbox)。
- **inbox 優先 guard×証跡必須の循環(T162、小太郎 hotfix 走行中)**: `codex_inbox_priority_guard`(T30)が証跡作成 command まで BLOCK し `inbox_mark_read` の証跡必須と循環=家老が inbox を読めない。fail-closed guard は解除行動を許可リストへ。
- **run_tests runner fixture の構造 writer 依存(CI RED 10/11 回目、疾風 a3e312e2a+飛猿 f8adbd091)**: `tests/unit/test_run_tests.bats` の runner fixture に structural writer 依存を copy(shard 1/4/6/compat)、startup owner fixture(飛猿)。ci_fix は家老自立で 2 unit 並列。
- **報告在庫の便欠落(T158)**: forced_idle 世代の report(影丸 reflux 0158 19h/runner_portability 20h/才蔵 1530 6h50m)が gate_metrics 0・archive 0 で滞留。回収は将軍 loop の『completed∧未CLEAR(本日 mtime)』機械抽出→順序付き 1 通。構造根治は T124 INS(forced_idle は report 実在 task を idle 化しない)。
- **artifact のスマホ表示(殿指摘 22:56/23:22)**: `table-layout:fixed`+全要素 `overflow-wrap:anywhere`+`.wrap-x{overflow-x:visible}` で 1 文字折返し。是正=表は自コンテナ横スクロール、本文 `word-break:normal`、48rem 以下は `.row{display:block}`(grid 列を弄らず block へ落とす)。
