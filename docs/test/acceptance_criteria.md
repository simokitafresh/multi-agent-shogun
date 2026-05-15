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

| モジュール | 実装ファイル | 役割 |
|-----------|-------------|------|
| cmd_save | `scripts/cmd_save.sh` | 将軍コマンド品質ゲート |
| deploy_task | `scripts/deploy_task.sh` | 忍者タスク配備ヘルパー |
| inbox_write | `scripts/inbox_write.sh` | エージェント間アトミックメールボックス |
| ninja_monitor | `scripts/ninja_monitor.sh` | 陣形監視デーモン |
| dashboard_auto_section | `scripts/dashboard_auto_section.sh` | ダッシュボード自動生成 |
| restart_watchers | `scripts/restart_watchers.sh` | inbox_watcherデーモン再起動 |
| yaml_helpers | `scripts/lib/yaml_field_set.sh`, `scripts/lib/field_get.sh` | YAML安全操作ユーティリティ |

**リリースブロッキング制約（非交渉）**:

1. **flock排他アトミック書込み**: `inbox_write`, `cmd_save`, `deploy_task`, `yaml_helpers` の全YAML書込みは flock ベースの排他ロックを使用する。yaml.dump / yaml.safe_dump による運用YAML上書きは禁止（cmd_1399事故: データ消失実証済み）。
2. **API後方互換性**: `yaml_field_set` および `field_get` の既存APIシグネチャは変更不可。バッチ関数（`yaml_field_set_batch`, `field_get_multi`）は追加APIとして提供し、既存呼出元のテストはゼロリグレッションを維持する。
3. **忍者→将軍直接メッセージ禁止**: `inbox_write` は忍者から将軍への直接送信をブロックする。全通信は家老経由の鎖を維持する（SR-2 inbox_write）。

---

## 2. Acceptance Criteria

### 2.1 Traceability Matrix

以下に全依存設計書から抽出した検証可能動作と、対応するテストシナリオのマッピングを示す。

| ID | 検証可能動作 | ソース | テストシナリオ |
|----|------------|--------|--------------|
| VB-001 | cmd_save: 数値および `cmd_*` ID の正規化とブロック読込み | FR-1 cmd_save | AC-CS-01 |
| VB-002 | cmd_save: YAML構文エラー検出 | FR-2 cmd_save | AC-CS-02 |
| VB-003 | cmd_save: 存在しないコマンドの拒否 | FR-2 cmd_save | AC-CS-03 |
| VB-004 | cmd_save: delegated状態のコマンド不変性保護 | FR-2 cmd_save, SR-2 cmd_save | AC-CS-04 |
| VB-005 | cmd_save: pending/blocked状態のゲートブロック | FR-2 cmd_save, SR-1 cmd_save | AC-CS-05 |
| VB-006 | cmd_save: アーカイブ重複検出 | FR-2 cmd_save | AC-CS-06 |
| VB-007 | cmd_save: 並行ドラフト競合検出 | FR-2 cmd_save | AC-CS-07 |
| VB-008 | cmd_save: quality_gateフィールド検証 | FR-3 cmd_save | AC-CS-08 |
| VB-009 | cmd_save: BLOCK/WARN履歴時の診断/environment-change要求 | FR-3 cmd_save | AC-CS-09 |
| VB-010 | cmd_save: BLOCK/WARN/PASS結果の品質ログ記録 | FR-4 cmd_save | AC-CS-10 |
| VB-011 | cmd_save: セッション状態ファイル更新 | FR-4 cmd_save | AC-CS-11 |
| VB-012 | cmd_save: ロック競合警告 | FR-5 cmd_save | AC-CS-12 |
| VB-013 | cmd_save: 未コミット実装変更警告 | FR-5 cmd_save | AC-CS-13 |
| VB-014 | cmd_save: 重複GP番号警告 | FR-5 cmd_save | AC-CS-14 |
| VB-015 | cmd_save: 偵察/軍師分析重複警告 | FR-5 cmd_save | AC-CS-15 |
| VB-016 | cmd_save: bulletin action tracking更新 | FR-6 cmd_save | AC-CS-16 |
| VB-017 | cmd_save: flock排他によるキューファイル保護 | SR-3 cmd_save | AC-CS-17 |
| VB-020 | deploy_task: 通常モード配備 | FR-1 deploy_task | AC-DT-01 |
| VB-021 | deploy_task: `--direct`モード配備 | FR-1 deploy_task | AC-DT-02 |
| VB-022 | deploy_task: `--yaml`モード配備 | FR-1 deploy_task | AC-DT-03 |
| VB-023 | deploy_task: `--cmd`モード配備 | FR-1 deploy_task | AC-DT-04 |
| VB-024 | deploy_task: 古いタスクコンテキスト無効化デフォルトメッセージ | FR-1 deploy_task | AC-DT-05 |
| VB-025 | deploy_task: 空/None/cmd_*ターゲット拒否 | FR-2 deploy_task | AC-DT-06 |
| VB-026 | deploy_task: tmux/CLIヘルパー経由のペイン解決とidle/busy判定 | FR-3 deploy_task | AC-DT-07 |
| VB-027 | deploy_task: 古いタスクフィールド・通知フラグ・ghost None.yamlリセット | FR-4 deploy_task | AC-DT-08 |
| VB-028 | deploy_task: 親cmdからタスクメタデータ解決（task_id, task_type, project, purpose, AC, ACバージョン, 関連教訓, semantic concepts, engineering preferences, 実行制御） | FR-5 deploy_task | AC-DT-09 |
| VB-029 | deploy_task: 報告テンプレート生成（既存完了報告の上書き防止） | FR-6 deploy_task | AC-DT-10 |
| VB-030 | deploy_task: inbox_write.sh経由のタスク通知配信 | FR-7 deploy_task | AC-DT-11 |
| VB-031 | deploy_task: 完了済みピア報告存在時の重複配備ブロック | SR-2 deploy_task | AC-DT-12 |
| VB-032 | deploy_task: YAML操作にshared helpersを使用（yaml.dump禁止） | SR-1 deploy_task | AC-DT-13 |
| VB-033 | deploy_task: inbox経路通信（send-keys再nudgeのみフォールバック） | SR-3 deploy_task | AC-DT-14 |
| VB-040 | inbox_write: target/content/type/sender/action受理 | FR-1 inbox_write | AC-IW-01 |
| VB-041 | inbox_write: 不正・欠損ターゲット拒否 | FR-1 inbox_write | AC-IW-02 |
| VB-042 | inbox_write: エージェント名バリデーション | FR-2 inbox_write | AC-IW-03 |
| VB-043 | inbox_write: 忍者→将軍送信ブロック | FR-2 inbox_write, SR-2 inbox_write | AC-IW-04 |
| VB-044 | inbox_write: メッセージのqueue/inbox/{agent}.yamlへのシリアライズ（timestamp, id, type, sender, content, read, action） | FR-3 inbox_write | AC-IW-05 |
| VB-045 | inbox_write: WSL2 /mnt/* パス対応ロックファイル使用 | FR-4 inbox_write, SR-3 inbox_write | AC-IW-06 |
| VB-046 | inbox_write: 同一親cmdの重複task_assigned配備ブロック | FR-5 inbox_write | AC-IW-07 |
| VB-047 | inbox_write: deploy未注入時の教訓注入セーフティネット | FR-6 inbox_write | AC-IW-08 |
| VB-048 | inbox_write: 報告通知時のフォーマットチェック+下流レビュー/完了トリガー | FR-7 inbox_write | AC-IW-09 |
| VB-049 | inbox_write: メッセージ永続化後のペイン解決とCLI固有nudge送信 | FR-8 inbox_write | AC-IW-10 |
| VB-050 | inbox_write: inbox永続化を信頼源とし、nudge失敗は非致命的 | SR-1 inbox_write | AC-IW-11 |
| VB-060 | ninja_monitor: シングルトンデーモン起動 | FR-1 ninja_monitor | AC-NM-01 |
| VB-061 | ninja_monitor: tmuxメタデータからの忍者ペイン再発見 | FR-1 ninja_monitor | AC-NM-02 |
| VB-062 | ninja_monitor: @agent_state/タイムスタンプ/プロンプトパターン/サブプロセスによるidle/busy検出 | FR-2 ninja_monitor | AC-NM-03 |
| VB-063 | ninja_monitor: idle確認+レポートゲートチェック後のエージェントclear/respawn | FR-3 ninja_monitor | AC-NM-04 |
| VB-064 | ninja_monitor: ペインロス検出 | FR-4 ninja_monitor | AC-NM-05 |
| VB-065 | ninja_monitor: 古いデプロイメント検出 | FR-4 ninja_monitor | AC-NM-06 |
| VB-066 | ninja_monitor: 未配備コマンド検出 | FR-4 ninja_monitor | AC-NM-07 |
| VB-067 | ninja_monitor: 家老pending作業検出 | FR-4 ninja_monitor | AC-NM-08 |
| VB-068 | ninja_monitor: CLI死亡検出 | FR-4 ninja_monitor | AC-NM-09 |
| VB-069 | ninja_monitor: inbox未読数検出 | FR-4 ninja_monitor | AC-NM-10 |
| VB-070 | ninja_monitor: 報告/タスクミスマッチ検出 | FR-4 ninja_monitor | AC-NM-11 |
| VB-071 | ninja_monitor: karo_snapshot.txt生成（cmd, 忍者, モデル, コンテキスト, 報告状態） | FR-5 ninja_monitor | AC-NM-12 |
| VB-072 | ninja_monitor: inbox watcher監視 | FR-6 ninja_monitor | AC-NM-13 |
| VB-073 | ninja_monitor: ntfy listener監視 | FR-6 ninja_monitor | AC-NM-14 |
| VB-074 | ninja_monitor: CI status監視 | FR-6 ninja_monitor | AC-NM-15 |
| VB-075 | ninja_monitor: 修行auto-deploy条件監視 | FR-6 ninja_monitor | AC-NM-16 |
| VB-076 | ninja_monitor: 教訓health/ループhealth/workaround傾向/スクリプトサイズ傾向監視 | FR-6 ninja_monitor | AC-NM-17 |
| VB-077 | ninja_monitor: hook状態とbusy証拠をプロンプトのみのidle検出より優先 | SR-1 ninja_monitor | AC-NM-18 |
| VB-078 | ninja_monitor: タスク状態+レポートゲート未通過時のペインclear禁止 | SR-2 ninja_monitor | AC-NM-19 |
| VB-079 | ninja_monitor: inbox_write.sh経由の通信 | SR-3 ninja_monitor | AC-NM-20 |
| VB-080 | dashboard_auto: karo_snapshot.txt読込 | FR-1 dashboard_auto | AC-DA-01 |
| VB-081 | dashboard_auto: shogun_to_karo.yaml読込 | FR-1 dashboard_auto | AC-DA-02 |
| VB-082 | dashboard_auto: gate_metrics.log読込 | FR-1 dashboard_auto | AC-DA-03 |
| VB-083 | dashboard_auto: tasks/*.yaml読込 | FR-1 dashboard_auto | AC-DA-04 |
| VB-084 | dashboard_auto: settings.yaml/cli_profiles.yaml読込 | FR-1 dashboard_auto | AC-DA-05 |
| VB-085 | dashboard_auto: gate_fire_log.yaml/lesson_impact.tsv/lesson_effectiveness_status.txt読込 | FR-1 dashboard_auto | AC-DA-06 |
| VB-086 | dashboard_auto: 外部スクリプト5本のサブプロセス実行（knowledge_metrics, model_analysis, context_freshness_check, ci_status_check, skill_metrics） | FR-2 dashboard_auto | AC-DA-07 |
| VB-087 | dashboard_auto: 10セクション生成（忍者配備, CI Status, Unpushed Commits WARN, パイプライン, 戦況メトリクス, モデル別スコアボード, 知識サイクル健全度, スキル健全度, Context鮮度警告, 戦果） | FR-3 dashboard_auto | AC-DA-08 |
| VB-088 | dashboard_auto: --dry-runモード（stdout出力、dashboard.md変更なし） | FR-4 dashboard_auto | AC-DA-09 |
| VB-089 | dashboard_auto: 自動セクションマーカー外コンテンツ保全 | FR-5 dashboard_auto | AC-DA-10 |
| VB-090 | dashboard_auto: CLEAR数増加時のみntfy通知（重複排除） | FR-6 dashboard_auto | AC-DA-11 |
| VB-091 | dashboard_auto: 将軍宛報告セクションの取消線エントリ削除 | FR-7 dashboard_auto | AC-DA-12 |
| VB-092 | dashboard_auto: CIステータスキャッシュ（TTL 60s） | PR-1 dashboard_auto | AC-DA-13 |
| VB-093 | dashboard_auto: context freshness/git rev-listキャッシュ（TTL 60s/120s） | PR-1 dashboard_auto | AC-DA-14 |
| VB-094 | dashboard_auto: awk計算結果のmtimeキーキャッシュ | PR-2 dashboard_auto | AC-DA-15 |
| VB-095 | dashboard_auto: context_freshness_check/ci_status_checkバックグラウンド並列実行 | PR-3 dashboard_auto | AC-DA-16 |
| VB-096 | dashboard_auto: cksum($PROJECT_DIR)によるプロジェクトスコープキャッシュパス | PR-4 dashboard_auto | AC-DA-17 |
| VB-097 | dashboard_auto: tmpファイル+mvによるアトミック書込み | SR-1 dashboard_auto | AC-DA-18 |
| VB-098 | dashboard_auto: データソース欠損時の `—` プレースホルダー降格 | SR-2 dashboard_auto | AC-DA-19 |
| VB-099 | dashboard_auto: 成功時exit 0、失敗時exit 1 | SR-3 dashboard_auto | AC-DA-20 |
| VB-100 | dashboard_auto: マーカー不在時の非修正 | SR-4 dashboard_auto | AC-DA-21 |
| VB-110 | restart_watchers: /tmp/restart_watchers.lock によるシングルトン排他 | FR-1 restart_watchers | AC-RW-01 |
| VB-111 | restart_watchers: 既存inbox_watcher全プロセスSIGTERM停止 | FR-2 restart_watchers | AC-RW-02 |
| VB-112 | restart_watchers: SIGTERM後生存プロセスへのSIGKILLエスカレーション | FR-2 restart_watchers | AC-RW-03 |
| VB-113 | restart_watchers: shogun:mainペインからの将軍watcher起動 | FR-3 restart_watchers | AC-RW-04 |
| VB-114 | restart_watchers: shogun:agents.1ペインからの家老watcher起動 | FR-4 restart_watchers | AC-RW-05 |
| VB-115 | restart_watchers: agent_config.sh列挙+pane_lookup解決+空ペインスキップ | FR-5 restart_watchers | AC-RW-06 |
| VB-116 | restart_watchers: pgrep -fによる全watcher起動確認 | FR-6 restart_watchers | AC-RW-07 |
| VB-117 | restart_watchers: inotifywaitプロセス数一致チェック（不一致時警告） | FR-7 restart_watchers | AC-RW-08 |
| VB-118 | restart_watchers: sync_pane_vars.sh実行 | FR-8 restart_watchers | AC-RW-09 |
| VB-119 | restart_watchers: 2段階停止（SIGTERM→1秒待機→SIGKILL） | SR-1 restart_watchers | AC-RW-10 |
| VB-120 | restart_watchers: ペイン解決失敗の静黙スキップ | SR-2 restart_watchers | AC-RW-11 |
| VB-121 | restart_watchers: per-agentログファイルへのappend | SR-3 restart_watchers | AC-RW-12 |
| VB-130 | yaml_helpers: yaml_field_set_batch による1回flock+1回awkでの複数フィールド同時更新 | R3 refactor | AC-YH-01 |
| VB-131 | yaml_helpers: yaml_field_set_batch のverify_after_write 1回実行 | R3 refactor | AC-YH-02 |
| VB-132 | yaml_helpers: field_get_multi による1回awkでの複数フィールド一括抽出 | R4 refactor | AC-YH-03 |
| VB-133 | yaml_helpers: field_get_multi のeval可能出力形式 | R4 refactor | AC-YH-04 |
| VB-134 | yaml_helpers: resolve_cmd_to_task のyaml_field_set 7回→yaml_field_set_batch 1回化 | R1 refactor | AC-YH-05 |
| VB-135 | yaml_helpers: inject_ac_version のfield_get 6回→field_get_multi 1回化 + yaml_field_set 3回→yaml_field_set_batch 1回化 | R2 refactor | AC-YH-06 |
| VB-136 | yaml_helpers: 既存yaml_field_set APIシグネチャ不変 | refactor制約 | AC-YH-07 |
| VB-137 | yaml_helpers: 既存field_get APIシグネチャ不変 | refactor制約 | AC-YH-08 |
| VB-138 | yaml_helpers: リファクタリング後の全既存テストゼロリグレッション | refactor制約 | AC-YH-09 |
| VB-139 | yaml_helpers: flock排他の正確性維持（並行書込み安全） | refactor制約 | AC-YH-10 |

**カバレッジギャップ**: なし。全検証可能動作に対応するテストシナリオが存在する。

---

### 2.2 cmd_save.sh 受入基準

#### AC-CS-01: ID正規化とブロック読込み
- 数値入力 `123` が `cmd_123` に正規化される
- `cmd_123` 形式がそのまま受理される
- `queue/shogun_to_karo.yaml` から該当ブロックが正しく読み込まれる
- 存在しないIDで非ゼロ終了する

#### AC-CS-02: YAML構文エラー検出
- 不正YAMLを含むコマンドでBLOCKが発生する
- エラーメッセージが構文エラー箇所を特定する

#### AC-CS-03: 存在しないコマンド拒否
- `shogun_to_karo.yaml` に存在しないcmd_idで非ゼロ終了する

#### AC-CS-04: delegated状態不変性保護
- status: delegated のコマンドに対する再保存がBLOCKされる
- エラーメッセージが不変性制約を明示する

#### AC-CS-05: pending/blockedゲートブロック
- 前回BLOCKされたコマンドの再委任がブロックされる
- ゲート状態がpendingのコマンドの委任がブロックされる

#### AC-CS-06: アーカイブ重複検出
- アーカイブに同一cmd_idが存在する場合に警告を出す

#### AC-CS-07: 並行ドラフト競合検出
- 同一コマンドの並行保存試行が検出される

#### AC-CS-08: quality_gateフィールド検証
- q1〜q3欠損でBLOCK
- q4_depth=shallowでWARNING

#### AC-CS-09: BLOCK/WARN履歴時のenvironment_change要求
- 過去にBLOCK/WARNを受けたcmdの再保存で、diagnosis欄とenvironment_change欄（構造化: type/file/pattern）が必須
- environment_changeのgrep検証が実行される

#### AC-CS-10: 品質ログ記録
- BLOCK結果がログに記録される（タイムスタンプ、cmd_id、理由）
- WARN結果がログに記録される
- PASS結果がログに記録される

#### AC-CS-11: セッション状態ファイル更新
- ゲート結果がセッション状態ファイルに反映される

#### AC-CS-12〜16: 警告系
- AC-CS-12: ロック競合時に警告メッセージを出力する
- AC-CS-13: 未コミットの実装変更が存在する場合に警告する
- AC-CS-14: 重複するGP番号を検出し警告する
- AC-CS-15: 既存の軍師分析と重複する偵察cmdを検出し警告する
- AC-CS-16: bulletin action-required IDを参照するcmd保存時にaction trackingが更新される

#### AC-CS-17: flock排他
- `queue/shogun_to_karo.yaml` への書込みがflock排他で保護される
- 並行実行時にデータ消失が発生しない

---

### 2.3 deploy_task.sh 受入基準

#### AC-DT-01〜04: 配備モード
- AC-DT-01: 通常モード（`deploy_task.sh <ninja> <cmd_id>`）でタスクYAMLが生成される
- AC-DT-02: `--direct`モードでdirectメッセージが送信される
- AC-DT-03: `--yaml`モードで指定YAMLが直接配備される
- AC-DT-04: `--cmd`モードでcmd_idからタスクが自動解決される

#### AC-DT-05: 古いコンテキスト無効化
- 配備メッセージに前回タスクコンテキスト無効化の既定文が含まれる

#### AC-DT-06: 不正ターゲット拒否
- 空文字列ターゲットで非ゼロ終了する
- `None`ターゲットで非ゼロ終了する
- `cmd_*`形式のターゲット（忍者名ではない）で非ゼロ終了する
- 登録外の忍者名で非ゼロ終了する

#### AC-DT-07: ペイン解決とidle/busy判定
- tmuxペインが正しく解決される
- busy状態の忍者への配備時に適切な警告/処理が行われる

#### AC-DT-08: 古い状態のリセット
- 前回のタスクフィールドがリセットされる
- stale通知フラグがクリアされる
- `queue/tasks/None.yaml` ゴーストが削除される

#### AC-DT-09: 親cmd→タスクメタデータ解決
- `parent_cmd`, `task_id`, `task_type`, `project`, `status`, `purpose`, `_ac_task_id` がタスクYAMLに書き込まれる
- ACバージョンが計算・注入される
- 関連教訓（related_lessons）が注入される
- semantic conceptsが注入される
- engineering preferencesが注入される
- 実行制御フィールドが注入される

#### AC-DT-10: 報告テンプレート生成
- `queue/reports/` に対応する報告テンプレートが生成される
- 既存の完了済み報告は上書きされない

#### AC-DT-11: inbox_write.sh経由配信
- タスク通知が `scripts/inbox_write.sh` を呼び出して配信される
- inbox永続化成功をもって配信完了とする

#### AC-DT-12: 重複配備ブロック
- 同一親cmdの完了済みピア報告が存在する場合、新規配備がブロックされる

#### AC-DT-13: YAML操作安全性
- 全YAML変更が `yaml_field_set` / `yaml_field_set_batch` 経由で実行される
- `yaml.dump` / `yaml.safe_dump` が一切使用されない

#### AC-DT-14: 通信経路
- 主通信がinbox_write.sh経由で行われる
- tmux send-keysは再nudgeフォールバック時のみ使用される

---

### 2.4 inbox_write.sh 受入基準

#### AC-IW-01: 引数受理
- target, content, type, sender, action の各フィールドが正しくパースされる
- 必須フィールド（target, content）欠損で非ゼロ終了する

#### AC-IW-02: 不正ターゲット拒否
- 空文字列で非ゼロ終了する
- 未登録エージェント名で非ゼロ終了する

#### AC-IW-03: エージェント名バリデーション
- 有効なエージェント名（shogun, karo, gunshi, hayate, kagemaru, hanzo, saizo, kotaro, tobisaru）が受理される

#### AC-IW-04: 忍者→将軍直接送信ブロック（リリースブロッキング）
- sender=hayate, target=shogun の組合せで非ゼロ終了する
- sender=kagemaru, target=shogun の組合せで非ゼロ終了する
- sender=hanzo, target=shogun の組合せで非ゼロ終了する
- sender=saizo, target=shogun の組合せで非ゼロ終了する
- sender=kotaro, target=shogun の組合せで非ゼロ終了する
- sender=tobisaru, target=shogun の組合せで非ゼロ終了する
- 全ケースでエラーメッセージが経路違反を明示する

#### AC-IW-05: メッセージシリアライズ
- `queue/inbox/{agent}.yaml` にメッセージが追記される
- 各レコードに timestamp, id, type, sender, content, read: false, action が含まれる
- 複数メッセージの連続書込みで先行メッセージが消失しない

#### AC-IW-06: WSL2対応flock排他（リリースブロッキング）
- `/mnt/*` パス上のファイルに対してロックファイルが正しく機能する
- 並行書込み（10並列）でメッセージ消失が発生しない
- ロック取得タイムアウトが適切に処理される

#### AC-IW-07: 重複task_assigned配備ブロック
- 同一親cmdのtask_assignedが既にactive状態で存在する場合、新規配備がブロックされる

#### AC-IW-08: 教訓注入セーフティネット
- deploy_taskが教訓注入を実行しなかった場合、inbox_writeがフォールバック注入を実行する

#### AC-IW-09: 報告通知処理
- type=report_received でフォーマットチェックが実行される
- 下流のレビュー/完了トリガーが発火する

#### AC-IW-10: 永続化後nudge送信
- メッセージがファイルに書き込まれた後にのみnudgeが送信される
- nudge送信失敗が非致命的（exit 0維持）

#### AC-IW-11: 永続化優先
- nudge失敗時でもメッセージファイルが正常に保存されている

---

### 2.5 ninja_monitor.sh 受入基準

#### AC-NM-01: シングルトンデーモン
- 2つ目のインスタンスが起動を検出し自動終了する

#### AC-NM-02: ペイン再発見
- tmuxの `@agent_id` 変数から全忍者ペインが再発見される

#### AC-NM-03: idle/busy検出
- `@agent_state`=idle のペインがidle判定される
- last-activeタイムスタンプが閾値超過でidle判定される
- CLI固有のプロンプトパターンでidle判定される
- サブプロセスのクロスチェックでbusy判定が補強される

#### AC-NM-04: clear/respawn安全性
- idle確認済み+レポートゲートクリアの場合のみ `/clear` が送信される
- タスク状態が残っている場合はclearが抑止される

#### AC-NM-05〜11: 異常検出
- AC-NM-05: ペインロスが検出され家老に通知される
- AC-NM-06: 配備後一定時間進捗のないデプロイメントが検出される
- AC-NM-07: delegated状態だが未配備のコマンドが検出される
- AC-NM-08: 家老のpending作業が検出される
- AC-NM-09: CLIプロセス死亡が検出される
- AC-NM-10: 各エージェントのinbox未読数が集計される
- AC-NM-11: 報告YAMLとタスクYAMLの状態ミスマッチが検出される

#### AC-NM-12: karo_snapshot.txt生成
- cmd一覧、忍者配備状態、モデル、コンテキスト消費率、報告状態が含まれる
- フォーマットが `ninja|{name}|{cmd}|{status}|{project}|CTX:{pct}|M:{model}` に準拠する

#### AC-NM-13〜17: インフラ監視
- AC-NM-13: inbox_watcherプロセス不在が検出される
- AC-NM-14: ntfy listenerプロセス不在が検出される
- AC-NM-15: CI失敗が検出され報告される
- AC-NM-16: 修行auto-deploy条件（idle忍者+修行タスク未配備）が検出される
- AC-NM-17: 教訓health、ループhealth、workaround傾向、スクリプトサイズ傾向が集計される

#### AC-NM-18: 検出優先順位
- hook状態（`@agent_state`）がプロンプトパターンより優先される
- 明示的busy証拠がプロンプトのみのidle検出を上書きする

#### AC-NM-19: clear安全ゲート
- active task + report未提出の忍者ペインにclearが送信されない

#### AC-NM-20: 通信経路
- 全通知が `scripts/inbox_write.sh` 経由で送信される
- ad hocメッセージパスが使用されない

---

### 2.6 dashboard_auto_section.sh 受入基準

#### AC-DA-01〜06: データソース読込み
- 以下の全データソースが読込まれ、欠損時は `—` プレースホルダーで降格する:
  - `queue/karo_snapshot.txt`
  - `queue/shogun_to_karo.yaml`
  - `logs/gate_metrics.log`
  - `queue/tasks/*.yaml`
  - `config/settings.yaml`
  - `config/cli_profiles.yaml`
  - `logs/gate_fire_log.yaml`
  - `logs/lesson_impact.tsv`
  - `queue/lesson_effectiveness_status.txt`

#### AC-DA-07: 外部スクリプト実行
- `knowledge_metrics.sh`, `model_analysis.sh`, `context_freshness_check.sh`, `ci_status_check.sh`, `skill_metrics.sh` が呼び出される
- スクリプト失敗時に `—` で降格する

#### AC-DA-08: 10セクション生成
- 忍者配備、CI Status、Unpushed Commits WARN、パイプライン、戦況メトリクス、モデル別スコアボード、知識サイクル健全度、スキル健全度、Context鮮度警告、戦果の10セクションが全て生成される

#### AC-DA-09: --dry-runモード
- stdoutに出力され、`dashboard.md` ファイルに変更が加わらない
- dry-run前後で `dashboard.md` のmd5sumが一致する

#### AC-DA-10: マーカー外コンテンツ保全
- `<!-- DASHBOARD_AUTO_START -->` より前の内容が変更されない
- `<!-- DASHBOARD_AUTO_END -->` より後の内容が変更されない

#### AC-DA-11: ntfy通知重複排除
- CLEAR数が増加した場合のみ通知が送信される
- `/tmp/mas-dashboard-ntfy-last-clear.txt` で重複排除される
- CLEAR数が同一の場合は通知されない

#### AC-DA-12: 取消線エントリ削除
- 将軍宛報告セクションの `~~...~~` エントリが更新後に削除される

#### AC-DA-13〜17: パフォーマンス要件
- AC-DA-13: CIステータスが60秒TTLでキャッシュされる
- AC-DA-14: context freshness結果が120秒TTL、git rev-listが60秒TTLでキャッシュされる
- AC-DA-15: gate_fire_log/gate_metrics/lesson_impact/lesson_effectiveness_statusの計算結果がファイルmtimeキーでキャッシュされる
- AC-DA-16: context_freshness_check.shとci_status_check.shがバックグラウンドプロセスで並列実行される
- AC-DA-17: キャッシュパスが `cksum($PROJECT_DIR)` でプロジェクトスコープ化される

#### AC-DA-18: アトミック書込み
- tmpファイルに書込み後 `mv` で置換される
- 書込み途中でプロセスが中断しても `dashboard.md` が壊れない

#### AC-DA-19: 降格動作
- 個別データソースの欠損で全体がクラッシュしない
- 欠損セクションは `—` で表示される

#### AC-DA-20: 終了コード
- 正常終了: exit 0
- dashboard.md不在: exit 1
- マーカー不在: exit 1

#### AC-DA-21: マーカー不在時の非修正
- マーカーが見つからない場合、dashboard.mdへの一切の書込みが行われない

---

### 2.7 restart_watchers.sh 受入基準

#### AC-RW-01: シングルトン排他
- `/tmp/restart_watchers.lock` に `flock -n` で排他ロックを取得する
- 他インスタンス実行中に非ゼロ終了する

#### AC-RW-02〜03: プロセス停止
- 全既存 `inbox_watcher.sh` プロセスにSIGTERMが送信される
- 1秒待機後に生存プロセスがある場合のみSIGKILLが送信される
- 停止前後でプロセス数がカウントされる

#### AC-RW-04: 将軍watcher起動
- `shogun:main` ペインの `@agent_cli` が解決される
- `nohup inbox_watcher.sh shogun` が起動される
- ログが `logs/inbox_watcher_shogun.log` に出力される

#### AC-RW-05: 家老watcher起動
- `shogun:agents.1` ペインの `@agent_cli` が解決される
- `nohup inbox_watcher.sh karo` が起動される

#### AC-RW-06: 忍者watcher列挙・起動
- `get_all_agents()` から忍者リストが取得される
- karoが列挙からスキップされる
- `pane_lookup()` で各忍者のペインが解決される
- 空ペインの忍者がスキップされる（エラーなし）

#### AC-RW-07: 起動確認
- `pgrep -f "inbox_watcher\.sh.*{agent}"` で各watcherの生存が確認される
- 起動失敗watcherが集計され、1件以上で exit 1 となる

#### AC-RW-08: inotifywait一致チェック
- 2秒待機後にinotifywaitプロセス数が確認される
- watcher数との不一致時に警告が出力される（exit codeには影響しない）

#### AC-RW-09: sync_pane_vars.sh実行
- 全watcher起動後に `scripts/sync_pane_vars.sh` が実行される

#### AC-RW-10: 2段階停止
- SIGTERM→1秒待機→残存確認→必要時のみSIGKILLの順序が厳守される

#### AC-RW-11: ペイン解決失敗の静黙スキップ
- 存在しないペインの忍者が静黙にスキップされる
- ログに警告は出力されるがエラー終了しない

#### AC-RW-12: ログ出力先
- 各watcherのログが `logs/inbox_watcher_{agent}.log` にappendされる

---

### 2.8 yaml_helpers 受入基準（バッチ操作リファクタリング）

#### AC-YH-01: yaml_field_set_batch
- `yaml_field_set_batch <file> <block_id> field1=value1 field2=value2 ...` のAPIで動作する
- 1回のflock取得で全フィールドが同時に更新される
- 1回のawk passで全フィールドが処理される
- 既存フィールドの更新と新規フィールドの追加が混在して動作する

#### AC-YH-02: yaml_field_set_batch verify_after_write
- バッチ全フィールド書込み後に1回だけverify_after_writeが実行される
- 各フィールドの書込み値がverify_after_writeで確認される

#### AC-YH-03: field_get_multi
- `field_get_multi <file> field1 field2 ...` のAPIで動作する
- 1回のawk passで複数フィールドが一括抽出される

#### AC-YH-04: field_get_multi出力形式
- 出力が `field1=value1\nfield2=value2\n...` のeval可能形式である
- 存在しないフィールドは空値で出力される

#### AC-YH-05: resolve_cmd_to_task バッチ化
- yaml_field_set の7回逐次呼出しが yaml_field_set_batch の1回呼出しに置換される
- 出力されるタスクYAMLの内容がリファクタリング前と同一である

#### AC-YH-06: inject_ac_version バッチ化
- field_get の6-7回逐次呼出しが field_get_multi の1回呼出しに置換される
- yaml_field_set の3回逐次呼出しが yaml_field_set_batch の1回呼出しに置換される
- ACバージョン計算結果がリファクタリング前と同一である

#### AC-YH-07: yaml_field_set 後方互換性（リリースブロッキング）
- 既存の `yaml_field_set <file> <block_id> <field> <value>` APIシグネチャが不変である
- 既存の呼出元（deploy_task.sh以外含む全スクリプト）が変更なしで動作する

#### AC-YH-08: field_get 後方互換性（リリースブロッキング）
- 既存の `field_get` APIシグネチャが不変である
- 既存の呼出元が変更なしで動作する

#### AC-YH-09: ゼロリグレッション（リリースブロッキング）
- 全既存テスト（48テスト含む全テストスイート）がPASSする
- SKIPは0件である（SKIP=FAILルール適用）

#### AC-YH-10: flock排他正確性
- yaml_field_set_batch が並行実行（10並列）で正しく排他する
- 並行バッチ書込みでフィールド値の混在・消失が発生しない

### 2.9 パフォーマンス受入基準（リファクタリング）

| 関数 | Before基準値 | After目標 | 短縮率 |
|------|------------|-----------|--------|
| resolve_cmd_to_task | 627ms | ≤100ms | ≥84% |
| inject_ac_version | 541ms | ≤80ms | ≥85% |
| 1テスト合計 | 2639ms | ≤400ms | ≥85% |
| 48テスト(ac_handling) | 34s | ≤5s | ≥85% |

---

## 3. Failure Criteria

以下のいずれかに該当する場合、リリースをブロックする。

### 3.1 データ整合性

| FC-ID | 失敗条件 | 重大度 |
|-------|---------|--------|
| FC-001 | yaml_field_set / yaml_field_set_batch の並行実行でフィールド値の消失・混在が発生する | CRITICAL |
| FC-002 | inbox_write の並行書込みでメッセージレコードが消失する | CRITICAL |
| FC-003 | dashboard_auto_section がマーカー外コンテンツを変更する | CRITICAL |
| FC-004 | deploy_task が完了済み報告ファイルを上書きする | HIGH |
| FC-005 | yaml.dump / yaml.safe_dump が運用YAMLに使用される | CRITICAL |

### 3.2 通信経路

| FC-ID | 失敗条件 | 重大度 |
|-------|---------|--------|
| FC-010 | 忍者senderから将軍targetへのメッセージがinbox_writeを通過する | CRITICAL |
| FC-011 | ninja_monitor がinbox_write.sh以外のパスでエージェントにメッセージを送信する | HIGH |
| FC-012 | deploy_task が inbox_write.sh を経由せず直接tmux send-keysでタスクを配信する（再nudge以外） | HIGH |

### 3.3 安全性

| FC-ID | 失敗条件 | 重大度 |
|-------|---------|--------|
| FC-020 | cmd_save がpending/blocked状態のcmdを委任する | CRITICAL |
| FC-021 | cmd_save がdelegated状態のcmdの変更を許可する | CRITICAL |
| FC-022 | ninja_monitor がactive task+report未提出の忍者ペインをclearする | CRITICAL |
| FC-023 | restart_watchers がSIGTERM段階をスキップしてSIGKILLを送信する | HIGH |
| FC-024 | deploy_task が同一親cmdの完了済みピア報告存在下で重複配備を許可する | HIGH |

### 3.4 テスト品質

| FC-ID | 失敗条件 | 重大度 |
|-------|---------|--------|
| FC-030 | テストスイートにSKIP=1以上が存在する | CRITICAL |
| FC-031 | リファクタリング後に既存テストがFAILする | CRITICAL |
| FC-032 | yaml_field_set/field_get の既存APIシグネチャが変更される | CRITICAL |

### 3.5 パフォーマンス

| FC-ID | 失敗条件 | 重大度 |
|-------|---------|--------|
| FC-040 | resolve_cmd_to_task が100msを超過する | HIGH |
| FC-041 | inject_ac_version が80msを超過する | HIGH |
| FC-042 | 48テスト合計が5sを超過する | HIGH |

### 3.6 インフラ

| FC-ID | 失敗条件 | 重大度 |
|-------|---------|--------|
| FC-050 | restart_watchers がシングルトン排他なしに二重起動する | HIGH |
| FC-051 | ninja_monitor がシングルトン排他なしに二重起動する | HIGH |
| FC-052 | dashboard_auto_section がアトミック書込みなしにdashboard.mdを直接編集する | HIGH |
| FC-053 | dashboard_auto_section のマーカー不在時にファイル修正が行われる | HIGH |

---

## 4. E2E Test Generation Meta-Prompt

### 4.1 テストレベル分離

E2Eテストは以下の2レベルに分離する。本プロジェクトはCLIベースのシェルスクリプト群であるため、「APIテスト」はHTTPエンドポイントではなくスクリプトの終了コード・stdout・ファイル出力を検証するシェル統合テストとなり、「ブラウザテスト」は不要（Web UIなし）。

| レベル | 手法 | 対象 |
|--------|------|------|
| スクリプト統合テスト | bats-core（`@test`） | スクリプトの引数処理、終了コード、ファイル出力、並行安全性 |
| プロセス統合テスト | bats-core + tmux自動操作 | デーモン起動、ペイン操作、プロセスライフサイクル |

### 4.2 MECEドメイン分割

| ドメイン | 責務範囲 | 出力ファイル |
|---------|---------|-------------|
| cmd-save | コマンド品質ゲート全機能（ID正規化、バリデーション、quality_gate、ログ記録） | `tests/e2e/cmd-save.spec.bats` |
| deploy-task | タスク配備全モード（通常/direct/yaml/cmd）、メタデータ解決、報告テンプレート生成 | `tests/e2e/deploy-task.spec.bats` |
| inbox-write | メールボックス書込み全機能（シリアライズ、flock排他、経路制約、nudge） | `tests/e2e/inbox-write.spec.bats` |
| inbox-routing | 忍者→将軍禁止、sender validation、重複task_assignedブロック | `tests/e2e/inbox-routing.spec.bats` |
| ninja-monitor | デーモンライフサイクル、idle/busy検出、異常検出、snapshot生成 | `tests/e2e/ninja-monitor.spec.bats` |
| dashboard-auto | セクション生成、マーカー保全、dry-run、キャッシュ、アトミック書込み | `tests/e2e/dashboard-auto.spec.bats` |
| restart-watchers | シングルトン排他、プロセス停止/起動、inotifywait検証 | `tests/e2e/restart-watchers.spec.bats` |
| yaml-helpers | yaml_field_set_batch、field_get_multi、並行安全性、後方互換性 | `tests/e2e/yaml-helpers.spec.bats` |
| yaml-perf | リファクタリング前後のパフォーマンス計測 | `tests/e2e/yaml-perf.spec.bats` |

### 4.3 シナリオ導出ルール

1. **正常系**: 受入基準（AC-*）ごとに最低1つの `@test` を生成する
2. **異常系**: 失敗基準（FC-*）を反転し、「この失敗が発生しないこと」をアサーションとして生成する
3. **並行系**: flock排他を要求する全モジュール（inbox_write, yaml_helpers, cmd_save）に対し、10並列書込みテストを生成する
4. **境界値**: 空入力、最大長入力、特殊文字（日本語、改行、シングルクォート、ダブルクォート、バックスラッシュ）を含む入力のテストを生成する

### 4.4 アーキテクチャ適応

テスト生成時に以下のスキャンを実行する:

1. `scripts/` ディレクトリをスキャンし、対象スクリプトの実際の関数リストを抽出する
2. `scripts/lib/` ディレクトリをスキャンし、ヘルパーライブラリの実APIを抽出する
3. 未実装の関数（設計書に記載されているがコードに存在しない）は `bats_skip "not yet implemented: <function_name>"` ではなく以下のパターンでマークする:

```bash
@test "yaml_field_set_batch: unimplemented" {
  # @fixme: not yet implemented — yaml_field_set_batch
  skip "FIXME: not yet implemented"
}
```

ただし、SKIP=FAILルールにより `skip` 付きテストはリリースブロッキングとなる。未実装テストは実装完了まで別ファイル（`tests/e2e/pending/`）に隔離し、本テストスイートには含めない。

### 4.5 ランタイム環境

本プロジェクトはWebアプリケーションではなくシェルスクリプト群であるため、サーバー起動は不要。ただし以下の前提条件が必要:

1. **tmux**: `shogun` セッションが存在し、agentsウィンドウのペインが構成されていること
2. **bats-core**: `bats` コマンドが利用可能であること
3. **flock**: `flock` コマンドが利用可能であること（WSL2環境）
4. **テスト用一時ディレクトリ**: 各テストは `setup()` で `$BATS_TMPDIR` 配下に作業ディレクトリを作成し、`teardown()` でクリーンアップする
5. **テスト用fixture**: `tests/fixtures/` にテスト用YAMLファイル、ダミーshogun_to_karo.yaml、ダミーtasks/*.yaml を配置する

CI環境では:
```bash
# tmuxセッション作成（ヘッドレス）
tmux new-session -d -s shogun -x 200 -y 50
# agentsウィンドウ構成
# ... (reset_layout.sh 相当のペイン構成)
# テスト実行
bats tests/e2e/*.spec.bats --formatter tap
```

### 4.6 品質ゲート

| 基準 | 条件 |
|------|------|
| 全テストPASS | FAILが0件 |
| SKIPゼロ | SKIP=FAILルール。SKIPが1件以上あればリリースブロック |
| 受入基準カバレッジ | 全AC-*に対応する `@test` が存在する |
| 失敗基準カバレッジ | 全FC-*に対応する反転アサーションが存在する |
| flock排他検証 | inbox_write, yaml_helpers, cmd_saveの並行テストがPASS |
| 後方互換性 | yaml_field_set/field_get の既存テストがゼロリグレッション |
| パフォーマンス目標 | yaml-perf テストの計測値が目標閾値以内 |

### 4.7 共有ヘルパー

`tests/e2e/helpers/` ディレクトリに以下を配置し、全テストファイルで共有する:

| ファイル | 責務 |
|---------|------|
| `setup_common.bash` | テスト用一時ディレクトリ作成、PATH設定、fixture読込み、PROJECT_DIR設定 |
| `yaml_assertions.bash` | YAMLフィールド値アサーション、ブロック存在チェック、フィールド一覧比較 |
| `inbox_helpers.bash` | テスト用inboxファイル作成、メッセージ追加、未読数カウント |
| `tmux_helpers.bash` | テスト用tmuxセッション作成/破棄、ペイン変数設定、capture-pane |
| `concurrency_helpers.bash` | N並列書込み実行、結果検証、flock競合シミュレーション |
| `perf_helpers.bash` | 実行時間計測（`date +%s%N`）、閾値比較アサーション |

### 4.8 生成マーカー

全生成ファイルの先頭に以下のヘッダーを含める:

```bash
#!/usr/bin/env bats
# @generated-from: docs/test/acceptance_criteria.md
# @generated-by: codd propagate
```

手動テスト（自動生成の補完として人間が書いたテスト）には以下のマーカーを付与する:

```bash
# @manual
@test "edge case: manual verification of ..." {
```

`codd propagate` による再生成時、`# @manual` マーカー付きテストは保持され、上書きされない。

### 4.9 出力ファイルマッピング

| ドメイン | ファイルパス | AC-* カバレッジ |
|---------|------------|----------------|
| cmd-save | `tests/e2e/cmd-save.spec.bats` | AC-CS-01〜AC-CS-17 |
| deploy-task | `tests/e2e/deploy-task.spec.bats` | AC-DT-01〜AC-DT-14 |
| inbox-write | `tests/e2e/inbox-write.spec.bats` | AC-IW-01〜AC-IW-03, AC-IW-05〜AC-IW-11 |
| inbox-routing | `tests/e2e/inbox-routing.spec.bats` | AC-IW-04, AC-IW-07 |
| ninja-monitor | `tests/e2e/ninja-monitor.spec.bats` | AC-NM-01〜AC-NM-20 |
| dashboard-auto | `tests/e2e/dashboard-auto.spec.bats` | AC-DA-01〜AC-DA-21 |
| restart-watchers | `tests/e2e/restart-watchers.spec.bats` | AC-RW-01〜AC-RW-12 |
| yaml-helpers | `tests/e2e/yaml-helpers.spec.bats` | AC-YH-01〜AC-YH-10 |
| yaml-perf | `tests/e2e/yaml-perf.spec.bats` | パフォーマンス基準（§2.9） |
| 共有ヘルパー | `tests/e2e/helpers/*.bash` | （テストインフラ） |
| 未実装隔離 | `tests/e2e/pending/*.spec.bats` | （実装待ちテスト） |

### 4.10 非交渉制約の反映

本テストドキュメントは以下のリリースブロッキング制約を明示的に反映する:

1. **flock排他アトミック書込み（module:inbox_write, module:cmd_save, module:deploy_task, module:yaml_helpers）**: AC-IW-06, AC-CS-17, AC-DT-13, AC-YH-10 で並行安全性を検証。FC-001, FC-002, FC-005 で違反を検出。yaml.dump使用はFC-005およびAC-DT-13で明示的に禁止。
2. **API後方互換性（module:yaml_helpers, module:deploy_task）**: AC-YH-07, AC-YH-08, AC-YH-09 で既存API不変とゼロリグレッションを検証。FC-031, FC-032 で違反を検出。
3. **忍者→将軍直接メッセージ禁止（module:inbox_write）**: AC-IW-04 で全6忍者×将軍の組合せを検証。FC-010 で違反を検出。inbox-routing.spec.bats が専用ドメインとして全経路制約をカバー。
