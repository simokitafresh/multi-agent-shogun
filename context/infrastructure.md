# インフラコンテキスト
<!-- last_updated: 2026-08-01 -->
<!-- last_synced_lesson: L1502 -->

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
<!-- last_synced_lesson: L1504 -->
- L1504: appendとarchiveはreaderを含むgeneration transactionにせよ（cmd_karo_hotfix_gunshi_cs_remediation_generation_20260801）

## 設計標準・テスト・因果

結論: 詳細は `docs/research/infrastructure-design-standards.md` に保存。原文を省略せず移設済み。
見出し: 軍師レビュー効果計測（cmd_1144導入） / ベースライン（導入前） / 導入後計測 / 判定基準（30cmd後） / PD裁定反映（cmd_354同期） / skill_gate_feedback.sh 最適化パターン（cmd_2589, 2026-05-06） / SKILL.md品質基準（7項目チェックリスト） / フロントマター必須フィールド / オプションフィールド / North Star / Diff-aware Testing 方針（GStack/GBrain #26） / 適用判断フロー / CI固有FAIL切り分け手順(ローカル未再現時) / WSL2固有の注意点 / 変更ファイルに関連するテスト特定方法 / 変更ファイルのテストを特定 / 制約（SKIP=FAILルール、Test Rules §1） / DB guard = 語彙一致ではなく操作意図×信頼境界で判定せよ（cmd_karo_hotfix_guard14_db_trust_boundary_202607120854） / 重量テストジョブのhost-wide admission契約（cmd_karo_hotfix_heavy_job_admission_202607121348） / 因果リンク
