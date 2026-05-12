#!/bin/bash
# restart_watchers.sh — inbox_watcher全プロセスを再起動
# Usage: bash scripts/restart_watchers.sh
# cmd_100: スクリプト更新後の再起動用

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 並行実行ガード（flock排他）
LOCK_FILE="/tmp/restart_watchers.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "ERROR: restart_watchers.sh is already running. Aborting."
    exit 1
fi

echo "=== inbox_watcher 再起動 ==="

# 1. 既存プロセスを停止
echo "[1/3] 既存プロセスを停止..."
pkill -f "inbox_watcher.sh" 2>/dev/null || true
pkill -f "inotifywait.*queue/inbox" 2>/dev/null || true
sleep 1

remaining=$(pgrep -fc "inbox_watcher\.sh" 2>/dev/null) || remaining=0
echo "  残存プロセス: $remaining"

if [ "$remaining" -gt 0 ]; then
    echo "  残存あり。SIGKILL送信..."
    pkill -9 -f "inbox_watcher\.sh" 2>/dev/null || true
    sleep 1
    remaining=$(pgrep -fc "inbox_watcher\.sh" 2>/dev/null) || remaining=0
    echo "  SIGKILL後残存: $remaining"
fi

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
    &>> "$SCRIPT_DIR/logs/inbox_watcher_shogun.log" &
disown
echo "  shogun → shogun:main ($!)"
LAUNCHED_AGENTS+=("shogun")
LAUNCHED_PIDS+=("$!")

# 家老
_cli=$(tmux show-options -p -t "shogun:agents.1" -v @agent_cli 2>/dev/null || echo "claude")
unset ASW_DISABLE_ESCALATION
nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" karo "shogun:agents.1" "$_cli" \
    &>> "$SCRIPT_DIR/logs/inbox_watcher_karo.log" &
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
        &>> "$SCRIPT_DIR/logs/inbox_watcher_${name}.log" &
    disown
    echo "  ${name} → ${pane} ($!)"
    LAUNCHED_AGENTS+=("${name}")
    LAUNCHED_PIDS+=("$!")
done

echo "[3/3] 起動確認..."
sleep 1
failed_agents=()
for i in "${!LAUNCHED_AGENTS[@]}"; do
    agent="${LAUNCHED_AGENTS[$i]}"
    # pgrep で実際の inbox_watcher.sh プロセスを確認（kill -0 はnohup bashが終了すると偽陽性になる）
    if ! pgrep -f "inbox_watcher\.sh.*${agent}" > /dev/null 2>&1; then
        failed_agents+=("${agent}")
    fi
done

total=${#LAUNCHED_AGENTS[@]}
failed=${#failed_agents[@]}
ok=$((total - failed))

if [ "$failed" -eq 0 ]; then
    echo "  稼働中: ${ok}/${total} プロセス"
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
sleep 2
inotify_count=$(pgrep -fc "inotifywait.*queue/inbox" 2>/dev/null) || inotify_count=0
if [[ "$inotify_count" -lt "$ok" ]]; then
    echo "  WARN: inotifywait ${inotify_count}/${ok} — watcher起動したがinotifywait未稼働の可能性"
else
    echo "  OK: inotifywait ${inotify_count}/${ok}"
fi

# ペイン変数同期
echo "[+] ペイン変数同期..."
bash "$SCRIPT_DIR/scripts/sync_pane_vars.sh"
