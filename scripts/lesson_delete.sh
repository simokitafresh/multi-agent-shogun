#!/bin/bash
# lesson_delete.sh — SSoTから教訓を削除（flock排他制御付き）
# Usage: bash scripts/lesson_delete.sh <project_id> <lesson_id>
# Example: bash scripts/lesson_delete.sh infra L023

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${1:-}"
LESSON_ID="${2:-}"

if [ -z "$PROJECT_ID" ] || [ -z "$LESSON_ID" ]; then
    echo "Usage: lesson_delete.sh <project_id> <lesson_id>" >&2
    echo "Example: lesson_delete.sh infra L023" >&2
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

        export LESSONS_FILE LESSON_ID PY_EXIT_FILE
        python3 << 'PYEOF'
import re, os, sys, tempfile

lessons_file = os.environ["LESSONS_FILE"]
lesson_id_raw = os.environ["LESSON_ID"]
py_exit_file = os.environ["PY_EXIT_FILE"]

m_id = re.match(r'L(\d+)', lesson_id_raw)
if not m_id:
    print(f'ERROR: Invalid lesson ID format: {lesson_id_raw}', file=sys.stderr)
    with open(py_exit_file, 'w') as f:
        f.write('1')
    sys.exit(0)

target_num = int(m_id.group(1))

with open(lessons_file, encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')
found = False
entry_start = None
entry_end = None

i = 0
while i < len(lines):
    m = re.match(r'^### L(\d+):', lines[i])
    if m and int(m.group(1)) == target_num:
        found = True
        entry_start = i
        # Find entry end (next heading or EOF)
        j = i + 1
        while j < len(lines):
            if lines[j].strip().startswith('## ') or lines[j].strip().startswith('### '):
                break
            j += 1
        entry_end = j
        break
    i += 1

if not found:
    print(f'ERROR: Lesson {lesson_id_raw} not found in {lessons_file}', file=sys.stderr)
    with open(py_exit_file, 'w') as f:
        f.write('1')
    sys.exit(0)

# Print deleted content to stdout (confirmation)
deleted_lines = lines[entry_start:entry_end]
print(f'[lesson_delete] Deleting {lesson_id_raw}:')
for dl in deleted_lines:
    print(f'  {dl}')

# Remove the entry (also remove trailing blank lines)
new_lines = lines[:entry_start] + lines[entry_end:]
# Clean up consecutive blank lines at deletion point
while entry_start < len(new_lines) and entry_start > 0:
    if new_lines[entry_start].strip() == '' and new_lines[entry_start - 1].strip() == '':
        new_lines.pop(entry_start)
    else:
        break

# Atomic write
new_content = '\n'.join(new_lines)
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(lessons_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(new_content)
    os.replace(tmp_path, lessons_file)
except Exception:
    os.unlink(tmp_path)
    raise

print(f'[lesson_delete] {lesson_id_raw} removed from {lessons_file}')
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
            echo "[lesson_delete] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[lesson_delete] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
