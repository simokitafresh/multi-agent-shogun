#!/bin/bash
# gist_sync.sh — dashboard.md変更検知 → Gist自動アップロード
# Usage: bash scripts/gist_sync.sh [--once | gist_id]
#   --once: 1回sync実行後にexit (0=成功, 1=失敗)
#   gist_id: 固定Gist ID指定（デーモンモード）
#
# WSL2の/mnt/c/ではinotifywaitがdrvfs上で機能しないため、
# statによるmtimeポーリング方式を採用。
# Linux FSパスの場合はinotifywaitを使用（高速・低負荷）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DASHBOARD="$SCRIPT_DIR/dashboard.md"
LOG="$SCRIPT_DIR/logs/gist_sync.log"

# ─── GIST_ID動的解決関数 ───
# sync毎にcurrent_project → gist_url → GIST_IDを再解決する
# 引数指定時は固定値を使用（後方互換）
DEFAULT_GIST_ID="6eb495d917fb00ba4d4333c237a4ee0c"
ONCE_MODE=false
if [ "${1:-}" = "--once" ]; then
    ONCE_MODE=true
    FIXED_GIST_ID=""
else
    FIXED_GIST_ID="${1:-}"  # 引数あれば固定
fi

resolve_gist_id() {
    if [ -n "$FIXED_GIST_ID" ]; then
        GIST_ID="$FIXED_GIST_ID"
        CURRENT_PJ="fixed"
        return
    fi

    PROJECTS_YAML="$SCRIPT_DIR/config/projects.yaml"
    if [ -f "$PROJECTS_YAML" ]; then
        # current_projectと対応gist_urlを1回の読込で解決する。
        # idより後にcurrent_projectが現れる配置にも対応するためURLをid別に保持する。
        local -a _project_meta=()
        mapfile -t _project_meta < <(awk '
            /^current_project:/ { current=$2 }
            /^[[:space:]]*- id:/ { id=$NF }
            /^[[:space:]]*gist_url:/ && id != "" {
                value=$0
                sub(/.*gist_url:[[:space:]]*"?/, "", value)
                sub(/"?[[:space:]]*$/, "", value)
                urls[id]=value
            }
            END { print current; print urls[current] }
        ' "$PROJECTS_YAML")
        CURRENT_PJ="${_project_meta[0]:-}"
        if [ -n "$CURRENT_PJ" ]; then
            GIST_URL="${_project_meta[1]:-}"
            if [ -n "$GIST_URL" ]; then
                # URLから末尾のGIST_IDを抽出（32文字hex）
                EXTRACTED_ID="${GIST_URL##*/}"
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
            CURRENT_PJ="unknown"
        fi
    else
        GIST_ID="$DEFAULT_GIST_ID"
        CURRENT_PJ="unknown"
    fi
}

# 起動時に初回解決
resolve_gist_id

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

# ─── Gist同期コア（1回実行） ───
# Returns: 0=sync成功, 1=sync失敗
do_sync() {
    [ "$ONCE_MODE" != true ] && resolve_gist_id
    log "Syncing to project=${CURRENT_PJ} GIST_ID=${GIST_ID}"

    UPLOAD_FILE="$DASHBOARD"
    local tmpfile=""
    if [ "$CURRENT_PJ" != "fixed" ] && [ "$CURRENT_PJ" != "unknown" ]; then
        tmpfile=$(mktemp)
        sed "1s/# 🏯 Dashboard \[.*\]/# 🏯 Dashboard [${CURRENT_PJ}]/; t; 1s/# 🏯 Dashboard/# 🏯 Dashboard [${CURRENT_PJ}]/" "$DASHBOARD" > "$tmpfile"
        UPLOAD_FILE="$tmpfile"
    fi

    local rc=0
    # Use gh api instead of gh gist edit — edit misdetects UTF-8 with emoji as binary
    local payload_file
    payload_file=$(mktemp)
    jq -n --rawfile content "$UPLOAD_FILE" \
        '{"files":{"dashboard.md":{"content":$content}}}' > "$payload_file" 2>/dev/null
    if gh api --method PATCH "gists/${GIST_ID}" --input "$payload_file" > /dev/null 2>&1; then
        log "Gist updated successfully (project=${CURRENT_PJ})"
    else
        log "ERROR: Gist update failed (project=${CURRENT_PJ})"
        rc=1
    fi
    rm -f "$payload_file"

    [ -n "$tmpfile" ] && rm -f "$tmpfile"
    return $rc
}

# ─── デバウンス付きsync（デーモンモード用） ───
sync_gist() {
    log "Change detected. Debouncing ${DEBOUNCE}s..."
    sleep "$DEBOUNCE"
    LAST_MTIME=$(stat -c %Y "$DASHBOARD" 2>/dev/null || echo "0")
    do_sync
}

# ─── --onceモード: 1回sync→即終了 ───
if [ "$ONCE_MODE" = true ]; then
    log "Once mode: executing single sync"
    do_sync
    rc=$?
    log "Once mode: finished (rc=$rc)"
    exit $rc
fi

# ─── パス判定: /mnt/ 配下ならWSL2 drvfs（inotify非対応） ───
is_wsl_drvfs() {
    case "$DASHBOARD" in
        /mnt/[a-z]/*) return 0 ;;  # /mnt/c/, /mnt/d/ etc.
        *) return 1 ;;
    esac
}

# ─── ポーリングループ（WSL2 drvfs + inotifywait未検出時の共通処理） ───
poll_loop() {
    LAST_MTIME=$(stat -c %Y "$DASHBOARD" 2>/dev/null || echo "0")
    while true; do
        sleep "$POLL_INTERVAL"
        CURRENT_MTIME=$(stat -c %Y "$DASHBOARD" 2>/dev/null || echo "0")
        if [ "$CURRENT_MTIME" != "$LAST_MTIME" ]; then
            sync_gist
            # LAST_MTIME is updated inside sync_gist after debounce
        fi
    done
}

if is_wsl_drvfs; then
    # ═══ ポーリングモード（WSL2 /mnt/c/ 用） ═══
    log "Mode: polling (WSL2 drvfs detected: $DASHBOARD)"
    log "Poll interval: ${POLL_INTERVAL}s, Debounce: ${DEBOUNCE}s"
    poll_loop
else
    # ═══ inotifywaitモード（Linux FS用 — 高速） ═══
    if ! command -v inotifywait &>/dev/null; then
        log "WARNING: inotifywait not found, falling back to polling mode"
        poll_loop
    fi

    log "Mode: inotifywait (Linux FS detected: $DASHBOARD)"

    while true; do
        inotifywait -qq -e close_write,moved_to "$DASHBOARD" 2>/dev/null
        sync_gist
    done
fi
