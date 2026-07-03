#!/bin/bash
# lesson_review.sh — draft教訓の一覧を表示（読み取り専用）
# Usage: bash scripts/lesson_review.sh <project_id>
# Example: bash scripts/lesson_review.sh infra

set -e

_lrv_self="${BASH_SOURCE[0]}"; [[ "$_lrv_self" != /* ]] && _lrv_self="$PWD/$_lrv_self"
SCRIPT_DIR="${_lrv_self%/scripts/lesson_review.sh}"
PROJECT_ID="${1:-}"

if [ -z "$PROJECT_ID" ]; then
    echo "Usage: lesson_review.sh <project_id>" >&2
    echo "Example: lesson_review.sh infra" >&2
    exit 0
fi

# Resolve project path in pure bash — avoids importing the yaml package just
# for this single "- id: / path:" lookup (import yaml alone costs ~35-55ms,
# dominated by yaml/__init__.py pulling in loader+dumper+cyaml submodules
# regardless of which Loader is used; cmd_training_speed_lesson_review).
resolve_project_path() {
    local project_id="$1" file="$2"
    local line current_id="" path_value="" matched=0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "  - id: "*)
                [ "$matched" -eq 1 ] && break
                current_id="${line#*id: }"
                current_id="${current_id//[[:space:]]/}"
                [ "$current_id" = "$project_id" ] && matched=1
                ;;
            "    path: "*)
                if [ "$matched" -eq 1 ] && [ -z "$path_value" ]; then
                    path_value="${line#*path: }"
                    path_value="${path_value//[[:space:]\"]/}"
                fi
                ;;
        esac
    done < "$file"
    printf '%s\n' "$path_value"
}

PROJECT_PATH="$(resolve_project_path "$PROJECT_ID" "$SCRIPT_DIR/config/projects.yaml")"
if [ -z "$PROJECT_PATH" ]; then
    echo "ERROR: Project '$PROJECT_ID' not found in config/projects.yaml" >&2
    exit 0
fi

LESSONS_FILE="$PROJECT_PATH/tasks/lessons.md"
if [ ! -f "$LESSONS_FILE" ]; then
    PROJECT_LESSONS_YAML="$SCRIPT_DIR/projects/${PROJECT_ID}/lessons.yaml"
    if [ -f "$PROJECT_LESSONS_YAML" ]; then
        export PROJECT_LESSONS_YAML
        python3 << 'PYEOF'
import os
import yaml

lessons_file = os.environ["PROJECT_LESSONS_YAML"]

with open(lessons_file, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

drafts = []
for lesson in data.get("lessons", []) or []:
    if str(lesson.get("status", "")).strip() == "draft":
        drafts.append({
            "id": lesson.get("id", ""),
            "title": lesson.get("title", ""),
            "source": lesson.get("source", ""),
            "date": lesson.get("date", ""),
        })

if not drafts:
    print(f"[lesson_review] No draft lessons found in {lessons_file}")
else:
    print(f"[lesson_review] {len(drafts)} draft lesson(s) found:\n")
    print(f'{"ID":<8} {"Date":<12} {"Source":<16} Title')
    print(f'{"-"*8} {"-"*12} {"-"*16} {"-"*40}')
    for d in drafts:
        print(f'{d["id"]:<8} {d["date"]:<12} {d["source"]:<16} {d["title"]}')
    print(f"\nTotal: {len(drafts)} draft(s)")
PYEOF
        exit 0
    fi
    echo "ERROR: $LESSONS_FILE not found." >&2
    exit 0
fi

export LESSONS_FILE
python3 << 'PYEOF'
import os
import re

lessons_file = os.environ["LESSONS_FILE"]

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
        m_status = re.match(r'^- \*\*status\*\*:\s*(.+)', sline)
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
