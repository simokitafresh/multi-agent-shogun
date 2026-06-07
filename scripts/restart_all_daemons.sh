#!/bin/bash
# restart_all_daemons.sh — 全デーモン一発再起動（並列実行）
# Usage: bash scripts/restart_all_daemons.sh
#
# 3デーモンは独立プロセスのため並列再起動:
#   1. ninja_monitor (状態監視)
#   2. inbox_watcher (メッセージ配信)
#   3. ntfy_listener (外部通知受信)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== 全デーモン再起動開始 ==="
echo ""

# restart_watchers.lockを削除: 旧inbox_watcher群がfd200(旧inode)を保持していても
# 新inodeで再作成されるため flock -n 200 が誤検知しない
rm -f /tmp/restart_watchers.lock

bash "$SCRIPT_DIR/scripts/restart_monitor.sh" &
PID_MONITOR=$!

bash "$SCRIPT_DIR/scripts/restart_watchers.sh" &
PID_WATCHERS=$!

bash "$SCRIPT_DIR/scripts/restart_ntfy_listener.sh" &
PID_NTFY=$!

FAILED=0
wait "$PID_MONITOR"  || { echo "ERROR: restart_monitor.sh failed"; FAILED=1; }
wait "$PID_WATCHERS" || { echo "ERROR: restart_watchers.sh failed"; FAILED=1; }
wait "$PID_NTFY"     || { echo "ERROR: restart_ntfy_listener.sh failed"; FAILED=1; }

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "=== 全デーモン再起動完了 ==="
else
    echo "ERROR: 一部デーモンの再起動に失敗しました"
    exit 1
fi
