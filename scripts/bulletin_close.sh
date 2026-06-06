#!/usr/bin/env bash
# semantic-links: [[掲示板通信基盤]]
# bulletin_close.sh — 掲示板エントリを明示的に閉じる
# Usage: bash scripts/bulletin_close.sh <entry_id>

set -euo pipefail

SCRIPT_DIR="${BULLETIN_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BULLETIN_FILE="$SCRIPT_DIR/queue/bulletin_board.yaml"
LOCK_FILE="${BULLETIN_FILE}.lock"

if [[ $# -lt 1 ]]; then
    echo "Usage: bash scripts/bulletin_close.sh <entry_id>" >&2
    exit 1
fi

ENTRY_ID="$1"

if [[ ! -f "$BULLETIN_FILE" ]]; then
    echo "ERROR: bulletin file not found: $BULLETIN_FILE" >&2
    exit 1
fi

{
    flock -x 200
    tmp_file="$(mktemp "${BULLETIN_FILE}.XXXXXX")"
    if awk -v entry_id="$ENTRY_ID" '
function trim(value) {
    sub(/^[[:space:]]+/, "", value)
    sub(/[[:space:]]+$/, "", value)
    return value
}
function unquote(value) {
    value = trim(value)
    if (length(value) >= 2 && substr(value, 1, 1) == "'"'"'" && substr(value, length(value), 1) == "'"'"'") {
        value = substr(value, 2, length(value) - 2)
        gsub(/'"'"''"'"'/, "'"'"'", value)
    } else if (length(value) >= 2 && substr(value, 1, 1) == "\"" && substr(value, length(value), 1) == "\"") {
        value = substr(value, 2, length(value) - 2)
        gsub(/\\"/, "\"", value)
        gsub(/\\\\/, "\\", value)
    }
    return value
}
function flush_missing_status() {
    if (in_target && !closed) {
        print "  status: '\''closed'\''"
        closed = 1
    }
}
BEGIN {
    entries_seen = 0
    found = 0
    in_target = 0
    closed = 0
}
/^entries:[[:space:]]*$/ {
    entries_seen = 1
    print
    next
}
/^-[[:space:]]+id:[[:space:]]*/ {
    flush_missing_status()
    raw_id = $0
    sub(/^-[[:space:]]+id:[[:space:]]*/, "", raw_id)
    in_target = (unquote(raw_id) == entry_id)
    if (in_target) found = 1
    print
    next
}
in_target && /^[[:space:]]{2}status:[[:space:]]*/ {
    print "  status: '\''closed'\''"
    closed = 1
    in_target = 0
    next
}
{
    print
}
END {
    flush_missing_status()
    if (!entries_seen) {
        print "ERROR: entries list missing" > "/dev/stderr"
        exit 3
    }
    if (!found) {
        print "ERROR: entry not found: " entry_id > "/dev/stderr"
        exit 4
    }
}
' "$BULLETIN_FILE" > "$tmp_file"; then
        mv "$tmp_file" "$BULLETIN_FILE"
        printf '%s\n' "$ENTRY_ID"
    else
        rm -f "$tmp_file"
        exit 1
    fi
} 200>"$LOCK_FILE"
