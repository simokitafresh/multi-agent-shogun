#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# restart_ntfy_listener.sh
# ntfy_listener.shの安全な再起動スクリプト
# 旧プロセスkill → flock解放確認 → 新起動 → curl存在確認
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="/tmp/ntfy_listener.lock"
LISTENER_SCRIPT="$SCRIPT_DIR/scripts/ntfy_listener.sh"
LOG_DIR="$SCRIPT_DIR/logs"

mkdir -p "$LOG_DIR"

echo "[$(date)] === ntfy_listener restart initiated ==="

# --- Step 1: 旧プロセスの特定と停止 ---
# フルパスでマッチ: restart_ntfy_listener.sh への誤マッチを防ぐ
OLD_PIDS=$(pgrep -f "$LISTENER_SCRIPT" 2>/dev/null || true)

if [ -n "$OLD_PIDS" ]; then
    echo "[$(date)] Found existing ntfy_listener process(es): $OLD_PIDS"
    for pid in $OLD_PIDS; do
        # 自分自身(restart script)を除外
        if [ "$pid" -eq "$$" ]; then
            continue
        fi
        echo "[$(date)] Killing PID $pid ..."
        kill "$pid" 2>/dev/null || true
    done

    # curl子プロセスも停止(ntfy_listener.shのcoproc)
    CURL_PIDS=$(pgrep -f "curl.*ntfy.sh/.*/json" 2>/dev/null || true)
    if [ -n "$CURL_PIDS" ]; then
        echo "[$(date)] Killing orphan curl stream process(es): $CURL_PIDS"
        for pid in $CURL_PIDS; do
            kill "$pid" 2>/dev/null || true
        done
    fi

    # 停止完了を待機(最大5秒)
    WAIT_COUNT=0
    while [ "$WAIT_COUNT" -lt 10 ]; do
        REMAINING=$(pgrep -f "$LISTENER_SCRIPT" 2>/dev/null || true)
        if [ -z "$REMAINING" ]; then
            echo "[$(date)] Old process(es) terminated successfully"
            break
        fi
        sleep 0.5
        WAIT_COUNT=$((WAIT_COUNT + 1))
    done

    if [ -n "$(pgrep -f "$LISTENER_SCRIPT" 2>/dev/null || true)" ]; then
        echo "[$(date)] WARNING: Old process still running after 5s, sending SIGKILL"
        for pid in $OLD_PIDS; do
            [ "$pid" -eq "$$" ] && continue
            kill -9 "$pid" 2>/dev/null || true
        done
        sleep 1
    fi
else
    echo "[$(date)] No existing ntfy_listener process found"
fi

# --- Step 2: flockファイル解放確認 ---
if [ -f "$LOCK_FILE" ]; then
    # flockが解放されたか確認(ノンブロッキングで取得試行)
    if (flock -n 200) 200>"$LOCK_FILE" 2>/dev/null; then
        echo "[$(date)] Lock file is free"
    else
        echo "[$(date)] WARNING: Lock file still held, removing stale lock"
        rm -f "$LOCK_FILE"
        sleep 1
    fi
fi

# --- Step 3: 新ntfy_listener.shをnohup起動 ---
LOG_FILE="$LOG_DIR/ntfy_listener.log"
echo "[$(date)] Starting new ntfy_listener.sh ..."
nohup bash "$LISTENER_SCRIPT" >> "$LOG_FILE" 2>&1 &
NEW_PID=$!
echo "[$(date)] Launched with PID: $NEW_PID"

# --- Step 4: 起動確認(curlストリーム接続の存在チェック) ---
# ポーリング: curlが接続されたら即終了(最大3秒)
LISTENER_ALIVE=0
CURL_FOUND=0
POLL_COUNT=0
while [ "$POLL_COUNT" -lt 6 ]; do
    if kill -0 "$NEW_PID" 2>/dev/null; then
        LISTENER_ALIVE=1
    fi
    if pgrep -f "curl.*ntfy.sh/.*/json" >/dev/null 2>&1; then
        CURL_FOUND=1
    fi
    if [ "$LISTENER_ALIVE" -eq 1 ] && [ "$CURL_FOUND" -eq 1 ]; then
        break
    fi
    sleep 0.5
    POLL_COUNT=$((POLL_COUNT + 1))
done

echo ""
echo "=== Restart Result ==="
if [ "$LISTENER_ALIVE" -eq 1 ] && [ "$CURL_FOUND" -eq 1 ]; then
    echo "STATUS: SUCCESS"
    echo "  Listener PID: $NEW_PID"
    echo "  Curl stream:  active"
    echo "  Log file:     $LOG_FILE"
elif [ "$LISTENER_ALIVE" -eq 1 ]; then
    echo "STATUS: PARTIAL (listener running, curl stream not yet detected)"
    echo "  Listener PID: $NEW_PID"
    echo "  Log file:     $LOG_FILE"
    echo "  Note: curl may still be connecting. Check log in a few seconds."
else
    echo "STATUS: FAILED"
    echo "  Listener PID $NEW_PID is not running."
    echo "  Check log: $LOG_FILE"
    exit 1
fi
