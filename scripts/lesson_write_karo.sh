#!/bin/bash
# lesson_write_karo.sh — 家老専用教訓追記（排他ロック付き）
# Usage: bash scripts/lesson_write_karo.sh "タイトル" "詳細" cmd_XXX
# → projects/infra/lessons_karo.yaml に追記

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TITLE="${1:-}"
DETAIL="${2:-}"
SOURCE_CMD="${3:-}"

# Validate arguments
if [ -z "$TITLE" ] || [ -z "$DETAIL" ]; then
    echo "Usage: lesson_write_karo.sh \"タイトル\" \"詳細\" cmd_XXX" >&2
    exit 1
fi

# Detail quality gate
DETAIL_LEN=${#DETAIL}
if [ "$DETAIL_LEN" -lt 10 ]; then
    echo "ERROR: detail が10文字未満 (${DETAIL_LEN}文字)。具体的な内容を記載せよ" >&2
    exit 1
fi

LESSONS_FILE="$SCRIPT_DIR/projects/infra/lessons_karo.yaml"
LOCKFILE="${LESSONS_FILE}.lock"

# Verify lessons file exists
if [ ! -f "$LESSONS_FILE" ]; then
    echo "ERROR: $LESSONS_FILE not found." >&2
    exit 1
fi

TIMESTAMP=$(date "+%Y-%m-%d")

# Atomic append with flock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 10 200 || exit 1

        export LESSONS_FILE TIMESTAMP TITLE DETAIL SOURCE_CMD
        python3 << 'PYEOF'
import yaml, os, sys
from difflib import SequenceMatcher

lessons_file = os.environ["LESSONS_FILE"]
timestamp = os.environ["TIMESTAMP"]
title = os.environ["TITLE"]
detail = os.environ["DETAIL"]
source_cmd = os.environ.get("SOURCE_CMD", "")

with open(lessons_file, encoding='utf-8') as f:
    data = yaml.safe_load(f)

lessons = data.get('lessons', [])

# Find max numeric ID (LK format)
max_id = 0
for lesson in lessons:
    lid = lesson.get('id', '')
    if lid.startswith('LK'):
        try:
            num = int(lid[2:])
            if num > max_id:
                max_id = num
        except ValueError:
            pass

new_id = max_id + 1
new_id_str = f'LK{new_id:03d}'

# Duplicate title check
for lesson in lessons:
    existing_title = lesson.get('title', '')
    ratio = SequenceMatcher(None, title, existing_title).ratio()
    if ratio > 0.75:
        print(f'ERROR: 類似教訓あり: {lesson.get("id","")}: {existing_title} (類似度: {ratio:.0%})', file=sys.stderr)
        print(f'重複を確認して再実行せよ', file=sys.stderr)
        sys.exit(1)

# Append new lesson
new_lesson = {
    'id': new_id_str,
    'title': title,
    'detail': detail,
    'source_cmd': source_cmd,
    'created_at': timestamp,
}

lessons.append(new_lesson)
data['lessons'] = lessons

with open(lessons_file, 'w', encoding='utf-8') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)

print(f'{new_id_str} added to {lessons_file}')
PYEOF

    ) 200>"$LOCKFILE"; then
        exit 0
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[lesson_write_karo] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[lesson_write_karo] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
