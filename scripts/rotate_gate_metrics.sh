#!/usr/bin/env bash
# ============================================================
# gate_metrics.log Line-Based Rotation
# ============================================================
# Usage: bash scripts/rotate_gate_metrics.sh
#   Called after each gate_metrics.log write in cmd_complete_gate.sh.
#   If line count exceeds MAX_LINES, keeps the last KEEP_LINES
#   and moves older entries to logs/archive/gate_metrics_YYYYMMDD.log.
#
# Config: MAX_LINES=1000, KEEP_LINES=500

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_METRICS_LOG="$SCRIPT_DIR/logs/gate_metrics.log"
ARCHIVE_DIR="$SCRIPT_DIR/logs/archive"

MAX_LINES=1000
KEEP_LINES=500

# Early exit if file doesn't exist
[[ -f "$GATE_METRICS_LOG" ]] || exit 0

line_count=$(wc -l < "$GATE_METRICS_LOG")

if [[ "$line_count" -le "$MAX_LINES" ]]; then
    exit 0
fi

mkdir -p "$ARCHIVE_DIR"

# Calculate how many lines to archive
archive_lines=$((line_count - KEEP_LINES))

# Archive old entries (append to today's archive file)
archive_file="$ARCHIVE_DIR/gate_metrics_$(date +%Y%m%d).log"
head -n "$archive_lines" "$GATE_METRICS_LOG" >> "$archive_file"

# Keep only the last KEEP_LINES
tail -n "$KEEP_LINES" "$GATE_METRICS_LOG" > "${GATE_METRICS_LOG}.tmp"
mv "${GATE_METRICS_LOG}.tmp" "$GATE_METRICS_LOG"

echo "[rotate_gate_metrics] Archived ${archive_lines} lines -> $(basename "$archive_file"), kept ${KEEP_LINES} lines"
