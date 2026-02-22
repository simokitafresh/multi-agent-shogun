#!/bin/bash
# lesson_edit.sh — 教訓のtitle/summaryを更新+confirmed化（flock排他制御付き）
# Usage: bash scripts/lesson_edit.sh <project_id> <lesson_id> "<new_title>" "<new_summary>"
# Example: bash scripts/lesson_edit.sh infra L023 "新タイトル" "新しい要約テキスト"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${1:-}"
LESSON_ID="${2:-}"
NEW_TITLE="${3:-}"
NEW_SUMMARY="${4:-}"

if [ -z "$PROJECT_ID" ] || [ -z "$LESSON_ID" ] || [ -z "$NEW_TITLE" ] || [ -z "$NEW_SUMMARY" ]; then
    echo "Usage: lesson_edit.sh <project_id> <lesson_id> \"<new_title>\" \"<new_summary>\"" >&2
    echo "Example: lesson_edit.sh infra L023 \"新タイトル\" \"新しい要約テキスト\"" >&2
    exit 1
fi

# Normalize lesson ID (accept L23 or L023)
LESSON_ID=$(echo "$LESSON_ID" | sed -E 's/^L0*([0-9]+)$/L\1/')

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

if [ ! -f "$LESSONS_FILE" ]; then
    echo "ERROR: $LESSONS_FILE not found." >&2
    exit 1
fi

# Temp file for python exit code (L022)
PY_EXIT_FILE=$(mktemp)
trap 'rm -f "$PY_EXIT_FILE"' EXIT

attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 10 200 || exit 1

        export LESSONS_FILE LESSON_ID NEW_TITLE NEW_SUMMARY PY_EXIT_FILE
        python3 << 'PYEOF'
import re, os, sys, tempfile

lessons_file = os.environ["LESSONS_FILE"]
lesson_id_raw = os.environ["LESSON_ID"]
new_title = os.environ["NEW_TITLE"]
new_summary = os.environ["NEW_SUMMARY"]
py_exit_file = os.environ["PY_EXIT_FILE"]

m_id = re.match(r'L(\d+)', lesson_id_raw)
if not m_id:
    print(f'ERROR: Invalid lesson ID format: {lesson_id_raw}', file=sys.stderr)
    with open(py_exit_file, 'w') as f:
        f.write('1')
    sys.exit(0)

target_num = int(m_id.group(1))
target_id_str = f'L{target_num:03d}'

with open(lessons_file, encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')
found = False

i = 0
while i < len(lines):
    m = re.match(r'^### L(\d+):', lines[i])
    if m and int(m.group(1)) == target_num:
        found = True
        # Update title line
        lines[i] = f'### {target_id_str}: {new_title}'

        # Scan entry for status and summary content
        j = i + 1
        entry_end = len(lines)
        status_found = False
        summary_lines = []  # indices of non-metadata content lines

        while j < len(lines):
            sline = lines[j].strip()
            if sline.startswith('## ') or sline.startswith('### '):
                entry_end = j
                break
            # Update status line
            m_status = re.match(r'^- \*\*status\*\*:', lines[j])
            if m_status:
                lines[j] = '- **status**: confirmed'
                status_found = True
            # Identify summary content lines (not metadata)
            elif sline and not re.match(r'^- \*\*(日付|出典|記録者|status|状態|原因|影響|対策|教訓|修正|参照|結果)\*\*:', sline):
                summary_lines.append(j)
            j += 1

        # Replace summary content
        if summary_lines:
            # Replace first summary line, remove the rest
            first_summary = summary_lines[0]
            lines[first_summary] = f'- {new_summary}'
            # Remove extra summary lines in reverse order
            for idx in reversed(summary_lines[1:]):
                lines.pop(idx)
        else:
            # No summary lines found; insert before entry_end
            # Recalculate entry_end after potential changes
            insert_pos = i + 1
            while insert_pos < len(lines):
                if lines[insert_pos].strip().startswith('## ') or lines[insert_pos].strip().startswith('### '):
                    break
                insert_pos += 1
            lines.insert(insert_pos, f'- {new_summary}')

        # If no status line existed, add one after the heading metadata
        if not status_found:
            # Find insertion point (after last metadata line)
            insert_pos = i + 1
            while insert_pos < len(lines):
                sline = lines[insert_pos].strip()
                if sline.startswith('## ') or sline.startswith('### '):
                    break
                if re.match(r'^- \*\*(日付|出典|記録者)\*\*:', sline):
                    insert_pos += 1
                    continue
                break
            lines.insert(insert_pos, '- **status**: confirmed')

        break
    i += 1

if not found:
    print(f'ERROR: Lesson {lesson_id_raw} not found in {lessons_file}', file=sys.stderr)
    with open(py_exit_file, 'w') as f:
        f.write('1')
    sys.exit(0)

# Atomic write
new_content = '\n'.join(lines)
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(lessons_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(new_content)
    os.replace(tmp_path, lessons_file)
except Exception:
    os.unlink(tmp_path)
    raise

print(f'[lesson_edit] {target_id_str} updated: title="{new_title}", status=confirmed')
with open(py_exit_file, 'w') as f:
    f.write('0')
PYEOF

    ) 200>"$LOCKFILE"; then
        PY_EXIT=$(cat "$PY_EXIT_FILE" 2>/dev/null || echo "1")
        if [ "$PY_EXIT" != "0" ]; then
            exit 1
        fi
        bash "$SCRIPT_DIR/scripts/sync_lessons.sh" "$PROJECT_ID"
        exit 0
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[lesson_edit] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[lesson_edit] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
