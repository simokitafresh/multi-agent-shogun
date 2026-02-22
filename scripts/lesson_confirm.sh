#!/bin/bash
# lesson_confirm.sh — draft教訓をconfirmedに変更（flock排他制御付き）
# Usage: bash scripts/lesson_confirm.sh <project_id> <lesson_id>
# Example: bash scripts/lesson_confirm.sh infra L023

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${1:-}"
LESSON_ID="${2:-}"

if [ -z "$PROJECT_ID" ] || [ -z "$LESSON_ID" ]; then
    echo "Usage: lesson_confirm.sh <project_id> <lesson_id>" >&2
    echo "Example: lesson_confirm.sh infra L023" >&2
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

# Temp file for python exit code (L022: separate python exit from flock failure)
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

# Parse numeric part for matching
m_id = re.match(r'L(\d+)', lesson_id_raw)
if not m_id:
    print(f'ERROR: Invalid lesson ID format: {lesson_id_raw}', file=sys.stderr)
    with open(py_exit_file, 'w') as f:
        f.write('1')
    sys.exit(0)  # Exit 0 from python so flock doesn't retry (L022)

target_num = int(m_id.group(1))

with open(lessons_file, encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')
found = False
already_confirmed = False
modified = False

i = 0
while i < len(lines):
    m = re.match(r'^### L(\d+):', lines[i])
    if m and int(m.group(1)) == target_num:
        found = True
        # Scan for status line within this entry
        j = i + 1
        status_line_idx = None
        entry_end = len(lines)
        while j < len(lines):
            if lines[j].strip().startswith('## ') or lines[j].strip().startswith('### '):
                entry_end = j
                break
            m_status = re.match(r'^- \*\*状態\*\*:\s*(.+)', lines[j])
            if m_status:
                status_line_idx = j
                current_status = m_status.group(1).strip()
                if current_status == 'confirmed':
                    already_confirmed = True
                elif current_status == 'draft':
                    lines[j] = '- **状態**: confirmed'
                    modified = True
            j += 1
        break
    i += 1

if not found:
    print(f'ERROR: Lesson {lesson_id_raw} not found in {lessons_file}', file=sys.stderr)
    with open(py_exit_file, 'w') as f:
        f.write('1')
    sys.exit(0)

if already_confirmed:
    print(f'ERROR: Lesson {lesson_id_raw} is already confirmed', file=sys.stderr)
    with open(py_exit_file, 'w') as f:
        f.write('1')
    sys.exit(0)

if not modified:
    print(f'ERROR: Lesson {lesson_id_raw} has no status field or is not draft', file=sys.stderr)
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

print(f'[lesson_confirm] {lesson_id_raw} status changed: draft → confirmed')
with open(py_exit_file, 'w') as f:
    f.write('0')
PYEOF

    ) 200>"$LOCKFILE"; then
        # Check python exit code
        PY_EXIT=$(cat "$PY_EXIT_FILE" 2>/dev/null || echo "1")
        if [ "$PY_EXIT" != "0" ]; then
            exit 1
        fi
        # Sync cache
        bash "$SCRIPT_DIR/scripts/sync_lessons.sh" "$PROJECT_ID"
        exit 0
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[lesson_confirm] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[lesson_confirm] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
