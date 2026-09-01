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

# This process is long-lived and may be started from a restart transaction.
# Close only descriptors that actually point at the coordinator lock.
close_inherited_restart_watchers_lock() {
    local lock_path="${RESTART_WATCHERS_LOCK_FILE:-/tmp/restart_watchers.lock}"
    local fd_path fd target
    for fd_path in /proc/$$/fd/*; do
        fd="${fd_path##*/}"
        [[ "$fd" =~ ^[0-9]+$ && "$fd" != 0 && "$fd" != 1 && "$fd" != 2 ]] || continue
        target="$(readlink "$fd_path" 2>/dev/null || true)"
        [[ "$target" == "$lock_path" ]] || continue
        eval "exec ${fd}>&-"
    done
}
close_inherited_restart_watchers_lock

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
    # 2026-09-01 将軍 D0(殿『commit の hang はバグ。真因を掘り根治せよ』): 本 script は dashboard.md を
    # 指定 gist へ同期する常駐 loop。将軍が設計書の gist_id/path を渡して起動し、roadmap gist
    # da1b7617 に dashboard.md が混入した(19:07-19:13、REST PATCH で除去)。呼出し元は --once と
    # 無引数 daemon のみ(cmd_complete_gate/daemon_watchdog)。固定 id は dashboard 系 gist に限定し、
    # それ以外は usage で止める(設計書の gist 同期は scripts/gist_share.sh <path>)。
    if [ -n "$FIXED_GIST_ID" ]; then
        if [ -e "$FIXED_GIST_ID" ] || ! [[ "$FIXED_GIST_ID" =~ ^[0-9a-f]{32}$ ]]; then
            echo "gist_sync: BLOCK: 引数 '$FIXED_GIST_ID' は gist_id(32 hex)ではない。本 script は dashboard.md の常駐同期 daemon。設計書の gist 同期は bash scripts/gist_share.sh <repo-relative-path>" >&2
            exit 2
        fi
        if [ "$FIXED_GIST_ID" != "$DEFAULT_GIST_ID" ] && ! grep -qE "gist_url:.*$FIXED_GIST_ID" "$SCRIPT_DIR/config/projects.yaml" 2>/dev/null && [ "${GIST_SYNC_ALLOW_FIXED_ID:-0}" != "1" ]; then
            echo "gist_sync: BLOCK: $FIXED_GIST_ID は dashboard gist(DEFAULT/config/projects.yaml gist_url)ではない。dashboard.md をこの gist へ書くと設計書 gist を汚染する(2026-09-01 da1b7617 実証)。意図的なら GIST_SYNC_ALLOW_FIXED_ID=1" >&2
            exit 2
        fi
    fi
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
