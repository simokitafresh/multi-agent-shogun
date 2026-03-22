#!/usr/bin/env bash
# scripts/lib/script_update.sh — Self-restart on script/dependency change
# Required caller vars: SCRIPT_PATH, SCRIPT_HASH, STARTUP_TIME, MIN_UPTIME
# Optional caller vars: WATCHED_DEPS (array of sourced file paths), DEPS_HASH
# Usage: source this file, then call check_script_update [restart_args...]
# If log() is defined in caller, it is used; otherwise falls back to stderr.

# Compute combined hash of WATCHED_DEPS files.
# Caller must define WATCHED_DEPS array before calling.
compute_deps_hash() {
    if ! declare -p WATCHED_DEPS &>/dev/null || [ ${#WATCHED_DEPS[@]} -eq 0 ]; then
        echo ""
        return
    fi
    md5sum "${WATCHED_DEPS[@]}" 2>/dev/null | md5sum | cut -d' ' -f1
}

check_script_update() {
    local current_hash restart_reason=""
    current_hash="$(md5sum "$SCRIPT_PATH" | cut -d' ' -f1)"
    if [ "$current_hash" != "$SCRIPT_HASH" ]; then
        restart_reason="script"
    fi

    # Check sourced dependencies
    if [ -n "${DEPS_HASH:-}" ] && declare -p WATCHED_DEPS &>/dev/null && [ ${#WATCHED_DEPS[@]} -gt 0 ]; then
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
        exec "$SCRIPT_PATH" "$@"
    fi
}
