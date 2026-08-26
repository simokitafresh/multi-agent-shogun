#!/usr/bin/env bash
# scripts/lib/script_update.sh — Self-restart on script/dependency change
# Required caller vars: SCRIPT_PATH, SCRIPT_HASH, STARTUP_TIME, MIN_UPTIME
# Optional caller vars: WATCHED_DEPS (array of sourced file paths), DEPS_HASH
# Usage: source this file, then call check_script_update [restart_args...]
# If log() is defined in caller, it is used; otherwise falls back to stderr.

# Compute combined mtime of WATCHED_DEPS files.
# Caller must define WATCHED_DEPS array before calling.
# Uses stat mtime instead of md5sum: same change-detection, ~3x faster.
compute_deps_hash() {
    if [ "${WATCHED_DEPS+x}" != x ] || [ ${#WATCHED_DEPS[@]} -eq 0 ]; then
        echo ""
        return
    fi
    stat --printf='%Y:' "${WATCHED_DEPS[@]}" 2>/dev/null
}

check_script_update() {
    local current_hash restart_reason=""
    current_hash="$(stat --printf='%Y' "$SCRIPT_PATH" 2>/dev/null)"
    if [ "$current_hash" != "$SCRIPT_HASH" ]; then
        restart_reason="script"
    fi

    # Check sourced dependencies
    if [ -n "${DEPS_HASH:-}" ] && [ "${WATCHED_DEPS+x}" = x ] && [ ${#WATCHED_DEPS[@]} -gt 0 ]; then
        local current_deps_hash
        current_deps_hash="$(compute_deps_hash)"
        if [ "$current_deps_hash" != "$DEPS_HASH" ]; then
            restart_reason="${restart_reason:+$restart_reason+}deps"
        fi
    fi

    if [ -n "$restart_reason" ]; then
        local uptime=$(($(date +%s) - STARTUP_TIME))
        if [ "$uptime" -lt "$MIN_UPTIME" ]; then
            if declare -f log >/dev/null 2>&1; then
                log "RESTART-GUARD: Change detected ($restart_reason) but uptime too short (${uptime}s < ${MIN_UPTIME}s), skipping"
            else
                echo "[$(date)] [RESTART-GUARD] Change detected ($restart_reason) but uptime too short (${uptime}s < ${MIN_UPTIME}s), skipping" >&2
            fi
            return 0
        fi
        local detail="script:$SCRIPT_HASH→$current_hash"
        [ -n "${current_deps_hash:-}" ] && detail="$detail deps:${DEPS_HASH:-?}→$current_deps_hash"
        if declare -f log >/dev/null 2>&1; then
            log "AUTO-RESTART: Change detected ($restart_reason) [$detail], restarting..."
        else
            echo "[$(date)] [AUTO-RESTART] Change detected ($restart_reason) [$detail], restarting..." >&2
        fi
        # Release singleton flock before exec so the new process can acquire it.
        # Callers can set SCRIPT_UPDATE_SINGLETON_FD when their lock fd is not 9.
        local singleton_fd="${SCRIPT_UPDATE_SINGLETON_FD:-9}"
        if [[ "$singleton_fd" =~ ^[0-9]+$ ]]; then
            eval "exec ${singleton_fd}>&-" 2>/dev/null || true
        fi
        # 実行ビット欠落(2026-08-26 restore/convergeで8本が100644化→全inbox_watcherが毎分死亡)でも
        # 自己修復して再起動できるよう、非実行なら bash 経由で exec する。
        if [[ -x "$SCRIPT_PATH" ]]; then
            exec "$SCRIPT_PATH" "$@"
        else
            echo "[$(date)] [AUTO-RESTART] $SCRIPT_PATH is not executable; exec via bash (fix: chmod +x)" >&2
            exec bash "$SCRIPT_PATH" "$@"
        fi
    fi
}
