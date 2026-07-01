#!/bin/bash
# lesson_update_score.sh — lessons.yaml のスコアフィールドを更新（排他ロック付き）
# Usage: bash scripts/lesson_update_score.sh <project> <lesson_id> helpful|harmful
# Example: bash scripts/lesson_update_score.sh infra L035 helpful

set -e

_lus_self="${BASH_SOURCE[0]}"; [[ "$_lus_self" != /* ]] && _lus_self="$PWD/$_lus_self"
SCRIPT_DIR="${_lus_self%/scripts/lesson_update_score.sh}"
PROJECT_ID="${1:-}"
LESSON_ID="${2:-}"
SCORE_TYPE="${3:-}"

# Validate arguments
if [ -z "$PROJECT_ID" ] || [ -z "$LESSON_ID" ] || [ -z "$SCORE_TYPE" ]; then
    echo "Usage: lesson_update_score.sh <project> <lesson_id> helpful|harmful" >&2
    exit 1
fi

if [ "$SCORE_TYPE" != "helpful" ] && [ "$SCORE_TYPE" != "harmful" ] && [ "$SCORE_TYPE" != "inject" ]; then
    echo "ERROR: score_type must be 'helpful', 'harmful', or 'inject' (got: $SCORE_TYPE)" >&2
    exit 1
fi

# Vercel化済みPJはlessons_archive.yaml(詳細層)に書込み、索引(lessons.yaml)を触らない
ARCHIVE_FILE="$SCRIPT_DIR/projects/${PROJECT_ID}/lessons_archive.yaml"
FALLBACK_FILE="$SCRIPT_DIR/projects/${PROJECT_ID}/lessons.yaml"

if [ -f "$ARCHIVE_FILE" ]; then
    CACHE_FILE="$ARCHIVE_FILE"
else
    CACHE_FILE="$FALLBACK_FILE"
fi
LOCKFILE="${CACHE_FILE}.lock"

if [ ! -f "$CACHE_FILE" ]; then
    echo "ERROR: $CACHE_FILE not found." >&2
    exit 1
fi

# Atomic update with flock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 10 200 || exit 1

        field="${SCORE_TYPE}_count"
        if [ "$SCORE_TYPE" = "inject" ]; then
            field="injection_count"
        fi
        ts="$(date '+%Y-%m-%dT%H:%M:%S')"
        tmp_file="$(mktemp "${CACHE_FILE}.XXXXXX.tmp")"
        meta_file="$(mktemp "${CACHE_FILE}.XXXXXX.meta")"

        if awk -v lesson_id="$LESSON_ID" -v field="$field" -v ts="$ts" -v meta_file="$meta_file" '
function flush_missing() {
    if (in_block && !field_done) {
        print "  " field ": 1"
        count_val = 1
        field_done = 1
    }
    if (in_block && !ts_done) {
        print "  last_referenced: " q ts q
        ts_done = 1
    }
}
BEGIN {
    target_start = "- id: " lesson_id
    field_prefix = "  " field ":"
    ts_prefix = "  last_referenced:"
    q = sprintf("%c", 39)
}
{
    s = $0
    sub(/\r$/, "", s)

    if (s == target_start) {
        in_block = 1
        found = 1
        field_done = 0
        ts_done = 0
        print
        next
    }

    if (in_block) {
        if (s ~ /^- id:/ || (s != "" && s !~ /^[ \t#]/)) {
            flush_missing()
            in_block = 0
            print
            next
        }

        if (!field_done && index(s, field_prefix) == 1) {
            rest = substr(s, length(field_prefix) + 1)
            if (match(rest, /^[[:space:]]*[0-9]+/)) {
                num_text = substr(rest, RSTART, RLENGTH)
                gsub(/[[:space:]]/, "", num_text)
                count_val = num_text + 1
                print field_prefix " " count_val
                field_done = 1
                next
            }
        }

        if (!ts_done && index(s, ts_prefix) == 1) {
            print ts_prefix " " q ts q
            ts_done = 1
            next
        }
    }

    print
}
END {
    if (in_block) {
        flush_missing()
    }
    if (!found) {
        print "ERROR: " lesson_id " not found in " FILENAME > "/dev/stderr"
        exit 1
    }
    print lesson_id " " field " → " count_val > meta_file
}
' "$CACHE_FILE" > "$tmp_file"; then
            mv "$tmp_file" "$CACHE_FILE"
            cat "$meta_file"
            rm -f "$meta_file"
        else
            rm -f "$tmp_file" "$meta_file"
            exit 1
        fi

    ) 200>"$LOCKFILE"; then
        exit 0
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[lesson_update_score] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[lesson_update_score] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
