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

remaining=$(ps aux | grep inbox_watcher | grep -v grep | grep -v restart_watchers | wc -l)
echo "  残存プロセス: $remaining"

# 2. PANE_BASEを取得
PANE_BASE=$(tmux show-options -p -t "shogun:agents.1" -v @pane_index 2>/dev/null || echo "1")

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

# 忍者
NINJA_NAMES=(sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru)
NINJA_PANES=(2 3 4 5 6 7 8 9)

for i in "${!NINJA_NAMES[@]}"; do
    name="${NINJA_NAMES[$i]}"
    pane="${NINJA_PANES[$i]}"
    _cli=$(tmux show-options -p -t "shogun:agents.${pane}" -v @agent_cli 2>/dev/null || echo "claude")
    nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "${name}" "shogun:agents.${pane}" "$_cli" \
        &>> "$SCRIPT_DIR/logs/inbox_watcher_${name}.log" &
    disown
    echo "  ${name} → shogun:agents.${pane} ($!)"
done

echo "[3/3] 起動確認..."
sleep 1
count=$(ps aux | grep inbox_watcher | grep -v grep | grep -v restart_watchers | wc -l)
echo "  稼働中: ${count} プロセス"

if [ "$count" -eq 10 ]; then
    echo "=== 再起動完了 (10/10) ==="
else
    echo "=== 警告: 期待10だが${count}プロセスのみ ==="
fi

# ペイン変数同期
echo "[+] ペイン変数同期..."
bash "$(dirname "$0")/sync_pane_vars.sh"
