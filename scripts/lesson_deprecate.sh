#!/bin/bash
# semantic-links: [[教訓ライフサイクル管理]]
# lesson_deprecate.sh - Mark a lesson as deprecated in projects/<project>/lessons.yaml
# Usage: bash scripts/lesson_deprecate.sh <project> <lesson_id> "<reason>" [cmd_id]
# Example: bash scripts/lesson_deprecate.sh infra L044 "Injected 12x, referenced 0x" cmd_414

set -euo pipefail

SCRIPT_DIR="${LESSON_DEPRECATE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT="${1:-}"
LESSON_ID="${2:-}"
REASON="${3:-}"
CMD_ID="${4:-}"

if [ -z "$PROJECT" ] || [ -z "$LESSON_ID" ] || [ -z "$REASON" ]; then
    echo "Usage: bash scripts/lesson_deprecate.sh <project> <lesson_id> \"<reason>\" [cmd_id]" >&2
    exit 1
fi

LESSONS_FILE="$SCRIPT_DIR/projects/${PROJECT}/lessons.yaml"
LOCKFILE="${LESSONS_FILE}.lock"

if [ ! -f "$LESSONS_FILE" ]; then
    echo "ERROR: project '${PROJECT}' not found or lessons file missing: $LESSONS_FILE" >&2
    exit 1
fi

TIMESTAMP=$(date -Iseconds)

attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 10 200 || exit 1

        TMP=$(mktemp --tmpdir="$(dirname "$LESSONS_FILE")" .lesson_dep_XXXXXX.tmp)

        # awk-based: yaml.dump/safe_load不要。ターゲット教訓ブロックのみ編集し他は無変更パス
        # deprecated_*フィールドが既存でも正しく更新する
        if LESSON_ID="$LESSON_ID" REASON="$REASON" CMD_ID="$CMD_ID" TIMESTAMP="$TIMESTAMP" \
           awk '
           function sq(s,    q) {
               q = sprintf("%c", 39)
               gsub(q, q q, s)
               return q s q
           }
           function flush_block(    i) {
               for (i = 0; i < block_n; i++) print block[i]
               print "  deprecated: true"
               print "  deprecated_at: " sq(ts)
               print "  deprecated_reason: " sq(reason)
               if (cmd_id != "") print "  deprecated_by: " sq(cmd_id)
               block_n = 0; in_skip = 0
           }
           BEGIN {
               lid = ENVIRON["LESSON_ID"]
               reason = ENVIRON["REASON"]
               cmd_id = ENVIRON["CMD_ID"]
               ts = ENVIRON["TIMESTAMP"]
               found = 0; in_target = 0; in_skip = 0; block_n = 0
           }
           /^- id:[[:space:]]/ {
               if (in_target) { flush_block(); in_target = 0 }
               if ($0 ~ ("^- id:[[:space:]]+" lid "[[:space:]]*$")) {
                   in_target = 1; found = 1; block[block_n++] = $0; next
               }
               print; next
           }
           in_target {
               if (/^  deprecated(_at|_reason|_by)?:[[:space:]]/) {
                   in_skip = ($0 ~ /:[[:space:]]*(\|-|>)/)
                   next
               }
               if (in_skip && /^    /) { next }
               in_skip = 0
               block[block_n++] = $0; next
           }
           { print }
           END {
               if (in_target) flush_block()
               if (!found) {
                   printf "ERROR: lesson_id '"'"'%s'"'"' not found\n", lid > "/dev/stderr"
                   exit 1
               }
           }
           ' "$LESSONS_FILE" > "$TMP"; then
            mv "$TMP" "$LESSONS_FILE"
            echo "DEPRECATED: ${PROJECT}/${LESSON_ID} — ${REASON}"
        else
            rm -f "$TMP"
            exit 1
        fi
    ) 200>"$LOCKFILE"; then
        exit 0
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[lesson_deprecate] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[lesson_deprecate] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
