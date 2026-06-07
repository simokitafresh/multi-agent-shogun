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

# perf: wc subshell → awk END (same cost, cleaner)
TOTAL_LINES=$(awk 'END{print NR}' "$FILE")
if [ "$TOTAL_LINES" -le "$MAX_LINES" ]; then
    exit 0
fi

echo "ROTATE: $FILE — $TOTAL_LINES lines > $MAX_LINES threshold"

# perf: head -1 subshell → bash builtin read (no fork)
IFS= read -r FIRST_LINE < "$FILE"
WRAPPER_LINE=0
# perf: echo|grep -qE pipe (2 forks) → bash regex (0 forks)
if [[ "$FIRST_LINE" =~ ^[a-z_]+:$ ]]; then
    WRAPPER_LINE=1
fi

if [ -z "$ENTRY_PATTERN" ]; then
    # perf: sed -n '2p' subshell → double read builtin (no fork)
    { IFS= read -r _skip_line; IFS= read -r SECOND_LINE; } < "$FILE"
    # perf: echo|grep -qE pipe (2 forks) → bash regex (0 forks)
    if [[ "$SECOND_LINE" =~ ^'  - ' ]]; then
        ENTRY_PATTERN='^  - '
    else
        ENTRY_PATTERN='^- '
    fi
fi

# perf: mktemp subshell → fixed tmp path (no fork)
ENTRY_LINES_FILE="/tmp/ylr_$$_entries"
TEMP_FILE="/tmp/ylr_$$_main"
trap 'rm -f "$ENTRY_LINES_FILE" "$TEMP_FILE"' EXIT

# perf: grep -n + cut pipe (2 procs) → awk 1-pass (1 proc)
awk -v pat="$ENTRY_PATTERN" '$0 ~ pat {print NR}' "$FILE" > "$ENTRY_LINES_FILE"
ENTRY_COUNT=$(awk 'END{print NR}' "$ENTRY_LINES_FILE")

if [ "$ENTRY_COUNT" -le 1 ]; then
    echo "WARN: only $ENTRY_COUNT entries, skipping" >&2
    exit 0
fi

HALF_ENTRIES=$((ENTRY_COUNT / 2))
# perf: head -1 + sed -n "Np" (2 subshells) → awk 1-pass (1 subshell)
read -r FIRST_ENTRY KEEP_START < <(awk -v n="$((HALF_ENTRIES + 1))" \
    'NR==1{f=$0} NR==n{k=$0} END{print f, k}' "$ENTRY_LINES_FILE")

if [ -z "$FIRST_ENTRY" ] || [ -z "$KEEP_START" ]; then
    echo "WARN: could not determine split boundary" >&2
    exit 0
fi

# perf: dirname/basename subshells → bash string ops (no forks)
FILE_DIR="${FILE%/*}"; [[ "$FILE_DIR" == "$FILE" ]] && FILE_DIR="."
BASENAME="${FILE##*/}"; BASENAME="${BASENAME%.yaml}"
ARCHIVE_DIR="$FILE_DIR/archive"
mkdir -p "$ARCHIVE_DIR"

# perf: date subshell → printf builtin (no fork)
printf -v _ts '%(%Y%m%d_%H%M)T' -1
ARCHIVE_FILE="$ARCHIVE_DIR/${BASENAME}_${_ts}.yaml"

# Archive older half
sed -n "${FIRST_ENTRY},$((KEEP_START - 1))p" "$FILE" > "$ARCHIVE_FILE"
# perf: wc -l subshell → awk END
ARCHIVED_LINES=$(awk 'END{print NR}' "$ARCHIVE_FILE")

# Rebuild main file
if [ "$WRAPPER_LINE" -eq 1 ]; then
    head -n "$((FIRST_ENTRY - 1))" "$FILE" > "$TEMP_FILE"
    sed -n "${KEEP_START},\$p" "$FILE" >> "$TEMP_FILE"
else
    sed -n "${KEEP_START},\$p" "$FILE" > "$TEMP_FILE"
fi

cp "$TEMP_FILE" "$FILE"

# perf: wc -l subshell → awk END
NEW_LINES=$(awk 'END{print NR}' "$FILE")
echo "ROTATE: done. ${ARCHIVED_LINES} lines → ${ARCHIVE_FILE##*/}. Main: ${TOTAL_LINES} → ${NEW_LINES} lines"
