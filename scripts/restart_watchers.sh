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

# 家老
_cli=$(tmux show-options -p -t "shogun:agents.1" -v @agent_cli 2>/dev/null || echo "claude")
unset ASW_DISABLE_ESCALATION
nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" karo "shogun:agents.1" "$_cli" \
    &>> "$SCRIPT_DIR/logs/inbox_watcher_karo.log" 200>&- &
disown
echo "  karo → shogun:agents.1 ($!)"
LAUNCHED_AGENTS+=("karo")
LAUNCHED_PIDS+=("$!")

# 忍者+軍師（settings.yamlから動的取得 — cmd_1136）
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/pane_lookup.sh"

for name in $(get_all_agents); do
    [[ "$name" == "karo" ]] && continue  # karo is handled above
    pane=$(pane_lookup "$name" 2>/dev/null)
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
# Adaptive poll (max 1s) instead of fixed sleep 1
_lp_i=0
_all_launched=0
while [ "$_lp_i" -lt 10 ]; do
    _all_launched=1
    for _la in "${LAUNCHED_AGENTS[@]}"; do
        if ! pgrep -f "[i]nbox_watcher\.sh ${_la} " > /dev/null 2>&1; then
            _all_launched=0
            break
        fi
    done
    [ "$_all_launched" -eq 1 ] && break
    sleep 0.1
    ((_lp_i++)) || true
done
failed_agents=()
for i in "${!LAUNCHED_AGENTS[@]}"; do
    agent="${LAUNCHED_AGENTS[$i]}"
    # pgrep で実際の inbox_watcher.sh プロセスを確認（kill -0 はnohup bashが終了すると偽陽性になる）
    if ! pgrep -f "[i]nbox_watcher\.sh ${agent} " > /dev/null 2>&1; then
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

# ペイン変数同期
echo "[+] ペイン変数同期..."
bash "$SCRIPT_DIR/scripts/sync_pane_vars.sh"
