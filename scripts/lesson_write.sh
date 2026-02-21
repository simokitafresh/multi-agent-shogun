#!/bin/bash
# lesson_write.sh — SSOT (DM-signal/tasks/lessons.md) への教訓追記（排他ロック付き）
# Usage: bash scripts/lesson_write.sh <project_id> "<title>" "<detail>" "<source_cmd>" "<author>" [cmd_id] [--strategic]
# Example: bash scripts/lesson_write.sh dm-signal "本番DBはPostgreSQL" "SQLiteに書くな" "cmd_079" "karo"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${1:-}"
TITLE="${2:-}"
DETAIL="${3:-}"
SOURCE_CMD="${4:-}"
AUTHOR="${5:-karo}"
CMD_ID="${6:-""}"
STRATEGIC="${7:-""}"

# Scan for --force flag (bypasses duplicate check)
FORCE=0
for arg in "$@"; do
    if [ "$arg" == "--force" ]; then FORCE=1; fi
done

# Validate arguments
if [ -z "$PROJECT_ID" ] || [ -z "$TITLE" ] || [ -z "$DETAIL" ]; then
    echo "Usage: lesson_write.sh <project_id> <title> <detail> [source_cmd] [author]" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

if [[ "$PROJECT_ID" == cmd_* ]]; then
    echo "ERROR: 第1引数はproject_id（例: infra, dm-signal）。cmd_idではない。" >&2
    echo "Usage: lesson_write.sh <project_id> <title> <detail> [source_cmd] [author]" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

# Summary quality gate (cmd_158)
DETAIL_LEN=${#DETAIL}
if [ "$DETAIL_LEN" -lt 10 ]; then
    echo "ERROR: summary(detail)が10文字未満 (${DETAIL_LEN}文字)。具体的な内容を記載せよ" >&2
    exit 1
fi

# Get project path from config/projects.yaml
PROJECT_PATH=$(python3 -c "
import yaml
with open('$SCRIPT_DIR/config/projects.yaml', encoding='utf-8') as f:
    cfg = yaml.safe_load(f)
for p in cfg.get('projects', []):
    if p['id'] == '$PROJECT_ID':
        print(p['path'])
        break
")

if [ -z "$PROJECT_PATH" ]; then
    echo "ERROR: Project '$PROJECT_ID' not found in config/projects.yaml" >&2
    exit 1
fi

LESSONS_FILE="$PROJECT_PATH/tasks/lessons.md"
LOCKFILE="${LESSONS_FILE}.lock"

# Verify lessons file exists
if [ ! -f "$LESSONS_FILE" ]; then
    echo "ERROR: $LESSONS_FILE not found." >&2
    exit 1
fi

TIMESTAMP=$(date "+%Y-%m-%d")

# Temp file for passing lesson ID out of flock subshell
LESSON_ID_FILE=$(mktemp)
trap 'rm -f "$LESSON_ID_FILE"' EXIT

# Atomic append with flock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 10 200 || exit 1

        # Find max ID and append new entry
        export LESSONS_FILE TIMESTAMP TITLE DETAIL SOURCE_CMD AUTHOR FORCE LESSON_ID_FILE
        python3 << 'PYEOF'
import re, os, sys
from difflib import SequenceMatcher

lessons_file = os.environ["LESSONS_FILE"]
timestamp = os.environ["TIMESTAMP"]
title = os.environ["TITLE"]
detail = os.environ["DETAIL"]
source_cmd = os.environ["SOURCE_CMD"]
author = os.environ["AUTHOR"]

with open(lessons_file, encoding='utf-8') as f:
    content = f.read()

# Find max numeric ID from:
#   ## N. pattern → N
#   ### L{N}: pattern → N
max_id = 0

for m in re.finditer(r'^## (\d+)\.', content, re.MULTILINE):
    num = int(m.group(1))
    if num > max_id:
        max_id = num

for m in re.finditer(r'^### L(\d+):', content, re.MULTILINE):
    num = int(m.group(1))
    if num > max_id:
        max_id = num

new_id = max_id + 1
new_id_str = f'L{new_id:03d}'

# Duplicate title check (bypass with --force)
existing = []
for m in re.finditer(r'^### L(\d+): (.+)$', content, re.MULTILINE):
    existing.append((f'L{int(m.group(1)):03d}', m.group(2)))

force = os.environ.get("FORCE", "") == "1"
if not force:
    for eid, etitle in existing:
        ratio = SequenceMatcher(None, title, etitle).ratio()
        if ratio > 0.75:
            print(f'ERROR: 類似教訓あり: {eid}: {etitle} (類似度: {ratio:.0%})', file=sys.stderr)
            print(f'強制登録: --force フラグを追加', file=sys.stderr)
            sys.exit(1)

# Build new entry
entry = f'\n### {new_id_str}: {title}\n'
entry += f'- **日付**: {timestamp}\n'
if source_cmd:
    entry += f'- **出典**: {source_cmd}\n'
entry += f'- **記録者**: {author}\n'
entry += f'- {detail}\n'

# Append to file
with open(lessons_file, 'a', encoding='utf-8') as f:
    f.write(entry)

print(f'{new_id_str} added to {lessons_file}')

# Write lesson ID to temp file for post-flock --strategic processing
id_file = os.environ.get("LESSON_ID_FILE", "")
if id_file:
    with open(id_file, 'w') as f:
        f.write(new_id_str)
PYEOF

    ) 200>"$LOCKFILE"; then
        # AC3: Auto-call sync_lessons.sh after write
        bash "$SCRIPT_DIR/scripts/sync_lessons.sh" "$PROJECT_ID"
        # --strategic: Register as pending decision (replaces direct dashboard.md editing)
        if [ "$STRATEGIC" == "--strategic" ]; then
            NEW_LESSON_ID=""
            if [ -f "$LESSON_ID_FILE" ]; then
                NEW_LESSON_ID=$(cat "$LESSON_ID_FILE")
            fi
            if [ -n "$NEW_LESSON_ID" ]; then
                if [ -f "$SCRIPT_DIR/scripts/pending_decision_write.sh" ]; then
                    bash "$SCRIPT_DIR/scripts/pending_decision_write.sh" create \
                        "MCP昇格候補: $NEW_LESSON_ID — $TITLE（将軍確認待ち）" \
                        "$SOURCE_CMD" "skill_candidate" "$AUTHOR"
                else
                    echo "WARN: pending_decision_write.sh not found, skipping strategic registration" >&2
                fi
            fi
        fi
        # cmd_108: Write .done flag for cmd_complete_gate
        if [ -n "$CMD_ID" ]; then
            gates_dir="$SCRIPT_DIR/queue/gates/${CMD_ID}"
            mkdir -p "$gates_dir"
            echo "timestamp: $(date +%Y-%m-%dT%H:%M:%S)" > "$gates_dir/lesson.done"
            echo "source: lesson_write" >> "$gates_dir/lesson.done"
        fi
        exit 0
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[lesson_write] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[lesson_write] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
