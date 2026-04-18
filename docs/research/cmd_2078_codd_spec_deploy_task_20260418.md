# CoDD Spec: deploy_task.sh — cmd_2078 正規CoDD再改善

**Generated**: 2026-04-18
**Worker**: kagemaru
**Script**: `scripts/deploy_task.sh` (3999 lines)

---

## §1 Before計測 (hot path median 5回)

### 計測条件
- **Hot path定義**: no-args exit path (source cost + validate early return)
  - `bash scripts/deploy_task.sh` (引数なし → NINJA_NAME空でearly return)
  - 8ライブラリsource + 変数初期化 + parse_deploy_task_args + validate で終了
  - 家老が配備する度に実行されるスクリプトの最低コスト計測
- **計測環境**: WSL2 `/mnt/c/tools/multi-agent-shogun/` (NTFS)
- **条件**: FIELD_GET_NO_LOG=1 (スクリプト内で設定)

### Before計測結果
| run | ms |
|-----|-----|
| 1 | 76 |
| 2 | 70 |
| 3 | 99 |
| 4 | 83 |
| 5 | 115 |
| **median** | **83** |
| min | 70 |
| max | 115 |

### Full cmd deployment path (参考: /tmp fixture)
| run | ms |
|-----|-----|
| 1 | 369 (cold) |
| 2 | 219 |
| 3 | 203 |
| 4 | 182 |
| 5 | 179 |
| **median** | **203** |

---

## §2 ボトルネック分析 (上位3箇所)

### B1: pane_lookup.sh source — agent_config.sh二重load問題 (+50ms)

**場所**: `scripts/lib/pane_lookup.sh` lines 14, 18, 23, 31 (source時実行)

**現象**:
```
Cumulative source after ctx_utils.sh:  20ms
Cumulative source after pane_lookup.sh: 70ms
↳ pane_lookup.sh単独コスト: +50ms
```

**根因 (3層)**:
1. Line 14: `_PANE_LOOKUP_SCRIPT_DIR="${...:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"` — `$(dirname ...)` 外部プロセス + `$(cd ... pwd)` subshell ≒ 5ms
2. Line 18: `source "${...}/scripts/lib/agent_config.sh"` — agent_config.shは既にdeploy_task.shでsource済み。しかしagent_config.sh先頭の`_AGENT_CONFIG_RAW=""`行が**キャッシュをリセット**する。includeガードが存在しない。
3. Lines 23, 31: `$(get_all_agents)` が2回サブシェルで呼ばれる。各呼び出しでagent_config.shキャッシュが空(`_AGENT_CONFIG_RAW=""`)のためawk on settings.yaml が2回実行 → 約25ms × 2 = 50ms

**修正方針**:
- `agent_config.sh` 先頭にincludeガード追加: `[[ -n "${_AGENT_CONFIG_LOADED:-}" ]] && return 0; _AGENT_CONFIG_LOADED=1`
- これにより再source時キャッシュ保持 → `$(get_all_agents)` のawk再実行を排除
- `$(get_all_agents)` を1回に統合: `_all_str="$(get_all_agents)"` で取得後、MAP構築と PANE_LOOKUP_AGENT_ORDER を同一変数から設定

**期待節約**: ~35-40ms → hot path 83ms → 45ms以下

---

### B2: resolve_cmd_to_task field extraction — 6×subshell (~19ms)

**場所**: `scripts/deploy_task.sh` lines 300-305

**現象**:
```
6x echo "$output" | grep | cut パターン
Current:  ~20ms
Optimized (while+IFS): ~3ms
節約: ~17ms
```

**コード**:
```bash
# 現状 (6x subprocess triplet = 18 subprocesses)
project=$(echo "$_resolve_output" | grep '^project=' | cut -d= -f2-)
task_type=$(echo "$_resolve_output" | grep '^task_type=' | cut -d= -f2-)
title=$(echo "$_resolve_output" | grep '^title=' | cut -d= -f2-)
purpose=$(echo "$_resolve_output" | grep '^purpose=' | cut -d= -f2-)
_depends_on=$(echo "$_resolve_output" | grep '^depends_on=' | cut -d= -f2-)
_scout_exempt_stk=$(echo "$_resolve_output" | grep '^scout_exempt=' | cut -d= -f2-)
```

**修正方針**:
```bash
# while+IFS one-pass (0 subprocesses)
declare -A _rv=()
while IFS='=' read -r _k _v; do
    [[ -n "$_k" ]] && _rv["$_k"]="$_v"
done <<< "$_resolve_output"
project="${_rv[project]}"
task_type="${_rv[task_type]}"
title="${_rv[title]}"
purpose="${_rv[purpose]}"
_depends_on="${_rv[depends_on]}"
_scout_exempt_stk="${_rv[scout_exempt]}"
unset _rv _k _v
```

**期待節約**: ~17ms (full cmd pathに限定)

---

### B3: GP-198 session_state python3 fast-path (~53ms)

**場所**: `scripts/deploy_task.sh` lines 3830-3840

**現象**:
```
python3 -c "import yaml, json, sys; ..." が毎CMD_ID配備で実行
python3 + yaml + json import: ~53ms
ほとんどの場合 session_state は空 or null → python3起動コストが無駄
```

**修正方針**:
- awk fast-path: task YAML に `session_state:` キーが存在しなければ python3 呼び出しをスキップ
```bash
# fast-path: session_state フィールドが存在しなければスキップ
if grep -qE '^[[:space:]]+session_state:' "$task_yaml" 2>/dev/null; then
    _DEPLOY_PREV_SESSION_STATE=$(python3 -c "...")
else
    _DEPLOY_PREV_SESSION_STATE=""
fi
```
- session_state を持つケースは稀 → ほぼ全ての配備で53ms節約

**期待節約**: ~50ms (session_state非存在ケース、full cmd pathに限定)

---

## §3 改善計画

| 優先 | 対象 | 改善内容 | 期待節約 | パス |
|------|------|----------|---------|------|
| B1 | `scripts/lib/agent_config.sh` | includeガード追加 (`_AGENT_CONFIG_LOADED`) | ~35ms | hot path |
| B1 | `scripts/lib/pane_lookup.sh` | `$(get_all_agents)` 1回化、SCRIPT_DIR string ops | ~5ms | hot path |
| B2 | `scripts/deploy_task.sh` L300-305 | 6x echo+grep+cut → while+IFS | ~17ms | cmd path |
| B3 | `scripts/deploy_task.sh` L3830-3840 | session_state awk fast-path | ~50ms | cmd path |

### 合計期待改善
- **hot path** (no-args): 83ms → **45ms以下** (目標50ms以下✅)
- **full cmd path**: 203ms → **130ms以下**

---

## §4 テスト計画

```bash
# batsテスト確認 (既存10ファイル)
cd /mnt/c/tools/multi-agent-shogun
bats tests/unit/test_deploy_task_lifecycle.bats
bats tests/unit/test_deploy_task_ac_handling.bats
bats tests/unit/test_deploy_task_ac_version.bats
bats tests/unit/test_deploy_task_codd_failure_history.bats
bats tests/unit/test_deploy_task_match_ninja.bats
bats tests/unit/test_deploy_task_recent_noncmd_commit_warn.bats
bats tests/unit/test_deploy_task_target_files.bats
bats tests/unit/test_deploy_task_template_generation.bats
bats tests/unit/test_deploy_task_useful_rate_decay.bats
```

- agent_config.sh includeガード: 既存テストが依存するfunction動作は変わらない
- pane_lookup.sh: pane_lookup()関数動作は変わらない (source時の初期化のみ)
- resolve_cmd_to_task: awk出力のparse方式変更のみ (値は同一)
- GP-198 fast-path: session_state空の場合は`""`返却 (変化なし)、存在する場合は従来通りpython3

### regression判定
- 全batsテストPASS → AC4へ
- after median > before median → revert (AC3)
