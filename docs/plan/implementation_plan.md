---
codd:
  node_id: plan:implementation-plan
  type: plan
  depends_on:
  - id: detailed_design:module-ownership
    relation: depends_on
    semantic: technical
  - id: detailed_design:shared-state-model
    relation: depends_on
    semantic: technical
  - id: detailed_design:dispatch-flow
    relation: depends_on
    semantic: technical
  - id: test:test-strategy
    relation: constrained_by
    semantic: governance
  depended_by: []
  conventions:
  - targets:
    - module:ninja_monitor
    reason: 'FR-4: Each module extraction step must be followed by full bats test
      suite run (854 tests, zero SKIP). No batch extraction without intermediate verification.'
  - targets:
    - module:ninja_monitor
    - module:idle_management
    - module:stall_detection
    - module:health_checks
    - module:karo_monitor
    - module:pane_management
    - module:report_utils
    - module:state_io
    reason: 'NFR-2: No new external dependencies may be introduced at any extraction
      step.'
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

# Implementation Plan — Extraction Sequence

## 1. Overview

ninja_monitor.sh（3,158行・59関数）を `scripts/lib/monitor/` 配下の7モジュールに純粋分割する。抽出は1モジュールずつ逐次実行し、各ステップの完了後に854 batsテスト全PASS・SKIP=0を確認してから次のステップに進む。並列抽出・バッチ抽出は禁止する。

抽出対象モジュールと関数数:

| モジュール | 関数数 | 責務 |
|-----------|--------|------|
| `state_io.sh` | 2 | 状態ファイルI/O・flock排他制御 |
| `report_utils.sh` | 6 | 報告ファイル解決・ゲート判定 |
| `pane_management.sh` | 9 | tmuxペイン操作・コンテキスト追跡 |
| `idle_management.sh` | 10 | idle検知・clear送信・deploy-stall処理 |
| `stall_detection.sh` | 5 | タスクstall検知・cmd監視 |
| `health_checks.sh` | 10 | インフラ健全性監視・クリーンアップ |
| `karo_monitor.sh` | 5 | 家老固有監視 |

抽出後の `ninja_monitor.sh` 本体は約500行（グローバル変数宣言 Layer 1 ~150行 + source chain + 主ループディスパッチャ Phase A〜F + composite hash + シグナルハンドラ + 残留補助関数 ~12関数）。

**抽出順序の根拠**: モジュール間のクロスモジュール呼び出し依存（`idle_management → report_utils`, `idle_management → state_io`, `stall_detection → report_utils`）により、被呼出し側を先に抽出する。`state_io` と `report_utils` は他モジュールから呼び出される基盤サービスのため最初に抽出する。`pane_management` は `PANE_TARGETS[]` の唯一の書込み所有者であり、後続の `idle_management` と `health_checks` がこれを参照するため3番目に抽出する。`karo_monitor` は他モジュールへの依存が最小のため末尾に配置する。

**コンベンション準拠（FR-4: 中間検証必須）**: `module:ninja_monitor` を対象とし、各モジュール抽出ステップの完了後に854 batsテストスイート全件実行（SKIP=0）を義務付ける。中間検証なしのバッチ抽出は release-blocking 違反である。抽出ステップごとに `bats tests/ --recursive --formatter tap` を実行し、854 PASS・0 FAIL・0 SKIPを確認してから次のステップに進む。

**コンベンション準拠（NFR-2: 新規外部依存禁止）**: `module:ninja_monitor`, `module:idle_management`, `module:stall_detection`, `module:health_checks`, `module:karo_monitor`, `module:pane_management`, `module:report_utils`, `module:state_io` の全モジュールにおいて、いかなる抽出ステップでも新規外部依存（外部コマンド、言語ランタイム、パッケージ）を追加しない。各ステップで `grep -rE 'python3?|node|npm|npx' scripts/lib/monitor/*.sh | wc -l` → 0 を検証する。リファクタリング前後で `$()` / バッククォート経由の外部ツール呼出しを diff し、新規コマンドがないことを確認する。

### 前提条件

- bats-core ≥ 1.5.0 + bats-support + bats-assert + bats-file がインストール済み
- Bash 5.x, WSL2 Ubuntu, NTFS-mounted `/mnt/c` 環境
- tmux 利用可能
- 既存854 batsテストが全PASS・SKIP=0（ベースライン確認済み）

### ゼロ動作変更の原則

関数の物理的移動のみを行う。関数本体の1文字も変更しない（FR-4）。制御フロー・条件分岐・変数操作の変更は一切行わない。関数シグネチャ（引数の数・位置・名前）、戻り値（return code）、副作用（ファイル書込み・tmuxコマンド発行・外部コマンド実行）は分割前後で完全同一とする。

## 2. Milestones

### M0: 準備（ベースライン確立）

**目的**: 抽出作業の前提条件を確立し、ベースラインを記録する。

| ステップ | 作業内容 | 完了条件 |
|---------|---------|---------|
| M0-1 | 既存854 batsテスト実行・結果記録 | 854 PASS・0 FAIL・0 SKIP。`baseline.tap` として保存 |
| M0-2 | 現行 `ninja_monitor.sh` から59関数名を抽出・記録 | `tests/expected_functions.txt`（59行）を作成 |
| M0-3 | 主ループの call graph 確認: `sed -n '/while true/,/^done$/p' scripts/ninja_monitor.sh` で全行列挙 | 本体残留関数リスト確定（OQ-1解決）。Phase A〜F の条件分岐構造を記録（OQ-DF-1解決） |
| M0-4 | 外部ライブラリ source 文の全列挙: `grep -E '^\s*source\s' scripts/ninja_monitor.sh` | Phase 1リスト確定（OQ-4解決）。ファイル数記録 |
| M0-5 | `scripts/lib/monitor/` ディレクトリ作成 | ディレクトリ存在 |
| M0-6 | テストヘルパー作成: `tests/e2e/helpers/mock_globals.bash`, `mock_externals.bash`, `assert_functions.bash`, `setup_tmpdir.bash` | 各ヘルパーが `source` 可能（exit 0） |
| M0-7 | ディスパッチ順序期待値ファイル作成: `tests/expected_dispatch_order.txt` | M0-3 の call graph から自動生成。Phase A〜F の関数呼び出し列を固定 |
| M0-8 | 構造テストファイル作成: `tests/e2e/module-structure.spec.bats` | ファイル存在・source順序・重複検出・行数・依存検証のテスト骨格。モジュール未抽出のため一部テストは `@manual` マーカー付き |

### M1: state_io 抽出

**目的**: 最も小さく依存の少ないモジュールを最初に抽出し、抽出プロセスを検証する。

| ステップ | 作業内容 | 完了条件 |
|---------|---------|---------|
| M1-1 | `scripts/lib/monitor/state_io.sh` を作成。`write_state_file`, `write_karo_snapshot` の2関数を `ninja_monitor.sh` からカット＆ペースト | 関数本体が1文字も変更されていない |
| M1-2 | `ninja_monitor.sh` に `source "$SCRIPT_DIR/lib/monitor/state_io.sh"` を追加。Phase 1 の最終 source 文の後、Phase 2 の最初として配置 | source 文が Phase 1 より後の行番号に存在 |
| M1-3 | 854 batsテスト全件実行 | 854 PASS・0 FAIL・0 SKIP |
| M1-4 | `tests/e2e/state-io.spec.bats` 作成・実行: 独立 sourcing（mock_globals + mock_externals）→ 2関数の `type -t` 検証 | テスト PASS・SKIP=0 |
| M1-5 | 新規外部依存チェック | `grep -rE 'python3?|node|npm|npx' scripts/lib/monitor/state_io.sh | wc -l` → 0 |

### M2: report_utils 抽出

**目的**: `idle_management` と `stall_detection` が依存する共有サービスモジュールを抽出する。

| ステップ | 作業内容 | 完了条件 |
|---------|---------|---------|
| M2-1 | `scripts/lib/monitor/report_utils.sh` を作成。6関数（`get_latest_report_file`, `find_matching_report_file`, `resolve_expected_report_file`, `can_send_clear_with_report_gate`, `check_and_update_done_task`, `is_task_deployed`）をカット＆ペースト | 関数本体不変 |
| M2-2 | `ninja_monitor.sh` に source 文追加。`state_io.sh` の後に配置 | source 順序: `state_io → report_utils` |
| M2-3 | 854 batsテスト全件実行 | 854 PASS・0 FAIL・0 SKIP |
| M2-4 | `tests/e2e/report-utils.spec.bats` 作成・実行: 独立 sourcing → 6関数検証 | テスト PASS・SKIP=0 |
| M2-5 | 新規外部依存チェック | 0 件 |

### M3: pane_management 抽出

**目的**: `PANE_TARGETS[]` の唯一の書込み所有者を抽出する。

| ステップ | 作業内容 | 完了条件 |
|---------|---------|---------|
| M3-1 | `scripts/lib/monitor/pane_management.sh` を作成。9関数（`discover_panes`, `check_pane_survival`, `check_ninja_cli_dead`, `update_context_pct`, `update_all_context_pct`, `get_context_pct`, `check_model_names`, `update_inbox_counts`, `check_shogun_ctx`）をカット＆ペースト | 関数本体不変 |
| M3-2 | `ninja_monitor.sh` に source 文追加。`report_utils.sh` の後に配置 | source 順序: `state_io → report_utils → pane_management` |
| M3-3 | 854 batsテスト全件実行 | 854 PASS・0 FAIL・0 SKIP |
| M3-4 | `tests/e2e/pane-management.spec.bats` 作成・実行: 独立 sourcing → 9関数検証 + `PANE_TARGETS[]` 書込み検証 | テスト PASS・SKIP=0 |
| M3-5 | 新規外部依存チェック | 0 件 |

### M4: idle_management 抽出

**目的**: 最大関数数（10関数）のモジュールを抽出。report_utils と state_io への依存が解決済みであることを前提とする。

| ステップ | 作業内容 | 完了条件 |
|---------|---------|---------|
| M4-1 | `scripts/lib/monitor/idle_management.sh` を作成。10関数（`check_idle`, `safe_send_clear`, `handle_confirmed_idle`, `handle_busy`, `_handle_post_clear_pending`, `_handle_deploy_stall`, `_handle_idle_notify`, `_handle_auto_clear`, `notify_idle_batch`, `_cleanup_stale_keys`）をカット＆ペースト | 関数本体不変 |
| M4-2 | `ninja_monitor.sh` に source 文追加。`pane_management.sh` の後に配置 | source 順序: `... → pane_management → idle_management` |
| M4-3 | 854 batsテスト全件実行 | 854 PASS・0 FAIL・0 SKIP |
| M4-4 | `tests/e2e/idle-management.spec.bats` 作成・実行: 独立 sourcing → 10関数検証 + クロスモジュール呼出し（`can_send_clear_with_report_gate`, `write_state_file`）のモック検証 | テスト PASS・SKIP=0 |
| M4-5 | 新規外部依存チェック | 0 件 |

### M5: stall_detection 抽出

**目的**: `STALL_FIRST_SEEN[]`, `STALL_NOTIFIED[]`, `STALL_COUNT[]` の唯一の書込み所有者を抽出する。

| ステップ | 作業内容 | 完了条件 |
|---------|---------|---------|
| M5-1 | `scripts/lib/monitor/stall_detection.sh` を作成。5関数（`check_stall`, `check_report_done_idle_mismatch`, `list_pending_cmds`, `check_stale_cmds`, `check_undeployed_cmds`）をカット＆ペースト | 関数本体不変 |
| M5-2 | `ninja_monitor.sh` に source 文追加。`idle_management.sh` の後に配置 | source 順序確立 |
| M5-3 | 854 batsテスト全件実行 | 854 PASS・0 FAIL・0 SKIP |
| M5-4 | `tests/e2e/stall-detection.spec.bats` 作成・実行: 独立 sourcing → 5関数検証 + 連想配列書込み・読取り検証 | テスト PASS・SKIP=0 |
| M5-5 | 新規外部依存チェック | 0 件 |

### M6: health_checks 抽出

**目的**: インフラ健全性監視の10関数を抽出する。

| ステップ | 作業内容 | 完了条件 |
|---------|---------|---------|
| M6-1 | `scripts/lib/monitor/health_checks.sh` を作成。10関数（`check_ntfy_listener_health`, `check_inbox_watcher_health`, `check_lesson_health`, `check_loop_health`, `check_workaround_pattern`, `check_gate_improvement`, `check_yaml_size`, `run_cdp_cleanup`, `run_lock_cleanup`, `check_auto_archive`）をカット＆ペースト | 関数本体不変 |
| M6-2 | `ninja_monitor.sh` に source 文追加。`stall_detection.sh` の後に配置 | source 順序確立 |
| M6-3 | 854 batsテスト全件実行 | 854 PASS・0 FAIL・0 SKIP |
| M6-4 | `tests/e2e/health-checks.spec.bats` 作成・実行: 独立 sourcing → 10関数検証 | テスト PASS・SKIP=0 |
| M6-5 | 新規外部依存チェック | 0 件 |

### M7: karo_monitor 抽出

**目的**: 最後のモジュールを抽出し、7モジュール分割を完了する。

| ステップ | 作業内容 | 完了条件 |
|---------|---------|---------|
| M7-1 | `scripts/lib/monitor/karo_monitor.sh` を作成。5関数（`check_karo_pending_cmd`, `check_karo_pending`, `check_karo_clear`, `send_karo_clear`, `check_karo_idle_cycle`）をカット＆ペースト | 関数本体不変 |
| M7-2 | `ninja_monitor.sh` に source 文追加。`health_checks.sh` の後に配置（Phase 2 の末尾） | source 順序: `state_io → report_utils → pane_management → idle_management → stall_detection → health_checks → karo_monitor` |
| M7-3 | 854 batsテスト全件実行 | 854 PASS・0 FAIL・0 SKIP |
| M7-4 | `tests/e2e/karo-monitor.spec.bats` 作成・実行: 独立 sourcing → 5関数検証 | テスト PASS・SKIP=0 |
| M7-5 | 新規外部依存チェック | 0 件 |

### M8: システム統合検証・完了

**目的**: 全モジュール抽出後のシステム統合検証と構造的性質の最終確認。

| ステップ | 作業内容 | 完了条件 |
|---------|---------|---------|
| M8-1 | composite hash 更新: hash算出式を `sha256sum scripts/ninja_monitor.sh scripts/lib/monitor/*.sh | sha256sum` に変更 | glob展開で8ファイルをカバー。`ls scripts/lib/monitor/*.sh | wc -l` → 7 |
| M8-2 | `ninja_monitor.sh` 本体の行数確認 | `wc -l scripts/ninja_monitor.sh` ≤ 500 |
| M8-3 | 関数完全性検証: 59関数が全てモジュール+本体に存在 | `grep -rhE '^\s*(function\s+)?[a-zA-Z_][a-zA-Z_0-9]*\s*\(\)' scripts/lib/monitor/*.sh scripts/ninja_monitor.sh | wc -l` ≥ 59+12（残留） |
| M8-4 | 関数重複なし検証 | `grep ... | sort | uniq -d | wc -l` → 0 |
| M8-5 | FR-3 シャドウイング検証: 7モジュール内に `declare`/`local`/`typeset` による共有変数の再宣言がない | CI検証スクリプト PASS |
| M8-6 | source 順序検証: Phase 1 最終行番号 < Phase 2 最初行番号 | アサーション PASS |
| M8-7 | `tests/e2e/full-chain.system.bats` 作成・実行: 完全 source chain → 59関数全呼出し可能 + 共有状態伝播 + composite hash 変更検知 + WSL2パス互換 | テスト PASS・SKIP=0 |
| M8-8 | `tests/e2e/module-structure.spec.bats` の `@manual` マーカーを除去し全テスト有効化 | テスト PASS・SKIP=0 |
| M8-9 | 既存854 batsテスト + 新規構造テスト全件実行（最終ゲート） | 全 PASS・0 SKIP |
| M8-10 | ディスパッチ順序検証: `expected_dispatch_order.txt` と実際の主ループ内呼び出し順序の diff | diff 出力が空 |

### マイルストーンサマリ

| マイルストーン | 抽出モジュール | 累積抽出関数数 | ゲート |
|--------------|--------------|--------------|--------|
| M0 | （なし: 準備） | 0 / 59 | ベースライン854 PASS |
| M1 | state_io (2) | 2 / 59 | 854 PASS・SKIP=0 |
| M2 | report_utils (6) | 8 / 59 | 854 PASS・SKIP=0 |
| M3 | pane_management (9) | 17 / 59 | 854 PASS・SKIP=0 |
| M4 | idle_management (10) | 27 / 59 | 854 PASS・SKIP=0 |
| M5 | stall_detection (5) | 32 / 59 | 854 PASS・SKIP=0 |
| M6 | health_checks (10) | 42 / 59 | 854 PASS・SKIP=0 |
| M7 | karo_monitor (5) | 47 / 59 | 854 PASS・SKIP=0 |
| M8 | （なし: 統合検証） | 47 抽出 + ~12 残留 = 59 | 全ゲート PASS |

## 3. Risks

| ID | リスク | 影響 | 発生可能性 | 緩和策 |
|----|--------|------|-----------|--------|
| R-01 | 関数カット＆ペースト時に1文字でも変更が入る（空白・改行・コメント含む） | FR-4 違反。既存テスト FAIL | 中 | 各マイルストーンで854 batsテスト全件実行により即座に検出。`diff` でカット元とペースト先を照合。関数本体のみを移動し、周囲のコメント・空行は現状維持 |
| R-02 | source 順序の誤り（Phase 2 モジュールが Phase 1 外部ライブラリより前に source される） | モジュール関数内で `yaml_field_get` 等が `command not found` になる。テスト FAIL | 低 | M0-7 で Phase 1/Phase 2 の行番号ベースCIアサーションを確立。各マイルストーンの source 文追加時に検証 |
| R-03 | グローバル変数のシャドウイング（モジュール内で `declare -A STALL_COUNT` 等を再宣言） | FR-3 違反。連想配列が空で再初期化されデータ消失 | 中 | M8-5 で CI 自動検証（`grep -nE` による共有変数名の `declare`/`local`/`typeset` 検出）。各 `.spec.bats` の独立 sourcing テストでもモック注入後の変数値維持を検証 |
| R-04 | 主ループ内ディスパッチ順序の変更（Phase A〜F の関数呼び出し順序が入れ替わる） | FR-2/FR-4 違反。データ依存DAG崩壊（`PANE_TARGETS[]` 未更新状態で `check_idle` が走る等） | 低 | 抽出作業は関数の移動のみであり、主ループ内のコードは変更しない。M8-10 で `expected_dispatch_order.txt` との diff 検証。`full-chain.system.bats` でトレースログベースの順序検証 |
| R-05 | OQ-1（本体残留関数リスト未確定）の解決遅延 | M0 の完了が遅延。抽出対象の59関数と残留関数の境界が曖昧なまま作業が開始される | 中 | M0-3 で主ループの call graph を最初に確認し、残留関数を確定してから M1 に進む。M0 を完了しないまま M1 以降に進むことを禁止する |
| R-06 | composite hash の glob 展開が7ファイルをカバーしない（ファイル名typo・パス不一致） | 自動再起動がモジュール変更を検知できない | 低 | M8-1 で `ls scripts/lib/monitor/*.sh | wc -l` → 7 を検証。`ninja_monitor.sh` 起動時に glob 展開後のファイル数が7でない場合に `[WARN]` を出力するガードを追加 |
| R-07 | WSL2 NTFS 上で `flock` がモジュール分割後に異なる挙動を示す | `state_io.sh` の排他制御が破綻 | 極低 | 現行の `flock` 利用パターンをそのまま維持（ゼロ動作変更）。既存テストの PASS で検証。`state_io.sh` の `write_state_file` は flock 呼び出し元を集約するため、分割後はむしろロック管理の一貫性が向上する |
| R-08 | テストヘルパー（`mock_globals.bash`）と `ninja_monitor.sh` Layer 1 の宣言乖離 | テストが本番と異なる共有状態で実行され、偽陽性が発生 | 中 | `full-chain.system.bats` のシステム統合テストが本番同等の source chain（mock なし）で検証するため乖離を検出可能。Layer 1 の `declare` 文と `mock_globals.bash` の `declare` 文を `diff` する CI ステップを M8 で実装 |
| R-09 | `_` プレフィックス関数（5関数）が他モジュールから誤って呼び出される | 所有権境界の暗黙的違反。bash には private 関数がないため実行時に検出不可 | 低 | 命名規約（`_` プレフィックス = モジュール内専用）をコードレビューで強制。CI で `_` プレフィックス関数がモジュール外から呼ばれていないことを `grep` で検証 |
| R-10 | 抽出途中で既存854テストが FAIL し、原因特定に時間を要する | マイルストーン進行が停滞 | 中 | 1モジュールずつ逐次抽出することで、FAIL 原因は直前のカット＆ペースト操作に限定される。ロールバック手順（`git checkout -- scripts/ninja_monitor.sh` + `rm -r scripts/lib/monitor/`）で即座に復元可能。ロールバック後に854テスト全PASS を再確認してから原因調査に移る |
