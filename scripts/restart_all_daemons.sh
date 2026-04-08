#!/bin/bash
# restart_all_daemons.sh — 全デーモン一発再起動
# Usage: bash scripts/restart_all_daemons.sh
#
# 実行順序:
#   1. ninja_monitor (状態監視)
#   2. inbox_watcher (メッセージ配信)
#   3. ntfy_listener (外部通知受信)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== 全デーモン再起動開始 ==="
echo ""

echo "--- [1/3] ninja_monitor ---"
bash "$SCRIPT_DIR/scripts/restart_monitor.sh"
echo ""

echo "--- [2/3] inbox_watcher ---"
bash "$SCRIPT_DIR/scripts/restart_watchers.sh"
echo ""

echo "--- [3/3] ntfy_listener ---"
bash "$SCRIPT_DIR/scripts/restart_ntfy_listener.sh"
echo ""

echo "=== 全デーモン再起動完了 ==="
