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
# If L-style entries exist, trust only that format to avoid duplicate/ghost IDs.
has_l_style_entries = any(re.match(r'^###\s+L\d+\s*[:：]\s*', ln) for ln in lines)

while i < len(lines):
    line = lines[i]

    title = None
    lesson_id = None
    date_str = None
    status = None
    deprecated_by = None
    merged_from = None

    # Match ## N. title (numbered top-level lesson)
    m_h2_num = re.match(r'^## (\d+)\.\s+(.+)', line)
    # Match ## non-numbered section heading
    m_h2_plain = re.match(r'^## (.+)', line) if not m_h2_num else None
    # Match ### title (subsection lesson)
    m_h3 = re.match(r'^### (.+)', line)

    if has_l_style_entries:
        # Canonical mode: parse only "### LXXX: title" entries.
        if not m_h3:
            i += 1
            continue
        raw_title = m_h3.group(1).strip()
        m_lid = re.match(r'^L(\d+)\s*[:：]\s*(.+)$', raw_title)
        if not m_lid:
            i += 1
            continue
        lesson_id = f'L{int(m_lid.group(1)):03d}'
        title = m_lid.group(2).strip()
    elif m_h2_num:
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
            # In legacy mode, non-L### headings are structural text, not lessons.
            i += 1
            continue
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
        # Extract status from **status** field
        if not status:
            m_fstatus = re.match(r'- \*\*status\*\*:\s*(.+)', sline)
            if m_fstatus:
                status = m_fstatus.group(1).strip()
        # Extract deprecated_by from **deprecated_by** field
        if not deprecated_by:
            m_fdep = re.match(r'- \*\*deprecated_by\*\*:\s*(.+)', sline)
            if m_fdep:
                deprecated_by = m_fdep.group(1).strip()
        # Extract merged_from from **merged_from** field
        if not merged_from:
            m_fmerge = re.match(r'- \*\*merged_from\*\*:\s*\[(.+)\]', sline)
            if m_fmerge:
                merged_from = [x.strip() for x in m_fmerge.group(1).split(',')]
        # Get summary from **発生**/**問題**/**課題** fields or plain content
        if sline.startswith('- **発生**:') or sline.startswith('- **問題**:') or sline.startswith('- **課題**:'):
            text = re.sub(r'^- \*\*[^*]+\*\*:\s*', '', sline)
            summary_parts.append(text)
        elif sline and not sline.startswith('```') and not sline.startswith('|'):
            # Skip metadata fields for summary
            if not re.match(r'^- \*\*(日付|出典|記録者|status|deprecated_by|merged_from|原因|影響|対策|教訓|修正|参照|結果)\*\*:', sline):
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
    if status:
        entry['status'] = status
    if deprecated_by:
        entry['deprecated_by'] = deprecated_by
    if merged_from:
        entry['merged_from'] = merged_from

    lessons.append(entry)
    i = j if j > i + 1 else i + 1

# Keep only explicit IDs to prevent ghost entries, then sort by newest ID first.
lessons = [l for l in lessons if l.get('id')]
lessons.sort(key=lambda x: int(x['id'].replace('L', '')), reverse=True)

# Deduplicate by lesson id (keep first/newest after sorting).
seen = set()
deduped = []
for lesson in lessons:
    lesson_id = lesson['id']
    if lesson_id in seen:
        continue
    seen.add(lesson_id)
    deduped.append(lesson)
lessons = deduped

# Preserve score fields from existing cache (helpful_count, harmful_count, last_referenced)
score_data = {}
old_data = None
try:
    with open(cache_file, encoding='utf-8') as cf:
        old_data = yaml.safe_load(cf)
    for old_lesson in (old_data or {}).get('lessons', []):
        lid = old_lesson.get('id')
        if lid:
            score_data[lid] = {
                'helpful_count': old_lesson.get('helpful_count', 0),
                'harmful_count': old_lesson.get('harmful_count', 0),
                'last_referenced': old_lesson.get('last_referenced'),
            }
except FileNotFoundError:
    pass
except Exception:
    pass

# Merge score fields into new lessons (preserve existing, default for new)
for lesson in lessons:
    lid = lesson.get('id')
    if lid in score_data:
        lesson['helpful_count'] = score_data[lid]['helpful_count']
        lesson['harmful_count'] = score_data[lid]['harmful_count']
        lesson['last_referenced'] = score_data[lid]['last_referenced']
    else:
        lesson['helpful_count'] = 0
        lesson['harmful_count'] = 0
        lesson['last_referenced'] = None

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
if old_data is not None:
    old_ids = {l['id'] for l in old_data.get('lessons', [])}
    deleted = old_ids - new_ids
    added = new_ids - old_ids
    if deleted:
        print(f'Deleted from cache: {sorted(deleted)}')
    if added:
        print(f'Added to cache: {sorted(added)}')

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
