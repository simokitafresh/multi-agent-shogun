---
codd:
  node_id: design:system-design
  type: design
  depends_on:
  - id: test:acceptance-criteria
    relation: constrained_by
    semantic: governance
  - id: governance:adr-modular-refactoring
    relation: constrained_by
    semantic: governance
  depended_by:
  - id: detailed_design:module-ownership
    relation: depends_on
    semantic: technical
  - id: detailed_design:shared-state-model
    relation: depends_on
    semantic: technical
  - id: operations:daemon-runbook
    relation: depends_on
    semantic: technical
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
    reason: 'NFR-1: Modules must be sourced after external libraries (scripts/lib/*.sh).
      Source order violation causes undefined function errors at runtime.'
  - targets:
    - module:ninja_monitor
    reason: 'FR-2: Main loop dispatcher must remain in ninja_monitor.sh. Target ~500
      lines (globals + main loop + source statements).'
  - targets:
    - module:ninja_monitor
    reason: 'Constraint: Auto-restart hash detection must cover all module files under
      scripts/lib/monitor/, not just ninja_monitor.sh.'
  modules:
  - ninja_monitor
  - idle_management
  - stall_detection
  - health_checks
  - karo_monitor
  - pane_management
  - report_utils
  - state_io
---

# System Design — Module Split Overview

## 1. Overview

ninja_monitor.sh（3,158行・59関数）を `scripts/lib/monitor/` 配下の7モジュールに純粋分割するリファクタリングのシステム設計書である。ロジック変更ゼロ、既存854 batsテスト全PASS・SKIP=0を維持する構造変更に限定する。

### 1.1 分割対象モジュール

| モジュール | 配置パス | 関数数 | 責務 |
|-----------|---------|--------|------|
| `idle_management.sh` | `scripts/lib/monitor/idle_management.sh` | 10 | idle検知、safe_send_clear、deploy-stall処理、idle通知バッチ |
| `stall_detection.sh` | `scripts/lib/monitor/stall_detection.sh` | 5 | タスクstall検知、report_done/idle不整合検出、pending/stale/undeployed cmd監視 |
| `health_checks.sh` | `scripts/lib/monitor/health_checks.sh` | 10 | ntfy_listener/inbox_watcher/lesson/loop健全性、workaround検知、yaml_size、CDP/lockクリーンアップ、auto_archive |
| `karo_monitor.sh` | `scripts/lib/monitor/karo_monitor.sh` | 5 | 家老pending_cmd/pending監視、clear送信、idle_cycle監視 |
| `pane_management.sh` | `scripts/lib/monitor/pane_management.sh` | 9 | tmuxペイン探索・生存確認・CLI死活監視、コンテキスト%追跡、モデル名/inbox件数更新、将軍CTXチェック |
| `report_utils.sh` | `scripts/lib/monitor/report_utils.sh` | 6 | 報告ファイル解決（latest/matching/expected）、report_gate判定、done_task更新、task_deployed判定 |
| `state_io.sh` | `scripts/lib/monitor/state_io.sh` | 2 | 状態ファイル書込み、karo_snapshot生成 |

合計: **47関数**がモジュールへ抽出される。残り**12関数**（主ループディスパッチャ・グローバル初期化・composite hash算出等）は `ninja_monitor.sh` 本体に残留し、本体は約500行に縮小する。

### 1.2 設計原則

- **ゼロロジック変更**: 関数の移動のみ。シグネチャ・制御フロー・副作用は一切変更しない
- **bash純粋分割**: Bash 5.x の `source` 機構のみ使用。Python, Node.js, 新規外部パッケージの導入は禁止（NFR-2）
- **共有名前空間**: グローバル変数・連想配列は `ninja_monitor.sh` 本体で宣言し、全モジュールが直接参照する。引数渡しへの変換は行わない
- **WSL2 NTFS互換**: `/mnt/c` 配下のNTFSマウントパスで動作する。inotifyは使用不可のため、既存のstat-basedポーリングを維持する（`state_io`, `health_checks`, `pane_management` が該当）

### 1.3 コンベンション準拠表

| コンベンション | 対象モジュール | 本設計書での反映箇所 |
|--------------|--------------|-------------------|
| **NFR-1**: モジュールは外部ライブラリ（`scripts/lib/*.sh`）の後にsourceする。順序違反は実行時に未定義関数エラーを引き起こす | 全8モジュール | §2.2 Source Chain — 外部ライブラリ12本→monitor/モジュール7本の厳密な順序を定義。行番号ベースの検証手順を規定 |
| **FR-2**: 主ループディスパッチャは `ninja_monitor.sh` に残留。目標約500行 | `ninja_monitor` | §2.1 Main File Structure — 本体に残留するコンポーネント（グローバル変数宣言・source文・20秒ポーリング主ループ）を明示。500行上限を設計制約として記載 |
| **Constraint**: 自動再起動ハッシュ検知は `scripts/lib/monitor/` 配下の全モジュールファイルをカバーする | `ninja_monitor` | §2.4 Auto-Restart — composite hash方式（`sha256sum ninja_monitor.sh scripts/lib/monitor/*.sh | sha256sum`）の設計を記載。20秒ポーリングサイクル内での検知を保証 |

## 2. Architecture

### 2.1 Main File Structure（ninja_monitor.sh 本体）

リファクタリング後の `ninja_monitor.sh` は以下の3層で構成される。目標行数: **500行以下**（FR-2）。

```
┌─────────────────────────────────────────┐
│ Layer 1: グローバル変数宣言 (~150行)       │
│  - NINJA_NAMES[]      (indexed array)    │
│  - PANE_TARGETS[]     (indexed array)    │
│  - STALL_FIRST_SEEN[] (associative)      │
│  - STALL_NOTIFIED[]   (associative)      │
│  - STALL_COUNT[]      (associative)      │
│  - STATE_DIR, SCRIPT_DIR, LOG (scalars)  │
│  - POLL_INTERVAL=20                      │
│  - composite hash 初期値                  │
├─────────────────────────────────────────┤
│ Layer 2: Source文 (~30行)                 │
│  ① 外部ライブラリ 12本 (scripts/lib/*.sh) │
│  ② monitor/モジュール 7本                 │
│    (scripts/lib/monitor/*.sh)            │
├─────────────────────────────────────────┤
│ Layer 3: 主ループディスパッチャ (~300行)    │
│  - 20秒ポーリングサイクル (現L2860-3158)   │
│  - composite hash変更検知 → 自動再起動    │
│  - 各モジュール関数の呼び出し              │
│  - ディスパッチャ補助関数 (~12関数)        │
└─────────────────────────────────────────┘
```

### 2.2 Source Chain（NFR-1 準拠）

source順序は厳密に以下を守る。モジュールは外部ライブラリの関数（`yaml_field_get`, `log`, `send_inbox_message` 等）に依存するため、**必ず外部ライブラリの後に**sourceする。順序違反はbash実行時に即座に `command not found` エラーとなる。

```
ninja_monitor.sh
│
│  ── Phase 1: 外部ライブラリ (scripts/lib/*.sh) ──
│  source scripts/lib/cli_lookup.sh
│  source scripts/lib/yaml_field_get.sh
│  source scripts/lib/yaml_field_set.sh
│  source scripts/lib/inbox_utils.sh
│  source scripts/lib/log_utils.sh
│  source scripts/lib/model_resolve.sh
│  source scripts/lib/pane_format.sh
│  ...（12本）
│
│  ── Phase 2: Monitor モジュール (scripts/lib/monitor/*.sh) ──
│  source scripts/lib/monitor/state_io.sh
│  source scripts/lib/monitor/report_utils.sh
│  source scripts/lib/monitor/pane_management.sh
│  source scripts/lib/monitor/idle_management.sh
│  source scripts/lib/monitor/stall_detection.sh
│  source scripts/lib/monitor/health_checks.sh
│  source scripts/lib/monitor/karo_monitor.sh
│
│  ── Phase 3: 主ループ開始 ──
│  while true; do ... sleep $POLL_INTERVAL; done
```

**検証方法**: `ninja_monitor.sh` 内の全source文の行番号を抽出し、Phase 1の最大行番号 < Phase 2の最小行番号であることをアサートする。CI/batsテストで自動検証する。

### 2.3 モジュール間依存関係

```
                    ninja_monitor.sh (dispatcher)
                    ┌──────────┴──────────┐
                    │  globals & arrays    │
                    └──────────┬──────────┘
                               │ source (Phase 1)
                    ┌──────────┴──────────┐
                    │  scripts/lib/*.sh    │
                    │  (12 external libs)  │
                    └──────────┬──────────┘
                               │ source (Phase 2)
          ┌────────┬───────┬───┴───┬────────┬──────────┬──────────┐
          │        │       │       │        │          │          │
     state_io  report  pane_  idle_  stall_  health_  karo_
              _utils  mgmt   mgmt   detect  checks   monitor
```

**モジュール間の直接呼び出し**: モジュール間で関数を直接呼ぶケースが存在する（例: `idle_management.sh` の `handle_confirmed_idle` が `report_utils.sh` の `can_send_clear_with_report_gate` を呼ぶ）。これはbashの共有名前空間により自然に解決される。全モジュールが同一プロセスにsourceされるため、定義済みの全関数は名前で直接呼び出し可能である。

**共有状態へのアクセスパターン**:

| 共有状態 | 型 | 書込みモジュール | 読取りモジュール |
|---------|-----|----------------|----------------|
| `NINJA_NAMES[]` | indexed array | dispatcher（初期化のみ） | idle_management, stall_detection, pane_management, karo_monitor |
| `PANE_TARGETS[]` | indexed array | pane_management | idle_management, health_checks |
| `STALL_FIRST_SEEN[]` | associative array | stall_detection | stall_detection |
| `STALL_NOTIFIED[]` | associative array | stall_detection | stall_detection |
| `STALL_COUNT[]` | associative array | stall_detection | idle_management |
| `STATE_DIR` | scalar | dispatcher（初期化のみ） | state_io, health_checks |
| `SCRIPT_DIR` | scalar | dispatcher（初期化のみ） | 全モジュール |
| `LOG` | scalar | dispatcher（初期化のみ） | health_checks |

### 2.4 Auto-Restart（Composite Hash方式）

既存のスクリプトハッシュ検知による自動再起動機構を拡張し、7モジュールファイルの変更も検知対象に含める。

**算出方式**:
```bash
# 二段ハッシュ: 個別ファイルハッシュ → 結合ハッシュ
COMPOSITE_HASH=$(sha256sum scripts/ninja_monitor.sh scripts/lib/monitor/*.sh | sha256sum | awk '{print $1}')
```

**検知フロー**:
1. 起動時に `COMPOSITE_HASH` を算出・保存
2. 20秒ポーリングの各サイクル末尾で再算出
3. 値が変化した場合、daemonは自身を `exec` で再起動
4. 検知対象: `ninja_monitor.sh` 本体 + `scripts/lib/monitor/*.sh`（7ファイル）= 計8ファイル

**glob展開の保証**: `scripts/lib/monitor/*.sh` はモジュール分割完了後に必ず7ファイルが存在する。ファイル数が7でない場合は起動時に警告を出力する。

### 2.5 ディレクトリ構造

```
scripts/
├── ninja_monitor.sh              # 本体（~500行）: globals + source chain + main loop
├── lib/
│   ├── cli_lookup.sh             # 既存外部ライブラリ（Phase 1 source対象）
│   ├── yaml_field_get.sh         #   〃
│   ├── yaml_field_set.sh         #   〃
│   ├── inbox_utils.sh            #   〃
│   ├── log_utils.sh              #   〃
│   ├── model_resolve.sh          #   〃
│   ├── pane_format.sh            #   〃
│   ├── ...                       #   〃（12本）
│   └── monitor/                  # 新設ディレクトリ（Phase 2 source対象）
│       ├── idle_management.sh    # 10関数
│       ├── stall_detection.sh    #  5関数
│       ├── health_checks.sh      # 10関数
│       ├── karo_monitor.sh       #  5関数
│       ├── pane_management.sh    #  9関数
│       ├── report_utils.sh       #  6関数
│       └── state_io.sh           #  2関数
tests/
├── ...                           # 既存854 batsテスト（変更禁止）
└── e2e/
    ├── helpers/
    │   ├── mock_globals.bash     # グローバル変数・連想配列スタブ
    │   ├── mock_externals.bash   # 外部ライブラリ関数モック
    │   ├── assert_functions.bash # 構造検証ユーティリティ
    │   └── setup_tmpdir.bash     # 一時ディレクトリ管理
    ├── module-structure.spec.bats
    ├── idle-management.spec.bats
    ├── stall-detection.spec.bats
    ├── health-checks.spec.bats
    ├── karo-monitor.spec.bats
    ├── pane-management.spec.bats
    ├── report-utils.spec.bats
    ├── state-io.spec.bats
    └── full-chain.system.bats
```

### 2.6 関数配置マップ（59関数 → 7モジュール + 本体）

**idle_management.sh（10関数）**:
`check_idle`, `safe_send_clear`, `handle_confirmed_idle`, `handle_busy`, `_handle_post_clear_pending`, `_handle_deploy_stall`, `_handle_idle_notify`, `_handle_auto_clear`, `notify_idle_batch`, `_cleanup_stale_keys`

**stall_detection.sh（5関数）**:
`check_stall`, `check_report_done_idle_mismatch`, `list_pending_cmds`, `check_stale_cmds`, `check_undeployed_cmds`

**health_checks.sh（10関数）**:
`check_ntfy_listener_health`, `check_inbox_watcher_health`, `check_lesson_health`, `check_loop_health`, `check_workaround_pattern`, `check_gate_improvement`, `check_yaml_size`, `run_cdp_cleanup`, `run_lock_cleanup`, `check_auto_archive`

**karo_monitor.sh（5関数）**:
`check_karo_pending_cmd`, `check_karo_pending`, `check_karo_clear`, `send_karo_clear`, `check_karo_idle_cycle`

**pane_management.sh（9関数）**:
`discover_panes`, `check_pane_survival`, `check_ninja_cli_dead`, `update_context_pct`, `update_all_context_pct`, `get_context_pct`, `check_model_names`, `update_inbox_counts`, `check_shogun_ctx`

**report_utils.sh（6関数）**:
`get_latest_report_file`, `find_matching_report_file`, `resolve_expected_report_file`, `can_send_clear_with_report_gate`, `check_and_update_done_task`, `is_task_deployed`

**state_io.sh（2関数）**:
`write_state_file`, `write_karo_snapshot`

**ninja_monitor.sh 本体に残留する関数**: 主ループディスパッチャ関数、composite hash算出、初期化・シグナルハンドラ等（約12関数）。これらは主ループの制御フローに密結合しており、抽出するとディスパッチャの可読性が低下するため本体に残す。

**重複排除**: 各関数は厳密に1ファイルにのみ定義される。同一関数名が複数ファイルに存在することは禁止する。CIで `grep` + `uniq -d` による自動検証を実施する。

### 2.7 テスト戦略概要

| レベル | 対象 | 検証内容 | ファイル形式 |
|--------|------|---------|-------------|
| 既存テスト（854件） | 全体 | 動作の同一性。リファクタリング前後で結果が変わらないことが最終ゲート | `tests/**/*.bats` |
| 単体統合テスト | 各モジュール単独 | モック注入後のsource成功、関数定義存在、呼出し可能性 | `tests/e2e/*.spec.bats` |
| システム統合テスト | フルsourceチェーン | 59関数全呼出し可能、共有状態伝播、composite hash変更検知 | `tests/e2e/*.system.bats` |

**リリースゲート**:
- 854既存テスト: 全PASS、SKIP=0（SKIP=FAILとして扱う）
- 新規構造テスト: 全PASS、SKIP=0
- 関数カバレッジ: 59/59関数に存在アサーション
- モジュールカバレッジ: 7/7モジュールに独立sourceテスト
- 重複関数: 0件

**テスト独立性（NFR-3）**: 各モジュールはテストフィクスチャから単独でsource可能とする。`mock_globals.bash` でグローバル変数・連想配列をスタブ化し、`mock_externals.bash` で外部ライブラリ関数（`yaml_field_get`, `log`, `send_inbox_message`, `tmux`, `inotifywait`）をモック定義した後にモジュールをsourceすることで、外部依存なしの単体テストを実現する。

### 2.8 WSL2 NTFS互換性

`state_io`, `health_checks`, `pane_management` はWSL2上の `/mnt/c` 配下NTFSマウントパスで動作する。設計上の制約:

- **inotify不使用**: NTFSマウントではinotifyが動作しないため、全I/O監視はstatコマンドによるポーリングに依拠する
- **ファイルロック**: `flock` はNTFS上で動作する。state_ioの書込みは既存のflock方式を維持する
- **パス形式**: `/home/simokitafresh/multi-agent-shogun/queue/` 等の長いパスを扱う。パス操作にWindowsスタイルのバックスラッシュは使用しない

### 2.9 非機能要件

| 項目 | 閾値 | 根拠 |
|------|------|------|
| ポーリング間隔 | 20秒 | 既存値を維持。変更なし |
| composite hash算出コスト | <100ms/サイクル | sha256sum 8ファイル → 再ハッシュ。実測で数ms |
| source完了時間 | 既存と同等（<500ms） | 7ファイル追加source。bash sourceはファイル読込のみで軽量 |
| テスト実行時間 | 個別ファイル60秒以内、全体300秒以内 | CI timeout設定値 |

## 3. Open Questions

| # | 質問 | 影響範囲 | 決定期限 | 暫定方針 |
|---|------|---------|---------|---------|
| OQ-1 | 本体に残留する約12関数の正確なリスト確定 | ninja_monitor.sh の最終行数、関数配置マップの完成 | モジュール抽出開始前 | 主ループから直接呼ばれるdispatcher補助関数・初期化関数・シグナルハンドラを本体残留とする。抽出作業中に実際のcall graphを確認して確定する |
| OQ-2 | monitor/モジュール7本のsource順序（Phase 2内部の順序） | モジュール間の直接呼び出しがある場合、source順序に依存する可能性 | 抽出作業中に確認 | 現時点では依存関係が低結合のため順序不問と想定。抽出作業中にcall graphを確認し、モジュール間呼出しがある場合は被呼出し側を先にsourceする |
| OQ-3 | composite hashのglob `scripts/lib/monitor/*.sh` がモジュール追加・削除時に自動追従するが、意図しないファイル混入をどう防ぐか | 自動再起動の信頼性 | 分割完了後 | glob展開後のファイル数を7と比較し、不一致時は警告を出力する。ファイル数チェックは主ループの冒頭で毎サイクル実施する |
| OQ-4 | 外部ライブラリ12本の正確なリスト。`model_resolve.sh` と `pane_format.sh` は直近追加（commit 9008af1）であり、他に未把握のライブラリが存在する可能性 | source chain Phase 1の完全性 | 抽出作業開始前 | `grep -E '^\s*source\s' scripts/ninja_monitor.sh` で現行のsource文を全列挙し、Phase 1リストを確定する |
