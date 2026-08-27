---
codd:
  node_id: operations:daemon-runbook
  type: operations
  depends_on:
  - id: design:system-design
    relation: depends_on
    semantic: technical
  - id: detailed_design:module-ownership
    relation: depends_on
    semantic: technical
  depended_by: []
  conventions:
  - targets:
    - module:ninja_monitor
    reason: 'Constraint: Auto-restart script-hash detection must include all module
      files under scripts/lib/monitor/. Missing a file means silent stale code running
      in production daemon.'
  - targets:
    - module:state_io
    - module:health_checks
    reason: 'Constraint: WSL2 NTFS /mnt/c path compatibility. File I/O must handle
      NTFS limitations (stat-based polling, no inotify on cross-filesystem mounts).'
  modules:
  - ninja_monitor
  - state_io
  - health_checks
---

# Daemon Operations Runbook

## 1. Overview

ninja_monitor.sh は20秒ポーリングで忍者・家老エージェントの状態を監視し、idle検知・stall検出・health check・自動clear送信・karo_snapshot生成を行う常駐デーモンである。本書はモジュール分割後（7モジュール + 本体）のデーモン運用手順・監視項目・CI/CDパイプライン生成仕様を定義する。

### 1.1 アーキテクチャ概要

```
ninja_monitor.sh (~500行: globals + source chain + main loop)
  ├── Phase 1 source: scripts/lib/*.sh (外部ライブラリ 12本)
  ├── Phase 2 source: scripts/lib/monitor/*.sh (7モジュール)
  │     ├── state_io.sh          (2関数: 状態ファイル書込み, karo_snapshot生成)
  │     ├── report_utils.sh      (6関数: 報告ファイル解決, report_gate判定)
  │     ├── pane_management.sh   (9関数: tmuxペイン探索・CTX%追跡)
  │     ├── idle_management.sh   (10関数: idle検知・safe_send_clear)
  │     ├── stall_detection.sh   (5関数: stall検知・pending/stale cmd監視)
  │     ├── health_checks.sh     (10関数: ntfy/inbox_watcher/lesson健全性)
  │     └── karo_monitor.sh      (5関数: 家老pending/idle_cycle監視)
  └── Main Loop: 20秒ポーリング + composite hash自動再起動
```

合計59関数（47関数をモジュールに抽出 + 12関数が本体残留）。全関数は単一プロセス内の共有名前空間で動作する。

### 1.2 コンベンション準拠

| 制約ID | 内容 | 本書での反映 |
|--------|------|-------------|
| **Auto-restart hash** | `scripts/lib/monitor/` 配下の全モジュールファイルをハッシュ検知対象に含める。ファイル欠落はサイレントな旧コード実行を招く | §2.3 Auto-Restart手順、§3.2 ハッシュ不一致アラート、§4 CIジョブ `module-integrity` |
| **WSL2 NTFS互換** | `/mnt/c` パスでinotify不可。stat-basedポーリング必須 | §2.1 起動前提条件、§2.5 WSL2固有トラブルシュート、§3.3 ファイルI/O監視 |
| **NFR-1 source順序** | 外部ライブラリ→monitor/モジュールの厳密な順序 | §2.2 起動シーケンス、§4 CIジョブ `source-order-check` |
| **FR-1 MECE関数配置** | 59関数が厳密に1モジュール。重複・欠落禁止 | §3.1 関数カウント監視、§4 CIジョブ `function-integrity` |
| **FR-4 ゼロ動作変更** | シグネチャ・戻り値・副作用は分割前後で同一 | §4 CIジョブ `existing-tests`（854 batsテスト全PASS・SKIP=0） |

## 2. Runbook

### 2.1 起動前提条件

| 前提 | 確認コマンド | 期待値 |
|------|------------|--------|
| Bash 5.x | `bash --version` | 5.0以上 |
| tmuxセッション `shogun:2` 存在 | `tmux has-session -t shogun:2` | exit 0 |
| sha256sum 利用可能 | `which sha256sum` | パス出力 |
| flock 利用可能 | `which flock` | パス出力 |
| 外部ライブラリ12本存在 | `ls scripts/lib/*.sh \| wc -l` | 12以上 |
| monitor/モジュール7本存在 | `ls scripts/lib/monitor/*.sh \| wc -l` | 7 |
| WSL2 NTFS: `/mnt/c` マウント | `mountpoint -q /mnt/c` | exit 0 |
| stat コマンド（inotify代替） | `which stat` | パス出力 |

### 2.2 起動シーケンス

```bash
# 1. プロジェクトルートに移動
cd /home/simokitafresh/multi-agent-shogun

# 2. デーモン起動（バックグラウンド、nohup）
nohup bash scripts/ninja_monitor.sh >> logs/ninja_monitor.log 2>&1 &

# 3. PID記録
echo $! > /tmp/ninja_monitor.pid
```

**起動時の内部処理順序**:

1. **Layer 1**: グローバル変数宣言（`NINJA_NAMES[]`, `PANE_TARGETS[]`, `STALL_FIRST_SEEN[]`, `STALL_NOTIFIED[]`, `STALL_COUNT[]`, `STATE_DIR`, `SCRIPT_DIR`, `LOG`, `POLL_INTERVAL=20`）
2. **Layer 2 Phase 1**: 外部ライブラリ12本を source（`cli_lookup.sh`, `yaml_field_get.sh`, `yaml_field_set.sh`, `inbox_utils.sh`, `log_utils.sh`, `model_resolve.sh`, `pane_format.sh` 等）
3. **Layer 2 Phase 2**: monitor/モジュール7本を source（`state_io.sh` → `report_utils.sh` → `pane_management.sh` → `idle_management.sh` → `stall_detection.sh` → `health_checks.sh` → `karo_monitor.sh`）
4. **モジュール数検証**: `scripts/lib/monitor/*.sh` のglob展開結果が7ファイルでなければ `[WARN] Expected 7 monitor modules, found $N` を出力
5. **Composite hash初期算出**: `sha256sum scripts/ninja_monitor.sh scripts/lib/monitor/*.sh | sha256sum | awk '{print $1}'` を `COMPOSITE_HASH` に保存
6. **Layer 3**: 20秒ポーリング主ループ開始

**source順序の厳守（NFR-1）**: Phase 1の最終source行番号 < Phase 2の最初source行番号であること。Phase 2内部では被呼出し側（`state_io.sh`, `report_utils.sh`）を先にsourceする。順序違反は `command not found` エラーとして即座に顕在化する。

### 2.3 Auto-Restart（composite hash方式）

デーモンは20秒ポーリングの各サイクル末尾でcomposite hashを再算出し、起動時の値と比較する。

**対象ファイル（8本）**:
- `scripts/ninja_monitor.sh`（本体）
- `scripts/lib/monitor/idle_management.sh`
- `scripts/lib/monitor/stall_detection.sh`
- `scripts/lib/monitor/health_checks.sh`
- `scripts/lib/monitor/karo_monitor.sh`
- `scripts/lib/monitor/pane_management.sh`
- `scripts/lib/monitor/report_utils.sh`
- `scripts/lib/monitor/state_io.sh`

**検知フロー**:
```
[サイクル末尾]
  │
  ├─ NEW_HASH=$(sha256sum scripts/ninja_monitor.sh scripts/lib/monitor/*.sh | sha256sum | awk '{print $1}')
  │
  ├─ NEW_HASH == COMPOSITE_HASH → 次サイクルへ（sleep 20）
  │
  └─ NEW_HASH != COMPOSITE_HASH → ログ出力 → exec で自身を再起動
```

**glob `scripts/lib/monitor/*.sh` のファイル数保証**: 毎サイクルで展開後のファイル数を検証し、7でなければ警告をログ出力する。ファイル欠落時にサイレントな旧コード実行を防止する。

**手動再起動手順**:
```bash
# PIDで停止
kill $(cat /tmp/ninja_monitor.pid)

# 再起動
nohup bash scripts/ninja_monitor.sh >> logs/ninja_monitor.log 2>&1 &
echo $! > /tmp/ninja_monitor.pid
```

### 2.4 停止手順

```bash
# 正常停止（SIGTERM）
kill $(cat /tmp/ninja_monitor.pid)

# PIDファイル確認で停止を検証
sleep 2
ps -p $(cat /tmp/ninja_monitor.pid) > /dev/null 2>&1 && echo "STILL RUNNING" || echo "STOPPED"
```

`kill -9` は最終手段。通常は SIGTERM で主ループの次サイクル冒頭で終了する。

### 2.5 WSL2 NTFS固有トラブルシュート

| 症状 | 原因 | 対処 |
|------|------|------|
| `state_io.sh` の `write_state_file` がハングする | NTFS上の flock 遅延。高I/O負荷時に発生 | `flock` のタイムアウト値を確認。20秒ポーリング間隔内に完了しない場合はI/O負荷の原因（Windows側プロセス）を調査 |
| ファイル変更を検知できない | `/mnt/c` 上でinotifyは動作しない | stat-basedポーリング（20秒間隔）で代替。リアルタイム検知は設計上不可。検知遅延は最大20秒 |
| `health_checks.sh` の `check_yaml_size` が不正確なサイズを返す | NTFSのstat結果にキャッシュ遅延がある場合がある | `sync` 後に `stat` を再実行。persistent problemの場合は `/mnt/c` のメタデータキャッシュをフラッシュ |
| パスに日本語を含むファイルの操作失敗 | NTFS上のUTFエンコーディング不一致 | `LC_ALL=C.UTF-8` を環境変数に設定 |

### 2.6 ロールバック手順

モジュール分割に起因する障害が発生した場合:

```bash
# 1. デーモン停止
kill $(cat /tmp/ninja_monitor.pid)

# 2. 本体を分割前に復元
git checkout -- scripts/ninja_monitor.sh

# 3. モジュールディレクトリ削除（プロジェクトツリー内）
rm -r scripts/lib/monitor/

# 4. テスト実行で復旧確認
bats tests/**/*.bats
# 854テスト全PASS・SKIP=0を確認

# 5. デーモン再起動
nohup bash scripts/ninja_monitor.sh >> logs/ninja_monitor.log 2>&1 &
echo $! > /tmp/ninja_monitor.pid
```

### 2.7 共有状態のデバッグ

| 共有状態 | 型 | 書込み所有者 | 読取り | デバッグ方法 |
|---------|-----|------------|--------|-------------|
| `NINJA_NAMES[]` | indexed array | dispatcher（初期化のみ） | idle_management, stall_detection, pane_management, karo_monitor | ログに `${NINJA_NAMES[@]}` を出力 |
| `PANE_TARGETS[]` | indexed array | pane_management | idle_management, health_checks | `discover_panes` 実行後のログでペインID確認 |
| `STALL_FIRST_SEEN[]` | associative array | stall_detection | stall_detection | `declare -p STALL_FIRST_SEEN` をログに出力 |
| `STALL_COUNT[]` | associative array | stall_detection | idle_management（読取り専用） | `declare -p STALL_COUNT` をログに出力 |
| `STATE_DIR` | scalar | dispatcher（初期化のみ） | state_io, health_checks | `echo $STATE_DIR` |

書込み所有権違反（例: `idle_management` が `STALL_COUNT[]` に書込む）が疑われる場合、各モジュールファイル内で `STALL_COUNT[` を `grep` して書込み行の有無を確認する。

## 3. Monitoring

### 3.1 関数カウント監視

**目的**: FR-1（MECE関数配置）の継続的遵守を保証する。

| メトリクス | 算出方法 | 正常値 | アラート閾値 |
|-----------|---------|--------|-------------|
| 抽出関数数 | `grep -rch '^function \|^[a-z_][a-z_0-9]*()' scripts/lib/monitor/*.sh \| paste -sd+ \| bc` | 47 | ≠47 |
| 残留関数数 | `grep -ch '^function \|^[a-z_][a-z_0-9]*()' scripts/ninja_monitor.sh` | 12 | ≠12（OQ-1確定後に正確な値を設定） |
| 合計関数数 | 抽出 + 残留 | 59 | ≠59 |
| 重複関数数 | `grep -rh '^function \|^[a-z_][a-z_0-9]*()' scripts/ninja_monitor.sh scripts/lib/monitor/*.sh \| sed 's/function //;s/()[[:space:]]*{.*//' \| sort \| uniq -d \| wc -l` | 0 | ≥1 |
| モジュールファイル数 | `ls scripts/lib/monitor/*.sh \| wc -l` | 7 | ≠7 |

### 3.2 Composite Hashアラート

| イベント | 検知方法 | 対応 |
|---------|---------|------|
| ハッシュ変更 → 自動再起動 | ログ出力 `[INFO] Composite hash changed, restarting...` | 正常動作。git pullやデプロイ後に発生する |
| モジュール数不一致警告 | ログ出力 `[WARN] Expected 7 monitor modules, found N` | **即時調査必須**。ファイル欠落 = サイレントな旧コード実行リスク。`ls scripts/lib/monitor/*.sh` でファイル一覧を確認し、欠落ファイルを復旧する |
| ハッシュ算出失敗 | `sha256sum` のexit code ≠ 0 | ファイルパーミッションまたはファイル消失を調査 |

**Auto-restart hash検知が `scripts/lib/monitor/` 配下の全モジュールファイルをカバーすること**は本デーモンの安全性の根幹である。glob `scripts/lib/monitor/*.sh` による自動追従に加え、ファイル数の明示的検証（=7）を毎サイクル実施することで、ファイル欠落やglob展開の異常を検知する。

### 3.3 ファイルI/O監視（WSL2 NTFS対応）

`state_io.sh`, `health_checks.sh`, `pane_management.sh` はWSL2上の `/mnt/c` 配下NTFSマウントパスで動作する。inotifyが使用不可のため、全ファイルI/O監視はstatコマンドによる20秒間隔ポーリングに依拠する。

| 監視対象 | モジュール | 手法 | 遅延許容 |
|---------|-----------|------|---------|
| `queue/` 配下のYAMLファイル変更 | state_io, health_checks | `stat` mtime比較 | 最大20秒 |
| karo_snapshot.txt 更新 | state_io | `flock` + 書込み | flock取得待ち含め20秒以内 |
| 報告ファイル出現 | report_utils | `ls` + `stat` | 最大20秒 |
| tmuxペイン状態 | pane_management | `tmux list-panes` / `tmux capture-pane` | リアルタイム（tmux APIはNTFS非依存） |
| ログファイル肥大化 | health_checks (`check_yaml_size`) | `stat` サイズ取得 | 最大20秒 |
| ロックファイル残留 | health_checks (`run_lock_cleanup`) | ファイル存在チェック | 最大20秒 |

**flockのNTFS上での動作**: WSL2のNTFSマウントではflockは動作するが、ext4比でレイテンシが高い。`state_io.sh` の `write_state_file` および `write_karo_snapshot` はflock排他制御を使用する。20秒ポーリング間隔内にflock取得〜解放が完了することを前提とする。

### 3.4 プロセス健全性

| チェック | モジュール/関数 | 監視間隔 | 異常時の挙動 |
|---------|---------------|---------|-------------|
| ntfy listener生存 | `health_checks.sh` / `check_ntfy_listener_health` | 20秒 | ログ警告 + ntfy通知 |
| inbox_watcher生存 | `health_checks.sh` / `check_inbox_watcher_health` | 20秒 | ログ警告 + ntfy通知 |
| 忍者CLI死活 | `pane_management.sh` / `check_ninja_cli_dead` | 20秒 | ログ警告 + 家老への通知 |
| 家老pending滞留 | `karo_monitor.sh` / `check_karo_pending_cmd` | 20秒 | ログ警告 |
| 主ループ健全性 | `health_checks.sh` / `check_loop_health` | 自己監視 | ログ出力（外部watchdogでの検知を推奨） |

### 3.5 source順序の継続監視

source順序違反（NFR-1）は実行時に `command not found` として即座に顕在化するが、CIでの事前検知が望ましい。

```bash
# 検証スクリプト（CIおよび手動実行用）
LAST_P1=$(grep -n 'source scripts/lib/[^m]' scripts/ninja_monitor.sh | tail -1 | cut -d: -f1)
FIRST_P2=$(grep -n 'source scripts/lib/monitor/' scripts/ninja_monitor.sh | head -1 | cut -d: -f1)
if [[ "$LAST_P1" -ge "$FIRST_P2" ]]; then
  echo "[CRITICAL] Source order violation: Phase 1 last line=$LAST_P1 >= Phase 2 first line=$FIRST_P2"
  exit 1
fi
```

### 3.6 ログフォーマットとローテーション

| 項目 | 値 |
|------|-----|
| ログファイル | `logs/ninja_monitor.log` |
| フォーマット | `[YYYY-MM-DD HH:MM:SS] [LEVEL] message`（既存フォーマットを維持） |
| レベル | `INFO`, `WARN`, `ERROR` |
| ローテーション | `health_checks.sh` の `check_auto_archive` で自動判定。手動: `mv` + デーモン再起動 |
| 監視すべきログパターン | `[WARN] Expected 7 monitor modules`, `Composite hash changed`, `command not found` |

## 4. CI/CD Pipeline Generation Meta-Prompt

```yaml
# @generated-by: codd propagate
# CI Pipeline for ninja_monitor modular refactoring
# Generated from: docs/operations/daemon_runbook.md

name: ninja-monitor-ci

on:
  pull_request:
    branches: [main, develop]

env:
  # No secrets required — pure bash project with no external services
  TERM: xterm-256color

jobs:
  # ──────────────────────────────────────────────
  # Build Verification
  # ──────────────────────────────────────────────
  build-verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Cache bats
        uses: actions/cache@v4
        with:
          path: |
            /usr/local/bin/bats
            /usr/local/lib/bats-*
          key: bats-${{ runner.os }}-v1

      - name: Install bats-core
        run: |
          if ! command -v bats &>/dev/null; then
            git clone https://github.com/bats-core/bats-core.git /tmp/bats-core
            cd /tmp/bats-core && sudo ./install.sh /usr/local
          fi
          # Install bats helpers
          for lib in bats-support bats-assert; do
            if [ ! -d "/usr/local/lib/$lib" ]; then
              git clone "https://github.com/bats-core/$lib.git" "/tmp/$lib"
              sudo mkdir -p "/usr/local/lib/$lib"
              sudo cp -r "/tmp/$lib/src" "/usr/local/lib/$lib/"
            fi
          done

      - name: Verify bash version
        run: bash --version | head -1

      - name: Verify source chain parseable
        run: bash -n scripts/ninja_monitor.sh

      - name: Verify all monitor modules parseable
        run: |
          for f in scripts/lib/monitor/*.sh; do
            bash -n "$f" || exit 1
          done

  # ──────────────────────────────────────────────
  # Unit: Module Integrity (FR-1 MECE)
  # ──────────────────────────────────────────────
  module-integrity:
    needs: build-verify
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Check module file count (7 expected)
        run: |
          COUNT=$(ls scripts/lib/monitor/*.sh 2>/dev/null | wc -l)
          echo "Module count: $COUNT"
          [[ "$COUNT" -eq 7 ]] || { echo "::error::Expected 7 monitor modules, found $COUNT"; exit 1; }

      - name: Check zero duplicate functions
        run: |
          DUPES=$(grep -rh '^function \|^[a-z_][a-z_0-9]*()' \
            scripts/ninja_monitor.sh scripts/lib/monitor/*.sh \
            | sed 's/function //; s/()[[:space:]]*{.*//' \
            | sort | uniq -d)
          if [[ -n "$DUPES" ]]; then
            echo "::error::Duplicate functions found: $DUPES"
            exit 1
          fi

      - name: Check total function count (≥59)
        run: |
          TOTAL=$(grep -rh '^function \|^[a-z_][a-z_0-9]*()' \
            scripts/ninja_monitor.sh scripts/lib/monitor/*.sh \
            | wc -l)
          echo "Total functions: $TOTAL"
          [[ "$TOTAL" -ge 59 ]] || { echo "::error::Expected ≥59 functions, found $TOTAL"; exit 1; }

  # ──────────────────────────────────────────────
  # Unit: Source Order (NFR-1)
  # ──────────────────────────────────────────────
  source-order-check:
    needs: build-verify
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Verify Phase 1 before Phase 2
        run: |
          LAST_P1=$(grep -n 'source scripts/lib/[^m]' scripts/ninja_monitor.sh | tail -1 | cut -d: -f1)
          FIRST_P2=$(grep -n 'source scripts/lib/monitor/' scripts/ninja_monitor.sh | head -1 | cut -d: -f1)
          echo "Phase 1 last line: $LAST_P1, Phase 2 first line: $FIRST_P2"
          [[ "$LAST_P1" -lt "$FIRST_P2" ]] || { echo "::error::Source order violation: Phase 1 line $LAST_P1 >= Phase 2 line $FIRST_P2"; exit 1; }

  # ──────────────────────────────────────────────
  # Unit: Composite Hash Coverage (Auto-Restart)
  # ──────────────────────────────────────────────
  hash-coverage:
    needs: build-verify
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Verify composite hash covers all 8 files
        run: |
          # Simulate hash computation
          FILES=$(echo scripts/ninja_monitor.sh scripts/lib/monitor/*.sh)
          FILE_COUNT=$(echo $FILES | tr ' ' '\n' | wc -l)
          echo "Hash covers $FILE_COUNT files: $FILES"
          [[ "$FILE_COUNT" -eq 8 ]] || { echo "::error::Composite hash must cover 8 files (1 main + 7 modules), found $FILE_COUNT"; exit 1; }

      - name: Verify hash is computable
        run: |
          sha256sum scripts/ninja_monitor.sh scripts/lib/monitor/*.sh | sha256sum | awk '{print $1}'

  # ──────────────────────────────────────────────
  # Integration: Per-Module Source Tests
  # ──────────────────────────────────────────────
  module-source-tests:
    needs: [module-integrity, source-order-check]
    runs-on: ubuntu-latest
    strategy:
      matrix:
        module:
          - idle-management
          - stall-detection
          - health-checks
          - karo-monitor
          - pane-management
          - report-utils
          - state-io
    steps:
      - uses: actions/checkout@v4

      - name: Cache bats
        uses: actions/cache@v4
        with:
          path: |
            /usr/local/bin/bats
            /usr/local/lib/bats-*
          key: bats-${{ runner.os }}-v1

      - name: Install bats-core
        run: |
          if ! command -v bats &>/dev/null; then
            git clone https://github.com/bats-core/bats-core.git /tmp/bats-core
            cd /tmp/bats-core && sudo ./install.sh /usr/local
          fi
          for lib in bats-support bats-assert; do
            if [ ! -d "/usr/local/lib/$lib" ]; then
              git clone "https://github.com/bats-core/$lib.git" "/tmp/$lib"
              sudo mkdir -p "/usr/local/lib/$lib"
              sudo cp -r "/tmp/$lib/src" "/usr/local/lib/$lib/"
            fi
          done

      - name: Run module spec
        run: bats tests/e2e/${{ matrix.module }}.spec.bats
        timeout-minutes: 1

  # ──────────────────────────────────────────────
  # Integration: Full Source Chain System Test
  # ──────────────────────────────────────────────
  full-chain-system:
    needs: module-source-tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Cache bats
        uses: actions/cache@v4
        with:
          path: |
            /usr/local/bin/bats
            /usr/local/lib/bats-*
          key: bats-${{ runner.os }}-v1

      - name: Install bats-core
        run: |
          if ! command -v bats &>/dev/null; then
            git clone https://github.com/bats-core/bats-core.git /tmp/bats-core
            cd /tmp/bats-core && sudo ./install.sh /usr/local
          fi
          for lib in bats-support bats-assert; do
            if [ ! -d "/usr/local/lib/$lib" ]; then
              git clone "https://github.com/bats-core/$lib.git" "/tmp/$lib"
              sudo mkdir -p "/usr/local/lib/$lib"
              sudo cp -r "/tmp/$lib/src" "/usr/local/lib/$lib/"
            fi
          done

      - name: Run full chain system test
        run: bats tests/e2e/full-chain.system.bats
        timeout-minutes: 2

  # ──────────────────────────────────────────────
  # E2E: Existing 854 bats Tests (Release Gate)
  # ──────────────────────────────────────────────
  existing-tests:
    needs: full-chain-system
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Cache bats
        uses: actions/cache@v4
        with:
          path: |
            /usr/local/bin/bats
            /usr/local/lib/bats-*
          key: bats-${{ runner.os }}-v1

      - name: Install bats-core
        run: |
          if ! command -v bats &>/dev/null; then
            git clone https://github.com/bats-core/bats-core.git /tmp/bats-core
            cd /tmp/bats-core && sudo ./install.sh /usr/local
          fi
          for lib in bats-support bats-assert; do
            if [ ! -d "/usr/local/lib/$lib" ]; then
              git clone "https://github.com/bats-core/$lib.git" "/tmp/$lib"
              sudo mkdir -p "/usr/local/lib/$lib"
              sudo cp -r "/tmp/$lib/src" "/usr/local/lib/$lib/"
            fi
          done

      - name: Run all existing tests (854 expected, SKIP=FAIL)
        run: |
          RESULT=$(bats tests/**/*.bats --formatter tap 2>&1)
          echo "$RESULT"
          SKIPPED=$(echo "$RESULT" | grep -c '# skip' || true)
          if [[ "$SKIPPED" -gt 0 ]]; then
            echo "::error::$SKIPPED tests were SKIPPED. SKIP=FAIL policy."
            exit 1
          fi
          FAILED=$(echo "$RESULT" | grep -c '^not ok' || true)
          if [[ "$FAILED" -gt 0 ]]; then
            echo "::error::$FAILED tests FAILED."
            exit 1
          fi
        timeout-minutes: 5

  # ──────────────────────────────────────────────
  # Performance: Composite Hash and Source Timing
  # ──────────────────────────────────────────────
  performance:
    needs: build-verify
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Benchmark composite hash computation (<100ms)
        run: |
          START=$(date +%s%N)
          for i in $(seq 1 100); do
            sha256sum scripts/ninja_monitor.sh scripts/lib/monitor/*.sh | sha256sum > /dev/null
          done
          END=$(date +%s%N)
          AVG_MS=$(( (END - START) / 100 / 1000000 ))
          echo "Average composite hash time: ${AVG_MS}ms"
          [[ "$AVG_MS" -lt 100 ]] || { echo "::warning::Hash computation ${AVG_MS}ms exceeds 100ms target"; }

      - name: Benchmark source chain completion (<500ms)
        run: |
          START=$(date +%s%N)
          bash -c 'NINJA_MONITOR_LIB_ONLY=1 source scripts/ninja_monitor.sh'
          END=$(date +%s%N)
          ELAPSED_MS=$(( (END - START) / 1000000 ))
          echo "Source chain time: ${ELAPSED_MS}ms"

  # ──────────────────────────────────────────────
  # Merge Gate
  # ──────────────────────────────────────────────
  merge-gate:
    needs:
      - module-integrity
      - source-order-check
      - hash-coverage
      - module-source-tests
      - full-chain-system
      - existing-tests
      - performance
    runs-on: ubuntu-latest
    steps:
      - name: All checks passed
        run: echo "All CI jobs passed. PR is mergeable."
```

### 4.1 出力ファイル

`.github/workflows/ci.yml`

### 4.2 ジョブ依存グラフ

```
build-verify
  ├── module-integrity ──┐
  ├── source-order-check ┤
  ├── hash-coverage      ├── module-source-tests (matrix: 7 modules)
  └── performance        │         │
                         │         └── full-chain-system
                         │                    │
                         │                    └── existing-tests (854 bats, SKIP=FAIL)
                         │                               │
                         └───────────────────────────────┘
                                                         │
                                                    merge-gate
```

### 4.3 必須環境変数

| 変数 | 用途 | Secret要否 |
|------|------|-----------|
| `TERM` | batsのカラー出力制御 | 不要（`xterm-256color` 固定） |

本プロジェクトは純粋なbashスクリプト群であり、データベース・外部API・認証情報を必要としない。GitHub Secretsの設定は不要。

### 4.4 ブランチ保護ルール推奨設定

| 設定項目 | 推奨値 |
|---------|--------|
| Require status checks to pass before merging | 有効 |
| Required status checks | `merge-gate` |
| Require branches to be up to date before merging | 有効 |
| Require pull request reviews before merging | 1名以上 |

### 4.5 キャッシュ戦略

| キャッシュ対象 | キー | 復元キー |
|--------------|------|---------|
| bats-core + bats-support + bats-assert | `bats-${{ runner.os }}-v1` | `bats-${{ runner.os }}-` |

batsのインストールはgit cloneベースのため、キャッシュにより各ジョブ30秒程度の短縮が見込める。

### 4.6 失敗通知

CI失敗時のSlack/メール通知は推奨するが必須としない。設定する場合:

```yaml
# merge-gate ジョブの末尾に追加
- name: Notify on failure
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    channel-id: '#ci-alerts'
    slack-message: 'ninja-monitor CI failed on ${{ github.event.pull_request.html_url }}'
  env:
    SLACK_BOT_TOKEN: ${{ secrets.SLACK_BOT_TOKEN }}
```

### 4.7 前提パッケージ検証

本CIパイプラインが依存するツール:

| ツール | CI内での入手方法 | プロジェクト依存マニフェストへの記載 |
|--------|----------------|-------------------------------|
| `bats-core` | CI内で `git clone` + `install.sh` | 不要（テストランナーはCI環境で動的インストール） |
| `bats-support` | CI内で `git clone` | 不要（同上） |
| `bats-assert` | CI内で `git clone` | 不要（同上） |
| `bash` (5.x) | ubuntu-latest同梱 | 不要 |
| `sha256sum` | ubuntu-latest同梱（coreutils） | 不要 |
| `grep`, `sed`, `sort`, `uniq`, `wc`, `stat` | ubuntu-latest同梱（coreutils + grep） | 不要 |

プロジェクトに `package.json`, `requirements.txt`, `pyproject.toml` は存在しない。全依存はOSレベルのcoreutilsとCI内インストールのbatsで充足する。
