#!/usr/bin/env bash
# process_stop.sh — 安全ガード付きプロセス停止
# D006のkill直接実行禁止を遵守しつつ、エージェントがプロセスを停止できる。
#
# Usage: bash scripts/process_stop.sh <PID> [--force]
#   --force: SIGTERM後5秒待ってSIGKILL（デフォルトはSIGTERMのみ）
#
# 安全ガード:
#   1. PIDが存在すること
#   2. プロセスが現ユーザー所有であること
#   3. プロセスがプロジェクト関連コマンドであること（python/node/bash）
#   4. PID 1, init, systemd等のシステムプロセスは絶対拒否
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../logs/process_stop.log"

log() {
    local msg="$1"
    local ts
    ts="$(date '+%Y-%m-%dT%H:%M:%S')"
    echo "[$ts] $msg" | tee -a "$LOG_FILE"
}

die() {
    log "DENIED: $1"
    echo "ERROR: $1" >&2
    exit 1
}

# --- 引数解析 ---
PID="${1:-}"
FORCE=false
if [[ "${2:-}" == "--force" ]]; then
    FORCE=true
fi

if [[ -z "$PID" ]]; then
    echo "Usage: bash scripts/process_stop.sh <PID> [--force]" >&2
    exit 1
fi

# --- ガード1: 数値チェック ---
if ! [[ "$PID" =~ ^[0-9]+$ ]]; then
    die "PID must be numeric: $PID"
fi

# --- ガード2: システムプロセス拒否 ---
if (( PID <= 10 )); then
    die "System process (PID <= 10) cannot be stopped: $PID"
fi

# --- ガード3: プロセス存在確認 ---
if ! kill -0 "$PID" 2>/dev/null; then
    log "PID $PID does not exist (already stopped?)"
    echo "PID $PID does not exist"
    exit 0
fi

# --- ガード4: 所有者確認 ---
PROC_USER="$(ps -o user= -p "$PID" 2>/dev/null || true)"
CURRENT_USER="$(whoami)"
if [[ -z "$PROC_USER" ]]; then
    die "Cannot determine owner of PID $PID"
fi
if [[ "$PROC_USER" != "$CURRENT_USER" ]]; then
    die "PID $PID belongs to '$PROC_USER', not '$CURRENT_USER'"
fi

# --- ガード5: コマンド確認（プロジェクト関連のみ許可）---
PROC_CMD="$(ps -o args= -p "$PID" 2>/dev/null || true)"
if [[ -z "$PROC_CMD" ]]; then
    die "Cannot determine command of PID $PID"
fi

# 許可パターン: python/python3/node/bash のスクリプト実行
ALLOWED=false
case "$PROC_CMD" in
    python*|*python3*|node*|bash*|/bin/bash*)
        ALLOWED=true
        ;;
esac

if [[ "$ALLOWED" != "true" ]]; then
    die "PID $PID is not a recognized project process: $PROC_CMD"
fi

# --- 停止実行 ---
log "STOP PID=$PID USER=$PROC_USER CMD='$PROC_CMD' FORCE=$FORCE"

kill -TERM "$PID" 2>/dev/null || true
log "SIGTERM sent to PID $PID"

if [[ "$FORCE" == "true" ]]; then
    sleep 5
    if kill -0 "$PID" 2>/dev/null; then
        kill -KILL "$PID" 2>/dev/null || true
        log "SIGKILL sent to PID $PID (did not stop after SIGTERM)"
    else
        log "PID $PID stopped after SIGTERM (SIGKILL not needed)"
    fi
fi

# --- 確認 ---
sleep 1
if kill -0 "$PID" 2>/dev/null; then
    log "WARNING: PID $PID still alive after stop attempt"
    echo "WARNING: PID $PID still alive. Try with --force"
else
    log "PID $PID stopped successfully"
    echo "PID $PID stopped"
fi
