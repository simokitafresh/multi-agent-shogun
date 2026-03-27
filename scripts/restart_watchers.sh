#!/bin/bash
# restart_watchers.sh — inbox_watcher全プロセスを再起動
# Usage: bash scripts/restart_watchers.sh
# cmd_100: スクリプト更新後の再起動用

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

# 将軍
_cli=$(tmux show-options -p -t "shogun:main" -v @agent_cli 2>/dev/null || echo "claude")
nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" shogun "shogun:main" "$_cli" \
    &>> "$SCRIPT_DIR/logs/inbox_watcher_shogun.log" &
disown
echo "  shogun → shogun:main ($!)"

# 家老
_cli=$(tmux show-options -p -t "shogun:agents.1" -v @agent_cli 2>/dev/null || echo "claude")
nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" karo "shogun:agents.1" "$_cli" \
    &>> "$SCRIPT_DIR/logs/inbox_watcher_karo.log" &
disown
echo "  karo → shogun:agents.1 ($!)"

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
    nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "${name}" "$pane" "$_cli" \
        &>> "$SCRIPT_DIR/logs/inbox_watcher_${name}.log" &
    disown
    echo "  ${name} → ${pane} ($!)"
done

echo "[3/3] 起動確認..."
sleep 1
count=$(pgrep -fc "inbox_watcher\.sh" 2>/dev/null) || count=0
echo "  稼働中: ${count} プロセス"

# 期待プロセス数: shogun(1) + get_all_agents全員のwatcher
expected=$((1 + $(get_all_agents | wc -w)))
if [ "$count" -eq "$expected" ]; then
    echo "=== 再起動完了 (${count}/${expected}) ==="
else
    echo "=== 警告: 期待${expected}だが${count}プロセスのみ ==="
fi

# ペイン変数同期
echo "[+] ペイン変数同期..."
bash "$(dirname "$0")/sync_pane_vars.sh"
