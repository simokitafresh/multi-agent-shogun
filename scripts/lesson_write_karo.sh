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

# Entry count gate — 肥大化防止 (v2統合後: 22件→上限35件)
ENTRY_COUNT=$(grep -c '^- id:' "$LESSONS_FILE" 2>/dev/null || echo 0)
if [ "$ENTRY_COUNT" -ge 35 ]; then
    echo "BLOCK: lessons_karo.yaml が ${ENTRY_COUNT}件に到達(上限35件)。" >&2
    echo "  新規追加の前に既存教訓を統合・パターン昇格せよ。" >&2
    echo "  個別事故→パターンに昇格し件数を減らしてから再実行。" >&2
    echo "  参考: docs/research/lessons_karo_v1_archive.md (92件→22件の統合実績)" >&2
    exit 1
fi

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

# yaml.dump禁止(CLAUDE.md): 手動YAML構築でデータ消失を防止
# 既存データを書き換えず、新エントリを末尾に追記
sq = chr(39)
def _sv(v):
    s = str(v)
    if '\n' in s:
        return '|-\n' + '\n'.join('    ' + ln for ln in s.split('\n'))
    return sq + s.replace(sq, sq+sq) + sq

with open(lessons_file, 'rb') as f:
    f.seek(0, 2)
    size = f.tell()
    needs_nl = False
    if size > 0:
        f.seek(-1, 2)
        needs_nl = f.read(1) != b'\n'

with open(lessons_file, 'a', encoding='utf-8') as f:
    if needs_nl:
        f.write('\n')
    f.write(f'- id: {_sv(new_id_str)}\n')
    f.write(f'  title: {_sv(title)}\n')
    f.write(f'  detail: {_sv(detail)}\n')
    f.write(f'  source_cmd: {_sv(source_cmd)}\n')
    f.write(f'  created_at: {_sv(timestamp)}\n')

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
