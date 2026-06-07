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

        export CACHE_FILE LESSON_ID SCORE_TYPE
        python3 -c '
import re, os, tempfile
from datetime import datetime

cache_file = os.environ["CACHE_FILE"]
lesson_id = os.environ["LESSON_ID"]
score_type = os.environ["SCORE_TYPE"]

field = "injection_count" if score_type == "inject" else f"{score_type}_count"
ts = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")

with open(cache_file, encoding="utf-8") as f:
    lines = f.readlines()

in_block = False
found = False
field_done = False
ts_done = False
count_val = None
out = []

target_start = f"- id: {lesson_id}"
field_prefix = f"  {field}:"
ts_prefix = "  last_referenced:"

for line in lines:
    s = line.rstrip("\n").rstrip("\r")

    # Detect block start: "- id: LESSON_ID"
    if s == target_start:
        in_block = True
        found = True
        field_done = False
        ts_done = False
        out.append(line)
        continue

    if in_block:
        # Block ends at next list item or non-indented non-comment
        if s.startswith("- id:") or (s and s[0] not in (" ", "\t", "#")):
            if not field_done:
                out.append(f"  {field}: 1\n")
                count_val = 1
            if not ts_done:
                out.append(f"  last_referenced: '\''{ts}'\''\n")
            in_block = False
            out.append(line)
            continue

        # Update count field
        if not field_done and s.startswith(field_prefix):
            m = re.match(r"^(\s+" + re.escape(field) + r":\s*)(\d+)", s)
            if m:
                count_val = int(m.group(2)) + 1
                nl = "\n" if line.endswith("\n") else ""
                out.append(f"{m.group(1)}{count_val}{nl}")
                field_done = True
                continue

        # Update last_referenced
        if not ts_done and s.startswith(ts_prefix):
            m = re.match(r"^(\s+last_referenced:\s*)", s)
            if m:
                nl = "\n" if line.endswith("\n") else ""
                out.append(f"{m.group(1)}'\''{ts}'\''{nl}")
                ts_done = True
                continue

    out.append(line)

# EOF while still in block
if in_block:
    if not field_done:
        out.append(f"  {field}: 1\n")
        count_val = 1
    if not ts_done:
        out.append(f"  last_referenced: '\''{ts}'\''\n")

if not found:
    print(f"ERROR: {lesson_id} not found in {cache_file}", flush=True)
    raise SystemExit(1)

print(f"{lesson_id} {field} → {count_val}", flush=True)

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(cache_file), suffix=".tmp")
try:
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
        f.writelines(out)
    os.replace(tmp_path, cache_file)
except Exception:
    os.unlink(tmp_path)
    raise
'

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
