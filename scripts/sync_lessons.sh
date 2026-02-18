#!/bin/bash
# sync_lessons.sh — SSOT (lessons.md) からキャッシュ (lessons.yaml) を自動生成
# Usage: bash scripts/sync_lessons.sh [project_id]
# Default project_id: dm-signal

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${1:-dm-signal}"

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

SSOT_FILE="$PROJECT_PATH/tasks/lessons.md"
CACHE_FILE="$SCRIPT_DIR/projects/${PROJECT_ID}/lessons.yaml"
LOCKFILE="${CACHE_FILE}.lock"

if [ ! -f "$SSOT_FILE" ]; then
    echo "ERROR: SSOT file not found: $SSOT_FILE" >&2
    exit 1
fi

# Ensure output directory exists
mkdir -p "$(dirname "$CACHE_FILE")"

# Atomic write with flock
(
    flock -w 10 200 || { echo "ERROR: Could not acquire lock" >&2; exit 1; }

    export SSOT_FILE CACHE_FILE
    python3 << 'PYEOF'
import re, yaml, os, tempfile
from datetime import datetime

ssot_file = os.environ["SSOT_FILE"]
cache_file = os.environ["CACHE_FILE"]

with open(ssot_file, encoding='utf-8') as f:
    content = f.read()

# Remove YAML front matter (between --- markers)
parts = content.split('---')
if len(parts) >= 3:
    body = '---'.join(parts[2:])
else:
    body = content

lines = body.split('\n')
lessons = []
i = 0
in_numbered_section = False  # True when inside ## N. section

while i < len(lines):
    line = lines[i]

    title = None
    lesson_id = None
    date_str = None

    # Match ## N. title (numbered top-level lesson)
    m_h2_num = re.match(r'^## (\d+)\.\s+(.+)', line)
    # Match ## non-numbered section heading
    m_h2_plain = re.match(r'^## (.+)', line) if not m_h2_num else None
    # Match ### title (subsection lesson)
    m_h3 = re.match(r'^### (.+)', line)

    if m_h2_num:
        in_numbered_section = True
        num = int(m_h2_num.group(1))
        lesson_id = f'L{num:03d}'
        title = m_h2_num.group(2).strip()
    elif m_h2_plain:
        # Non-numbered ## heading (structural section like ドキュメント整合性)
        in_numbered_section = False
        i += 1
        continue
    elif m_h3:
        # ### heading: only treat as lesson if NOT inside a ## N. section
        # Exception: ### L{id}: format is always a lesson entry (from lesson_write.sh)
        raw_title_check = m_h3.group(1).strip()
        if in_numbered_section and not re.match(r'L\d+:', raw_title_check):
            # Subsection of a numbered lesson — skip
            i += 1
            continue
        raw_title = m_h3.group(1).strip()
        # Check for L{id}: prefix (shogun system format)
        m_lid = re.match(r'L(\d+):\s*(.*)', raw_title)
        if m_lid:
            lesson_id = f'L{int(m_lid.group(1)):03d}'
            title = m_lid.group(2).strip()
        else:
            title = raw_title
            # Extract date from parenthesized suffix
            m_date = re.search(r'[（(](\d{4}-\d{2}-\d{2})[）)]', raw_title)
            if m_date:
                date_str = m_date.group(1)
                title = re.sub(r'\s*[（(]\d{4}-\d{2}-\d{2}[）)]\s*$', '', title)
    else:
        i += 1
        continue

    if not title:
        i += 1
        continue

    # Collect summary from subsequent lines
    summary_parts = []
    source = ''
    j = i + 1
    while j < len(lines) and len(summary_parts) < 2:
        sline = lines[j].strip()
        # Stop at next heading
        if sline.startswith('## ') or sline.startswith('### '):
            break
        # Stop at horizontal rule
        if sline == '---':
            break
        # Extract source cmd
        if not source:
            m_src = re.search(r'(cmd_\d+\w*|subtask_\d+\w*)', sline)
            if m_src:
                source = m_src.group(1)
        # Extract date from **日付** field
        if not date_str:
            m_fdate = re.match(r'- \*\*日付\*\*:\s*(.+)', sline)
            if m_fdate:
                date_str = m_fdate.group(1).strip()
        # Extract source from **出典** field
        if not source:
            m_fsrc = re.match(r'- \*\*出典\*\*:\s*(.+)', sline)
            if m_fsrc:
                source = m_fsrc.group(1).strip()
        # Get summary from **発生**/**問題**/**課題** fields or plain content
        if sline.startswith('- **発生**:') or sline.startswith('- **問題**:') or sline.startswith('- **課題**:'):
            text = re.sub(r'^- \*\*[^*]+\*\*:\s*', '', sline)
            summary_parts.append(text)
        elif sline and not sline.startswith('```') and not sline.startswith('|'):
            # Skip metadata fields for summary
            if not re.match(r'^- \*\*(日付|出典|記録者|原因|影響|対策|教訓|修正|参照|結果)\*\*:', sline):
                if sline.startswith('- '):
                    summary_parts.append(sline[2:])
                elif not sline.startswith('**') and not sline.startswith('#'):
                    summary_parts.append(sline)
        j += 1

    summary = ' '.join(summary_parts)[:200].strip() if summary_parts else title

    entry = {'id': lesson_id, 'title': title, 'summary': summary}
    if source:
        entry['source'] = source
    if date_str:
        entry['date'] = date_str

    lessons.append(entry)
    i = j if j > i + 1 else i + 1

# Assign IDs to lessons without explicit IDs
max_num = 0
for l in lessons:
    if l.get('id'):
        try:
            num = int(l['id'].replace('L', ''))
            max_num = max(max_num, num)
        except ValueError:
            pass

for l in lessons:
    if not l.get('id'):
        max_num += 1
        l['id'] = f'L{max_num:03d}'

# Sort by ID number descending (newest/highest first), limit to 20
lessons.sort(key=lambda x: int(x['id'].replace('L', '')), reverse=True)
lessons = lessons[:20]

# Build output
data = {
    'ssot_path': ssot_file,
    'last_synced': datetime.now().strftime('%Y-%m-%dT%H:%M:%S'),
    'lessons': lessons,
}

header = (
    f'# Auto-generated by sync_lessons.sh — DO NOT EDIT DIRECTLY\n'
    f'# SSOT: {ssot_file}\n'
)

# Report deletions: compare with existing cache before overwrite
new_ids = {l['id'] for l in lessons}
try:
    with open(cache_file, encoding='utf-8') as cf:
        old_data = yaml.safe_load(cf)
    old_ids = {l['id'] for l in (old_data or {}).get('lessons', [])}
    deleted = old_ids - new_ids
    added = new_ids - old_ids
    if deleted:
        print(f'Deleted from cache: {sorted(deleted)}')
    if added:
        print(f'Added to cache: {sorted(added)}')
except FileNotFoundError:
    pass
except Exception:
    pass

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(cache_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(header)
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2, sort_keys=False)
    os.replace(tmp_path, cache_file)
except Exception:
    os.unlink(tmp_path)
    raise

print(f'Synced {len(lessons)} lessons to {cache_file}')
PYEOF

) 200>"$LOCKFILE"
