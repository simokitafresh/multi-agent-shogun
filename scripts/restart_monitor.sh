#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# restart_monitor.sh
# ninja_monitor.shの安全な再起動スクリプト
# 旧プロセスkill → 新起動 → 起動確認
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MONITOR_SCRIPT="$SCRIPT_DIR/scripts/ninja_monitor.sh"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/ninja_monitor.log"

mkdir -p "$LOG_DIR"

echo "[$(date)] === ninja_monitor restart initiated ==="

# --- Step 1: 旧プロセスの特定と停止 ---
OLD_PIDS=$(pgrep -f "ninja_monitor.sh" 2>/dev/null || true)

if [ -n "$OLD_PIDS" ]; then
    echo "[$(date)] Found existing ninja_monitor process(es): $OLD_PIDS"
    for pid in $OLD_PIDS; do
        # 自分自身(restart script)を除外
        if [ "$pid" -eq "$$" ]; then
            continue
        fi
        echo "[$(date)] Killing PID $pid ..."
        kill "$pid" 2>/dev/null || true
    done

    # 停止完了を待機(最大5秒)
    WAIT_COUNT=0
    while [ "$WAIT_COUNT" -lt 10 ]; do
        REMAINING=$(pgrep -f "ninja_monitor.sh" 2>/dev/null | grep -v "^$$\$" || true)
        if [ -z "$REMAINING" ]; then
            echo "[$(date)] Old process(es) terminated successfully"
            break
        fi
        sleep 0.5
        WAIT_COUNT=$((WAIT_COUNT + 1))
    done

    if [ -n "$(pgrep -f "ninja_monitor.sh" 2>/dev/null | grep -v "^$$\$" || true)" ]; then
        echo "[$(date)] WARNING: Old process still running after 5s, sending SIGKILL"
        for pid in $OLD_PIDS; do
            [ "$pid" -eq "$$" ] && continue
            kill -9 "$pid" 2>/dev/null || true
        done
        sleep 1
    fi
else
    echo "[$(date)] No existing ninja_monitor process found"
fi

# --- Step 2: 新ninja_monitor.shをnohup起動 ---
echo "[$(date)] Starting new ninja_monitor.sh ..."
nohup bash "$MONITOR_SCRIPT" >> "$LOG_FILE" 2>&1 &
NEW_PID=$!
echo "[$(date)] Launched with PID: $NEW_PID"

# --- Step 3: 起動確認 ---
sleep 3

if kill -0 "$NEW_PID" 2>/dev/null; then
    echo ""
    echo "=== Restart Result ==="
    echo "STATUS: SUCCESS"
    echo "  Monitor PID: $NEW_PID"
    echo "  Log file:    $LOG_FILE"
    # 直近ログ出力で動作確認
    echo ""
    echo "--- Recent log ---"
    tail -5 "$LOG_FILE" 2>/dev/null || true
else
    echo ""
    echo "=== Restart Result ==="
    echo "STATUS: FAILED"
    echo "  Monitor PID $NEW_PID is not running."
    echo "  Check log: $LOG_FILE"
    exit 1
fi
