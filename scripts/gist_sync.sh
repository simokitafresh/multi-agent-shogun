#!/bin/bash
# gist_sync.sh — dashboard.md変更検知 → Gist自動アップロード
# Usage: bash scripts/gist_sync.sh [gist_id]
#
# WSL2の/mnt/c/ではinotifywaitがdrvfs上で機能しないため、
# statによるmtimeポーリング方式を採用。
# Linux FSパスの場合はinotifywaitを使用（高速・低負荷）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DASHBOARD="$SCRIPT_DIR/dashboard.md"
LOG="$SCRIPT_DIR/logs/gist_sync.log"

# ─── GIST_ID動的解決: current_project → gist_url → GIST_ID ───
# 引数指定があればそちらを優先（後方互換）
DEFAULT_GIST_ID="6eb495d917fb00ba4d4333c237a4ee0c"
if [ -n "$1" ]; then
    GIST_ID="$1"
else
    PROJECTS_YAML="$SCRIPT_DIR/config/projects.yaml"
    if [ -f "$PROJECTS_YAML" ]; then
        # L034: 固定インデント依存にしない柔軟なパース
        CURRENT_PJ=$(awk '/^current_project:/{print $2}' "$PROJECTS_YAML")
        if [ -n "$CURRENT_PJ" ]; then
            # PJブロック内のgist_urlを取得（id:マッチ→次のgist_url:を抽出）
            GIST_URL=$(awk -v id="$CURRENT_PJ" '
                /^[[:space:]]*- id:/ { found=($NF == id) }
                found && /gist_url:/ { gsub(/.*gist_url:[[:space:]]*"?|"?[[:space:]]*$/, ""); print; exit }
            ' "$PROJECTS_YAML")
            if [ -n "$GIST_URL" ]; then
                # URLから末尾のGIST_IDを抽出（32文字hex）
                EXTRACTED_ID=$(echo "$GIST_URL" | grep -oP '[a-f0-9]{32}$')
                if [ -n "$EXTRACTED_ID" ]; then
                    GIST_ID="$EXTRACTED_ID"
                else
                    GIST_ID="$DEFAULT_GIST_ID"
                fi
            else
                GIST_ID="$DEFAULT_GIST_ID"
            fi
        else
            GIST_ID="$DEFAULT_GIST_ID"
        fi
    else
        GIST_ID="$DEFAULT_GIST_ID"
    fi
fi

POLL_INTERVAL=5   # ポーリング間隔（秒）
DEBOUNCE=3        # デバウンス待機（秒）— 家老の連続Edit対策

mkdir -p "$SCRIPT_DIR/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

log "gist_sync started. Watching: $DASHBOARD (GIST_ID=$GIST_ID, project=${CURRENT_PJ:-unknown})"

# gh認証チェック（起動時1回のみ）
if ! gh auth status &>/dev/null 2>&1; then
    log "ERROR: gh not authenticated"
    exit 1
fi
log "gh auth verified OK"

# dashboard.md存在確認
if [ ! -f "$DASHBOARD" ]; then
    log "ERROR: dashboard.md not found at $DASHBOARD"
    exit 1
fi

# ─── Gist同期処理（共通） ───
sync_gist() {
    log "Change detected. Debouncing ${DEBOUNCE}s..."
    sleep "$DEBOUNCE"

    # デバウンス後にmtimeを再取得（デバウンス中の追加更新をキャッチ）
    LAST_MTIME=$(stat -c %Y "$DASHBOARD" 2>/dev/null || echo "0")

    if gh gist edit "$GIST_ID" -f dashboard.md "$DASHBOARD" >> "$LOG" 2>&1; then
        log "Gist updated successfully"
    else
        log "ERROR: Gist update failed (will retry on next change)"
    fi
}

# ─── パス判定: /mnt/ 配下ならWSL2 drvfs（inotify非対応） ───
is_wsl_drvfs() {
    case "$DASHBOARD" in
        /mnt/[a-z]/*) return 0 ;;  # /mnt/c/, /mnt/d/ etc.
        *) return 1 ;;
    esac
}

if is_wsl_drvfs; then
    # ═══ ポーリングモード（WSL2 /mnt/c/ 用） ═══
    log "Mode: polling (WSL2 drvfs detected: $DASHBOARD)"
    log "Poll interval: ${POLL_INTERVAL}s, Debounce: ${DEBOUNCE}s"

    LAST_MTIME=$(stat -c %Y "$DASHBOARD" 2>/dev/null || echo "0")

    while true; do
        sleep "$POLL_INTERVAL"

        CURRENT_MTIME=$(stat -c %Y "$DASHBOARD" 2>/dev/null || echo "0")

        if [ "$CURRENT_MTIME" != "$LAST_MTIME" ]; then
            sync_gist
            # LAST_MTIME is updated inside sync_gist after debounce
        fi
    done
else
    # ═══ inotifywaitモード（Linux FS用 — 高速） ═══
    if ! command -v inotifywait &>/dev/null; then
        log "WARNING: inotifywait not found, falling back to polling mode"
        # Fallback to polling even on Linux FS
        LAST_MTIME=$(stat -c %Y "$DASHBOARD" 2>/dev/null || echo "0")
        while true; do
            sleep "$POLL_INTERVAL"
            CURRENT_MTIME=$(stat -c %Y "$DASHBOARD" 2>/dev/null || echo "0")
            if [ "$CURRENT_MTIME" != "$LAST_MTIME" ]; then
                sync_gist
            fi
        done
    fi

    log "Mode: inotifywait (Linux FS detected: $DASHBOARD)"

    while true; do
        inotifywait -qq -e close_write,moved_to "$DASHBOARD" 2>/dev/null
        sync_gist
    done
fi
