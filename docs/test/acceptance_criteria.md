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

| モジュール | node_id | 責務 |
|-----------|---------|------|
| `scripts/cmd_save.sh` | `req:script:cmd-save` | 将軍コマンドの品質ゲート。低品質・重複・陳腐化・安全でないコマンドの家老キュー流入を阻止 |
| `scripts/deploy_task.sh` | `req:script:deploy-task` | 忍者へのタスクYAML配備と inbox 経由の起床通知 |
| `scripts/inbox_write.sh` | `req:script:inbox-write` | エージェント間通信のアトミック・メールボックス書込みと起床ブリッジ |
| `scripts/ninja_monitor.sh` | `req:script:ninja-monitor` | tmux陣形の常時監視、idle/stall検知、インフラ健全性維持 |
| `scripts/dashboard_auto_section.sh` | `req:script:dashboard-auto-section` | `dashboard.md` の機械管理セクション自動生成 |
| `scripts/restart_watchers.sh` | `req:script:restart-watchers` | inbox_watcher デーモン群のアトミック再起動と生存確認 |
| `scripts/lib/yaml_field_set.sh` + `scripts/lib/field_get.sh` | `req:deploy-task-refactor-requirements` | YAML バッチ読み書きユーティリティ（`yaml_field_set_batch`, `field_get_multi`） |

### リリースブロック制約（Non-negotiable Conventions）

以下の3制約はリリースゲートであり、全テストシナリオで違反検出時は即FAILとする。

| ID | 制約 | 対象モジュール | 準拠方法 |
|----|------|--------------|---------|
| NNC-1 | flock ベースのアトミック YAML 書込みと inbox パス限定通信 | `inbox_write`, `cmd_save`, `deploy_task`, `yaml_helpers` | 全YAML変更操作が `flock` を経由することをテストで検証。直接 `echo >>` や `yaml.dump` による書込みがないことを grep で確認。通信は `inbox_write.sh` 経由のみ |
| NNC-2 | `yaml_field_set` / `field_get` の API 後方互換性とテストリグレッションゼロ | `yaml_helpers`, `deploy_task` | バッチ関数追加後、既存の単一フィールド呼び出しが同一出力を返すことを差分比較。既存テストスイート全 PASS |
| NNC-3 | 忍者→将軍の直接メッセージ送信禁止 | `inbox_write` | sender=ninja, target=shogun の組合せで `inbox_write.sh` がエラー終了（exit ≠ 0）し、メッセージが書き込まれないことを検証 |

---

## 2. Acceptance Criteria

### 2.0 Verifiable Behavior Traceability Matrix

全依存設計書から抽出した検証可能な振る舞いと、対応するテストシナリオの対応表。

#### cmd_save.sh

| 振る舞いID | 振る舞い | テストシナリオ | 要件元 |
|-----------|---------|--------------|--------|
| VB-CS-01 | 数値ID・`cmd_*` ID を正規化し `shogun_to_karo.yaml` から該当ブロックをロード | AC-CS-01 | FR-1 |
| VB-CS-02 | YAML構文不正を検出しBLOCK | AC-CS-02a | FR-2 |
| VB-CS-03 | 存在しないコマンドIDを拒否 | AC-CS-02b | FR-2 |
| VB-CS-04 | delegated 済みコマンドの変更を拒否 | AC-CS-02c | FR-2, SR-2 |
| VB-CS-05 | 前回 pending/blocked 状態のコマンドを委任しない | AC-CS-02d | FR-2, SR-1 |
| VB-CS-06 | アーカイブ済み重複を検出 | AC-CS-02e | FR-2 |
| VB-CS-07 | 同時ドラフト競合を検出 | AC-CS-02f | FR-2 |
| VB-CS-08 | quality_gate フィールド未設定時にBLOCK | AC-CS-03a | FR-3 |
| VB-CS-09 | 過去BLOCK/WARN歴ありで diagnosis/environment-change 未記載時にBLOCK | AC-CS-03b | FR-3 |
| VB-CS-10 | BLOCK 結果をログとセッション状態ファイルに記録 | AC-CS-04a | FR-4 |
| VB-CS-11 | WARN 結果をログとセッション状態ファイルに記録 | AC-CS-04b | FR-4 |
| VB-CS-12 | PASS 結果をログとセッション状態ファイルに記録 | AC-CS-04c | FR-4 |
| VB-CS-13 | ロック競合時に警告出力 | AC-CS-05a | FR-5 |
| VB-CS-14 | 未コミット実装変更時に警告出力 | AC-CS-05b | FR-5 |
| VB-CS-15 | 重複 GP 番号を検出し警告 | AC-CS-05c | FR-5 |
| VB-CS-16 | 既存軍師分析と重複する偵察/recon コマンドを検出し警告 | AC-CS-05d | FR-5 |
| VB-CS-17 | アクション付き掲示板IDを参照するコマンドで掲示板追跡を更新 | AC-CS-06 | FR-6 |
| VB-CS-18 | 共有キューファイルの操作が flock 経由 | AC-CS-07 | SR-3, NNC-1 |

#### deploy_task.sh

| 振る舞いID | 振る舞い | テストシナリオ | 要件元 |
|-----------|---------|--------------|--------|
| VB-DT-01 | 通常モードでタスクYAMLを配備 | AC-DT-01a | FR-1 |
| VB-DT-02 | `--direct` モードで配備 | AC-DT-01b | FR-1 |
| VB-DT-03 | `--yaml` モードで配備 | AC-DT-01c | FR-1 |
| VB-DT-04 | `--cmd` モードで配備 | AC-DT-01d | FR-1 |
| VB-DT-05 | デフォルトメッセージが古いタスクコンテキストを無効化 | AC-DT-01e | FR-1 |
| VB-DT-06 | ターゲットが空の場合に拒否 | AC-DT-02a | FR-2 |
| VB-DT-07 | ターゲットが `None` の場合に拒否 | AC-DT-02b | FR-2 |
| VB-DT-08 | ターゲットが `cmd_*` IDの場合に拒否 | AC-DT-02c | FR-2 |
| VB-DT-09 | ターゲットが有効な忍者名の場合にのみ受理 | AC-DT-02d | FR-2 |
| VB-DT-10 | tmux/CLI ヘルパー経由でターゲットペイン解決・idle/busy 判定 | AC-DT-03 | FR-3 |
| VB-DT-11 | 古いタスクフィールド・通知フラグ・ghost `None.yaml` をリセット | AC-DT-04 | FR-4 |
| VB-DT-12 | 親cmdからタスクメタデータ（task_id, task_type, project, purpose）を解決 | AC-DT-05a | FR-5 |
| VB-DT-13 | 親cmdから AC, ACバージョン, related_lessons, semantic_concepts, execution_controls を解決 | AC-DT-05b | FR-5 |
| VB-DT-14 | `queue/reports/` に報告テンプレートを生成（完了済み報告を上書きしない） | AC-DT-06 | FR-6 |
| VB-DT-15 | `inbox_write.sh` 経由でタスク通知を配信 | AC-DT-07 | FR-7, NNC-1 |
| VB-DT-16 | YAML操作が共有YAMLヘルパー経由（free-form dump禁止） | AC-DT-08 | SR-1, NNC-1 |
| VB-DT-17 | 完了済みピア報告が存在する場合、同一親cmdの重複配備をブロック | AC-DT-09 | SR-2 |
| VB-DT-18 | 通信は inbox パス経由。tmux 直接送信は re-nudge フォールバックに限定 | AC-DT-10 | SR-3, NNC-1 |

#### inbox_write.sh

| 振る舞いID | 振る舞い | テストシナリオ | 要件元 |
|-----------|---------|--------------|--------|
| VB-IW-01 | target, content, type, sender, action を受理 | AC-IW-01a | FR-1 |
| VB-IW-02 | ターゲット欠落・不正値で拒否（exit ≠ 0） | AC-IW-01b | FR-1 |
| VB-IW-03 | 有効なターゲットエージェント名のバリデーション | AC-IW-02a | FR-2 |
| VB-IW-04 | 忍者→将軍の直接送信を拒否 | AC-IW-02b | FR-2, SR-2, NNC-3 |
| VB-IW-05 | `queue/inbox/{agent}.yaml` にタイムスタンプ・ID・type・sender・content・read状態・action を書込み | AC-IW-03 | FR-3 |
| VB-IW-06 | WSL2 `/mnt/*` パスに対応したロックファイルの使用 | AC-IW-04 | FR-4, NNC-1 |
| VB-IW-07 | 同一親cmdの重複 `task_assigned` をブロック | AC-IW-05 | FR-5 |
| VB-IW-08 | task_assigned でデプロイヘルパー未注入時のレッスン注入セーフティネット | AC-IW-06 | FR-6 |
| VB-IW-09 | 報告通知時にフォーマットチェック実行 | AC-IW-07a | FR-7 |
| VB-IW-10 | 報告通知時に下流のレビュー/完了処理をトリガー | AC-IW-07b | FR-7 |
| VB-IW-11 | メッセージ永続化の後にのみペイン解決・CLI固有nudge送信 | AC-IW-08 | FR-8, SR-1 |
| VB-IW-12 | 全メールボックス更新が flock/アトミック書込みセマンティクスを保持 | AC-IW-09 | SR-3, NNC-1 |

#### ninja_monitor.sh

| 振る舞いID | 振る舞い | テストシナリオ | 要件元 |
|-----------|---------|--------------|--------|
| VB-NM-01 | シングルトンデーモンとして起動（多重起動防止） | AC-NM-01 | FR-1 |
| VB-NM-02 | tmux メタデータから忍者ペインを再発見 | AC-NM-02 | FR-1 |
| VB-NM-03 | `@agent_state`・タイムスタンプ・CLI パターン・サブプロセスで idle/busy 判定 | AC-NM-03 | FR-2 |
| VB-NM-04 | idle 確認と報告ゲートチェック後にのみ clear/respawn 実行 | AC-NM-04 | FR-3, SR-2 |
| VB-NM-05 | ペイン消失を検知 | AC-NM-05a | FR-4 |
| VB-NM-06 | stale デプロイメントを検知 | AC-NM-05b | FR-4 |
| VB-NM-07 | 未デプロイコマンドを検知 | AC-NM-05c | FR-4 |
| VB-NM-08 | 家老 pending ワークを検知 | AC-NM-05d | FR-4 |
| VB-NM-09 | CLI 死亡を検知 | AC-NM-05e | FR-4 |
| VB-NM-10 | inbox 未読カウントを検知 | AC-NM-05f | FR-4 |
| VB-NM-11 | 報告/タスクミスマッチを検知 | AC-NM-05g | FR-4 |
| VB-NM-12 | `queue/karo_snapshot.txt` をcmd・忍者・モデル・コンテキスト・報告状態で生成 | AC-NM-06 | FR-5 |
| VB-NM-13 | inbox watcher, ntfy listener, CI status, training auto-deploy, lesson health, loop health, workaround trends, script size trends を監視 | AC-NM-07 | FR-6 |
| VB-NM-14 | hook state と明示的 busy 証拠をプロンプト単独 idle 検知より優先 | AC-NM-08 | SR-1 |
| VB-NM-15 | エージェント通信は `inbox_write.sh` 経由 | AC-NM-09 | SR-3, NNC-1 |

#### dashboard_auto_section.sh

| 振る舞いID | 振る舞い | テストシナリオ | 要件元 |
|-----------|---------|--------------|--------|
| VB-DA-01 | 9つのデータソースを読み込み | AC-DA-01 | FR-1 |
| VB-DA-02 | 5つの外部スクリプトをサブプロセスとして実行 | AC-DA-02 | FR-2 |
| VB-DA-03 | 10個の出力セクション（忍者配備/CI Status/Unpushed Commits WARN/パイプライン/戦況メトリクス/モデル別スコアボード/知識サイクル健全度/スキル健全度/Context鮮度警告/戦果）を生成 | AC-DA-03 | FR-3 |
| VB-DA-04 | `--dry-run` で stdout 出力のみ、`dashboard.md` 無変更 | AC-DA-04 | FR-4 |
| VB-DA-05 | `<!-- DASHBOARD_AUTO_START -->` / `<!-- DASHBOARD_AUTO_END -->` マーカー外のコンテンツを保持 | AC-DA-05 | FR-5 |
| VB-DA-06 | CLEAR 件数増加時のみ ntfy 通知（`/tmp/mas-dashboard-ntfy-last-clear.txt` で重複排除） | AC-DA-06 | FR-6 |
| VB-DA-07 | 将軍宛報告セクションの取消線エントリを削除 | AC-DA-07 | FR-7 |
| VB-DA-08 | CI status (60s), context freshness (120s), git rev-list (60s) のTTLキャッシュ | AC-DA-08 | PR-1 |
| VB-DA-09 | awk計算のmtimeキー付きキャッシュ | AC-DA-09 | PR-2 |
| VB-DA-10 | `context_freshness_check.sh` と `ci_status_check.sh` のバックグラウンド並列実行 | AC-DA-10 | PR-3 |
| VB-DA-11 | `cksum` ベースのプロジェクトスコープ別キャッシュパス | AC-DA-11 | PR-4 |
| VB-DA-12 | temp file + mv によるアトミック書込み | AC-DA-12 | SR-1 |
| VB-DA-13 | データソース欠落・サブプロセス失敗時に `—` プレースホルダーで graceful degradation | AC-DA-13 | SR-2 |
| VB-DA-14 | 成功時 exit 0、失敗時 exit 1 | AC-DA-14 | SR-3 |
| VB-DA-15 | マーカー不在時は dashboard を変更しない | AC-DA-15 | SR-4 |

#### restart_watchers.sh

| 振る舞いID | 振る舞い | テストシナリオ | 要件元 |
|-----------|---------|--------------|--------|
| VB-RW-01 | `/tmp/restart_watchers.lock` で `flock -n` によるシングルトンロック | AC-RW-01 | FR-1 |
| VB-RW-02 | 既存 `inbox_watcher.sh` を SIGTERM → 1秒待機 → SIGKILL の二段階停止 | AC-RW-02 | FR-2, SR-1 |
| VB-RW-03 | shogun watcher を `shogun:main` ペインの `@agent_cli` から nohup 起動、ログ出力先 `logs/inbox_watcher_shogun.log` | AC-RW-03 | FR-3 |
| VB-RW-04 | karo watcher を `shogun:agents.1` ペインから同パターンで起動 | AC-RW-04 | FR-4 |
| VB-RW-05 | `agent_config.sh::get_all_agents()` で列挙、karo スキップ、ペイン解決、空ペインスキップ | AC-RW-05 | FR-5, SR-2 |
| VB-RW-06 | `pgrep -f "inbox_watcher\.sh.*{agent}"` で各 watcher の生存確認 | AC-RW-06 | FR-6 |
| VB-RW-07 | 2秒後に inotifywait プロセス数 = watcher 数を確認（不一致時に警告） | AC-RW-07 | FR-7 |
| VB-RW-08 | `scripts/sync_pane_vars.sh` を実行 | AC-RW-08 | FR-8 |
| VB-RW-09 | watcher 起動失敗時に exit 1 | AC-RW-09 | FR-6 |

#### yaml_helpers（バッチユーティリティ）

| 振る舞いID | 振る舞い | テストシナリオ | 要件元 |
|-----------|---------|--------------|--------|
| VB-YH-01 | `yaml_field_set_batch` が 1回の flock + 1回の awk pass で複数フィールドを同時更新 | AC-YH-01 | R3 |
| VB-YH-02 | `yaml_field_set_batch` が既存フィールドの更新と新規フィールドの追加を同時処理 | AC-YH-02 | R3 |
| VB-YH-03 | `yaml_field_set_batch` の出力結果が個別 `yaml_field_set` を順次実行した結果と完全一致 | AC-YH-03 | R3, NNC-2 |
| VB-YH-04 | `field_get_multi` が 1回の awk pass で複数フィールドを一括抽出 | AC-YH-04 | R4 |
| VB-YH-05 | `field_get_multi` の出力形式が `field=value\n` の eval 可能形式 | AC-YH-05 | R4 |
| VB-YH-06 | `field_get_multi` の各フィールド結果が個別 `field_get` 結果と完全一致 | AC-YH-06 | R4, NNC-2 |
| VB-YH-07 | `resolve_cmd_to_task` がバッチ化後も同一出力（yaml_field_set 7回→1回） | AC-YH-07 | R1, NNC-2 |
| VB-YH-08 | `inject_ac_version` がバッチ化後も同一出力（field_get 6→1, field_set 3→1） | AC-YH-08 | R2, NNC-2 |
| VB-YH-09 | バッチ化後の `resolve_cmd_to_task` が 100ms 以下で完了 | AC-YH-09 | R1 |
| VB-YH-10 | バッチ化後の `inject_ac_version` が 80ms 以下で完了 | AC-YH-10 | R2 |
| VB-YH-11 | バッチ化後の flock 排他正確性が維持される（並行書込み安全） | AC-YH-11 | R3, NNC-1 |
| VB-YH-12 | 既存 `yaml_field_set` 単一フィールド API が互換維持 | AC-YH-12 | NNC-2 |
| VB-YH-13 | 既存 `field_get` 単一フィールド API が互換維持 | AC-YH-13 | NNC-2 |

**カバレッジ未到達の振る舞い**: なし。全VBに対応するACが存在する。

---

### 2.1 cmd_save.sh

#### AC-CS-01: ID正規化とブロックロード

- 入力 `42` → `cmd_42` として `shogun_to_karo.yaml` からブロックをロード → exit 0
- 入力 `cmd_42` → 同上
- 入力 `cmd_99999`（存在しないID）→ エラーメッセージ出力 → exit ≠ 0

#### AC-CS-02a: YAML構文検証

- `shogun_to_karo.yaml` にインデント不正のブロックを含む場合 → BLOCK 判定、エラー内容を出力

#### AC-CS-02b: コマンド存在検証

- 存在しない cmd ID → BLOCK 判定、「コマンドが見つかりません」相当のメッセージ出力

#### AC-CS-02c: delegated 状態の不変性

- `status: delegated` のコマンドに対して実行 → BLOCK 判定、「delegated 済みコマンドは変更不可」相当のメッセージ出力

#### AC-CS-02d: pending/blocked ゲート状態の委任拒否

- 前回 BLOCK で gate_state が pending のコマンド → BLOCK 判定
- 前回 BLOCK で gate_state が blocked のコマンド → BLOCK 判定

#### AC-CS-02e: アーカイブ重複検出

- アーカイブ済みの同一コマンドID → BLOCK 判定、重複を報告

#### AC-CS-02f: 同時ドラフト競合

- 同一 cmd ID に対して並行実行 → 後発がBLOCKまたは警告

#### AC-CS-03a: quality_gate フィールド強制

- `quality_gate` セクション未設定のコマンド → BLOCK 判定

#### AC-CS-03b: BLOCK/WARN歴時の diagnosis/environment-change 強制

- 過去に BLOCK 歴あり + `diagnosis` 未記載 → BLOCK 判定
- 過去に WARN 歴あり + `environment_change` 未記載 → BLOCK 判定
- 過去に BLOCK 歴あり + `diagnosis` + `environment_change` 記載あり → PASS可能

#### AC-CS-04a/04b/04c: 結果記録

- BLOCK 判定時 → `logs/` 配下の品質ログに BLOCK エントリが追記される + セッション状態ファイルに BLOCK 状態を記録
- WARN 判定時 → 同上（WARN エントリ）
- PASS 判定時 → 同上（PASS エントリ）

#### AC-CS-05a: ロック競合警告

- 別プロセスが `shogun_to_karo.yaml` を flock 中に実行 → 警告メッセージを出力（BLOCKではない）

#### AC-CS-05b: 未コミット変更警告

- 実装ファイルに未コミット変更がある状態で実行 → WARN 出力

#### AC-CS-05c: 重複GP番号警告

- 既存コマンドと同じ GP 番号を持つコマンド → WARN 出力

#### AC-CS-05d: 偵察/recon と軍師分析の重複警告

- 既存の gunshi 分析と重複するスコープを持つ偵察 cmd → WARN 出力

#### AC-CS-06: 掲示板アクション追跡更新

- コマンドが `bulletin_ids` に action-required な ID を参照 → 掲示板追跡ファイルの該当エントリが更新される

#### AC-CS-07: flock 経由の共有ファイル操作

- `shogun_to_karo.yaml` への全書込み操作が flock を経由することを `strace` またはテストモックで確認
- `yaml.dump` / `yaml.safe_dump` による直接書込みが存在しないことをソースコード grep で確認

---

### 2.2 deploy_task.sh

#### AC-DT-01a/01b/01c/01d: 4つのデプロイモード

- 通常モード: `deploy_task.sh hayate` → `queue/tasks/hayate.yaml` が更新される
- `--direct` モード: `deploy_task.sh --direct hayate "直接メッセージ"` → タスク YAML 作成 + inbox 送信
- `--yaml` モード: `deploy_task.sh --yaml hayate /path/to/task.yaml` → 指定YAMLをベースに配備
- `--cmd` モード: `deploy_task.sh --cmd cmd_100 hayate` → cmd_100 からタスクメタデータを解決して配備

#### AC-DT-01e: デフォルトメッセージによる古いコンテキスト無効化

- 配備メッセージに前回タスクのコンテキストを無効化する文言が含まれることを確認

#### AC-DT-02a/02b/02c/02d: ターゲットバリデーション

- ターゲット空文字 → exit ≠ 0, エラーメッセージ出力
- ターゲット `None` → exit ≠ 0, エラーメッセージ出力
- ターゲット `cmd_100` → exit ≠ 0, 「cmd_* はターゲットに指定できません」相当のメッセージ
- ターゲット `hayate`（有効な忍者名）→ 処理続行

#### AC-DT-03: ペイン解決と idle/busy 判定

- tmux/CLI ヘルパーライブラリ経由でターゲットの tmux ペインを解決
- 解決結果に基づき idle/busy 状態を判定（busy 時は警告出力して続行または待機）

#### AC-DT-04: stale 状態リセット

- 配備前に `queue/tasks/{ninja}.yaml` の stale フィールド（古い status, progress 等）がリセットされる
- stale 通知フラグがクリアされる
- `queue/tasks/None.yaml` が存在する場合に削除される

#### AC-DT-05a/05b: 親cmd からのメタデータ解決

- `--cmd cmd_100` 指定時、タスク YAML に以下が設定される:
  - `parent_cmd: cmd_100`
  - `task_id`: 生成された一意のID
  - `task_type`: cmd から継承
  - `project`: cmd から継承
  - `status: assigned`（初期値）
  - `purpose`: cmd から継承
- AC バージョン, `related_lessons`, `semantic_concepts`, `engineering_preferences`, `execution_controls` が cmd から注入される

#### AC-DT-06: 報告テンプレート生成

- `queue/reports/{task_id}.yaml` にテンプレートが生成される
- 既に `status: completed` の報告が存在する場合は上書きされない

#### AC-DT-07: inbox 経由タスク通知

- `scripts/inbox_write.sh` が `type: task_assigned` で呼び出される
- inbox ファイルにメッセージが永続化されていることを確認

#### AC-DT-08: YAML ヘルパー経由の操作

- ソースコード内に `yaml.dump`, `yaml.safe_dump`, `echo >>` による直接YAML書込みがないことを grep で確認
- 全 YAML 変更が `yaml_field_set` または `yaml_field_set_batch` 経由

#### AC-DT-09: 重複配備ブロック

- cmd_100 に対する完了済み報告が `queue/reports/` に存在する状態で再配備 → BLOCK、エラーメッセージ出力

#### AC-DT-10: 通信パス限定

- タスク通知が `inbox_write.sh` 経由であることをテストログで確認
- tmux `send-keys` 直接呼び出しは re-nudge フォールバック時のみ発生

---

### 2.3 inbox_write.sh

#### AC-IW-01a: 引数受理

- `inbox_write.sh karo "メッセージ" report_received hanzo` → 正常終了、メッセージ永続化
- `inbox_write.sh karo "メッセージ"` → type/sender 省略時もデフォルト値で正常終了

#### AC-IW-01b: ターゲット不正で拒否

- `inbox_write.sh "" "msg"` → exit ≠ 0
- `inbox_write.sh invalid_agent "msg"` → exit ≠ 0

#### AC-IW-02a: エージェント名バリデーション

- 有効なエージェント名（shogun, karo, gunshi, hayate, kagemaru, hanzo, saizo, kotaro, tobisaru）→ 受理
- 無効な名前 → exit ≠ 0

#### AC-IW-02b: 忍者→将軍の直接送信禁止（NNC-3）

- `inbox_write.sh shogun "msg" report hanzo` → exit ≠ 0, メッセージが `queue/inbox/shogun.yaml` に書き込まれていないことを確認
- `inbox_write.sh shogun "msg" report karo` → 家老は許可、正常終了

#### AC-IW-03: メッセージレコードのシリアライズ

- 書込み後の `queue/inbox/{agent}.yaml` に以下のフィールドが含まれる:
  - `timestamp`: ISO 8601 形式
  - `id`: 一意の識別子
  - `type`: 指定されたメッセージタイプ
  - `sender`: 送信元エージェント名
  - `content`: メッセージ本文
  - `read: false`（初期値）
  - `action`（指定された場合）

#### AC-IW-04: WSL2 対応ロックファイル

- `/mnt/c/` 配下のプロジェクトで実行した場合も flock が正常に機能する
- 並行 `inbox_write.sh` 実行（10回同時）でメッセージ消失が発生しないことを確認

#### AC-IW-05: 重複 task_assigned ブロック

- cmd_100 に対する active な `task_assigned` が既に存在する状態で再送信 → ブロックまたは警告

#### AC-IW-06: レッスン注入セーフティネット

- `type: task_assigned` でデプロイヘルパーがレッスンを注入していない場合 → inbox_write がフォールバックでレッスン注入を実行

#### AC-IW-07a: 報告フォーマットチェック

- `type: report_received` で報告 YAML が不正な場合 → フォーマットエラーを出力

#### AC-IW-07b: 報告通知の下流処理トリガー

- `type: report_received` 送信後、下流のレビュー/完了ワークフローがトリガーされることを確認

#### AC-IW-08: 永続化→nudge の順序保証

- メッセージが `queue/inbox/{agent}.yaml` に書き込まれた後にのみ、CLI 固有の nudge が送信される
- nudge 失敗時もメッセージは永続化されていることを確認

#### AC-IW-09: flock/アトミック書込み（NNC-1）

- 全書込み操作が flock 排他ロック下で実行される
- 部分書込み（書込み途中のクラッシュ）で inbox ファイルが破損しないことを確認

---

### 2.4 ninja_monitor.sh

#### AC-NM-01: シングルトンデーモン起動

- 2つ目のインスタンスを起動 → 既存インスタンスを検知して起動中止

#### AC-NM-02: tmux ペイン再発見

- tmux ペイン構成が変更された後もメタデータから忍者ペインを正しく再発見

#### AC-NM-03: idle/busy 判定

- `@agent_state` が idle → idle 判定
- CLI プロンプトパターンが表示されている → idle 判定の補助情報
- サブプロセスが実行中 → busy 判定（hook state 優先: VB-NM-14）

#### AC-NM-04: safe clear/respawn

- idle 確認済み + 報告ゲート通過 → clear 実行可能
- idle 確認済み + 報告未提出 → clear 実行不可（SR-2）
- busy 状態 → clear 実行不可

#### AC-NM-05a〜05g: 異常状態検知

- ペイン消失 → `karo_snapshot.txt` に LOST 相当の状態を記録 + inbox_write で家老に通知
- stale デプロイメント（配備から一定時間経過、進捗なし）→ 検知して通知
- 未デプロイコマンド（`shogun_to_karo.yaml` に delegated だが配備なし）→ 検知して通知
- 家老 pending ワーク → 検知して通知
- CLI 死亡（ペインは存在するが CLI プロセスなし）→ 検知して通知
- inbox 未読カウント > 0 → 検知して通知
- 報告/タスクミスマッチ（報告 YAML と タスク YAML の状態不整合）→ 検知して通知

#### AC-NM-06: karo_snapshot.txt 生成

- 出力に以下が含まれる: 各忍者の cmd・ステータス・モデル・コンテキスト使用率・報告状態
- フォーマットがパイプ区切り（`ninja|{name}|{cmd}|{status}|{project}|CTX:{pct}%|M:{model}`）

#### AC-NM-07: インフラ健全性監視

- inbox watcher プロセスの生存を確認
- ntfy listener の生存を確認
- CI ステータスを `gh` コマンド経由で確認
- training auto-deploy 条件を監視
- lesson health（教訓ファイルの整合性）を監視
- loop health（学習ループの稼働状態）を監視
- workaround trends（`logs/karo_workarounds.yaml` の傾向）を監視
- script size trends（スクリプトの行数増加傾向）を監視

#### AC-NM-08: hook state 優先

- `@agent_state: busy`（hook設定）の場合、プロンプトが表示されていても busy と判定

#### AC-NM-09: 通信は inbox_write 経由

- 家老への通知が全て `inbox_write.sh` 経由であることをテストログで確認

---

### 2.5 dashboard_auto_section.sh

#### AC-DA-01: データソース読み込み

- 以下の9ファイルからデータを取得:
  - `queue/karo_snapshot.txt`, `queue/shogun_to_karo.yaml`, `logs/gate_metrics.log`
  - `queue/tasks/*.yaml`, `config/settings.yaml`, `config/cli_profiles.yaml`
  - `logs/gate_fire_log.yaml`, `logs/lesson_impact.tsv`, `queue/lesson_effectiveness_status.txt`

#### AC-DA-02: 外部スクリプト実行

- 以下の5スクリプトをサブプロセスとして呼び出し:
  - `knowledge_metrics.sh`, `model_analysis.sh`, `context_freshness_check.sh`, `ci_status_check.sh`, `skill_metrics.sh`

#### AC-DA-03: 10セクション生成

- 出力に以下の10セクションが全て含まれる: 忍者配備, CI Status, Unpushed Commits WARN, パイプライン, 戦況メトリクス, モデル別スコアボード, 知識サイクル健全度, スキル健全度, Context鮮度警告, 戦果

#### AC-DA-04: --dry-run モード

- `--dry-run` 指定時: 生成内容が stdout に出力される + `dashboard.md` の mtime が変更されない

#### AC-DA-05: マーカー外コンテンツ保持

- `<!-- DASHBOARD_AUTO_START -->` 前と `<!-- DASHBOARD_AUTO_END -->` 後のコンテンツが実行前後で完全一致

#### AC-DA-06: ntfy 通知重複排除

- CLEAR 件数が前回と同じ → ntfy 通知なし
- CLEAR 件数が増加 → ntfy 通知あり
- `/tmp/mas-dashboard-ntfy-last-clear.txt` に最新 CLEAR 件数が記録される

#### AC-DA-07: 取消線エントリ削除

- 将軍宛報告セクションに `~~取消済み~~` エントリがある → 自動セクション更新後に削除されている

#### AC-DA-08/09/10/11: パフォーマンスキャッシュ

- CI status 結果が 60 秒以内の再実行でキャッシュヒット
- context freshness 結果が 120 秒以内の再実行でキャッシュヒット
- git rev-list 結果が 60 秒以内の再実行でキャッシュヒット
- `gate_fire_log.yaml` の mtime 未変化時に awk 再計算をスキップ
- `context_freshness_check.sh` と `ci_status_check.sh` がバックグラウンドで並列起動される
- 異なるプロジェクトディレクトリから実行 → キャッシュパスが異なる（`cksum` ベース）

#### AC-DA-12: アトミック書込み

- 書込み中に SIGTERM → `dashboard.md` が破損していないことを確認（temp file + mv）

#### AC-DA-13: graceful degradation

- `queue/karo_snapshot.txt` が存在しない → 該当セクションに `—` を表示して正常終了
- サブプロセスが exit ≠ 0 → 該当セクションに `—` を表示して正常終了

#### AC-DA-14: 終了コード

- 全データソース存在 + マーカー存在 → exit 0
- `dashboard.md` 不在 → exit 1
- マーカー不在 → exit 1

#### AC-DA-15: マーカー不在時の安全性

- `<!-- DASHBOARD_AUTO_START -->` / `<!-- DASHBOARD_AUTO_END -->` が存在しない → `dashboard.md` は一切変更されない

---

### 2.6 restart_watchers.sh

#### AC-RW-01: シングルトンロック

- 同時に2つ実行 → 後発が `/tmp/restart_watchers.lock` の `flock -n` で即座に exit ≠ 0

#### AC-RW-02: 二段階停止

- 既存 watcher に SIGTERM 送信 → 1秒待機 → 生存プロセスに SIGKILL
- SIGTERM で停止した場合は SIGKILL にエスカレーションしない

#### AC-RW-03/04: shogun/karo watcher 起動

- shogun watcher: `shogun:main` ペインから `@agent_cli` を解決し `nohup inbox_watcher.sh shogun` で起動
- ログが `logs/inbox_watcher_shogun.log` に追記される
- karo watcher: `shogun:agents.1` ペインから同様に起動

#### AC-RW-05: 他エージェント watcher 起動

- `get_all_agents()` で列挙された全エージェントのうち karo 以外に対して watcher を起動
- ペイン解決失敗 → 当該エージェントをスキップ（エラーではなく警告）
- 空ペイン → スキップ

#### AC-RW-06: 生存確認

- 起動後に `pgrep -f "inbox_watcher\.sh.*{agent}"` で各 watcher を確認
- 1つでも起動失敗 → exit 1（失敗リスト出力）

#### AC-RW-07: inotifywait プロセス数確認

- 起動2秒後に inotifywait プロセス数 = 起動成功 watcher 数
- 不一致時 → 警告メッセージ出力（exit コードは変更しない）

#### AC-RW-08: sync_pane_vars 実行

- `scripts/sync_pane_vars.sh` が restart_watchers の完了前に実行されることを確認

#### AC-RW-09: watcher 起動失敗時の終了コード

- 1つ以上の watcher が起動失敗 → exit 1
- 全 watcher 起動成功 → exit 0

---

### 2.7 yaml_helpers（バッチユーティリティ）

#### AC-YH-01: yaml_field_set_batch 基本動作

```bash
yaml_field_set_batch task.yaml hayate \
  parent_cmd=cmd_100 \
  task_id=task_001 \
  status=assigned
```
- 1回の flock 取得 + 1回の awk pass で3フィールドを同時更新
- 結果が以下と完全一致:
  ```bash
  yaml_field_set task.yaml hayate parent_cmd cmd_100
  yaml_field_set task.yaml hayate task_id task_001
  yaml_field_set task.yaml hayate status assigned
  ```

#### AC-YH-02: 既存+新規フィールド混在

- 既存フィールド `status` + 新規フィールド `new_field` を同時に処理
- 既存は値更新、新規は追加

#### AC-YH-03: API 互換性（NNC-2）

- `yaml_field_set` 単一フィールド API のシグネチャ・出力が変更されていない
- バッチ関数追加前の全テストケースが PASS

#### AC-YH-04: field_get_multi 基本動作

```bash
field_get_multi task.yaml ac_version task_id worker_id
```
- 出力: `ac_version=v3\ntask_id=task_001\nworker_id=hayate\n`
- 1回の awk pass で処理

#### AC-YH-05: eval 可能な出力形式

- `field_get_multi` の出力を `eval` に渡した後、各変数がシェル変数として利用可能

#### AC-YH-06: field_get 互換性（NNC-2）

- `field_get` 単一フィールド API のシグネチャ・出力が変更されていない
- 各フィールドの `field_get_multi` 結果 = 個別 `field_get` 結果

#### AC-YH-07/08: リファクタリング後の出力一致

- `resolve_cmd_to_task` のバッチ化前後で同一入力に対する `queue/tasks/{ninja}.yaml` の内容が差分ゼロ
- `inject_ac_version` のバッチ化前後で同一入力に対する AC バージョン・タスクID・ワーカーIDの値が完全一致
- 既存テストスイート48件が全 PASS（SKIP ゼロ）

#### AC-YH-09/10: パフォーマンス目標

- `resolve_cmd_to_task`: before 627ms → after ≤ 100ms
- `inject_ac_version`: before 541ms → after ≤ 80ms
- 計測方法: `time` コマンドの real 値、10回平均

#### AC-YH-11: 並行書込み安全

- 10プロセス同時で `yaml_field_set_batch` を同一ファイルに実行 → 全フィールドが正しく反映、データ消失なし

#### AC-YH-12/13: 既存API後方互換

- `yaml_field_set <file> <block_id> <field> <value>` が引き続き動作
- `field_get <file> <field>` が引き続き動作
- 既存の呼び出し元（`deploy_task.sh`, `cmd_save.sh`, `inbox_write.sh` 等）に変更不要

---

## 3. Failure Criteria

以下のいずれかに該当する場合、テストは **FAIL** とする。

### 3.1 グローバル Failure Criteria

| ID | 条件 | 根拠 |
|----|------|------|
| FC-G-01 | テスト結果に SKIP が 1件以上存在する | SKIP = FAIL（プロジェクトルール） |
| FC-G-02 | flock を経由しない YAML 書込みが検出される | NNC-1 違反 |
| FC-G-03 | `yaml.dump` / `yaml.safe_dump` による運用YAML上書きが検出される | CLAUDE.md YAML書込み安全規則違反 |
| FC-G-04 | 忍者→将軍の直接 inbox 送信が成功する | NNC-3 違反 |
| FC-G-05 | バッチ関数追加後に既存テストがリグレッションする | NNC-2 違反 |
| FC-G-06 | inbox パス以外（tmux send-keys 直接）でタスク配備が主経路として実行される | NNC-1 通信パス制約違反 |

### 3.2 cmd_save.sh Failure Criteria

| ID | 条件 |
|----|------|
| FC-CS-01 | gate_state が pending/blocked のコマンドが委任（delegated）される |
| FC-CS-02 | delegated 済みコマンドの内容が変更される |
| FC-CS-03 | quality_gate 未設定のコマンドが PASS する |
| FC-CS-04 | BLOCK/WARN 歴あり + diagnosis/environment_change 未記載で PASS する |
| FC-CS-05 | BLOCK/WARN/PASS 結果がログに記録されない |

### 3.3 deploy_task.sh Failure Criteria

| ID | 条件 |
|----|------|
| FC-DT-01 | ターゲットが空文字・`None`・`cmd_*` の場合に処理が続行される |
| FC-DT-02 | 完了済みピア報告が存在する cmd に対して重複配備される |
| FC-DT-03 | 完了済み報告 YAML が上書きされる |
| FC-DT-04 | free-form YAML 書込み（`yaml_field_set` 以外の直接操作）が検出される |
| FC-DT-05 | 親 cmd からのメタデータ解決で必須フィールド（parent_cmd, task_id, status）が欠落する |

### 3.4 inbox_write.sh Failure Criteria

| ID | 条件 |
|----|------|
| FC-IW-01 | 不正なターゲットでメッセージが書き込まれる |
| FC-IW-02 | 忍者 sender → shogun target でメッセージが永続化される |
| FC-IW-03 | メッセージ永続化前に nudge が送信される |
| FC-IW-04 | 並行書込み（10同時）でメッセージ消失が発生する |
| FC-IW-05 | メッセージレコードに timestamp, id, type, sender, content, read のいずれかが欠落する |

### 3.5 ninja_monitor.sh Failure Criteria

| ID | 条件 |
|----|------|
| FC-NM-01 | 多重インスタンスが同時稼働する |
| FC-NM-02 | busy 状態のペインが clear される |
| FC-NM-03 | 報告未提出の忍者が clear される |
| FC-NM-04 | 家老への通知が inbox_write 以外の経路で送信される |
| FC-NM-05 | `karo_snapshot.txt` が必須フィールド（cmd, ninja名, status, model, CTX%）を欠落する |

### 3.6 dashboard_auto_section.sh Failure Criteria

| ID | 条件 |
|----|------|
| FC-DA-01 | マーカー外のコンテンツが変更される |
| FC-DA-02 | `--dry-run` で `dashboard.md` が変更される |
| FC-DA-03 | 10セクション中いずれかが出力されない（データソース欠落時の `—` 代替は許容） |
| FC-DA-04 | マーカー不在時に `dashboard.md` が変更される |
| FC-DA-05 | データソース欠落でクラッシュ（exit ≠ 0 で中断、graceful degradation 未実行） |

### 3.7 restart_watchers.sh Failure Criteria

| ID | 条件 |
|----|------|
| FC-RW-01 | 多重インスタンスが同時実行される |
| FC-RW-02 | SIGTERM なしで SIGKILL に直接エスカレーションする |
| FC-RW-03 | watcher 起動失敗が exit 0 で返される |
| FC-RW-04 | ペイン解決失敗がスクリプト全体を中断する（silent skip であるべき） |

### 3.8 yaml_helpers Failure Criteria

| ID | 条件 |
|----|------|
| FC-YH-01 | `yaml_field_set_batch` の結果が個別 `yaml_field_set` 順次実行の結果と異なる |
| FC-YH-02 | `field_get_multi` の各フィールド値が個別 `field_get` 結果と異なる |
| FC-YH-03 | 既存テストスイート48件中 1件でも FAIL または SKIP |
| FC-YH-04 | バッチ化後の `resolve_cmd_to_task` が 100ms を超過（10回平均） |
| FC-YH-05 | バッチ化後の `inject_ac_version` が 80ms を超過（10回平均） |
| FC-YH-06 | 10並行 `yaml_field_set_batch` 実行でデータ消失が発生 |

---

## 4. E2E Test Generation Meta-Prompt

### 4.1 テストレベル分離

E2Eテストは以下の2レベルに厳密に分離する。混在禁止。

| レベル | ツール | 検証対象 | ファイル命名規則 |
|--------|--------|---------|---------------|
| **シェルスクリプト統合テスト** | bats-core + bash | スクリプトの入出力・終了コード・ファイル副作用 | `tests/e2e/<domain>.spec.bats` |
| **tmux 統合テスト** | bats-core + tmux API | ペイン操作・watcher生存・daemon動作 | `tests/e2e/<domain>.tmux.spec.bats` |

本プロジェクトは Web アプリケーションではなくシェルスクリプト基盤のマルチエージェントシステムであるため、ブラウザテストの代わりに tmux 統合テストを採用する。

### 4.2 MECE ドメイン分割

| ドメイン | 所有スコープ | 出力ファイル |
|---------|------------|------------|
| `cmd-save` | cmd_save.sh の品質ゲート全機能 | `tests/e2e/cmd-save.spec.bats` |
| `deploy-task` | deploy_task.sh の配備モード・バリデーション・メタデータ解決 | `tests/e2e/deploy-task.spec.bats` |
| `inbox-write` | inbox_write.sh のメッセージ永続化・ルーティング・排他制御 | `tests/e2e/inbox-write.spec.bats` |
| `inbox-routing` | 忍者→将軍禁止・sender validation 専用 | `tests/e2e/inbox-routing.spec.bats` |
| `ninja-monitor` | ninja_monitor.sh のデーモン・検知・snapshot生成 | `tests/e2e/ninja-monitor.tmux.spec.bats` |
| `dashboard` | dashboard_auto_section.sh のセクション生成・キャッシュ・安全性 | `tests/e2e/dashboard.spec.bats` |
| `watchers` | restart_watchers.sh の停止・起動・生存確認 | `tests/e2e/watchers.tmux.spec.bats` |
| `yaml-helpers` | yaml_field_set_batch / field_get_multi のバッチ操作・互換性 | `tests/e2e/yaml-helpers.spec.bats` |
| `yaml-helpers-perf` | バッチ関数のパフォーマンス計測 | `tests/e2e/yaml-helpers-perf.spec.bats` |
| `concurrency` | 並行書込み安全・flock 排他の横断テスト | `tests/e2e/concurrency.spec.bats` |

### 4.3 シナリオ導出ルール

1. **Acceptance Criteria → 正常系テスト**: 各 AC-XX-NN に対して少なくとも1つの `@test` ケースを生成
2. **Failure Criteria → 異常系テスト**: 各 FC-XX-NN を反転してアサーションに変換（例: FC-IW-02「忍者→将軍でメッセージが永続化される」→ テスト「忍者→将軍で `queue/inbox/shogun.yaml` にエントリが追加されないこと」）
3. **NNC 制約 → ガードテスト**: NNC-1/2/3 の各制約に対して専用の `@test` ケースを生成
4. **境界値**: ID正規化（`0`, `1`, `99999`, `cmd_`, `cmd_0`）、並行数（1, 10）、空ファイル、巨大ファイル

### 4.4 アーキテクチャ適応ルール

- テスト生成時に `scripts/` ディレクトリの実際のスクリプト構造をスキャンし、存在しないスクリプトへの参照を `# @fixme: script not found` でマークする
- 内部関数テストは `source` で対象スクリプトをロードし、関数を直接呼び出す
- tmux ペイン操作を伴うテストは `tmux.spec.bats` ファイルに分離し、CI で tmux セッションが利用不可の場合は `# @requires: tmux` アノテーションで条件付きスキップ（ただし SKIP はローカル開発限定。CI では tmux セッションを起動するか該当テストを除外構成する）

### 4.5 ランタイム環境

```bash
# テスト前提条件
# 1. bats-core インストール済み
# 2. テスト用一時ディレクトリ: $BATS_TMPDIR (bats 自動設定)
# 3. tmux テスト: tmux new-session -d -s test_session でセッション起動
# 4. 共有ヘルパーのロード: load 'helpers/setup'

# テスト実行
bats tests/e2e/          # 全ドメイン
bats tests/e2e/inbox-write.spec.bats  # 単一ドメイン

# CI 環境
# tmux テストは CI ジョブ内で tmux セッションを起動してから実行:
tmux new-session -d -s ci_test
bats tests/e2e/
tmux kill-session -t ci_test
```

### 4.6 品質ゲート

| 基準 | 閾値 |
|------|------|
| 全テスト PASS | 100%（SKIP ゼロ、FC-G-01） |
| Acceptance Criteria カバレッジ | 全 AC-XX-NN に対応する `@test` が存在 |
| Failure Criteria カバレッジ | 全 FC-XX-NN に対応する `@test` が存在 |
| NNC カバレッジ | NNC-1, NNC-2, NNC-3 に対応する専用 `@test` が存在 |
| 並行安全テスト | `concurrency.spec.bats` 内で flock 排他・メッセージ消失ゼロを検証 |
| パフォーマンス回帰 | `yaml-helpers-perf.spec.bats` で閾値（100ms/80ms）を超過しない |

### 4.7 共有ヘルパー

`tests/e2e/helpers/` ディレクトリに以下を配置:

| ファイル | 責務 |
|---------|------|
| `setup.bash` | 一時ディレクトリ作成、テスト用 `queue/inbox/`・`queue/tasks/`・`queue/reports/` の初期化、環境変数設定 |
| `teardown.bash` | 一時ファイル削除、テスト用 tmux セッション破棄 |
| `yaml_fixtures.bash` | テスト用 YAML ファイル生成（`shogun_to_karo.yaml`, タスク YAML, 報告 YAML のテンプレート） |
| `assertions.bash` | YAML フィールド値アサーション、ファイル存在アサーション、flock 検証アサーション |
| `concurrency.bash` | 並行実行ヘルパー（N プロセス同時起動 + 結果収集 + 消失チェック） |
| `tmux_helpers.bash` | tmux セッション起動/破棄、ペイン変数設定、agent_state シミュレーション |

### 4.8 生成マーカー

全生成ファイルに以下のヘッダーを付与:

```bash
# @generated-from: docs/test/acceptance_criteria.md
# @generated-by: codd propagate
```

`# @manual` マーカーが付与されたテストケースは再生成時に保持し、上書きしない。

### 4.9 ファイルマッピング

| ドメイン | 出力パス | AC カバレッジ |
|---------|---------|-------------|
| cmd-save | `tests/e2e/cmd-save.spec.bats` | AC-CS-01〜AC-CS-07 |
| deploy-task | `tests/e2e/deploy-task.spec.bats` | AC-DT-01a〜AC-DT-10 |
| inbox-write | `tests/e2e/inbox-write.spec.bats` | AC-IW-01a〜AC-IW-09 |
| inbox-routing | `tests/e2e/inbox-routing.spec.bats` | AC-IW-02b (NNC-3 専用) |
| ninja-monitor | `tests/e2e/ninja-monitor.tmux.spec.bats` | AC-NM-01〜AC-NM-09 |
| dashboard | `tests/e2e/dashboard.spec.bats` | AC-DA-01〜AC-DA-15 |
| watchers | `tests/e2e/watchers.tmux.spec.bats` | AC-RW-01〜AC-RW-09 |
| yaml-helpers | `tests/e2e/yaml-helpers.spec.bats` | AC-YH-01〜AC-YH-08, AC-YH-11〜AC-YH-13 |
| yaml-helpers-perf | `tests/e2e/yaml-helpers-perf.spec.bats` | AC-YH-09, AC-YH-10 |
| concurrency | `tests/e2e/concurrency.spec.bats` | AC-IW-04, AC-YH-11, FC-IW-04, FC-YH-06 |
| helpers | `tests/e2e/helpers/*.bash` | （テストインフラ） |
