#!/usr/bin/env bash
# ============================================================
# Log Rotation Script
# ============================================================
# Rotates log files exceeding size limit with generation management.
# Usage: bash scripts/log_rotate.sh [--dry-run]
#
# Config: MAX_SIZE_MB=10, MAX_GENERATIONS=5
# Targets: All .log files in logs/ directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS_DIR="$SCRIPT_DIR/logs"

MAX_SIZE_BYTES=$((10 * 1024 * 1024))  # 10MB
MAX_GENERATIONS=5
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

rotate_log() {
    local logfile="$1"
    local basename="${logfile##*/}"

    # Remove oldest generation if it exists (.gz compressed)
    local oldest="${logfile}.${MAX_GENERATIONS}.gz"
    if [[ -f "$oldest" ]]; then
        if $DRY_RUN; then
            echo "[DRY-RUN] rm $oldest"
        else
            rm -f "$oldest"
        fi
    fi

    # Shift existing generations (compressed .gz files)
    local i=$((MAX_GENERATIONS - 1))
    while [[ $i -ge 1 ]]; do
        local src="${logfile}.${i}.gz"
        local dst="${logfile}.$((i + 1)).gz"
        if [[ -f "$src" ]]; then
            if $DRY_RUN; then
                echo "[DRY-RUN] mv $src -> $dst"
            else
                mv "$src" "$dst"
            fi
        fi
        i=$((i - 1))
    done

    # Rotate current log to .1 and compress
    if $DRY_RUN; then
        echo "[DRY-RUN] mv $logfile -> ${logfile}.1"
        echo "[DRY-RUN] gzip ${logfile}.1 -> ${logfile}.1.gz"
        echo "[DRY-RUN] touch $logfile"
    else
        mv "$logfile" "${logfile}.1"
        gzip "${logfile}.1"
        touch "$logfile"
    fi

    echo "[log_rotate] Rotated and compressed: $basename"
}

ROTATED=0

# Use find -printf to get size+path in one pass, avoiding per-file stat subprocesses
while IFS=' ' read -r size logfile; do
    if [[ $size -gt $MAX_SIZE_BYTES ]]; then
        size_mb_int=$(( size / 1048576 ))
        size_mb_frac=$(( (size * 10 / 1048576) % 10 ))
        echo "[log_rotate] ${logfile##*/}: ${size_mb_int}.${size_mb_frac}MB > 10MB threshold"
        rotate_log "$logfile"
        ROTATED=$((ROTATED + 1))
    fi
done < <(find "$LOGS_DIR" -maxdepth 1 -name "*.log" -printf "%s %p\n" 2>/dev/null)

if [[ $ROTATED -eq 0 ]]; then
    echo "[log_rotate] No logs exceeded 10MB threshold"
else
    echo "[log_rotate] Rotated $ROTATED log(s)"
fi
