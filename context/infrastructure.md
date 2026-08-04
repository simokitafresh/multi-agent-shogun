# インフラコンテキスト
<!-- last_updated: 2026-08-04 cmd_karo_hotfix_ga432_context_freshness reviewed source boundary -->
<!-- source_commit:515f0214e reason:cmd_karo_hotfix_ga432_context_freshness reviewed source boundary evidence:cmd_complete_gate project=infra context=context/infrastructure.md commit=515f0214e -->
<!-- source_commit:23a1ce61205ce4496ab11570583e8e8adcaeac4e reason:reflux backlink SSOT update reviewed evidence:incoming 0 to 1; runner69/69; target doc diff0 -->
<!-- last_synced_lesson: L1550 -->

結論: 本ファイルは検索起点となる索引層。運用詳細・経緯・教訓本文は7つの詳細正本へ移設した。
参照: 見出し名を `rg` し、該当する詳細ファイルを読む。全見出し対応は `docs/research/infrastructure-section-manifest-20260801.yaml` が正本。

## コンテキスト・記憶・品質基盤

結論: 詳細は `docs/research/infrastructure-context-memory.md` に保存。原文を省略せず移設済み。
見出し: インフラコンテキスト / コンテキスト管理 / 2026-07-24インフラ修正バッチ(cmd_4154-4164) / lord_conversation / 記憶DBデータフロー（cmd_2963〜cmd_3032） / 三層記憶×学習ループ接続（cmd_3116〜cmd_3128, 2026-06-02） / 直近改善（cmd_181〜cmd_541） / 直近改善（cmd_602〜cmd_612） / 直近改善（cmd_875〜cmd_878） / 直近改善（cmd_1039〜cmd_1120） / 直近改善（cmd_3300〜GA-050） / 軍師品質管理ユニット（cmd_1144〜cmd_1181） / 偵察デフォルト品質5要件（cmd_754+cmd_1476） / 直近改善（cmd_1532〜cmd_1543） / 直近改善（2026-04-16〜2026-04-30 CoDD波 / GP-198〜240）

## 配備・CLI・自動化基盤

結論: 詳細は `docs/research/infrastructure-agents-delivery.md` に保存。原文を省略せず移設済み。
見出し: deploy_task.sh --direct mode（cmd_1672） / /henseiスキル（cmd_1673） / Claude CLIモデル指定とコンテキスト（ci_fix_200k） / Codex multi-CLI統合(2026-05-11確立) / 直近24日間の主要裁定/実装（2026-05-01〜2026-05-24） / Claude Code バージョン固定と復帰 / 忍者個別弱点自動注入（cmd_1307） / gate強化（cmd_1178〜cmd_1180） / 知識サイクル現状（cmd_531/533/541/1111/1113/1117 反映） / 稼働中の仕組み / 現行メトリクス（2026-03-30時点） / 設計思想 / SessionStart hook — startup gate自動実行（cmd_2683） / 二重配備防止3層防御（cmd_2681/2682/2684） / 暗黒物質Phase 2: 高優先度60関数（cmd_2777） / ninja_monitor.sh: 状態管理・配備・監視・自動化（26件） / deploy_task.sh: 注入・ゲート・配備制御（20件） / inbox_write.sh: メッセージ管理・重複検出（9件） / cmd_save.sh: 品質ゲート補助（5件） / ninja_monitor.sh / inbox_watcher.sh / ntfy.sh / ログローテーション / field_deps.tsv

## プラットフォーム運用

結論: 詳細は `docs/research/infrastructure-platforms-operations.md` に保存。原文を省略せず移設済み。
見出し: tmux設定 / Claude Code マルチアカウント管理（cmd_313偵察） / Google Workspace CLI (gws) — 全PJ共通ツール / Render運用（cmd_2824, 2026-05-17） / プラン別挙動 / 障害切り分け手順 / 全サービス一覧 / WSL2固有 / 競合調査 / Android App / 記憶DBバックアップ棚卸し（cmd_3869） / DM-Signal outputs陳腐化中間成果物削除（cmd_3871） / `/mnt/c`残量の事前検知（cmd_3875） / 防御機構スループット棚卸し（cmd_4059） / 外れ値型防御checkの発生条件（cmd_4185） / DM-signal outputs陳腐化成果物削除（cmd_3871, 2026-07-24）

## 教訓索引 A（配備・gate）

結論: 詳細は `docs/research/infrastructure-lessons-deploy-gates.md` に保存。原文を省略せず移設済み。
見出し: テスト方針（全PJ共通・殿裁定2026-07-19） / Infra教訓索引 / カテゴリ別索引（L051-L466）

## 教訓索引 B（git・test）

結論: 詳細は `docs/research/infrastructure-lessons-git-testing.md` に保存。原文を省略せず移設済み。
見出し: 前節「Infra教訓索引」の連続本文（source lines 1301-1700）。

## 教訓索引 C（review・operations）

結論: 詳細は `docs/research/infrastructure-lessons-reviews-operations.md` に保存。原文を省略せず移設済み。
見出し: 前節「Infra教訓索引」の連続本文（source lines 1701-2123）。
- L1503: 既存legacy欠損は不変multisetで隔離せよ（cmd_karo_hotfix_shared_operational_log_ownership_20260801）
<!-- last_synced_lesson: L1550 -->
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

## 設計標準・テスト・因果

結論: 詳細は `docs/research/infrastructure-design-standards.md` に保存。原文を省略せず移設済み。
見出し: 軍師レビュー効果計測（cmd_1144導入） / ベースライン（導入前） / 導入後計測 / 判定基準（30cmd後） / PD裁定反映（cmd_354同期） / skill_gate_feedback.sh 最適化パターン（cmd_2589, 2026-05-06） / SKILL.md品質基準（7項目チェックリスト） / フロントマター必須フィールド / オプションフィールド / North Star / Diff-aware Testing 方針（GStack/GBrain #26） / 適用判断フロー / CI固有FAIL切り分け手順(ローカル未再現時) / WSL2固有の注意点 / 変更ファイルに関連するテスト特定方法 / 変更ファイルのテストを特定 / 制約（SKIP=FAILルール、Test Rules §1） / DB guard = 語彙一致ではなく操作意図×信頼境界で判定せよ（cmd_karo_hotfix_guard14_db_trust_boundary_202607120854） / 重量テストジョブのhost-wide admission契約（cmd_karo_hotfix_heavy_job_admission_202607121348） / 因果リンク
