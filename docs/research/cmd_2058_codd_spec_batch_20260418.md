# cmd_2058 CoDD Spec Batch

日付: 2026-04-18
担当: tobisaru (spec補完) / kotaro (実装)
対象: `scripts/hooks/pre-write-report-deny.sh`, `scripts/cmd_quality_log.sh`, `scripts/task_deploy.sh`

本文書は cmd_2050 (batch 13-B) および cmd_2046 (batch 12-B) で実装済みの改善に対する
正規 CoDD spec を事後補完するものである (cmd_2058)。

---

## 1. `scripts/hooks/pre-write-report-deny.sh`

### ボトルネック分析

PreToolUse hook として Claude Code から毎回起動される。
実装コミット前 (commit 6b150d4) の構造:

| ボトルネック | コード | コスト |
|---|---|---|
| stdin 読み込み | `payload="$(cat)"` | `cat` subprocess 起動 (~4ms) |
| tool_name 抽出 | `printf '%s' "$payload" \| jq -r '.tool_name'` | `jq` subprocess 起動 (~7ms) |
| file_path 抽出 | `printf '%s' "$payload" \| jq -r '.tool_input.file_path'` | `jq` subprocess 起動 (~7ms) |
| JSON 生成 | `jq -cn --arg reason "$reason" '{...}'` | `jq` subprocess 起動 (~7ms) |

非 report exit path (tool_name が Write/Edit でない場合) でも jq を 2 回呼び出す設計だった。
WSL2 では subprocess 起動コスト (~5–10ms/個) が支配的。

### 改善方針

1. **stdin 読み込み**: `IFS='' read -r -d '' payload || true` — `cat` subprocess を排除
2. **tool_name / file_path 抽出**: `[[ "$payload" =~ "tool_name"... ]]` + `BASH_REMATCH` — jq subprocess を bash 正規表現で置換
3. **JSON 生成**: `printf` builtin + bash 文字列置換でエスケープ — `jq -cn` subprocess を排除

早期 exit パス (tool_name が Write/Edit 以外) では stdin 読み込みと tool_name 抽出のみが実行されるため
最大の恩恵を受ける。

### 計測結果

計測パス: 非 report exit path (tool_name=Bash、report 以外のファイル)
計測方法: 同一 payload を stdin に与え 12 回実行、中央値

| 対象 | Before | After | 改善 |
|------|--------|-------|------|
| `scripts/hooks/pre-write-report-deny.sh` | `31ms` | `13ms` | `-58%` |

検証計測 (cmd_2058 時点): After = 4ms (Before 比さらに改善)

### 変更内容 (commit 10f1495, cmd_2050)

- `$(cat)` → `IFS='' read -r -d '' payload || true`
- `printf '%s' "$payload" | jq -r '.tool_name'` → bash regex `[[ "$payload" =~ \"tool_name\"... ]]`
- `printf '%s' "$payload" | jq -r '.tool_input.file_path'` → bash regex `[[ "$payload" =~ \"file_path\"... ]]`
- `jq -cn --arg reason "$reason" '{...}'` → `printf` builtin + bash string escape

### テスト

```bash
bats tests/unit/test_pre_bash_report_deny.bats tests/unit/test_pre_edit_report_deny.bats
```

21/21 PASS

---

## 2. `scripts/cmd_quality_log.sh`

### ボトルネック分析

cmd 完了時に gate から呼び出される。
実装コミット前 (commit e974e15^) の構造:

| ボトルネック | コード | コスト |
|---|---|---|
| SCRIPT_DIR 解決 | `$(cd "$(dirname "$0")" && pwd)` | subshell × 2 (~10ms) |
| REPO_ROOT 解決 | `$(cd "$SCRIPT_DIR/.." && pwd)` | subshell × 2 (~10ms) |

合計 4 subshell (dirname + cd + SCRIPT_DIR cd + cd) が起動パスで必ず実行される。
使用パス (usage exit path、引数不正) でも同様にコストが発生。

### 改善方針

`BASH_SOURCE[0]` を起点とした bash 文字列操作で SCRIPT_DIR/REPO_ROOT を解決。
- `_cql_self="${BASH_SOURCE[0]:-$0}"` → 相対パスを `$PWD` で補完
- `SCRIPT_DIR="${_cql_self%/*}"` → `%/*` で末尾ディレクトリを除去
- `REPO_ROOT="${SCRIPT_DIR%/scripts}"` → `%/scripts` で scripts ディレクトリを除去

subprocess ゼロで同等の結果を得る。

### 計測結果

計測パス: usage-exit path (引数なしで呼び出し)
計測方法: 12 回実行、中央値

| 対象 | Before | After | 改善 |
|------|--------|-------|------|
| `scripts/cmd_quality_log.sh` | `26ms` | `11ms` | `-58%` |

検証計測 (cmd_2058 時点): After = 5ms (Before 比さらに改善)

### 変更内容 (commit e974e15, cmd_2046)

```diff
-SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
-REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
+_cql_self="${BASH_SOURCE[0]:-$0}"
+[[ "$_cql_self" != /* ]] && _cql_self="$PWD/$_cql_self"
+SCRIPT_DIR="${_cql_self%/*}"
+REPO_ROOT="${SCRIPT_DIR%/scripts}"
```

### テスト

```bash
bats tests/unit/test_cmd_save_diagnose.bats
```

3/3 PASS (cmd_quality_log.sh を QUALITY_LOG_SCRIPT として参照)

---

## 3. `scripts/task_deploy.sh`

### ボトルネック分析

偵察タスク配備後の2名並行チェックゲート。
実装コミット前 (commit e974e15^) の構造:

| ボトルネック | コード | コスト |
|---|---|---|
| SCRIPT_DIR 解決 | `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)` | subshell × 3 (~15ms) |
| ゲートフラグ書込み timestamp | `date +%Y-%m-%dT%H:%M:%S` (cat heredoc 内) | `date` subprocess |
| ゲートフラグ書込み | `cat > "$flag_file" <<EOF2 ... EOF2` | heredoc + cat |
| gates_dir 作成 | `mkdir -p "$gates_dir"` | 毎回実行 |

非 recon path (task_type != recon) でもゲートフラグ書込みが発生するため
SCRIPT_DIR の subshell コストが常に適用される。

### 改善方針

1. **SCRIPT_DIR**: `%/scripts/task_deploy.sh` 文字列操作で解決 (subshell ゼロ)
2. **timestamp**: `printf -v _ts '%(%Y-%m-%dT%H:%M:%S)T' -1` (bash 4.2+ builtin)
3. **gates_dir 作成**: `[[ -d "$gates_dir" ]] || mkdir -p "$gates_dir"` (存在時はスキップ)
4. **ゲートフラグ書込み**: `printf` builtin で直接ファイルへ書込み (`cat` heredoc を排除)

### 計測結果

計測パス: non-recon path (task_type=implement)
計測方法: 12 回実行、中央値

| 対象 | Before | After | 改善 |
|------|--------|-------|------|
| `scripts/task_deploy.sh` | `17ms` | `8ms` | `-53%` |

検証計測 (cmd_2058 時点): After = 7ms (Before 比改善維持)

### 変更内容 (commit e974e15, cmd_2046)

```diff
-SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
+_td_self="${BASH_SOURCE[0]:-$0}"
+[[ "$_td_self" != /* ]] && _td_self="$PWD/$_td_self"
+SCRIPT_DIR="${_td_self%/scripts/task_deploy.sh}"
```

write_gate_flag 内:
```diff
-mkdir -p "$gates_dir"
+local _ts
+printf -v _ts '%(%Y-%m-%dT%H:%M:%S)T' -1
+[[ -d "$gates_dir" ]] || mkdir -p "$gates_dir"
-cat > "$flag_file" <<EOF2
-timestamp: $(date +%Y-%m-%dT%H:%M:%S)
-...
-EOF2
+printf 'timestamp: %s\ncmd_id: %s\n...\n' "$_ts" ... > "$flag_file"
```

### テスト

直接 unit test なし。cmd_complete_gate テストスイートで間接的にカバー。

```bash
bats tests/test_cmd_complete_gate.bats
```

---

## まとめ

| スクリプト | Before | After | 改善 | 実装 cmd |
|---|---|---|---|---|
| `scripts/hooks/pre-write-report-deny.sh` | 31ms | 13ms | -58% | cmd_2050 (batch 13-B) |
| `scripts/cmd_quality_log.sh` | 26ms | 11ms | -58% | cmd_2046 (batch 12-B) |
| `scripts/task_deploy.sh` | 17ms | 8ms | -53% | cmd_2046 (batch 12-B) |

共通ボトルネック: WSL2 上の subprocess 起動コスト (~5–10ms/個)
共通改善原則: bash 組み込み + 文字列操作で subprocess を排除
