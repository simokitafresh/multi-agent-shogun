#!/bin/bash
# checklist_update.sh — 段取りリストの項目更新（flock排他制御+進捗自動再計算）
# Usage: bash scripts/checklist_update.sh <checklist_file> <item_number> <status> <result> <ninja_name>
#
# 段取りリストのMarkdownテーブル行を更新し、先頭の進捗行を再計算する。
# flock排他制御で複数忍者からの同時更新に対応。

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHECKLIST_FILE="$1"
ITEM_NUMBER="$2"
STATUS="$3"
RESULT="$4"
NINJA_NAME="$5"

if [ -z "$CHECKLIST_FILE" ] || [ -z "$ITEM_NUMBER" ] || [ -z "$STATUS" ] || [ -z "$RESULT" ] || [ -z "$NINJA_NAME" ]; then
    echo "Usage: checklist_update.sh <checklist_file> <item_number> <status> <result> <ninja_name>" >&2
    exit 1
fi

# Resolve relative paths from project root
case "$CHECKLIST_FILE" in
    /*) ;;
    *) CHECKLIST_FILE="$SCRIPT_DIR/$CHECKLIST_FILE" ;;
esac

# Ensure queue/checklists/ directory exists
CHECKLIST_DIR="$(dirname "$CHECKLIST_FILE")"
mkdir -p "$CHECKLIST_DIR"

if [ ! -f "$CHECKLIST_FILE" ]; then
    echo "FATAL: checklist_update: file not found: $CHECKLIST_FILE" >&2
    exit 1
fi

LOCKFILE="${CHECKLIST_FILE}.lock"

attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 10 200 || exit 1

        CHECKLIST_PATH="$CHECKLIST_FILE" \
        ITEM_NUMBER="$ITEM_NUMBER" \
        STATUS="$STATUS" \
        RESULT="$RESULT" \
        NINJA_NAME="$NINJA_NAME" \
        python3 -c "
import os, sys, tempfile, re

checklist_path = os.environ['CHECKLIST_PATH']
item_number = int(os.environ['ITEM_NUMBER'])
status = os.environ['STATUS']
result = os.environ['RESULT']
ninja_name = os.environ['NINJA_NAME']

with open(checklist_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Parse and update the table
updated = False
done_count = 0
total_count = 0

# First pass: find and update the target row
new_lines = []
for line in lines:
    stripped = line.strip()
    # Match table data rows: | N | ... |
    m = re.match(r'^\|\s*(\d+)\s*\|', stripped)
    if m:
        row_num = int(m.group(1))
        # Split into cells
        cells = stripped.split('|')
        # cells[0]='' cells[1]=N cells[2]=対象 ... cells[5]=状態 cells[6]=結果 cells[7]=担当 cells[8]=実績
        if len(cells) >= 9 and row_num == item_number:
            cells[5] = f' {status} '
            cells[6] = f' {result} '
            cells[7] = f' {ninja_name} '
            new_line = '|'.join(cells)
            if not new_line.endswith('\n'):
                new_line += '\n'
            new_lines.append(new_line)
            updated = True
            continue
    new_lines.append(line)

if not updated:
    print(f'FATAL: checklist_update: item_number {item_number} not found', file=sys.stderr)
    sys.exit(2)

# Second pass: count done items and recalculate progress
done_count = 0
total_count = 0
for line in new_lines:
    stripped = line.strip()
    m = re.match(r'^\|\s*(\d+)\s*\|', stripped)
    if m:
        cells = stripped.split('|')
        if len(cells) >= 9:
            total_count += 1
            cell_status = cells[5].strip()
            if cell_status.lower() in ('done', 'pass', 'o', 'ok'):
                done_count += 1

# Update progress line: # 進捗: N/M (X%)
pct = int(done_count * 100 / total_count) if total_count > 0 else 0
progress_line = f'# 進捗: {done_count}/{total_count} ({pct}%)\n'

final_lines = []
progress_updated = False
for line in new_lines:
    if not progress_updated and line.startswith('# 進捗:'):
        final_lines.append(progress_line)
        progress_updated = True
    else:
        final_lines.append(line)

# Atomic write via tempfile + os.replace
dir_name = os.path.dirname(checklist_path)
fd, tmp_path = tempfile.mkstemp(dir=dir_name, prefix='.checklist_tmp_')
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as tmp_f:
        tmp_f.writelines(final_lines)
    os.replace(tmp_path, checklist_path)
except Exception:
    os.unlink(tmp_path)
    raise

print(f'[checklist_update] Updated item {item_number}: status={status} result={result} ninja={ninja_name} progress={done_count}/{total_count} ({pct}%)')
"
    ) 200>"$LOCKFILE"; then
        exit 0
    fi

    attempt=$((attempt + 1))
    if [ $attempt -lt $max_attempts ]; then
        sleep 1
    fi
done

echo "FATAL: checklist_update: failed after $max_attempts attempts" >&2
exit 1
