#!/usr/bin/env bash
# CDP Chrome Cleanup — Kill all residual Chrome processes tracked by PID files
# Standalone script callable from ninja_monitor.sh or cron
# Location: /mnt/c/tools/multi-agent-shogun/scripts/cdp_chrome_cleanup.sh
set -euo pipefail

PID_DIR="/tmp"
PID_PREFIX="cdp_chrome_"
LOG_PREFIX="[cdp_cleanup]"

log() {
    echo "${LOG_PREFIX} $(date '+%Y-%m-%d %H:%M:%S') $*"
}

log_err() {
    echo "${LOG_PREFIX} $(date '+%Y-%m-%d %H:%M:%S') ERROR: $*" >&2
}

cleanup_all() {
    local pid_files
    pid_files=("${PID_DIR}/${PID_PREFIX}"*.pid)

    # Check if glob matched anything
    if [[ ! -f "${pid_files[0]:-}" ]]; then
        log "No PID files found. Nothing to clean."
        return 0
    fi

    local total=0
    local killed=0
    local failed=0

    for pid_file in "${pid_files[@]}"; do
        total=$((total + 1))
        local basename
        basename="$(basename "$pid_file")"
        local port_str="${basename#${PID_PREFIX}}"
        port_str="${port_str%.pid}"

        if [[ ! "$port_str" =~ ^[0-9]+$ ]]; then
            log_err "Malformed PID file: ${pid_file} — skipping"
            failed=$((failed + 1))
            continue
        fi

        local pid
        pid="$(cat "$pid_file" 2>/dev/null || echo "")"

        if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
            log_err "Invalid PID in ${pid_file}: '${pid}' — removing file"
            rm -f "$pid_file"
            failed=$((failed + 1))
            continue
        fi

        log "Killing Chrome PID ${pid} (port ${port_str})..."
        if powershell.exe -NoProfile -Command "Stop-Process -Id ${pid} -Force -ErrorAction SilentlyContinue" 2>/dev/null; then
            log "PID ${pid} killed successfully"
            killed=$((killed + 1))
        else
            log "PID ${pid} — process may already be gone"
            killed=$((killed + 1))
        fi

        rm -f "$pid_file"
        log "PID file removed: ${pid_file}"
    done

    log "Summary: ${killed}/${total} cleaned, ${failed} failed"
    return 0
}

# --- Main ---
log "Starting CDP Chrome cleanup scan..."
cleanup_all
log "Done."
