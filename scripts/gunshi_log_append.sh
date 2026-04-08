#!/usr/bin/env bash
# gunshi_log_append.sh — レビューログ末尾追記 + 自動アーカイブ
# Usage: bash scripts/gunshi_log_append.sh <<'ENTRY'
# - cmd_id: cmd_1234
#   review_type: report
#   ...
# ENTRY
#
# 追記後に行数チェック → 2500行超で古いエントリを自動アーカイブ

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/gunshi_review_log.yaml"
ARCHIVE_DIR="$SCRIPT_DIR/logs/archive"
MAX_LINES=2500

if [ ! -f "$LOG_FILE" ]; then
    echo "ERROR: $LOG_FILE not found" >&2
    exit 1
fi

# Read entry from stdin
ENTRY=$(cat)

if [ -z "$ENTRY" ]; then
    echo "ERROR: empty entry" >&2
    exit 1
fi

# Append to log file (flock for safety)
(
    flock -w 5 200 || { echo "ERROR: flock timeout" >&2; exit 1; }
    echo "$ENTRY" >> "$LOG_FILE"
) 200>"$LOG_FILE.lock"

echo "OK: appended to $LOG_FILE"

# --- Auto-archive check ---
TOTAL_LINES=$(wc -l < "$LOG_FILE")
if [ "$TOTAL_LINES" -le "$MAX_LINES" ]; then
    exit 0
fi

echo "ARCHIVE: $TOTAL_LINES lines > $MAX_LINES threshold"

# Find header end (line before first "- cmd_id:")
HEADER_END=$(grep -n '^- cmd_id:' "$LOG_FILE" | head -1 | cut -d: -f1 || true)
if [ -z "$HEADER_END" ]; then
    echo "WARN: no entries found, skipping archive" >&2
    exit 0
fi
HEADER_END=$((HEADER_END - 1))

# Find midpoint of entries to split
FIRST_ENTRY=$((HEADER_END + 1))
ENTRY_LINES=$((TOTAL_LINES - HEADER_END))
HALF=$((ENTRY_LINES / 2))
SPLIT_LINE=$((FIRST_ENTRY + HALF))

# Find nearest "- cmd_id:" boundary at or after split point
SPLIT_BOUNDARY=$(awk -v start="$SPLIT_LINE" 'NR >= start && /^- cmd_id:/ { print NR; exit }' "$LOG_FILE")
if [ -z "$SPLIT_BOUNDARY" ]; then
    echo "WARN: no clean split boundary found, skipping archive" >&2
    exit 0
fi

# Extract cmd range for archive filename (Vercel: 探す側の言葉で命名)
FIRST_CMD=$(sed -n "${FIRST_ENTRY}p" "$LOG_FILE" | grep -oP 'cmd_id:\s*\K\S+' || true)
LAST_ENTRY_LINE=$((SPLIT_BOUNDARY - 1))
# Walk backward to find the last "- cmd_id:" before split boundary
LAST_CMD=$(awk -v end="$LAST_ENTRY_LINE" 'NR <= end && /^- cmd_id:/ { last=$0 } END { print last }' "$LOG_FILE" | grep -oP 'cmd_id:\s*\K\S+' || true)
ARCHIVE_NAME="${FIRST_CMD:-unknown}_to_${LAST_CMD:-$(date +%Y%m%d)}"
ARCHIVE_FILE="$ARCHIVE_DIR/gunshi_review_log_${ARCHIVE_NAME}.yaml"

mkdir -p "$ARCHIVE_DIR"

# Archive old entries
sed -n "${FIRST_ENTRY},$((SPLIT_BOUNDARY - 1))p" "$LOG_FILE" > "$ARCHIVE_FILE"
ARCHIVED_LINES=$(wc -l < "$ARCHIVE_FILE")

# Rebuild main file: header + remaining entries
TEMP_FILE=$(mktemp)
{ sed -n "1,${HEADER_END}p" "$LOG_FILE"; sed -n "${SPLIT_BOUNDARY},\$p" "$LOG_FILE"; } > "$TEMP_FILE"

# Add archive reference to header (after last archive reference line)
LAST_ARCHIVE_LINE=$(grep -n '# 詳細エントリ:' "$TEMP_FILE" | tail -1 | cut -d: -f1 || true)
if [ -n "$LAST_ARCHIVE_LINE" ]; then
    sed -i "${LAST_ARCHIVE_LINE}a\\# 詳細エントリ: ${ARCHIVE_NAME} → logs/archive/gunshi_review_log_${ARCHIVE_NAME}.yaml" "$TEMP_FILE"
fi

cp "$TEMP_FILE" "$LOG_FILE"
rm -f "$TEMP_FILE"

NEW_LINES=$(wc -l < "$LOG_FILE")
echo "ARCHIVE: done. ${ARCHIVED_LINES} lines → ${ARCHIVE_FILE##*/}. Main: ${TOTAL_LINES} → ${NEW_LINES} lines"
