---
codd:
  node_id: governance:adr-modular-refactoring
  type: governance
  depends_on:
  - id: req:shogun-monitor-refactor-requirements
    relation: derives_from
    semantic: governance
  depended_by:
  - id: design:system-design
    relation: constrained_by
    semantic: governance
  conventions:
  - targets:
    - module:ninja_monitor
    - module:idle_management
    - module:stall_detection
    - module:health_checks
    - module:karo_monitor
    - module:pane_management
    - module:report_utils
    - module:state_io
    reason: 'NFR-2/Constraint: Bash 5.x only. No Python, Node.js, or new external
      packages. Pure bash source-splitting.'
  - targets:
    - module:state_io
    - module:health_checks
    - module:pane_management
    reason: 'Constraint: Must work on WSL2 with NTFS-mounted /mnt/c paths (no inotify,
      stat-based polling).'
  modules:
  - ninja_monitor
---

# ADR: Modular Refactoring Approach

## 1. Overview

ninja_monitor.sh（3,158行・59関数の単一ファイル）を `scripts/lib/monitor/` 配下の7モジュールに分割する構造リファクタリングの意思決定記録である。ロジック変更はゼロ、既存854 batsテストの全PASSを維持する。

**対象モジュール一覧:**

| モジュール | 責務 | 主要関数数 |
|-----------|------|-----------|
| `idle_management.sh` | idle検知・clear指揮・deploy-stall処理 | 10 |
| `stall_detection.sh` | タスクstall検知・cmd監視 | 5 |
| `health_checks.sh` | インフラ健全性監視（ntfy/inbox_watcher/lesson/loop/yaml_size等） | 10 |
| `karo_monitor.sh` | 家老専用監視（pending_cmd/idle_cycle/clear送信） | 5 |
| `pane_management.sh` | tmuxペイン操作・コンテキスト追跡・モデル名更新 | 9 |
| `report_utils.sh` | 報告ファイル解決・done判定・report_gate | 6 |
| `state_io.sh` | 状態ファイルI/O・karo_snapshot生成 | 2 |

**アーキテクチャ判断の核:**

- ninja_monitor.sh本体は**ディスパッチャ（主ループ+グローバル変数+source文）として残存**し、約500行に縮小する。20秒ポーリングの主ループ（現L2860-3158）はそのまま維持する。
- 全モジュールは既存外部ライブラリ（`scripts/lib/cli_lookup.sh`等12本）の**後に**sourceされる（NFR-1: Source Order）。外部ライブラリが提供する `yaml_field_get`, `log`, `send_inbox_message` 等の関数に依存するためである。
- 共有状態（`NINJA_NAMES[]`, `PANE_TARGETS[]`, `STALL_FIRST_SEEN[]`, `STALL_NOTIFIED[]`, `STALL_COUNT[]`, `STATE_DIR`, `SCRIPT_DIR`, `LOG` 等のグローバル変数・連想配列）は ninja_monitor.sh 本体で宣言され、全モジュールが直接参照する。bashのsource機構により名前空間は共有される。

**非機能制約の反映:**

- **NFR-2/Bash 5.x純粋分割**: Python, Node.js, 新規外部パッケージの導入を禁止する。全モジュール（`module:ninja_monitor`, `module:idle_management`, `module:stall_detection`, `module:health_checks`, `module:karo_monitor`, `module:pane_management`, `module:report_utils`, `module:state_io`）はbash sourceによる純粋なファイル分割のみで構成する。新しい言語ランタイムやパッケージマネージャへの依存は一切追加しない。
- **WSL2 NTFS互換性**: `module:state_io`, `module:health_checks`, `module:pane_management` は `/mnt/c` 配下のNTFSマウントパスで動作する必要がある。inotifyは使用不可のため、既存のstat-basedポーリング方式を維持する。state_ioのファイル書込み、health_checksのyaml_sizeチェック・lock_cleanup、pane_managementのコンテキスト追跡はいずれもstatコマンドによるポーリングに依拠し、inotify系APIを呼ばない。
- **自動再起動の検知範囲拡大**: ninja_monitor.shのスクリプトハッシュ検知による自動再起動機構は、`scripts/lib/monitor/*.sh` のモジュール変更も検知対象に含める。具体的には、sourceする全モジュールファイルのハッシュを結合したcomposite hashを算出し、変更検知に使用する。
- **テスト独立性（NFR-3）**: 各モジュールはテストフィクスチャから単独でsource可能とする。テスト時は依存関数（`log`, `yaml_field_get` 等）のモック定義後にモジュールをsourceすることで、モジュール単体のテストを実現する。854件のbatsテストは全件PASS・SKIP数ゼロを維持する。

## 2. Decision Log

| # | 決定事項 | 根拠 | 日付 |
|---|---------|------|------|
| D-1 | 7モジュール分割（idle_management / stall_detection / health_checks / karo_monitor / pane_management / report_utils / state_io） | FR-1に基づく機能凝集度分析。59関数を責務別に分類した結果、7グループが自然な境界を形成。各モジュールの関数間結合度が高く、モジュール間結合度が低い。 | 2026-04-13 |
| D-2 | 主ループはninja_monitor.sh本体に残留 | FR-2準拠。ディスパッチャパターンにより、主ループが各モジュールの関数を呼び出す構造を維持。制御フローの可読性を損なわない。 | 2026-04-13 |
| D-3 | グローバル変数・連想配列は本体で宣言、モジュールから直接参照 | FR-3準拠。bashのsource機構では名前空間が共有されるため、引数渡しやラッパー関数は不要な複雑化。既存の動作をそのまま保持する最小変更方針。 | 2026-04-13 |
| D-4 | source順序: 外部ライブラリ12本 → monitor/モジュール7本 | NFR-1準拠。モジュールは外部ライブラリの関数に依存するため、必ず後にsourceする。順序違反はbash実行時にcommand not foundで即時検知される。 | 2026-04-13 |
| D-5 | 新規外部依存の追加を禁止 | NFR-2準拠。Bash 5.xのみ。Python, Node.js, 追加パッケージ一切不可。純粋なbash source分割に限定する。 | 2026-04-13 |
| D-6 | ロジック変更ゼロ・854テスト全PASS必須 | FR-4準拠。リファクタリング前後でdiffが構造移動のみであることを確認する。テスト結果のSKIP数が1以上なら未完了扱い。 | 2026-04-13 |
| D-7 | スクリプトハッシュ検知をcomposite hash方式に拡張 | モジュール変更時もdaemonが自動再起動する必要がある。`sha256sum scripts/ninja_monitor.sh scripts/lib/monitor/*.sh | sha256sum` の二段ハッシュで算出。 | 2026-04-13 |
| D-8 | stat-basedポーリング維持（inotify不使用） | WSL2のNTFSマウント(/mnt/c)ではinotifyが動作しない制約。state_io, health_checks, pane_managementの全I/O操作はstatポーリングに依拠する。 | 2026-04-13 |
| D-9 | 配置先ディレクトリは `scripts/lib/monitor/` | 既存の `scripts/lib/` 配下にサブディレクトリを設けることで、外部ライブラリとモニターモジュールの区別を明確化。既存のlib/*.shとの名前衝突を回避する。 | 2026-04-13 |

**却下した代替案:**

| 代替案 | 却下理由 |
|--------|---------|
| Pythonへの段階的移行 | NFR-2違反。新規言語ランタイム導入禁止。daemonのbash純粋性を維持する。 |
| 関数を個別ファイルに1関数1ファイルで分割 | 59ファイルはsourceオーバーヘッドと管理コストが過大。7モジュールが凝集度と管理性のバランス点。 |
| グローバル変数を引数渡しに全変換 | FR-4（ゼロロジック変更）に違反。59関数のシグネチャ変更は構造リファクタリングの範囲を超える。 |
| サブシェルによるモジュール隔離 | bashのサブシェルではグローバル変数の共有ができず、FR-3に違反する。 |

## 3. Follow-ups

| # | 項目 | 優先度 | トリガー条件 |
|---|------|--------|-------------|
| F-1 | composite hash検知の実装 | 高 | モジュール分割完了直後。自動再起動がモジュール変更を検知できない状態は運用障害に直結する。 |
| F-2 | batsテスト854件の全件実行・PASS確認 | 高 | 各モジュール抽出後。SKIP≥1は未完了扱い。CIパイプライン（cmd_complete_gate.sh）でGATE WARN対象。 |
| F-3 | テストフィクスチャのモジュール単独source検証 | 中 | モジュール分割完了後。各モジュールをモック環境でsourceし、関数が正常に定義されることを確認する。依存関数未定義時のエラーメッセージが明確であることも検証する。 |
| F-4 | ninja_monitor.sh本体の行数計測 | 低 | 分割完了後。目標500行以下。超過時はグローバル変数宣言の整理を検討する。 |
| F-5 | WSL2 NTFS環境での統合テスト | 高 | 分割完了後。`/mnt/c` 配下のqueue/tasks/*.yaml, queue/inbox/*.yaml, logs/ へのread/writeが正常に動作することをstat-basedポーリングで確認する。 |
| F-6 | source順序の自動検証（CIチェック） | 中 | 運用安定後。ninja_monitor.sh内のsource文の順序が「外部ライブラリ→monitor/モジュール」であることをlintで検証するスクリプトの追加を検討する。 |
