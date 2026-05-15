---
codd:
  node_id: test:acceptance-criteria
  type: test
  depends_on:
  - id: req:script:cmd-save
    relation: derives_from
    semantic: governance
  - id: req:script:deploy-task
    relation: derives_from
    semantic: governance
  - id: req:script:inbox-write
    relation: derives_from
    semantic: governance
  - id: req:script:ninja-monitor
    relation: derives_from
    semantic: governance
  - id: req:script:dashboard-auto-section
    relation: derives_from
    semantic: governance
  - id: req:script:restart-watchers
    relation: derives_from
    semantic: governance
  - id: req:deploy-task-refactor-requirements
    relation: derives_from
    semantic: governance
  depended_by:
  - id: design:system-overview
    relation: constrained_by
    semantic: governance
  - id: test:test-strategy
    relation: depends_on
    semantic: governance
  conventions:
  - targets:
    - module:inbox_write
    - module:cmd_save
    - module:deploy_task
    - module:yaml_helpers
    reason: flock-based atomic YAML writes and inbox-path-only communication are release-blocking
      safety constraints across all agent-facing scripts (SR-3 inbox_write, SR-1 deploy_task,
      SR-3 cmd_save).
  - targets:
    - module:yaml_helpers
    - module:deploy_task
    reason: API backward compatibility for yaml_field_set and field_get and zero test
      regressions are release-blocking for the batch refactor (refactor constraints).
  - targets:
    - module:inbox_write
    reason: Ninja-to-shogun direct messaging prohibition is a release-blocking routing
      constraint (SR-2 inbox_write).
  modules:
  - cmd_save
  - deploy_task
  - inbox_write
  - ninja_monitor
  - dashboard_auto_section
  - restart_watchers
  - yaml_helpers
---

# Acceptance Criteria

## 1. Overview

本ドキュメントは、multi-agent-shogun インフラストラクチャの中核スクリプト群に対する受入基準を定義する。対象モジュールは以下の7つ:

| モジュール | スクリプト | 責務 |
|-----------|-----------|------|
| cmd_save | `scripts/cmd_save.sh` | 将軍コマンドの品質ゲート（BLOCK/WARN/PASS判定） |
| deploy_task | `scripts/deploy_task.sh` | 忍者へのタスクYAML配備＋inbox通知 |
| inbox_write | `scripts/inbox_write.sh` | エージェント間メールボックスの原子的書込み＋wake-up |
| ninja_monitor | `scripts/ninja_monitor.sh` | tmux陣形監視デーモン（idle/stall/pane loss検知） |
| dashboard_auto_section | `scripts/dashboard_auto_section.sh` | dashboard.md自動セクション生成 |
| restart_watchers | `scripts/restart_watchers.sh` | inbox_watcherデーモンの一括再起動＋検証 |
| yaml_helpers | `scripts/lib/yaml_field_set.sh`, `scripts/lib/field_get.sh` | YAML原子操作ユーティリティ（batch含む） |

**リリースブロッキング制約（Non-negotiable Conventions）:**

| ID | 制約 | 対象モジュール | 検証方法 |
|----|------|---------------|---------|
| NNC-1 | flock-based atomic YAML writes — 全キューファイル操作はflock排他ロックを使用 | inbox_write, cmd_save, deploy_task, yaml_helpers | 並行書込みテストでデータ消失ゼロを確認 |
| NNC-2 | inbox-path-only communication — エージェント間通信はinbox_write.sh経由のみ | inbox_write, deploy_task, ninja_monitor | direct tmux send-keys によるメッセージ送信がないことを確認 |
| NNC-3 | ninja-to-shogun direct messaging prohibition — 忍者からshogunへの直接メッセージはBLOCK | inbox_write | 忍者senderでshogunターゲット指定時にエラー終了を確認 |
| NNC-4 | yaml_field_set / field_get API backward compatibility — 既存シグネチャの完全互換維持 | yaml_helpers, deploy_task | 既存テスト全PASS＋新batch関数追加後も旧API動作不変 |
| NNC-5 | zero test regressions — リファクタリング前後でテスト結果が同一 | deploy_task, yaml_helpers | 48テスト(ac_handling)全PASS、SKIP=0 |

### Traceability Matrix

以下に全依存ドキュメントから抽出した検証可能動作とテストシナリオの対応を示す。

| ID | 検証可能動作 | 出典 | テストシナリオ |
|----|-------------|------|--------------|
| VB-CS-01 | cmd_*形式/数値形式のID正規化＋shogun_to_karo.yamlからのブロック読込 | cmd_save FR-1 | AC-CS-01 |
| VB-CS-02 | YAML構文エラー検出 | cmd_save FR-2 | AC-CS-02a |
| VB-CS-03 | 存在しないcmd IDの拒否 | cmd_save FR-2 | AC-CS-02b |
| VB-CS-04 | delegated状態のcmdへの変更拒否（不変性） | cmd_save FR-2, SR-2 | AC-CS-02c |
| VB-CS-05 | pending状態の既存cmdが存在する場合の検出 | cmd_save FR-2 | AC-CS-02d |
| VB-CS-06 | アーカイブ重複検出 | cmd_save FR-2 | AC-CS-02e |
| VB-CS-07 | 同時ドラフト競合検出 | cmd_save FR-2 | AC-CS-02f |
| VB-CS-08 | quality_gateフィールド検証（BLOCK/WARN履歴あり時のdiagnosis/environment-change要求） | cmd_save FR-3 | AC-CS-03 |
| VB-CS-09 | BLOCK/WARN/PASSの品質ログ記録 | cmd_save FR-4 | AC-CS-04 |
| VB-CS-10 | セッション状態ファイル更新 | cmd_save FR-4 | AC-CS-04 |
| VB-CS-11 | ロック競合警告 | cmd_save FR-5 | AC-CS-05a |
| VB-CS-12 | 未コミット実装変更警告 | cmd_save FR-5 | AC-CS-05b |
| VB-CS-13 | 重複GP番号警告 | cmd_save FR-5 | AC-CS-05c |
| VB-CS-14 | 偵察/recon重複の軍師分析検出 | cmd_save FR-5 | AC-CS-05d |
| VB-CS-15 | bulletin action追跡更新 | cmd_save FR-6 | AC-CS-06 |
| VB-CS-16 | ゲートpending/blocked時の委任拒否 | cmd_save SR-1 | AC-CS-07 |
| VB-CS-17 | flock+構造化チェックによる共有キューファイル保護 | cmd_save SR-3 | AC-CS-08 |
| VB-DT-01 | 通常/--direct/--yaml/--cmdモード解析 | deploy_task FR-1 | AC-DT-01 |
| VB-DT-02 | デフォルトメッセージによるstaleコンテキスト無効化 | deploy_task FR-1 | AC-DT-01 |
| VB-DT-03 | 第1位置引数の忍者名バリデーション（空/None/cmd_*拒否） | deploy_task FR-2 | AC-DT-02 |
| VB-DT-04 | tmux/CLIヘルパーによるターゲットペイン解決＋idle/busy判定 | deploy_task FR-3 | AC-DT-03 |
| VB-DT-05 | staleタスクフィールド/通知フラグ/ghost None.yamlリセット | deploy_task FR-4 | AC-DT-04 |
| VB-DT-06 | 親cmdからタスクメタデータ（AC/ACバージョン/教訓/意味概念/工学設定/実行制御）解決 | deploy_task FR-5 | AC-DT-05 |
| VB-DT-07 | queue/reports/下のレポートテンプレート生成（既存完了レポート上書き禁止） | deploy_task FR-6 | AC-DT-06 |
| VB-DT-08 | inbox_write.sh経由のタスク通知配信 | deploy_task FR-7 | AC-DT-07 |
| VB-DT-09 | 同一親cmdの完了済みピアレポート存在時の重複配備BLOCK | deploy_task SR-2 | AC-DT-08 |
| VB-DT-10 | YAML helpers使用（free-form YAML dump禁止） | deploy_task SR-1 | AC-DT-09 |
| VB-IW-01 | target/content/type/sender/actionフィールド受理＋不正ターゲット拒否 | inbox_write FR-1 | AC-IW-01 |
| VB-IW-02 | ターゲットエージェント検証＋sender routing（ninja→shogun禁止） | inbox_write FR-2, SR-2 | AC-IW-02 |
| VB-IW-03 | queue/inbox/{agent}.yamlへのメッセージシリアライズ（timestamp/id/type/sender/content/read/action） | inbox_write FR-3 | AC-IW-03 |
| VB-IW-04 | WSL2 /mnt/*パス対応ロックファイルによる並行書込み保護 | inbox_write FR-4, SR-3 | AC-IW-04 |
| VB-IW-05 | 同一親cmdの重複task_assigned配備BLOCK | inbox_write FR-5 | AC-IW-05 |
| VB-IW-06 | deploy未注入時の教訓注入セーフティネット | inbox_write FR-6 | AC-IW-06 |
| VB-IW-07 | レポート通知時のフォーマットチェック＋下流レビュー/完了トリガー | inbox_write FR-7 | AC-IW-07 |
| VB-IW-08 | メッセージ永続化後のペイン解決＋CLI nudge送信 | inbox_write FR-8, SR-1 | AC-IW-08 |
| VB-NM-01 | シングルトンデーモン起動＋tmuxメタデータからのペイン再発見 | ninja_monitor FR-1 | AC-NM-01 |
| VB-NM-02 | @agent_state/タイムスタンプ/CLI prompt/busy pattern/subprocess相互検証によるidle/busy判定 | ninja_monitor FR-2 | AC-NM-02 |
| VB-NM-03 | idle確認＋report-gateチェック後のclear/respawn | ninja_monitor FR-3, SR-2 | AC-NM-03 |
| VB-NM-04 | pane loss/stale deployment/未配備cmd/karo pending/CLI death/inbox unread/report-task mismatch検知 | ninja_monitor FR-4 | AC-NM-04 |
| VB-NM-05 | karo_snapshot.txt生成（cmd/忍者/model/context/report state） | ninja_monitor FR-5 | AC-NM-05 |
| VB-NM-06 | inbox watcher/ntfy listener/CI status/training auto-deploy/lesson health/loop health/workaround trends/script size trends監視 | ninja_monitor FR-6 | AC-NM-06 |
| VB-NM-07 | hook state優先＋busyエビデンスなしのidle判定禁止 | ninja_monitor SR-1 | AC-NM-07 |
| VB-NM-08 | inbox_write.sh経由の通信（ad hocパス禁止） | ninja_monitor SR-3 | AC-NM-08 |
| VB-DA-01 | 6データソース読込（karo_snapshot/shogun_to_karo/gate_metrics/tasks/*.yaml/settings/cli_profiles/gate_fire_log/lesson_impact/lesson_effectiveness_status） | dashboard FR-1 | AC-DA-01 |
| VB-DA-02 | 5外部スクリプトサブプロセス呼出し（knowledge_metrics/model_analysis/context_freshness/ci_status/skill_metrics） | dashboard FR-2 | AC-DA-02 |
| VB-DA-03 | 10出力セクション生成 | dashboard FR-3 | AC-DA-03 |
| VB-DA-04 | --dry-runモード（stdout出力＋dashboard.md不変） | dashboard FR-4 | AC-DA-04 |
| VB-DA-05 | auto-sectionマーカー外コンテンツ保全 | dashboard FR-5 | AC-DA-05 |
| VB-DA-06 | CLEAR数増加時のみntfy通知（重複排除） | dashboard FR-6 | AC-DA-06 |
| VB-DA-07 | 将軍宛報告セクションの取消線エントリ除去 | dashboard FR-7 | AC-DA-07 |
| VB-DA-08 | CI status(60s)/context freshness(120s)/git rev-list(60s)キャッシュTTL | dashboard PR-1 | AC-DA-08 |
| VB-DA-09 | mtime keyed awkキャッシュ | dashboard PR-2 | AC-DA-09 |
| VB-DA-10 | background process並行起動 | dashboard PR-3 | AC-DA-10 |
| VB-DA-11 | project-scoped cacheパス（cksum $PROJECT_DIR） | dashboard PR-4 | AC-DA-11 |
| VB-DA-12 | temp file + mv による原子的書込み | dashboard SR-1 | AC-DA-12 |
| VB-DA-13 | データソース欠損時の—プレースホルダー退避 | dashboard SR-2 | AC-DA-13 |
| VB-DA-14 | マーカー不在時のdashboard非変更 | dashboard SR-4 | AC-DA-14 |
| VB-RW-01 | /tmp/restart_watchers.lockによるシングルトンロック（flock -n） | restart_watchers FR-1 | AC-RW-01 |
| VB-RW-02 | 既存inbox_watcher全プロセスSIGTERM→1秒待ち→SIGKILL | restart_watchers FR-2 | AC-RW-02 |
| VB-RW-03 | shogun:mainペインからの@agent_cli解決＋shogun watcher起動 | restart_watchers FR-3 | AC-RW-03 |
| VB-RW-04 | shogun:agents.1ペインからのkaro watcher起動 | restart_watchers FR-4 | AC-RW-04 |
| VB-RW-05 | agent_config.sh::get_all_agents()による残忍者列挙＋karo skip＋ペイン空skip | restart_watchers FR-5 | AC-RW-05 |
| VB-RW-06 | pgrep -fによるwatcher存在確認＋失敗収集＋exit 1 | restart_watchers FR-6 | AC-RW-06 |
| VB-RW-07 | 2秒後のinotifywaitプロセス数一致確認＋不一致警告 | restart_watchers FR-7 | AC-RW-07 |
| VB-RW-08 | sync_pane_vars.sh実行 | restart_watchers FR-8 | AC-RW-08 |
| VB-RW-09 | 二段階停止（SIGTERM→SIGKILL）各段階で残存プロセス確認 | restart_watchers SR-1 | AC-RW-02 |
| VB-RW-10 | ペイン解決失敗時のsilent skip | restart_watchers SR-2 | AC-RW-09 |
| VB-YH-01 | yaml_field_set_batch: 1回のflock+1回のawk passで複数フィールド同時更新 | refactor R3 | AC-YH-01 |
| VB-YH-02 | field_get_multi: 1回のawk passで複数フィールド一括抽出 | refactor R4 | AC-YH-02 |
| VB-YH-03 | resolve_cmd_to_task: 7回→1回batch化（627ms→~100ms） | refactor R1 | AC-YH-03 |
| VB-YH-04 | inject_ac_version: field_get 6回→1回awk＋field_set 3回→1回batch化（541ms→~80ms） | refactor R2 | AC-YH-04 |
| VB-YH-05 | 既存yaml_field_set単体APIの完全互換維持 | refactor制約 | AC-YH-05 |
| VB-YH-06 | 既存field_get単体APIの完全互換維持 | refactor制約 | AC-YH-06 |
| VB-YH-07 | 48テスト(ac_handling)全PASS＋SKIP=0 | refactor制約 | AC-YH-07 |
| VB-YH-08 | flock排他正確性維持（並行書込み安全） | refactor制約 | AC-YH-08 |

**カバレッジギャップ: なし** — 全検証可能動作に対応テストシナリオが割当済み。

## 2. Acceptance Criteria

### 2.1 cmd_save.sh

| ID | 基準 | 検証方法 | 合格条件 |
|----|------|---------|---------|
| AC-CS-01 | `cmd_123`、`123`、`cmd_0123` いずれの形式でも正規化し、shogun_to_karo.yamlから該当ブロックを読込む | 各形式でスクリプト実行し、正しいブロックが処理されることを確認 | 3形式全てで同一ブロックを処理。存在しないIDはexit code非0 |
| AC-CS-02a | YAML構文エラーのあるcmdをBLOCK | 不正YAML（閉じ忘れ引用符、不正インデント）を含むcmdで実行 | exit code非0＋BLOCKログ記録＋エラーメッセージにYAML構文を明示 |
| AC-CS-02b | 存在しないcmd IDをBLOCK | shogun_to_karo.yamlに存在しないIDで実行 | exit code非0＋「コマンドが見つからない」旨のメッセージ |
| AC-CS-02c | delegated状態のcmdへの変更をBLOCK | status: delegatedのcmdに対して実行 | exit code非0＋不変性違反メッセージ＋cmdファイル無変更 |
| AC-CS-02d | pending状態の既存cmdがある場合に警告 | 別のcmdがpending状態の時に新cmdを保存 | WARN記録＋pending cmd IDの明示 |
| AC-CS-02e | アーカイブ済み重複検出 | アーカイブに同一IDが存在する状態で実行 | WARN or BLOCK＋重複IDの明示 |
| AC-CS-02f | 同時ドラフト競合検出 | 2プロセスが同時に同一cmdを処理 | 後発プロセスが競合を検出し適切にハンドリング |
| AC-CS-03 | BLOCK/WARN履歴ありの場合、diagnosis＋environment-changeフィールドを要求 | 過去にBLOCKされたcmd IDで、diagnosis未記入のcmdを保存 | BLOCK＋「diagnosis必須」メッセージ。environment-change記入済みの場合はPASS可能 |
| AC-CS-04 | BLOCK/WARN/PASS結果を品質ログ＋セッション状態ファイルに記録 | 各判定結果でスクリプト実行 | logs/gate_metrics.logに判定エントリ追記。セッション状態ファイルに最新状態反映 |
| AC-CS-05a | ロック競合時に警告出力 | flockタイムアウト発生を模擬 | stderrに警告メッセージ＋処理は中断しない |
| AC-CS-05b | 未コミット実装変更時に警告 | git statusでuncommitted changesがある状態で実行 | WARNログ記録＋変更ファイル一覧の明示 |
| AC-CS-05c | 重複GP番号を警告 | 既存cmdと同一GP番号を持つcmdを保存 | WARN＋重複GP番号と該当cmd IDsの明示 |
| AC-CS-05d | 偵察cmdが既存軍師分析と重複する場合に警告 | 軍師分析contextが存在するテーマの偵察cmdを保存 | WARN＋既存分析ファイルパスの明示 |
| AC-CS-06 | action-required bulletin IDを参照するcmdでbulletin追跡を更新 | bulletin action IDを含むcmdを保存 | bulletin_board.yamlの該当エントリにcmd参照が追記 |
| AC-CS-07 | ゲート状態がpending/blockedのcmdは委任されない | gate_state: pendingのcmdをdelegateしようとする | exit code非0＋委任拒否メッセージ |
| AC-CS-08 | 並行実行時のflock排他によるデータ整合性 | 10並行プロセスで同一キューファイルに書込み | 全エントリが欠損なく書込まれる。部分書込みなし |

### 2.2 deploy_task.sh

| ID | 基準 | 検証方法 | 合格条件 |
|----|------|---------|---------|
| AC-DT-01 | 通常/--direct/--yaml/--cmdの4モード解析＋staleコンテキスト無効化メッセージ | 各モードで実行 | 各モード固有のパス処理。デフォルトメッセージに「前回タスクは無効」旨の記述を含む |
| AC-DT-02 | 第1引数が空/None/cmd_*の場合にエラー終了 | 不正値（空文字列、"None"、"cmd_123"）で実行 | 各ケースでexit code非0＋具体的エラーメッセージ |
| AC-DT-03 | tmuxペイン解決＋idle/busy状態判定 | idle忍者とbusy忍者それぞれに配備 | idle: 配備続行。busy: 警告出力（配備は続行するが状態を通知） |
| AC-DT-04 | staleタスクフィールド/通知フラグ/ghost None.yamlをリセット | 前回タスクの残留フィールドがある状態で配備 | 新配備後にstaleフィールドが消去。queue/tasks/None.yamlが存在しない |
| AC-DT-05 | 親cmdからタスクメタデータ完全解決 | cmdにAC/教訓/意味概念/工学設定が設定された状態で配備 | task YAMLにparent_cmd/task_id/task_type/project/status/purpose/_ac_task_id/ac_version/related_lessons/semantic_concepts/engineering_preferencesが全て反映 |
| AC-DT-06 | queue/reports/にレポートテンプレート生成。既存完了レポートは上書きしない | 完了済みレポートが存在する忍者に再配備 | 新テンプレート生成されず、既存完了レポートが保全される |
| AC-DT-07 | inbox_write.sh経由でタスク通知を配信 | 配備実行後のinbox/{ninja}.yamlを確認 | type: task_assignedのエントリが追記。direct tmux send-keysによるメッセージ送信なし |
| AC-DT-08 | 同一親cmdの完了済みピアレポートが存在する場合に重複配備をBLOCK | 完了レポートが存在するcmdの同一タスクを別忍者に配備 | exit code非0＋重複配備拒否メッセージ |
| AC-DT-09 | YAML操作はyaml_field_set/yaml_field_set_batch経由のみ | ソースコード静的解析 | free-form echo/printf/catによるYAML直接書込みがないこと |

### 2.3 inbox_write.sh

| ID | 基準 | 検証方法 | 合格条件 |
|----|------|---------|---------|
| AC-IW-01 | target/content必須。type/sender/actionはオプショナル。不正ターゲットはエラー | 不正ターゲット（空、未定義名）で実行 | exit code非0＋「invalid target」メッセージ |
| AC-IW-02 | **忍者senderからshogunターゲットへの直接メッセージをBLOCK** | sender=hayate, target=shogunで実行 | exit code非0＋「ninja-to-shogun direct messaging prohibited」メッセージ。**NNC-3準拠** |
| AC-IW-03 | queue/inbox/{agent}.yamlにtimestamp/id/type/sender/content/read: false/actionを含むエントリ追記 | 正常パラメータで実行後ファイル解析 | 全フィールド存在。read: false。timestampはISO 8601。idはユニーク |
| AC-IW-04 | WSL2 /mnt/*パス対応のflockによる並行書込み保護 | 10並行プロセスで同一inboxファイルに書込み | 全10メッセージが欠損なく存在。部分書込み・データ混在なし。**NNC-1準拠** |
| AC-IW-05 | 同一親cmdの重複task_assigned配備をBLOCK | 同一parent_cmdで2回task_assigned送信 | 2回目がexit code非0＋重複メッセージ |
| AC-IW-06 | deploy_task未注入時の教訓注入セーフティネット | related_lessonsなしでtask_assigned送信 | 教訓注入が補完される（またはセーフティネット動作がログ記録される） |
| AC-IW-07 | type: report_received時にレポートフォーマットチェック＋下流トリガー | 不正フォーマットのレポート通知を送信 | フォーマットエラーの検出＋適切な下流処理（レビュー依頼or完了トリガー） |
| AC-IW-08 | メッセージ永続化完了後にのみCLI nudge送信 | 正常書込み実行 | inboxファイルへの書込み完了→ペイン解決→nudge送信の順序。永続化失敗時はnudge送信なし |

### 2.4 ninja_monitor.sh

| ID | 基準 | 検証方法 | 合格条件 |
|----|------|---------|---------|
| AC-NM-01 | シングルトンデーモンとして起動。多重起動を防止 | 2インスタンス同時起動 | 後発インスタンスが即座に終了 |
| AC-NM-02 | @agent_state/タイムスタンプ/CLI prompt/busy pattern/subprocess相互検証でidle/busy判定 | 各状態の忍者ペインを用意 | idle忍者: idle判定。busy忍者（subprocess活動中）: busy判定。hook stateがbusy証拠なしのidle判定を上書き（SR-1） |
| AC-NM-03 | idle確認＋report-gate通過後のみclear/respawn実行 | idle＋レポート未提出の忍者に対するclear試行 | report-gate未通過: clear実行されない。idle＋gate通過: clear実行 |
| AC-NM-04 | 6種異常検知（pane loss/stale deployment/未配備cmd/karo pending/CLI death/inbox unread/report-task mismatch） | 各異常状態を再現 | 各異常がkaro_snapshot.txtまたはinbox通知に反映 |
| AC-NM-05 | karo_snapshot.txt生成（cmd/忍者/model/context/report state列） | 正常稼働中に生成確認 | 全忍者＋cmd状態＋モデル＋CTX%＋レポート状態を含むフォーマット |
| AC-NM-06 | インフラ健全性監視（inbox watcher/ntfy listener/CI status/training/lesson/loop/workaround/script size） | 各サブシステムの正常/異常状態で実行 | 異常検知時に適切な通知。正常時は無出力 |
| AC-NM-07 | prompt-onlyのidle判定を禁止（hook state＋busy evidence優先） | @agent_state=busyだがpromptが表示されている状態 | busy判定（hook stateが優先） |
| AC-NM-08 | 全エージェント通信はinbox_write.sh経由 | ソースコード静的解析 | ad hoc tmux send-keysによるメッセージ送信がないこと（re-nudge fallbackを除く） |

### 2.5 dashboard_auto_section.sh

| ID | 基準 | 検証方法 | 合格条件 |
|----|------|---------|---------|
| AC-DA-01 | 指定10データソースの読込み | 全ソース存在時＋一部欠損時に実行 | 存在時: 正常読込。欠損時: —プレースホルダー表示（SR-2） |
| AC-DA-02 | 5外部スクリプト呼出し | 各スクリプトの正常/異常終了を模擬 | 正常: 出力を統合。異常: —プレースホルダー退避 |
| AC-DA-03 | 10出力セクション（忍者配備/CI Status/Unpushed/パイプライン/戦況メトリクス/モデル別スコアボード/知識サイクル健全度/スキル健全度/Context鮮度警告/戦果）生成 | 正常実行後のdashboard.md解析 | 全10セクションのヘッダーとコンテンツが存在 |
| AC-DA-04 | --dry-runモード | --dry-runで実行 | stdoutに生成内容出力。dashboard.mdのmtime不変 |
| AC-DA-05 | auto-sectionマーカー外コンテンツ保全 | マーカー外にカスタムコンテンツを含むdashboard.mdで実行 | カスタムコンテンツがバイト単位で不変 |
| AC-DA-06 | CLEAR数増加時のみntfy通知（/tmp/mas-dashboard-ntfy-last-clear.txtによる重複排除） | CLEAR数不変/増加の2パターンで実行 | 不変: ntfy呼出しなし。増加: ntfy呼出し1回。last-clear.txt更新 |
| AC-DA-07 | 将軍宛報告セクションの取消線エントリ（~~text~~）除去 | 取消線エントリを含むdashboard.mdで実行 | auto-section更新後、取消線エントリが除去 |
| AC-DA-08 | CI status/context freshness/git rev-listのキャッシュTTL | TTL内/外で2回連続実行 | TTL内: サブプロセス再実行なし（キャッシュヒット）。TTL外: サブプロセス再実行 |
| AC-DA-09 | gate_fire_log/gate_metrics/lesson_impact/lesson_effectiveness_statusのmtime keyedキャッシュ | ファイル変更なし/ありで2回実行 | mtime不変: awk再計算なし。mtime変更: awk再計算 |
| AC-DA-10 | context_freshness_check.sh/ci_status_check.shのbackground並行起動 | 実行時間計測 | 2スクリプトの実行時間がmax(A,B)≈合計。逐次実行時間(A+B)より短い |
| AC-DA-11 | cksum $PROJECT_DIRによるproject-scopedキャッシュパス | 異なるPROJECT_DIRで実行 | キャッシュパスが異なる。cross-project干渉なし |
| AC-DA-12 | temp file + mvによる原子的書込み | 書込み中にdashboard.mdを読む別プロセスを同時実行 | 部分書込み状態のdashboard.mdが読まれない |
| AC-DA-13 | 全データソース欠損時の—プレースホルダー退避 | 全データソースを削除して実行 | クラッシュせず、全セクションに—が表示。exit 0 |
| AC-DA-14 | DASHBOARD_AUTO_START/ENDマーカー不在時のdashboard非変更 | マーカーなしdashboard.mdで実行 | dashboard.md不変。exit 1 |

### 2.6 restart_watchers.sh

| ID | 基準 | 検証方法 | 合格条件 |
|----|------|---------|---------|
| AC-RW-01 | flock -nによるシングルトンロック | 2インスタンス同時起動 | 後発がexit code非0で即終了 |
| AC-RW-02 | SIGTERM→1秒待ち→SIGKILL二段階停止 | inbox_watcherプロセスが存在する状態で実行 | SIGTERM後に残存確認。残存あり: SIGKILL発行。全プロセス停止後に再起動 |
| AC-RW-03 | shogun:mainペインの@agent_cliからshogun watcher起動 | tmux環境で実行 | nohup + logs/inbox_watcher_shogun.logへのリダイレクト＋pgrep確認 |
| AC-RW-04 | shogun:agents.1ペインからkaro watcher起動 | tmux環境で実行 | nohup + logs/inbox_watcher_karo.logへのリダイレクト＋pgrep確認 |
| AC-RW-05 | get_all_agents()列挙＋karo skip＋空ペインskip | 一部ペインが空の陣形で実行 | karo未起動。空ペインのエージェントはskip。残りは正常起動 |
| AC-RW-06 | pgrep -fによる全watcher存在確認＋失敗時exit 1 | 1つのwatcherが起動失敗する状態を模擬 | 失敗watchers一覧出力＋exit 1 |
| AC-RW-07 | 2秒後のinotifywaitプロセス数一致確認 | 正常/不一致の2パターン | 一致: 正常完了。不一致: 警告メッセージ出力 |
| AC-RW-08 | sync_pane_vars.sh実行 | 実行ログ確認 | restart_watchers完了時にsync_pane_vars.shが呼出される |
| AC-RW-09 | ペイン解決失敗時のsilent skip | 存在しないペインを指すエージェントを含む陣形で実行 | エラー出力なし＋該当エージェントskip＋他エージェントは正常起動 |

### 2.7 yaml_helpers（リファクタリング）

| ID | 基準 | 検証方法 | 合格条件 |
|----|------|---------|---------|
| AC-YH-01 | `yaml_field_set_batch <file> <block_id> field1=val1 field2=val2 ...` で1回のflock+1回のawk passで全フィールド同時更新 | 7フィールドのbatch更新を実行＋strace/ltraceでflock呼出し回数確認 | 全フィールドが正確に更新。flock呼出し1回。awk実行1回 |
| AC-YH-02 | `field_get_multi <file> field1 field2 ...` で1回のawk passで複数フィールド一括抽出。出力: `field1=value1\nfield2=value2\n...` | 6フィールドの一括取得を実行 | eval可能な出力形式。全フィールドの値が正確。awk実行1回 |
| AC-YH-03 | resolve_cmd_to_task()がyaml_field_set_batch使用で627ms→100ms以下 | batsテスト内でtime計測（10回平均） | 平均実行時間100ms以下。出力結果はリファクタリング前と同一 |
| AC-YH-04 | inject_ac_version()がfield_get_multi+yaml_field_set_batch使用で541ms→80ms以下 | batsテスト内でtime計測（10回平均） | 平均実行時間80ms以下。AC version hash計算結果がリファクタリング前と同一 |
| AC-YH-05 | 既存 `yaml_field_set <file> <block_id> <field> <value>` の単体呼出しがAPIシグネチャ・動作ともに不変 | 既存テストスイート全実行 | 全テストPASS。出力差分ゼロ。**NNC-4準拠** |
| AC-YH-06 | 既存 `field_get <file> <field>` の単体呼出しがAPIシグネチャ・動作ともに不変 | 既存テストスイート全実行 | 全テストPASS。出力差分ゼロ。**NNC-4準拠** |
| AC-YH-07 | 48テスト(ac_handling)全PASS、SKIP=0 | `bats tests/ac_handling/` 全実行 | PASS=48, FAIL=0, SKIP=0。**NNC-5準拠** |
| AC-YH-08 | batch操作でもflock排他によるデータ整合性を維持 | 10並行プロセスでyaml_field_set_batch同時実行 | 全フィールドが正確に反映。データ消失・混在なし。**NNC-1準拠** |

## 3. Failure Criteria

以下の条件が1つでも該当した場合、リリースをブロックする。

### 3.1 テスト品質ゲート

| ID | 失敗条件 | 根拠 |
|----|---------|------|
| FC-01 | テスト実行結果にSKIPが1件以上存在 | SKIP=FAIL規則（CLAUDE.md Test Rules §1） |
| FC-02 | テスト実行結果にFAILが1件以上存在 | リグレッション禁止（refactor制約） |
| FC-03 | 前提条件（tmux環境/flock対応/bats実行環境）が不足した状態でテスト実行 | Preflight check義務（Test Rules §2） |

### 3.2 安全性ゲート

| ID | 失敗条件 | 根拠 |
|----|---------|------|
| FC-04 | inbox_write.shが忍者senderからshogunターゲットへのメッセージを通過させた | NNC-3: ninja-to-shogun prohibition |
| FC-05 | 並行書込みテストでメッセージ欠損またはデータ混在が発生 | NNC-1: flock-based atomic writes |
| FC-06 | deploy_task.shがfree-form YAML dump（yaml.dump/echo/printf直接書込み）を使用 | NNC-1 + yaml.dump禁止規則（CLAUDE.md） |
| FC-07 | yaml_field_setまたはfield_getの既存APIシグネチャが変更された | NNC-4: backward compatibility |
| FC-08 | ninja_monitorがactive task stateのペインをreport-gate未通過でclear | SR-2: active task protection |
| FC-09 | dashboard_auto_section.shがauto-sectionマーカー外のコンテンツを変更 | dashboard FR-5: marker isolation |
| FC-10 | restart_watchers.shがSIGTERMなしにSIGKILLを発行 | SR-1: two-stage termination |

### 3.3 パフォーマンスゲート

| ID | 失敗条件 | 根拠 |
|----|---------|------|
| FC-11 | リファクタリング後のresolve_cmd_to_task平均実行時間が200msを超過 | refactor R1目標: ~100ms（200msは安全マージン2倍） |
| FC-12 | リファクタリング後のinject_ac_version平均実行時間が160msを超過 | refactor R2目標: ~80ms（160msは安全マージン2倍） |
| FC-13 | リファクタリング後の48テスト合計実行時間が10sを超過 | refactor目標: ~5s（10sは安全マージン2倍） |

### 3.4 データ整合性ゲート

| ID | 失敗条件 | 根拠 |
|----|---------|------|
| FC-14 | yaml_field_set_batchの出力がyaml_field_set逐次呼出しの出力と一致しない | batch=逐次等価原則 |
| FC-15 | field_get_multiの出力がfield_get逐次呼出しの出力と一致しない | batch=逐次等価原則 |
| FC-16 | dashboard_auto_section.shがtemp fileなしにdashboard.mdを直接書換え | SR-1: atomic writes |

## 4. E2E Test Generation Meta-Prompt

以下はCoDD `propagate` が本ドキュメントからE2Eテストを自動生成するための機械可読指示である。

### 4.1 テストレベル分離

本プロジェクトはシェルスクリプトインフラのため、テストを以下の2レベルに分離する:

| レベル | 説明 | 実行方法 | ファイル命名 |
|--------|------|---------|-------------|
| **Script Integration** | 各スクリプトを実際のシェル環境で実行し、exit code/stdout/stderr/ファイル出力を検証 | bats (Bash Automated Testing System) | `tests/e2e/<domain>.spec.bats` |
| **Concurrency Stress** | flock排他・並行書込み・シングルトンロックを複数プロセスで検証 | bats + GNU parallel / background processes | `tests/e2e/<domain>.stress.spec.bats` |

### 4.2 MECEドメイン分解

| ドメイン | 責務 | 出力ファイルパス |
|---------|------|-----------------|
| cmd-save | cmd_save.shのBLOCK/WARN/PASS判定・品質ログ・不変性保護 | `tests/e2e/cmd-save.spec.bats` |
| deploy-task | deploy_task.shの4モード配備・メタデータ解決・レポート生成 | `tests/e2e/deploy-task.spec.bats` |
| inbox-write | inbox_write.shの原子的書込み・routing制約・教訓注入 | `tests/e2e/inbox-write.spec.bats` |
| ninja-monitor | ninja_monitor.shのidle検知・異常検知・snapshot生成 | `tests/e2e/ninja-monitor.spec.bats` |
| dashboard | dashboard_auto_section.shのセクション生成・キャッシュ・原子的書込み | `tests/e2e/dashboard.spec.bats` |
| restart-watchers | restart_watchers.shのシングルトン・二段階停止・watcher検証 | `tests/e2e/restart-watchers.spec.bats` |
| yaml-helpers | yaml_field_set_batch/field_get_multi/既存API互換・パフォーマンス | `tests/e2e/yaml-helpers.spec.bats` |
| concurrency | 全モジュール横断のflock排他・並行書込みストレス | `tests/e2e/concurrency.stress.spec.bats` |

### 4.3 シナリオ導出規則

1. **正常系**: 各ACの合格条件をそのままassertionに変換。1 ACにつき最低1テストケース
2. **異常系**: 各FCの失敗条件を反転し、「この条件が発生しないこと」をassert。FC-04～FC-16の各項目に対応テスト必須
3. **境界値**: 空文字列/None/cmd_*形式/最大長文字列/特殊文字(日本語/改行/引用符)を入力パラメータに含める
4. **並行テスト**: AC-CS-08/AC-IW-04/AC-YH-08は10並行プロセスで実行し、全メッセージ/フィールドの完全性を検証

### 4.4 テスト実行環境

#### 前提条件（Preflight）

```bash
# bats-core + bats-assert + bats-support 必須
command -v bats >/dev/null 2>&1 || { echo "bats-core required"; exit 1; }

# tmux セッション存在確認（ninja-monitor/restart-watchers テストに必須）
tmux has-session -t shogun 2>/dev/null || { echo "tmux session 'shogun' required"; exit 1; }

# flock 対応確認（WSL2 /mnt/* パスでの動作）
flock --version >/dev/null 2>&1 || { echo "flock required"; exit 1; }

# GNU parallel（concurrency stress テストに必須）
command -v parallel >/dev/null 2>&1 || { echo "GNU parallel required for stress tests"; exit 1; }
```

#### テスト実行順序

```bash
# 1. ユーティリティ層（依存なし）
bats tests/e2e/yaml-helpers.spec.bats

# 2. 通信層（yaml-helpersに依存）
bats tests/e2e/inbox-write.spec.bats

# 3. 配備層（inbox-write + yaml-helpersに依存）
bats tests/e2e/deploy-task.spec.bats
bats tests/e2e/cmd-save.spec.bats

# 4. 監視層（全下位層に依存）
bats tests/e2e/ninja-monitor.spec.bats
bats tests/e2e/dashboard.spec.bats
bats tests/e2e/restart-watchers.spec.bats

# 5. ストレステスト（全モジュール横断）
bats tests/e2e/concurrency.stress.spec.bats
```

#### CI環境

```bash
# GitHub Actions / CI での実行
# tmux セッションを仮想的に作成
tmux new-session -d -s shogun -x 200 -y 50
tmux new-window -t shogun -n agents

# テスト用ペインを作成（ninja-monitor/restart-watchers テスト用）
for i in $(seq 1 8); do
  tmux split-window -t shogun:agents -h 2>/dev/null || true
done
tmux select-layout -t shogun:agents tiled

# ペイン変数設定
tmux set-option -t shogun:agents.1 @agent_id karo
tmux set-option -t shogun:agents.1 @agent_cli claude
# ... 以下各エージェント分

# 全テスト実行
bats tests/e2e/*.spec.bats tests/e2e/*.stress.spec.bats
```

### 4.5 共有ヘルパー

`tests/e2e/helpers/` ディレクトリに以下のヘルパーを配置し、全specファイルから共有する:

| ファイル | 責務 |
|---------|------|
| `tests/e2e/helpers/setup.bash` | テスト用一時ディレクトリ作成、queue/inbox/logs/config構造のスキャフォールド、環境変数設定（PROJECT_DIR等） |
| `tests/e2e/helpers/teardown.bash` | 一時ディレクトリ削除、プロセスクリーンアップ（テストで起動したwatcher/monitor停止） |
| `tests/e2e/helpers/fixtures.bash` | テスト用YAML生成関数（valid cmd/invalid cmd/task YAML/inbox entry/dashboard.md テンプレート） |
| `tests/e2e/helpers/assertions.bash` | YAML フィールド値assertion、ファイル内容不変assertion、プロセス存在assertion、実行時間assertion |
| `tests/e2e/helpers/concurrency.bash` | N並行実行ヘルパー（GNU parallel wrapper）、結果集計、データ完全性チェック |
| `tests/e2e/helpers/tmux_mock.bash` | tmux環境モック（tmux非依存テスト用）、ペイン変数スタブ |

### 4.6 アーキテクチャ適応規則

1. テスト生成前に `scripts/` 配下の実際のスクリプト一覧を走査し、requirements/designドキュメントに記載されたスクリプトとの差分を検出すること
2. 未実装のスクリプトや関数に対するテストケースには `bats test.fixme` マーカー（`skip "FIXME: not yet implemented"`）を付与し、SKIPではなく明示的にFIXMEとして可視化すること
3. `scripts/lib/` 配下のヘルパー関数は `source` で読込み可能であることを前提とし、関数単体テストを生成すること

### 4.7 品質ゲート

| 基準 | 閾値 |
|------|------|
| テスト結果 | 全PASS（FAIL=0） |
| SKIP数 | 0（SKIP=FAIL規則） |
| AC カバレッジ | 全AC-*に対応テストが存在 |
| FC カバレッジ | 全FC-*に対応テストが存在（反転assertion） |
| NNC カバレッジ | 全NNC-*制約に対応テストが存在 |
| パフォーマンス | resolve_cmd_to_task ≤200ms, inject_ac_version ≤160ms, 48テスト合計 ≤10s |
| 並行安全性 | 10並行書込みでデータ欠損ゼロ |

### 4.8 生成マーカー

全生成ファイルに以下のヘッダーを含める:

```bash
#!/usr/bin/env bats
# @generated-from: codd/tests/acceptance-criteria.md
# @generated-by: codd propagate
# @generated-at: <ISO 8601 timestamp>
```

手動で追加されたテスト（`# @manual` マーカー付き）は再生成時に保全すること:

```bash
# @manual — 手動追加テスト。codd propagate再生成時に削除禁止
@test "manual: edge case for WSL2 path with spaces" {
  ...
}
```

### 4.9 出力ファイルマッピング

| ドメイン | 出力パス | テストレベル |
|---------|---------|-------------|
| cmd-save | `tests/e2e/cmd-save.spec.bats` | Script Integration |
| deploy-task | `tests/e2e/deploy-task.spec.bats` | Script Integration |
| inbox-write | `tests/e2e/inbox-write.spec.bats` | Script Integration |
| ninja-monitor | `tests/e2e/ninja-monitor.spec.bats` | Script Integration |
| dashboard | `tests/e2e/dashboard.spec.bats` | Script Integration |
| restart-watchers | `tests/e2e/restart-watchers.spec.bats` | Script Integration |
| yaml-helpers | `tests/e2e/yaml-helpers.spec.bats` | Script Integration |
| concurrency | `tests/e2e/concurrency.stress.spec.bats` | Concurrency Stress |
