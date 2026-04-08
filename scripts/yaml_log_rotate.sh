#!/usr/bin/env bash
# yaml_log_rotate.sh — 汎用YAML追記ログの自動アーカイブ
# Usage: bash scripts/yaml_log_rotate.sh <file> [max_lines] [entry_pattern]
#
# 追記型YAMLファイルが肥大化したら古いエントリをarchive/に退避。
# 対象: logs/*.yaml, queue/*.yaml の追記型ファイル全般。
# entry_pattern: エントリ境界のgrep正規表現。省略時は自動検出。

set -eu

FILE="${1:?Usage: yaml_log_rotate.sh <file> [max_lines] [entry_pattern]}"
MAX_LINES="${2:-2000}"
ENTRY_PATTERN="${3:-}"

if [ ! -f "$FILE" ]; then
    echo "ERROR: $FILE not found" >&2
    exit 1
fi

TOTAL_LINES=$(wc -l < "$FILE")
if [ "$TOTAL_LINES" -le "$MAX_LINES" ]; then
    exit 0
fi

echo "ROTATE: $FILE — $TOTAL_LINES lines > $MAX_LINES threshold"

# Auto-detect entry pattern and wrapper
FIRST_LINE=$(head -1 "$FILE")
WRAPPER_LINE=0
if echo "$FIRST_LINE" | grep -qE '^[a-z_]+:$'; then
    WRAPPER_LINE=1
fi

if [ -z "$ENTRY_PATTERN" ]; then
    # Check actual indentation of entries (line 2)
    SECOND_LINE=$(sed -n '2p' "$FILE")
    if echo "$SECOND_LINE" | grep -qE '^  - '; then
        ENTRY_PATTERN='^  - '
    else
        ENTRY_PATTERN='^- '
    fi
fi

# Collect all entry line numbers into a temp file (avoids SIGPIPE)
ENTRY_LINES_FILE=$(mktemp)
grep -n "$ENTRY_PATTERN" "$FILE" | cut -d: -f1 > "$ENTRY_LINES_FILE"
ENTRY_COUNT=$(wc -l < "$ENTRY_LINES_FILE")

if [ "$ENTRY_COUNT" -le 1 ]; then
    echo "WARN: only $ENTRY_COUNT entries, skipping" >&2
    rm -f "$ENTRY_LINES_FILE"
    exit 0
fi

FIRST_ENTRY=$(head -1 "$ENTRY_LINES_FILE")
HALF_ENTRIES=$((ENTRY_COUNT / 2))
KEEP_START=$(sed -n "$((HALF_ENTRIES + 1))p" "$ENTRY_LINES_FILE")
rm -f "$ENTRY_LINES_FILE"

if [ -z "$FIRST_ENTRY" ] || [ -z "$KEEP_START" ]; then
    echo "WARN: could not determine split boundary" >&2
    exit 0
fi

# Determine archive directory
FILE_DIR=$(dirname "$FILE")
ARCHIVE_DIR="$FILE_DIR/archive"
mkdir -p "$ARCHIVE_DIR"

BASENAME=$(basename "$FILE" .yaml)
ARCHIVE_FILE="$ARCHIVE_DIR/${BASENAME}_$(date +%Y%m%d_%H%M).yaml"

# Archive older half
sed -n "${FIRST_ENTRY},$((KEEP_START - 1))p" "$FILE" > "$ARCHIVE_FILE"
ARCHIVED_LINES=$(wc -l < "$ARCHIVE_FILE")

# Rebuild main file
TEMP_FILE=$(mktemp)
if [ "$WRAPPER_LINE" -eq 1 ]; then
    head -n "$((FIRST_ENTRY - 1))" "$FILE" > "$TEMP_FILE"
    sed -n "${KEEP_START},\$p" "$FILE" >> "$TEMP_FILE"
else
    sed -n "${KEEP_START},\$p" "$FILE" > "$TEMP_FILE"
fi

cp "$TEMP_FILE" "$FILE"
rm -f "$TEMP_FILE"

NEW_LINES=$(wc -l < "$FILE")
echo "ROTATE: done. ${ARCHIVED_LINES} lines → ${ARCHIVE_FILE##*/}. Main: ${TOTAL_LINES} → ${NEW_LINES} lines"
