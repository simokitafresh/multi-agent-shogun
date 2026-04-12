---
codd:
  node_id: test:test-strategy
  type: test
  depends_on:
  - id: detailed_design:module-ownership
    relation: depends_on
    semantic: technical
  - id: test:acceptance-criteria
    relation: constrained_by
    semantic: governance
  depended_by: []
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
    reason: 'FR-4/Constraint: All 854 bats tests must pass with zero SKIP. Each extraction
      step requires full suite verification before proceeding.'
  - targets:
    - module:idle_management
    - module:stall_detection
    - module:health_checks
    - module:karo_monitor
    - module:pane_management
    - module:report_utils
    - module:state_io
    reason: 'NFR-3: Each extracted module must be independently sourceable in bats
      test fixtures with mock setup for external library functions.'
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

# Test Strategy — Zero Regression Verification

## 1. Overview

ninja_monitor.sh（3,158行・59関数）を `scripts/lib/monitor/` 配下の7モジュールに純粋分割するリファクタリングにおいて、**ゼロ動作変更**を証明するテスト戦略を定義する。本戦略は既存854 batsテストの完全パス維持と、モジュール分割固有の構造的性質の追加検証を二本柱とする。

### 対象システム

| コンポーネント | パス | 役割 |
|--------------|------|------|
| 主ループ（dispatcher） | `scripts/ninja_monitor.sh` | グローバル変数宣言・source chain・20秒ポーリング主ループ（分割後 ~500行） |
| idle_management.sh | `scripts/lib/monitor/idle_management.sh` | idle検知・clear送信・deploy-stall処理（10関数） |
| stall_detection.sh | `scripts/lib/monitor/stall_detection.sh` | タスクstall検知・cmd監視（5関数） |
| health_checks.sh | `scripts/lib/monitor/health_checks.sh` | インフラ健全性監視・クリーンアップ（10関数） |
| karo_monitor.sh | `scripts/lib/monitor/karo_monitor.sh` | 家老固有監視（5関数） |
| pane_management.sh | `scripts/lib/monitor/pane_management.sh` | tmuxペイン操作・コンテキスト追跡（9関数） |
| report_utils.sh | `scripts/lib/monitor/report_utils.sh` | 報告ファイル解決・ゲート判定（6関数） |
| state_io.sh | `scripts/lib/monitor/state_io.sh` | 状態ファイルI/O・flock排他制御（2関数） |

### 実行環境

- **OS**: WSL2 Ubuntu, Bash 5.x, NTFS-mounted `/mnt/c` パス
- **テストフレームワーク**: bats-core ≥ 1.5.0 + bats-support + bats-assert + bats-file
- **サーバ不要**: テストはbashファイルを直接sourceして実行。HTTPサーバ・ブラウザは関与しない
- **tmux**: ペイン操作のモックベースラインとして利用可能

### コンベンション準拠

| コンベンション | 準拠方法 |
|--------------|---------|
| **Conv-1（FR-4）**: 全854 batsテストPASS・SKIP=0 | AC-01〜AC-03でテストスイート完全通過を強制。FC-01でSKIPをリリースブロッカーとして扱う。全テストシナリオにSKIP=0アサーションを含む |
| **Conv-2（NFR-3）**: 各モジュールがモック付きで独立sourceableであること | AC-08で7モジュール各々の独立sourcing検証を要求。テストフィクスチャはグローバル変数・連想配列・外部ライブラリ関数のモック注入を実装する |

### テストレベル分離

bashデーモンのリファクタリングであるため、テストレベルはWeb E2Eではなく以下の2層に分離する:

| レベル | Web対応物 | 内容 | ファイルサフィックス |
|-------|----------|------|-------------------|
| **ユニット統合** | APIインテグレーション | 単一モジュールをモック付きでsource → 関数の存在・呼出し可能性・動作を検証 | `.spec.bats` |
| **システム統合** | ブラウザE2E | 完全source chain（ninja_monitor.sh + 全モジュール）→ 端到端の関数ディスパッチ・共有状態伝播を検証 | `.system.bats` |

ユニット統合テストはConv-2（NFR-3: 独立sourceability）を検証する。システム統合テストはFR-4（ゼロ動作変更）をアセンブル済みデーモンとして検証する。

## 2. Acceptance Criteria

### 2.1 検証可能な動作の完全列挙

依存設計書から抽出した全検証可能動作を以下に列挙する。各動作は最低1つのテストシナリオにマッピングされる。

| ID | 検証可能動作 | 出典 | テストシナリオ | テストファイル |
|----|-------------|------|--------------|--------------|
| VB-01 | リファクタリング後に854 batsテスト全PASS | FR-4 | AC-01 | `full-chain.system.bats` |
| VB-02 | SKIPステータスのテストがゼロ | FR-4, Conv-1 | AC-01, AC-02 | `full-chain.system.bats` |
| VB-03 | ninja_monitor.shが7モジュール全てをsource | FR-2 | AC-03 | `module-structure.spec.bats` |
| VB-04 | ninja_monitor.shの行数が500行以下 | FR-2 | AC-04 | `module-structure.spec.bats` |
| VB-05 | 元の59関数全てが主ループから呼出し可能 | FR-1, FR-3 | AC-05 | `full-chain.system.bats` |
| VB-06 | idle_management.shが正確に10関数を含む: check_idle, safe_send_clear, handle_confirmed_idle, handle_busy, _handle_post_clear_pending, _handle_deploy_stall, _handle_idle_notify, _handle_auto_clear, notify_idle_batch, _cleanup_stale_keys | FR-1 | AC-06a | `idle-management.spec.bats` |
| VB-07 | stall_detection.shが正確に5関数を含む: check_stall, check_report_done_idle_mismatch, list_pending_cmds, check_stale_cmds, check_undeployed_cmds | FR-1 | AC-06b | `stall-detection.spec.bats` |
| VB-08 | health_checks.shが正確に10関数を含む: check_ntfy_listener_health, check_inbox_watcher_health, check_lesson_health, check_loop_health, check_workaround_pattern, check_gate_improvement, check_yaml_size, run_cdp_cleanup, run_lock_cleanup, check_auto_archive | FR-1 | AC-06c | `health-checks.spec.bats` |
| VB-09 | karo_monitor.shが正確に5関数を含む: check_karo_pending_cmd, check_karo_pending, check_karo_clear, send_karo_clear, check_karo_idle_cycle | FR-1 | AC-06d | `karo-monitor.spec.bats` |
| VB-10 | pane_management.shが正確に9関数を含む: discover_panes, check_pane_survival, check_ninja_cli_dead, update_context_pct, update_all_context_pct, get_context_pct, check_model_names, update_inbox_counts, check_shogun_ctx | FR-1 | AC-06e | `pane-management.spec.bats` |
| VB-11 | report_utils.shが正確に6関数を含む: get_latest_report_file, find_matching_report_file, resolve_expected_report_file, can_send_clear_with_report_gate, check_and_update_done_task, is_task_deployed | FR-1 | AC-06f | `report-utils.spec.bats` |
| VB-12 | state_io.shが正確に2関数を含む: write_state_file, write_karo_snapshot | FR-1 | AC-06g | `state-io.spec.bats` |
| VB-13 | モジュールsourceが外部ライブラリsourceの後（Phase 1 → Phase 2順序） | NFR-1 | AC-07 | `module-structure.spec.bats` |
| VB-14 | 各モジュールがモック付きで独立sourceable | NFR-3, Conv-2 | AC-08 | 各 `*.spec.bats` |
| VB-15 | 新規外部依存が追加されていない | NFR-2 | AC-09 | `module-structure.spec.bats` |
| VB-16 | モニターデーモンにPython/Node.jsが存在しない | Constraint | AC-09 | `module-structure.spec.bats` |
| VB-17 | 自動再起動がモジュールファイル変更を検知（composite hash） | Constraint | AC-10 | `full-chain.system.bats` |
| VB-18 | グローバル変数（NINJA_NAMES[], PANE_TARGETS[], STATE_DIR等）が全モジュールからアクセス可能 | FR-3 | AC-11 | `full-chain.system.bats` |
| VB-19 | 連想配列（STALL_FIRST_SEEN[], STALL_NOTIFIED[], STALL_COUNT[]）が全モジュールからアクセス可能 | FR-3 | AC-11 | `full-chain.system.bats` |
| VB-20 | 外部ライブラリ関数（yaml_field_get, log, send_inbox_message）が全モジュールから呼出し可能 | FR-3 | AC-12 | `full-chain.system.bats` |
| VB-21 | WSL2 NTFS-mounted `/mnt/c` パスで動作 | Constraint | AC-13 | `full-chain.system.bats` |
| VB-22 | モジュールファイルが `scripts/lib/monitor/*.sh` に存在 | FR-1 | AC-14 | `module-structure.spec.bats` |
| VB-23 | 関数が複数モジュールに重複定義されていない | FR-1 | AC-15 | `module-structure.spec.bats` |
| VB-24 | 関数欠落なし（元の59関数が全てモジュール+本体に存在） | FR-1, FR-4 | AC-05 | `module-structure.spec.bats`, `full-chain.system.bats` |

### 2.2 トレーサビリティ・カバレッジ確認

全VB-ID（VB-01〜VB-24）が少なくとも1つのテストドメインファイルにマッピングされている。カバレッジギャップ: なし。

### 2.3 受入基準定義

**AC-01: テストスイート全PASS**

既存854 batsテストを完全実行し、854 PASS・0 FAIL・0 SKIPを確認する。exit code 0。これがプライマリ・リリースゲートである。

```bash
bats tests/ --recursive --formatter tap | tee baseline.tap
PASS_COUNT=$(grep -c '^ok' baseline.tap)
SKIP_COUNT=$(grep -c '# skip' baseline.tap)
[[ "$PASS_COUNT" -eq 854 ]] && [[ "$SKIP_COUNT" -eq 0 ]]
```

**AC-02: SKIP=FAIL強制**

bats TAP出力を解析し、`^ok .* # skip` にマッチする行が1行でもあればbats exit codeに関係なくFAILとする。CIでbats exit statusとは独立にskipマーカーをgrepチェックする。

**AC-03: モジュールsource chain**

`ninja_monitor.sh` が7モジュール全てのsource文を含む:
- `scripts/lib/monitor/idle_management.sh`
- `scripts/lib/monitor/stall_detection.sh`
- `scripts/lib/monitor/health_checks.sh`
- `scripts/lib/monitor/karo_monitor.sh`
- `scripts/lib/monitor/pane_management.sh`
- `scripts/lib/monitor/report_utils.sh`
- `scripts/lib/monitor/state_io.sh`

検証: `grep -c 'source.*scripts/lib/monitor/' scripts/ninja_monitor.sh` → 7

**AC-04: 本体ファイルサイズ縮小**

`wc -l scripts/ninja_monitor.sh` ≤ 500行（3,158行からの縮小）。本体にはグローバル変数宣言・source文・主ループディスパッチャのみを残留する。

**AC-05: 関数完全性**

元の59関数全てが呼出し可能であること。リファクタリング前の `ninja_monitor.sh` から関数名を抽出し、各関数が7モジュールまたはリファクタリング後の本体のいずれか1箇所に存在することを検証する。

**AC-06a〜g: モジュール別関数割当**

各モジュールがFR-1で指定された正確な関数セットを含む（VB-06〜VB-12参照）。モジュールファイルから関数定義をgrepし、期待セットとの完全一致をアサートする。

| AC | モジュール | 関数数 |
|----|----------|--------|
| AC-06a | idle_management.sh | 10 |
| AC-06b | stall_detection.sh | 5 |
| AC-06c | health_checks.sh | 10 |
| AC-06d | karo_monitor.sh | 5 |
| AC-06e | pane_management.sh | 9 |
| AC-06f | report_utils.sh | 6 |
| AC-06g | state_io.sh | 2 |

**AC-07: source順序正確性**

`ninja_monitor.sh` 内で、全ての `source scripts/lib/monitor/*.sh` 行が全ての `source scripts/lib/*.sh` 行より後に出現する。行番号を抽出し、外部ライブラリの最終行番号 < モジュールの最初行番号をアサートする。

```bash
LAST_P1=$(grep -n 'source.*scripts/lib/[^m]' scripts/ninja_monitor.sh | tail -1 | cut -d: -f1)
FIRST_P2=$(grep -n 'source.*scripts/lib/monitor/' scripts/ninja_monitor.sh | head -1 | cut -d: -f1)
[[ "$LAST_P1" -lt "$FIRST_P2" ]]
```

**AC-08: 独立sourcing（Conv-2/NFR-3準拠）**

7モジュール各々に対し、以下の最小テストフィクスチャで検証する:

1. 必要なグローバル変数をスタブ宣言（NINJA_NAMES, PANE_TARGETS, STATE_DIR, SCRIPT_DIR, LOG, STALL_FIRST_SEEN, STALL_NOTIFIED, STALL_COUNT等）
2. 外部依存のモック関数を定義（yaml_field_get, log, send_inbox_message, tmux等）
3. 対象モジュール1ファイルのみをsource
4. アサート: source終了コード0、モジュール内の全関数が定義済み（`type -t` で確認）、未解決関数エラーなし

**AC-09: 新規依存なし**

- リファクタリング前後で外部ツール呼出し（`$()` またはバッククォート経由）をdiffし、新規コマンドがないことを確認
- 全モジュールファイルに `python`, `python3`, `node`, `npm`, `npx` 呼出しが存在しないことを確認
- 新規 `apt`, `pip`, `npm install` が不要であることを確認

```bash
grep -rE 'python3?|node|npm|npx' scripts/lib/monitor/*.sh | wc -l
# Assert: 0
```

**AC-10: 自動再起動ハッシュ検知**

composite hash算出が8ファイル（本体1 + モジュール7）をカバーする:

1. `scripts/lib/monitor/idle_management.sh` の1行を変更
2. デーモンが1ポーリングサイクル（20秒）以内にハッシュ変更を検知し再起動をトリガー
3. 変更を元に戻し、ハッシュが元の値に復帰することを確認

glob展開のカバレッジ検証:
```bash
MODULE_COUNT=$(ls scripts/lib/monitor/*.sh 2>/dev/null | wc -l)
[[ "$MODULE_COUNT" -eq 7 ]]
```

**AC-11: 共有状態アクセシビリティ**

グローバル変数・連想配列が全モジュール関数内からアクセス可能:

1. 全モジュールを順にsource
2. source前に `NINJA_NAMES[0]="test_ninja"` を設定
3. `idle_management.sh` の `check_idle` 等から `NINJA_NAMES[0]` を読取り、`"test_ninja"` を受信したことをアサート
4. 連想配列: `STALL_COUNT["test"]=5` を設定、`stall_detection.sh` の関数からアクセスを確認

**AC-12: 外部ライブラリ関数アクセス**

完全source chain実行後、各モジュール内の関数から `scripts/lib/*.sh` の関数（yaml_field_get, log, send_inbox_message等）が呼出し可能であり、"command not found" エラーが発生しないことを検証する。

**AC-13: WSL2 /mnt/c パス互換性**

モジュール内の全ファイルI/O操作がNTFS-mounted `/mnt/c` 配下のパスを正しく処理する。既存テストのファイル操作テストが引き続きPASSすることで確認（AC-01でカバー）。

**AC-14: モジュールファイル存在**

7ファイルが指定パスに存在:
```bash
for m in idle_management stall_detection health_checks karo_monitor pane_management report_utils state_io; do
  test -f "scripts/lib/monitor/${m}.sh"
done
```

**AC-15: 関数重複なし**

関数名が複数ファイル（7モジュール + ninja_monitor.sh）にわたって重複定義されていない:
```bash
grep -rhE '^\s*(function\s+)?[a-zA-Z_][a-zA-Z_0-9]*\s*\(\)' \
  scripts/lib/monitor/ scripts/ninja_monitor.sh \
  | sed 's/().*//' | sort | uniq -d | wc -l
# Assert: 0
```

## 3. Failure Criteria

以下の条件のいずれかが発生した場合、リリースブロッキング失敗とする。

| ID | 失敗条件 | 重大度 | トリガーAC | 対応するVB |
|----|---------|--------|----------|-----------|
| FC-01 | batsテストのSKIPが1件以上 | **BLOCK** | AC-01, AC-02 | VB-01, VB-02 |
| FC-02 | batsテストのFAILが1件以上 | **BLOCK** | AC-01 | VB-01 |
| FC-03 | batsテスト総数 ≠ 854（テスト消失または重複） | **BLOCK** | AC-01 | VB-01 |
| FC-04 | モジュールがモック付きで独立sourceできない（exit ≠ 0 or 未解決関数） | **BLOCK** | AC-08 | VB-14 |
| FC-05 | 元の59関数のいずれかがリファクタリング後に欠落 | **BLOCK** | AC-05 | VB-05, VB-24 |
| FC-06 | 関数が複数ファイルに定義されている | **BLOCK** | AC-15 | VB-23 |
| FC-07 | モジュールsource文が外部ライブラリsource文より前に出現 | **BLOCK** | AC-07 | VB-13 |
| FC-08 | ninja_monitor.shが500行を超過 | **WARN** | AC-04 | VB-04 |
| FC-09 | `scripts/lib/monitor/` のモジュールファイル数 ≠ 7 | **BLOCK** | AC-14 | VB-22 |
| FC-10 | 自動再起動がモジュールファイル変更を検知できない | **BLOCK** | AC-10 | VB-17 |
| FC-11 | 新規外部ツール・言語・パッケージ依存の追加 | **BLOCK** | AC-09 | VB-15 |
| FC-12 | モジュール内にpython/python3/node呼出しが存在 | **BLOCK** | AC-09 | VB-16 |
| FC-13 | モジュール関数からグローバル変数/連想配列にアクセスできない | **BLOCK** | AC-11 | VB-18, VB-19 |
| FC-14 | モジュール関数から外部ライブラリ関数を呼出せない | **BLOCK** | AC-12 | VB-20 |

### 失敗時のロールバック手順

FC-01〜FC-14のいずれかがBLOCK判定された場合:

```bash
git checkout -- scripts/ninja_monitor.sh
rm -r scripts/lib/monitor/    # プロジェクトツリー内のため安全
bats tests/ --recursive --formatter tap   # 854全PASS・SKIP=0を確認
```

ロールバックは関数を元の1ファイルに戻すだけで完了する。データ損失・状態破壊のリスクはない。

## 4. E2E Test Generation Meta-Prompt

### 4.1 コンテキスト

対象はbashデーモンのリファクタリングである。テスト対象は `scripts/ninja_monitor.sh` と `scripts/lib/monitor/` 配下の7モジュール。テストフレームワークはbats-core。Webエンドポイント・HTTPサーバ・ブラウザは関与しない。全テストはbashシェル環境で直接実行する。

### 4.2 既存テストベースライン

854 batsテストが `tests/` 配下に存在する。これらのテストの変更・削除・スキップは禁止する。生成されるテストは**追加テスト**であり、既存テストがカバーしないリファクタリング構造的性質を検証する。

### 4.3 テストレベル分離

| レベル | 検証対象 | ファイルサフィックス |
|-------|---------|-------------------|
| **ユニット統合** | 単一モジュールをモック付きでsource → 関数存在・動作検証 | `.spec.bats` |
| **システム統合** | 完全source chain → 端到端ディスパッチ・共有状態伝播・自動再起動検知 | `.system.bats` |

ユニット統合テストは各モジュールの独立sourceability（Conv-2/NFR-3）を検証する。システム統合テストはアセンブル済みデーモンの動作一致（FR-4）を検証する。

サーバヘルスベースライン: batsテストではHTTPステータスコードは不要だが、同等の原則として各source操作の終了コードを最初に検証する。source失敗（exit ≠ 0）は以降の全アサーションに先立つ基本チェックとする。

### 4.4 MECEドメイン分解

| ドメイン | スコープ | 出力ファイル |
|---------|--------|-------------|
| `module-structure` | ファイル存在・関数割当・重複なし・行数・source順序・新規依存なし・Python/Node禁止 | `tests/e2e/module-structure.spec.bats` |
| `idle-management` | idle_management.shの独立sourcing・10関数呼出し可能・グローバル変数モック注入 | `tests/e2e/idle-management.spec.bats` |
| `stall-detection` | stall_detection.shの独立sourcing・5関数呼出し可能・連想配列アクセス | `tests/e2e/stall-detection.spec.bats` |
| `health-checks` | health_checks.shの独立sourcing・10関数呼出し可能・外部コマンドモック | `tests/e2e/health-checks.spec.bats` |
| `karo-monitor` | karo_monitor.shの独立sourcing・5関数呼出し可能・tmuxモック | `tests/e2e/karo-monitor.spec.bats` |
| `pane-management` | pane_management.shの独立sourcing・9関数呼出し可能・tmuxモック・PANE_TARGETS書込み | `tests/e2e/pane-management.spec.bats` |
| `report-utils` | report_utils.shの独立sourcing・6関数呼出し可能・ファイルI/Oモック | `tests/e2e/report-utils.spec.bats` |
| `state-io` | state_io.shの独立sourcing・2関数呼出し可能・flock書込み検証 | `tests/e2e/state-io.spec.bats` |
| `full-chain` | 完全source chain・共有状態伝播・自動再起動ハッシュ検知・59関数全呼出し可能 | `tests/e2e/full-chain.system.bats` |

各ドメインは重複なし。1つのドメインが1つの出力ファイルを所有する。

### 4.5 共有ヘルパー

全共有テストユーティリティは `tests/e2e/helpers/` に配置する:

| ヘルパーファイル | 用途 | 提供する機能 |
|----------------|------|-------------|
| `tests/e2e/helpers/mock_globals.bash` | 全必要グローバル変数のスタブ宣言 | `NINJA_NAMES[]`, `PANE_TARGETS[]`, `STATE_DIR`, `SCRIPT_DIR`, `LOG`（スカラー）+ `STALL_FIRST_SEEN[]`, `STALL_NOTIFIED[]`, `STALL_COUNT[]`（連想配列） |
| `tests/e2e/helpers/mock_externals.bash` | 外部ライブラリ関数のモック定義 | `yaml_field_get()`, `yaml_field_set()`, `log()`, `send_inbox_message()`, `tmux()`, `pgrep()`, `flock()`, `inotifywait()` |
| `tests/e2e/helpers/assert_functions.bash` | 関数存在・重複・source順序の検証ユーティリティ | `assert_function_exists()`, `assert_function_count()`, `assert_no_duplicates()`, `assert_source_order()`, `assert_exact_function_set()` |
| `tests/e2e/helpers/setup_tmpdir.bash` | 一時ディレクトリの作成・クリーンアップ | `STATE_DIR`, `LOG`, `queue/` パスの隔離ディレクトリ。`setup()` で作成、`teardown()` で `rm -rf "$BATS_TMPDIR"/monitor_test_*` |

ヘルパーの利用方法（各 `.spec.bats` ファイルの `setup()` 内）:
```bash
setup() {
  load 'helpers/mock_globals'
  load 'helpers/mock_externals'
  load 'helpers/assert_functions'
  load 'helpers/setup_tmpdir'
  init_mock_globals
  init_mock_externals
  create_test_tmpdir
}
```

### 4.6 シナリオ導出ルール

各ドメインに対し以下の3カテゴリでシナリオを導出する:

**正のシナリオ（受入基準から）**:
- モジュールをsource → exit 0
- 指定された各関数が定義済み（`type -t function_name` = `function`）
- 関数数が仕様と完全一致
- 関数がエラーなしで呼出し可能（"command not found"なし）
- グローバル変数・連想配列が関数内からアクセス可能
- クロスモジュール呼出し（idle_management → report_utils の `can_send_clear_with_report_gate`、stall_detection → report_utils の `is_task_deployed`、idle_management → state_io の `write_state_file`）が正常動作

**負のシナリオ（失敗基準の反転）**:
- 必要なグローバル変数なしでモジュールをsource → 意味のあるエラーまたはグレースフルハンドリング（サイレント破損でない）
- 存在しないモジュールパスをsource → 非ゼロexit
- 関数名の重複を人為的に導入 → `assert_no_duplicates` が検出
- Python/Node呼出しをモジュールに含む → grepチェックが検出

**構造シナリオ（module-structureドメイン）**:
- `scripts/lib/monitor/` に7ファイルが存在
- `ninja_monitor.sh` ≤ 500行
- source順序: 全 `scripts/lib/*.sh` が全 `scripts/lib/monitor/*.sh` より前
- 関数名が複数ファイルにわたって重複なし
- 元の59関数名がリファクタリング後のコードベースに全て存在
- モジュールに `python`, `python3`, `node` 呼出しなし

**システムシナリオ（full-chainドメイン）**:
- 完全source chainがエラーなし完了
- source後に59関数全てが呼出し可能
- source前にグローバル変数を設定 → source後のモジュール関数内から読取り可能
- モジュールファイル変更 → composite hashが変化（自動再起動検知）
- 連想配列の書込み所有権: `STALL_COUNT[]` に `stall_detection` の関数経由で値を設定 → `idle_management` の関数から読取り可能

### 4.7 アーキテクチャ適応

テスト生成前に実際のファイル構造をスキャンする:

```bash
# 実際のモジュールを探索
ls scripts/lib/monitor/*.sh 2>/dev/null

# モジュールごとの実際の関数を探索
for f in scripts/lib/monitor/*.sh; do
  echo "=== $f ==="
  grep -E '^\s*(function\s+)?[a-zA-Z_][a-zA-Z_0-9]*\s*\(\)' "$f"
done

# 外部ライブラリsourceを探索
grep -E '^\s*source\s' scripts/ninja_monitor.sh
```

要件で指定されたモジュールファイルがまだ存在しない場合、テストを `bats_test_skipped "module not yet extracted"` として `# @manual` マーカー付きで生成する。これにより再生成時に保持されつつ、実装待ちとしてフラグが立つ。

### 4.8 実行環境

**前提条件**:
- bats-core ≥ 1.5.0（`bats --version` で確認）
- bats-support, bats-assert, bats-file ヘルパーライブラリが利用可能
- Bash 5.x（`bash --version` で確認）
- tmux利用可能（pane_managementモックのベースライン）
- サーバ不要 — テストはbashファイルを直接source

**実行シーケンス**:

```bash
# 1. 既存テストスイート実行（ベースラインゲート）
bats tests/ --recursive --formatter tap | tee baseline.tap
PASS_COUNT=$(grep -c '^ok' baseline.tap)
SKIP_COUNT=$(grep -c '# skip' baseline.tap)
echo "Baseline: ${PASS_COUNT} passed, ${SKIP_COUNT} skipped"
[[ "$PASS_COUNT" -eq 854 ]]
[[ "$SKIP_COUNT" -eq 0 ]]

# 2. リファクタリング受入テスト実行
bats tests/e2e/ --recursive --formatter tap | tee refactor.tap
REFACTOR_SKIP=$(grep -c '# skip' refactor.tap)
[[ "$REFACTOR_SKIP" -eq 0 ]]
```

**CI設定**:
- バックグラウンドサーバ不要
- テストは同期実行
- テストファイルごとのタイムアウト: 60秒
- スイート全体のタイムアウト: 300秒
- ヘルスチェック待機不要（bashの直接source実行のため）

### 4.9 品質ゲート

| 基準 | 閾値 | 強制レベル |
|------|------|----------|
| 既存テストPASS | 854/854 | リリースブロッカー |
| 既存テストSKIP | 0 | リリースブロッカー（Conv-1: SKIP=FAIL） |
| 新規構造テストPASS | 100% | リリースブロッカー |
| 新規構造テストSKIP | 0 | リリースブロッカー |
| 関数カバレッジ | 59/59の元関数に最低1つの存在アサーション | リリースブロッカー |
| モジュールカバレッジ | 7/7モジュールに独立sourcingテスト | リリースブロッカー（Conv-2） |
| 関数重複チェック | 全ファイルにわたり重複0 | リリースブロッカー |
| テスト総数整合性 | 既存854テストの総数が減少していないこと | リリースブロッカー |

### 4.10 生成マーカー

全生成テストファイルは以下のヘッダを含む:

```bash
#!/usr/bin/env bats
# @generated-from: docs/test/acceptance_criteria.md
# @generated-by: codd propagate
```

`# @manual` マーカー付きのテスト関数は再生成時に保持する。ジェネレータは既存の `# @manual` マーカーを検出し、変更なしで引き継ぐ。

### 4.11 トレーサビリティマトリクス

各ドメインファイルの先頭にVB-IDへのマッピングコメントブロックを含める:

**module-structure.spec.bats:**
```bash
# Traceability:
#   test_7_module_files_exist              → VB-22
#   test_no_duplicate_functions            → VB-23
#   test_all_59_functions_present          → VB-24
#   test_ninja_monitor_line_count          → VB-04
#   test_source_order_phase1_before_phase2 → VB-13
#   test_7_source_statements_in_main       → VB-03
#   test_no_python_node_invocations        → VB-16
#   test_no_new_external_dependencies      → VB-15
```

**idle-management.spec.bats:**
```bash
# Traceability:
#   test_source_exits_zero                → VB-14
#   test_10_functions_defined             → VB-06
#   test_check_idle_exists                → VB-06
#   test_safe_send_clear_exists           → VB-06
#   test_handle_confirmed_idle_exists     → VB-06
#   test_handle_busy_exists               → VB-06
#   test_handle_post_clear_pending_exists → VB-06
#   test_handle_deploy_stall_exists       → VB-06
#   test_handle_idle_notify_exists        → VB-06
#   test_handle_auto_clear_exists         → VB-06
#   test_notify_idle_batch_exists         → VB-06
#   test_cleanup_stale_keys_exists        → VB-06
```

**stall-detection.spec.bats:**
```bash
# Traceability:
#   test_source_exits_zero                        → VB-14
#   test_5_functions_defined                       → VB-07
#   test_check_stall_exists                        → VB-07
#   test_check_report_done_idle_mismatch_exists    → VB-07
#   test_list_pending_cmds_exists                  → VB-07
#   test_check_stale_cmds_exists                   → VB-07
#   test_check_undeployed_cmds_exists              → VB-07
#   test_associative_array_access                  → VB-19
```

**health-checks.spec.bats:**
```bash
# Traceability:
#   test_source_exits_zero                      → VB-14
#   test_10_functions_defined                    → VB-08
#   test_check_ntfy_listener_health_exists       → VB-08
#   test_check_inbox_watcher_health_exists       → VB-08
#   test_check_lesson_health_exists              → VB-08
#   test_check_loop_health_exists                → VB-08
#   test_check_workaround_pattern_exists         → VB-08
#   test_check_gate_improvement_exists           → VB-08
#   test_check_yaml_size_exists                  → VB-08
#   test_run_cdp_cleanup_exists                  → VB-08
#   test_run_lock_cleanup_exists                 → VB-08
#   test_check_auto_archive_exists               → VB-08
```

**karo-monitor.spec.bats:**
```bash
# Traceability:
#   test_source_exits_zero                    → VB-14
#   test_5_functions_defined                   → VB-09
#   test_check_karo_pending_cmd_exists         → VB-09
#   test_check_karo_pending_exists             → VB-09
#   test_check_karo_clear_exists               → VB-09
#   test_send_karo_clear_exists                → VB-09
#   test_check_karo_idle_cycle_exists          → VB-09
```

**pane-management.spec.bats:**
```bash
# Traceability:
#   test_source_exits_zero                   → VB-14
#   test_9_functions_defined                  → VB-10
#   test_discover_panes_exists                → VB-10
#   test_check_pane_survival_exists           → VB-10
#   test_check_ninja_cli_dead_exists          → VB-10
#   test_update_context_pct_exists            → VB-10
#   test_update_all_context_pct_exists        → VB-10
#   test_get_context_pct_exists               → VB-10
#   test_check_model_names_exists             → VB-10
#   test_update_inbox_counts_exists           → VB-10
#   test_check_shogun_ctx_exists              → VB-10
```

**report-utils.spec.bats:**
```bash
# Traceability:
#   test_source_exits_zero                          → VB-14
#   test_6_functions_defined                         → VB-11
#   test_get_latest_report_file_exists               → VB-11
#   test_find_matching_report_file_exists            → VB-11
#   test_resolve_expected_report_file_exists         → VB-11
#   test_can_send_clear_with_report_gate_exists      → VB-11
#   test_check_and_update_done_task_exists           → VB-11
#   test_is_task_deployed_exists                     → VB-11
```

**state-io.spec.bats:**
```bash
# Traceability:
#   test_source_exits_zero                → VB-14
#   test_2_functions_defined               → VB-12
#   test_write_state_file_exists           → VB-12
#   test_write_karo_snapshot_exists        → VB-12
```

**full-chain.system.bats:**
```bash
# Traceability:
#   test_full_source_chain_exits_zero      → VB-01, VB-03
#   test_existing_854_tests_pass           → VB-01, VB-02
#   test_skip_count_zero                   → VB-02
#   test_all_59_functions_callable         → VB-05, VB-24
#   test_global_variable_propagation       → VB-18
#   test_associative_array_propagation     → VB-19
#   test_external_library_function_access  → VB-20
#   test_auto_restart_hash_detection       → VB-17
#   test_wsl2_ntfs_path_compatibility      → VB-21
```

**カバレッジギャップ確認**: VB-01〜VB-24の全IDが上記トレーサビリティブロックに出現している。未カバレッジのVB-IDは存在しない。

### 4.12 出力ファイルマッピング（完全一覧）

| ドメイン | 出力パス | テストレベル |
|---------|---------|-------------|
| module-structure | `tests/e2e/module-structure.spec.bats` | ユニット統合 |
| idle-management | `tests/e2e/idle-management.spec.bats` | ユニット統合 |
| stall-detection | `tests/e2e/stall-detection.spec.bats` | ユニット統合 |
| health-checks | `tests/e2e/health-checks.spec.bats` | ユニット統合 |
| karo-monitor | `tests/e2e/karo-monitor.spec.bats` | ユニット統合 |
| pane-management | `tests/e2e/pane-management.spec.bats` | ユニット統合 |
| report-utils | `tests/e2e/report-utils.spec.bats` | ユニット統合 |
| state-io | `tests/e2e/state-io.spec.bats` | ユニット統合 |
| full-chain | `tests/e2e/full-chain.system.bats` | システム統合 |
| helpers/mock_globals | `tests/e2e/helpers/mock_globals.bash` | 共有ヘルパー |
| helpers/mock_externals | `tests/e2e/helpers/mock_externals.bash` | 共有ヘルパー |
| helpers/assert_functions | `tests/e2e/helpers/assert_functions.bash` | 共有ヘルパー |
| helpers/setup_tmpdir | `tests/e2e/helpers/setup_tmpdir.bash` | 共有ヘルパー |
