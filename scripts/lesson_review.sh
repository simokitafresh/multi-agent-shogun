#!/bin/bash
# lesson_review.sh — draft教訓の一覧を表示（読み取り専用）
# Usage: bash scripts/lesson_review.sh <project_id>
# Example: bash scripts/lesson_review.sh infra

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${1:-}"

if [ -z "$PROJECT_ID" ]; then
    echo "Usage: lesson_review.sh <project_id>" >&2
    echo "Example: lesson_review.sh infra" >&2
    exit 0
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
    exit 0
fi

LESSONS_FILE="$PROJECT_PATH/tasks/lessons.md"

if [ ! -f "$LESSONS_FILE" ]; then
    echo "ERROR: $LESSONS_FILE not found." >&2
    exit 0
fi

# Parse and display draft lessons (read-only, no flock needed)
export LESSONS_FILE
python3 << 'PYEOF'
import re, os

lessons_file = os.environ.get("LESSONS_FILE", "")
if not lessons_file:
    exit(0)

with open(lessons_file, encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')
drafts = []
i = 0

while i < len(lines):
    line = lines[i]

    # Match ### L{NNN}: title
    m = re.match(r'^### L(\d+):\s*(.+)', line)
    if not m:
        i += 1
        continue

    lesson_id = f'L{int(m.group(1)):03d}'
    title = m.group(2).strip()
    date_str = ''
    source_cmd = ''
    status = ''

    # Scan metadata lines
    j = i + 1
    while j < len(lines):
        sline = lines[j].strip()
        if sline.startswith('## ') or sline.startswith('### '):
            break
        m_date = re.match(r'^- \*\*日付\*\*:\s*(.+)', sline)
        if m_date:
            date_str = m_date.group(1).strip()
        m_src = re.match(r'^- \*\*出典\*\*:\s*(.+)', sline)
        if m_src:
            source_cmd = m_src.group(1).strip()
        m_status = re.match(r'^- \*\*状態\*\*:\s*(.+)', sline)
        if m_status:
            status = m_status.group(1).strip()
        j += 1

    if status == 'draft':
        drafts.append({
            'id': lesson_id,
            'title': title,
            'source': source_cmd,
            'date': date_str,
        })

    i = j if j > i + 1 else i + 1

if not drafts:
    print(f'[lesson_review] No draft lessons found in {lessons_file}')
else:
    print(f'[lesson_review] {len(drafts)} draft lesson(s) found:\n')
    print(f'{"ID":<8} {"Date":<12} {"Source":<16} Title')
    print(f'{"─"*8} {"─"*12} {"─"*16} {"─"*40}')
    for d in drafts:
        print(f'{d["id"]:<8} {d["date"]:<12} {d["source"]:<16} {d["title"]}')
    print(f'\nTotal: {len(drafts)} draft(s)')

PYEOF

exit 0
