#!/bin/bash
# semantic-links: [[inbox_watcherプロセスモデル]]
# restart_watchers.sh — inbox_watcher全プロセスを再起動
# Usage: bash scripts/restart_watchers.sh
# cmd_100: スクリプト更新後の再起動用

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_WATCHER_COUNT="${EXPECTED_WATCHER_COUNT:-9}"

# 並行実行ガード（flock排他）
LOCK_FILE="/tmp/restart_watchers.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "ERROR: restart_watchers.sh is already running. Aborting."
    exit 1
fi

# WSL shutdownで/tmp cacheが消えた直後も、三層記憶preflightより先に生成を始める。
# 非同期かつ共通ライブラリのflock single-flightなのでwatcher再起動を待たせない。
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/memory_db_cache.sh"
memory_db_source="${SHOGUN_MEMORY_DB_SOURCE_PATH:-$SCRIPT_DIR/data/multi_agent_shogun_memory.db}"
warm_memory_db_cache_async "$SCRIPT_DIR" "$memory_db_source"

# 隔離テスト用: watcher processへ触れず、上記の実起動フローだけを実行する。
if [ "${RESTART_WATCHERS_WARMUP_ONLY:-0}" = "1" ]; then
    exit 0
fi

echo "=== inbox_watcher 再起動 ==="

watcher_process_count() {
    ps -eo pid=,ppid=,args= 2>/dev/null | awk '
        /(^| )bash .*\/inbox_watcher\.sh [a-z]/ {
            pid=$1; ppid=$2; watcher[pid]=1; parent[pid]=ppid; line[pid]=$0
        }
        END {
            count=0
            for (pid in watcher) {
                if (!(parent[pid] in watcher)) count++
            }
            print count + 0
        }
    '
}

stop_existing_watchers() {
    local remaining

    pkill -TERM -f "[i]nbox_watcher\.sh" 2>/dev/null || true
    pkill -TERM -f "[i]notifywait.*queue/inbox" 2>/dev/null || true
    pkill -TERM -f "[t]imeout .*inotifywait.*queue/inbox" 2>/dev/null || true
    fuser -k /tmp/inbox_watcher_singleton_*.lock >/dev/null 2>&1 || true

    # Adaptive poll (max 1s) instead of fixed sleep 1
    local _sw_i=0
    remaining="$(watcher_process_count)"
    while [ "$remaining" -gt 0 ] && [ "$_sw_i" -lt 10 ]; do
        sleep 0.1
        ((_sw_i++)) || true
        remaining="$(watcher_process_count)"
    done
    echo "  SIGTERM後残存: $remaining"

    if [ "$remaining" -gt 0 ]; then
        echo "  残存あり。SIGKILL送信..."
        pkill -KILL -f "[i]nbox_watcher\.sh" 2>/dev/null || true
        pkill -KILL -f "[i]notifywait.*queue/inbox" 2>/dev/null || true
        pkill -KILL -f "[t]imeout .*inotifywait.*queue/inbox" 2>/dev/null || true
        fuser -k /tmp/inbox_watcher_singleton_*.lock >/dev/null 2>&1 || true
        # Adaptive poll (max 1s) for SIGKILL
        _sw_i=0
        remaining="$(watcher_process_count)"
        while [ "$remaining" -gt 0 ] && [ "$_sw_i" -lt 10 ]; do
            sleep 0.1
            ((_sw_i++)) || true
            remaining="$(watcher_process_count)"
        done
        echo "  SIGKILL後残存: $remaining"
    fi

    if [ "$remaining" -ne 0 ]; then
        echo "ERROR: 旧inbox_watcherが停止しきれていません (remaining=$remaining)"
        return 1
    fi
}

verify_watcher_count() {
    local expected="$1"
    local actual
    actual="$(watcher_process_count)"
    if [ "$actual" -ne "$expected" ]; then
        echo "ERROR: inbox_watcherプロセス数が不正です (actual=${actual}, expected=${expected})"
        ps -eo pid=,ppid=,args= 2>/dev/null | awk '
            /(^| )bash .*\/inbox_watcher\.sh [a-z]/ {
                pid=$1; ppid=$2; watcher[pid]=1; parent[pid]=ppid; line[pid]=$0
            }
            END {
                for (pid in watcher) {
                    if (!(parent[pid] in watcher)) print line[pid]
                }
            }
        ' || true
        return 1
    fi
    echo "  OK: inbox_watcher ${actual}/${expected}"
}

# 1. 既存プロセスを停止
echo "[1/3] 既存プロセスを停止..."
stop_existing_watchers

# 2. PANE_BASEを取得
# pane_base: pane_lookup()が内部で解決するため直接参照は不要

# 3. 全watcherを再起動
echo "[2/3] 新プロセスを起動..."

# PID追跡（個別watcher起動検証用）
declare -a LAUNCHED_AGENTS=()
declare -a LAUNCHED_PIDS=()

# 将軍
_cli=$(tmux show-options -p -t "shogun:main" -v @agent_cli 2>/dev/null || echo "claude")
unset ASW_DISABLE_ESCALATION
nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" shogun "shogun:main" "$_cli" \
    &>> "$SCRIPT_DIR/logs/inbox_watcher_shogun.log" 200>&- &
disown
echo "  shogun → shogun:main ($!)"
LAUNCHED_AGENTS+=("shogun")
LAUNCHED_PIDS+=("$!")

# 全エージェント（settings.yaml + @agent_idから動的取得 — cmd_1136）
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/pane_lookup.sh"

for name in $(get_all_agents); do
    [[ "$name" == "shogun" ]] && continue  # 将軍は行115-120で別途起動済み
    pane=$(pane_lookup "$name" 2>/dev/null) || true
    [[ -z "$pane" ]] && continue
    _cli=$(tmux show-options -p -t "$pane" -v @agent_cli 2>/dev/null || echo "claude")
    unset ASW_DISABLE_ESCALATION
    nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "${name}" "$pane" "$_cli" \
        &>> "$SCRIPT_DIR/logs/inbox_watcher_${name}.log" 200>&- &
    disown
    echo "  ${name} → ${pane} ($!)"
    LAUNCHED_AGENTS+=("${name}")
    LAUNCHED_PIDS+=("$!")
done

echo "[3/3] 起動確認..."
# Adaptive poll (max 1s): 単一pgrep-afで全エージェント一括チェック（N並列pgrep回避）
_lp_i=0
_all_launched=0
while [ "$_lp_i" -lt 10 ]; do
    _running=$(pgrep -af "[i]nbox_watcher\.sh" 2>/dev/null || true)
    _all_launched=1
    for _la in "${LAUNCHED_AGENTS[@]}"; do
        if ! printf '%s\n' "$_running" | grep -q "inbox_watcher\.sh ${_la} "; then
            _all_launched=0
            break
        fi
    done
    [ "$_all_launched" -eq 1 ] && break
    sleep 0.1
    ((_lp_i++)) || true
done
failed_agents=()
# 最終確認: 単一pgrep-afでまとめて取得し、各エージェントをgrep確認
_running=$(pgrep -af "[i]nbox_watcher\.sh" 2>/dev/null || true)
for i in "${!LAUNCHED_AGENTS[@]}"; do
    agent="${LAUNCHED_AGENTS[$i]}"
    # 一括取得済みリストからエージェント名で絞り込み（per-agent pgrep排除）
    if ! printf '%s\n' "$_running" | grep -q "inbox_watcher\.sh ${agent} "; then
        failed_agents+=("${agent}")
    fi
done

total=${#LAUNCHED_AGENTS[@]}
failed=${#failed_agents[@]}
ok=$((total - failed))

if [ "$failed" -eq 0 ]; then
    echo "  稼働中: ${ok}/${total} プロセス"
    if [ "$total" -ne "$EXPECTED_WATCHER_COUNT" ]; then
        echo "=== 警告: 起動対象数が正常値と異なります (${total}/${EXPECTED_WATCHER_COUNT}) ==="
        exit 1
    fi
    verify_watcher_count "$EXPECTED_WATCHER_COUNT"
    echo "=== 再起動完了 (${ok}/${total}) ==="
else
    echo "  稼働中: ${ok}/${total} プロセス"
    for agent in "${failed_agents[@]}"; do
        echo "  FAIL: ${agent}"
    done
    echo "=== 警告: ${failed}/${total} watcherが起動失敗 ==="
    exit 1
fi

# GP-226: ヘルスチェック — inotifywaitプロセスが実際に稼働しているか確認
echo "[+] ヘルスチェック (inotifywait)..."
# Adaptive poll (max 2s) instead of fixed sleep 2
_iw_i=0
inotify_count=$(pgrep -fc "inotifywait.*queue/inbox" 2>/dev/null) || inotify_count=0
while [[ "$inotify_count" -lt "$ok" ]] && [ "$_iw_i" -lt 20 ]; do
    sleep 0.1
    ((_iw_i++)) || true
    inotify_count=$(pgrep -fc "inotifywait.*queue/inbox" 2>/dev/null) || inotify_count=0
done
if [[ "$inotify_count" -lt "$ok" ]]; then
    echo "  WARN: inotifywait ${inotify_count}/${ok} — watcher起動したがinotifywait未稼働の可能性"
else
    echo "  OK: inotifywait ${inotify_count}/${ok}"
fi

# ペイン変数同期（バックグラウンド — model_detect capture-pane高コスト回避）
echo "[+] ペイン変数同期 (バックグラウンド)..."
nohup bash "$SCRIPT_DIR/scripts/sync_pane_vars.sh" \
    &>> "$SCRIPT_DIR/logs/sync_pane_vars.log" 200>&- &
disown
