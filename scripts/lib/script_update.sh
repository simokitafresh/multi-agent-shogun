#!/usr/bin/env bash
# scripts/lib/script_update.sh — Self-restart on script change
# Required caller vars: SCRIPT_PATH, SCRIPT_HASH, STARTUP_TIME, MIN_UPTIME
# Usage: source this file, then call check_script_update [restart_args...]
# If log() is defined in caller, it is used; otherwise falls back to stderr.

check_script_update() {
    local current_hash
    current_hash="$(md5sum "$SCRIPT_PATH" | cut -d' ' -f1)"
    if [ "$current_hash" != "$SCRIPT_HASH" ]; then
        local uptime=$(($(date +%s) - STARTUP_TIME))
        if [ "$uptime" -lt "$MIN_UPTIME" ]; then
            if declare -f log >/dev/null 2>&1; then
                log "RESTART-GUARD: Script changed but uptime too short (${uptime}s < ${MIN_UPTIME}s), skipping"
            else
                echo "[$(date)] [RESTART-GUARD] Script changed but uptime too short (${uptime}s < ${MIN_UPTIME}s), skipping" >&2
            fi
            return 0
        fi
        if declare -f log >/dev/null 2>&1; then
            log "AUTO-RESTART: Script file changed (hash: $SCRIPT_HASH → $current_hash), restarting..."
        else
            echo "[$(date)] [AUTO-RESTART] Script file changed (hash: $SCRIPT_HASH → $current_hash), restarting..." >&2
        fi
        exec "$SCRIPT_PATH" "$@"
    fi
}
