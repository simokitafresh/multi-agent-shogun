# restart_watchers.sh CoDD Spec (AC1)

cmd: cmd_training_L4_codd_202605152312_kotaro
date: 2026-05-15
author: kotaro

---

## Purpose

`scripts/restart_watchers.sh` は、全エージェントの `inbox_watcher.sh` プロセスを一括停止・再起動するデーモン再起動スクリプト。
スクリプト更新後や異常終了後に、watcher常駐プロセス群を確実に再起動し、ペイン変数を同期する。

---

## Scope

- **対象プロセス**: inbox_watcher.sh（全エージェント: shogun, karo, gunshi, 全ninja）
- **起動方法**: bash scripts/restart_watchers.sh (手動) / ninja_monitorによる自動呼出し
- **副作用**: pgrep/pkill で既存プロセス停止 → nohup で再起動 → inotifywaitヘルスチェック → sync_pane_vars.sh実行

---

## Functional Requirements (spec相当)

- FR-1: 並行実行ガード — `/tmp/restart_watchers.lock` にflock排他を取得し、多重起動を防止する
- FR-2: 既存プロセス停止 — `pkill -f "inbox_watcher.sh"` で全watcherを停止後、1秒待機して残存確認。残存時はSIGKILL送信
- FR-3: 将軍watcher起動 — `shogun:main` ペインに対し `inbox_watcher.sh shogun` をnohupで起動（@agent_cli取得）
- FR-4: 家老watcher起動 — `shogun:agents.1` ペインに対し `inbox_watcher.sh karo` をnohupで起動
- FR-5: 動的エージェント起動 — `agent_config.sh` の `get_all_agents()` からkaro以外を取得し、`pane_lookup.sh` でペイン解決。各エージェントに inbox_watcher.sh を起動
- FR-6: 起動確認 — 各watcherが `pgrep -f "inbox_watcher\.sh.*{agent}"` で検出できることを確認。失敗したエージェントを記録してexit 1
- FR-7: inotifywaitヘルスチェック — 2秒待機後 `pgrep -fc "inotifywait.*queue/inbox"` でinotifywaitプロセス数を確認。起動成功数と一致しない場合はWARN
- FR-8: ペイン変数同期 — `sync_pane_vars.sh` を実行して全ペイン変数を同期

---

## Constraints

- C-1: `/tmp/restart_watchers.lock` でflock排他。並行実行時は即exit 1
- C-2: SCRIPT_DIR は `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)` で絶対パス取得
- C-3: エージェントCLI (`@agent_cli`) はtmuxオプションから取得。取得失敗時は "claude" をデフォルト使用
- C-4: `set -e` によりコマンド失敗時は即中断（ただし `|| true` で抑制している箇所あり）
- C-5: 全watcher起動後に集計確認。1件でも失敗があればexit 1でエラー終了

---

## Data Boundaries

| 方向 | 対象 |
|------|------|
| 読込 | `scripts/lib/agent_config.sh`, `scripts/lib/pane_lookup.sh`, tmuxオプション (@agent_cli, @agent_id) |
| 書込 | `logs/inbox_watcher_{agent}.log`（nohupログ）, `/tmp/restart_watchers.lock` |
| 呼出 | `scripts/inbox_watcher.sh`, `scripts/sync_pane_vars.sh` |

---

## Safety Requirements

- SR-1: 全プロセス停止はSIGTERM→確認→SIGKILL の2段階。プロセス確認を挟む
- SR-2: ペインが解決できないエージェントはスキップ（`[[ -z "$pane" ]] && continue`）
- SR-3: 起動失敗エージェントは記録してfailed_agents配列に蓄積し、最後にまとめて報告

---

## elicit観点での要件穴・coverageギャップ (AC2相当)

### ギャップ1: 再起動失敗時の通知経路が未定義
- **問題**: exit 1で終了するが、呼出元(ninja_monitor等)に通知する経路が明文化されていない
- **質問**: 失敗時は呼出元がexit codeを検知するだけか？inbox_writeで家老/将軍に通知する仕組みは必要か？
- **severity**: medium

### ギャップ2: @agent_cli取得失敗時の挙動未明示
- **問題**: `tmux show-options -p -t "$pane" -v @agent_cli 2>/dev/null || echo "claude"` でフォールバックするが、
  CLIパスとして "claude" が有効かどうかの検証がない（CLAUDE.md: 手動起動は絶対パス `~/bin/claude` 必須）
- **質問**: フォールバック値 "claude" はWSL2環境で有効なCLIコマンドか？
- **severity**: high

### ギャップ3: inotifywaitヘルスチェックがWARNのみでexit 0
- **問題**: inotifywait未稼働時はWARNを出力するだけでexit 0のまま。
  呼出元はwatcherが完全に起動したと誤認する可能性
- **質問**: inotifywait未稼働状態は正常終了とすべきか？呼出元への影響は？
- **severity**: medium

### ギャップ4: 再起動ログの保存先がdiscard
- **問題**: nohupは `logs/inbox_watcher_{agent}.log` に追記するが、restart_watchers.sh自体の実行ログは保存されない
- **質問**: restart_watchers.shの成功/失敗履歴をどこかに記録する必要はあるか？
- **severity**: low

### ギャップ5: gunshiウォッチャーの扱いが不明確
- **問題**: コメントに「忍者+軍師（settings.yamlから動的取得）」とあるが、
  gunshiのペインが存在しない場合のスキップ条件が `pane_lookup` の返り値に依存
- **質問**: gunshiがidleの場合は `pane_lookup` は空を返すか？karo同様に明示的なハードコード起動が必要か？
- **severity**: low

## 追完ループ3: codd extract/generate/validate/measure (2026-05-16)

### AC1: extract

| コマンド | Exit | 結果 |
|---|---:|---|
| `timeout 1200 /home/simokitafresh/.codd-venv/bin/codd extract --path .` | 0 | `Extracted: 0 modules from 0 files (0 lines)`; `Output: .codd/extract/`; generated `system-context.md` and `architecture-overview.md` |

Extract output:

- `.codd/extract/system-context.md`
- `.codd/extract/architecture-overview.md`

### AC2: generate wave 1

| コマンド | Exit | 結果 |
|---|---:|---|
| `timeout 1200 /home/simokitafresh/.codd-venv/bin/codd generate --wave 1 --force --path .` | 0 | `Generated: docs/test/acceptance_criteria.md (test:acceptance-criteria)`; `Generated: docs/governance/adr_yaml_batch_operations.md (governance:adr-yaml-batch-operations)`; `Wave 1: 2 generated, 0 skipped` |

Generated files:

- `docs/test/acceptance_criteria.md`
- `docs/governance/adr_yaml_batch_operations.md`

### AC3: validate

| コマンド | Exit | 結果 |
|---|---:|---|
| `timeout 1200 /home/simokitafresh/.codd-venv/bin/codd validate --path .` | 1 | `ERROR: 661 error(s), 11 blocked issue(s), 386 warning(s), 628 Markdown files checked` |

代表的な検出内容:

- node_id重複: `codd/design/cmd_save_design.md` と `docs/design/cmd_2762_cmd_save_design.md` などで `design:script:*` / `req:script:*` が重複。
- 既存/生成governance文書の未定義参照: `docs/governance/adr_batch_yaml_io.md` が `design:system-architecture` / `detailed:yaml-io-library` を参照。
- 既存docs/research群のCoDD YAML frontmatter欠落が多数。
- 既存extract群に circular dependency と reciprocal reference warning が多数。

### AC4: measure

| コマンド | Exit | health_score | 結果 |
|---|---:|---:|---|
| `timeout 1200 /home/simokitafresh/.codd-venv/bin/codd measure --path .` | 0 | 0/100 | `Graph: 16 nodes, 12 edges, 4 orphans, max depth 1`; `Coverage: 0/0 source files tracked (N/A), 628 design docs`; `Quality: 628 docs validated (663 errors, 386 warnings)` |

Binary checks:

| AC | Check | Result |
|---|---|---|
| AC1 | `timeout 1200 codd extract --path .` を実行し、結果を本ファイル末尾に追記した | yes |
| AC2 | `timeout 1200 codd generate --wave 1 --force --path .` を実行し、結果を本ファイル末尾に追記した | yes |
| AC3 | `timeout 1200 codd validate --path .` を実行し、結果を本ファイル末尾に追記した | yes |
| AC4 | `timeout 1200 codd measure --path .` を実行し、health_score=0/100を本ファイル末尾に追記した | yes |
