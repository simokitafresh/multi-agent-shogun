#!/bin/bash
# sync_lessons.sh — SSOT (lessons.md) からキャッシュ (lessons.yaml) を自動生成
# Usage: bash scripts/sync_lessons.sh [project_id]
# Default project_id: dm-signal

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${1:-dm-signal}"

resolve_project_path() {
    local project_id="$1"
    awk -v id="$project_id" '
        /^[[:space:]]*- id:/ {
            val = $NF
            gsub(/"/, "", val)
            found = (val == id)
        }
        found && /^[[:space:]]*path:/ {
            sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "")
            gsub(/"/, "")
            print
            exit
        }
    ' "$SCRIPT_DIR/config/projects.yaml"
}

PROJECT_PATH="$(resolve_project_path "$PROJECT_ID")"

if [ -z "$PROJECT_PATH" ]; then
    echo "ERROR: Project '$PROJECT_ID' not found in config/projects.yaml" >&2
    exit 1
fi

SSOT_FILE="$PROJECT_PATH/tasks/lessons.md"
INDEX_FILE="$SCRIPT_DIR/projects/${PROJECT_ID}/lessons.yaml"
ARCHIVE_FILE="$SCRIPT_DIR/projects/${PROJECT_ID}/lessons_archive.yaml"
# CACHE_FILE kept as alias for backward compat (lesson_update_score.sh etc. use same lockfile)
CACHE_FILE="$INDEX_FILE"
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

    export SSOT_FILE INDEX_FILE ARCHIVE_FILE SCRIPT_DIR PROJECT_ID PROJECT_PATH
    python3 << 'PYEOF'
import csv
import re, yaml, os, sys, tempfile
from datetime import datetime
from collections import defaultdict

ssot_file = os.environ["SSOT_FILE"]
index_file = os.environ["INDEX_FILE"]
archive_file = os.environ["ARCHIVE_FILE"]
project_id = os.environ["PROJECT_ID"]
impact_file = os.path.join(os.environ["SCRIPT_DIR"], "logs", "lesson_impact.tsv")


def to_int(value):
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0

with open(ssot_file, encoding='utf-8') as f:
    content = f.read()

# Remove YAML front matter (between --- markers at line start only)
# Bug fix: content.split('---') matched mid-line '---' in lesson text (e.g. L069),
# truncating 69 of 74 lessons. Now only matches '^---$' at line boundaries.
lines_raw = content.split('\n')
body_start = 0
if lines_raw and lines_raw[0].strip() == '---':
    # Find closing --- of front matter
    for idx in range(1, len(lines_raw)):
        if lines_raw[idx].strip() == '---':
            body_start = idx + 1
            break
body = '\n'.join(lines_raw[body_start:])

lines = body.split('\n')
lessons = []
i = 0
in_numbered_section = False  # True when inside ## N. section
# If L-style entries exist, trust only that format to avoid duplicate/ghost IDs.
has_l_style_entries = any(re.match(r'^###\s+L\d+\s*[:：]\s*', ln) for ln in lines)
current_category = "未分類"

# 忍者成長速度改善2: ファイルキャッシュ+パターンをループ外で1回だけ構築
_tf_path_pat = re.compile(r'(?:scripts|tests|context|backend|frontend|config|queue|docs|app)/[\w/.-]+\.(?:sh|py|bats|yaml|md|json|ts|tsx|js)')
_tf_file_pat = re.compile(r'[a-zA-Z_][\w-]*\.(?:sh|py|bats|yaml|md|json)')
_tf_file_cache = set()
_tf_search_bases = []
for _tf_candidate in (os.environ.get('SCRIPT_DIR', ''), os.environ.get('PROJECT_PATH', '')):
    if _tf_candidate and _tf_candidate not in _tf_search_bases:
        _tf_search_bases.append(_tf_candidate)
if project_id == 'dm-signal' and '/mnt/c/Python_app/DM-signal' not in _tf_search_bases:
    _tf_search_bases.append('/mnt/c/Python_app/DM-signal')

for _tf_search_base in _tf_search_bases:
    if not _tf_search_base or not os.path.isdir(_tf_search_base):
        continue
    for _tf_sd in ('scripts', 'tests', 'context', 'config', 'backend', 'frontend', 'docs'):
        _tf_dir = os.path.join(_tf_search_base, _tf_sd)
        if not os.path.isdir(_tf_dir):
            continue
        for _tf_root, _, _tf_files in os.walk(_tf_dir):
            for _tf_f in _tf_files:
                _tf_file_cache.add(_tf_f)

while i < len(lines):
    line = lines[i]

    title = None
    lesson_id = None
    date_str = None
    status = None
    deprecated_by = None
    merged_from = None
    tags = None
    if_cond = None
    then_action = None
    because_reason = None
    when_cond = None
    how_action = None
    retired = None
    retired_at = None
    target_files = None
    subdomain = None

    # Match ## N. title (numbered top-level lesson)
    m_h2_num = re.match(r'^## (\d+)\.\s+(.+)', line)
    # Match ## non-numbered section heading
    m_h2_plain = re.match(r'^## (.+)', line) if not m_h2_num else None
    # Match ### title (subsection lesson)
    m_h3 = re.match(r'^### (.+)', line)

    # Track current category from ## section headings
    if m_h2_num:
        current_category = m_h2_num.group(2).strip()
    elif m_h2_plain:
        current_category = m_h2_plain.group(1).strip()

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
    while j < len(lines):
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
        # Extract tags from **tags** field
        if tags is None:
            m_ftags = re.match(r'- \*\*tags\*\*:\s*\[(.+)\]', sline)
            if m_ftags:
                tags = [t.strip() for t in m_ftags.group(1).split(',')]
        # Extract subdomain from **subdomain** field
        if subdomain is None:
            m_fsubdomain = re.match(r'- \*\*subdomain\*\*:\s*(.+)', sline)
            if m_fsubdomain:
                raw_subdomain = m_fsubdomain.group(1).strip()
                if raw_subdomain.startswith('[') and raw_subdomain.endswith(']'):
                    subdomain = [t.strip() for t in raw_subdomain[1:-1].split(',') if t.strip()]
                elif ',' in raw_subdomain:
                    subdomain = [t.strip() for t in raw_subdomain.split(',') if t.strip()]
                else:
                    subdomain = raw_subdomain
        # Extract if/then/because fields (IF-THEN形式教訓)
        if if_cond is None:
            m_fif = re.match(r'- \*\*if\*\*:\s*(.+)', sline)
            if m_fif:
                if_cond = m_fif.group(1).strip()
        if then_action is None:
            m_fthen = re.match(r'- \*\*then\*\*:\s*(.+)', sline)
            if m_fthen:
                then_action = m_fthen.group(1).strip()
        if because_reason is None:
            m_fbecause = re.match(r'- \*\*because\*\*:\s*(.+)', sline)
            if m_fbecause:
                because_reason = m_fbecause.group(1).strip()
        # Extract when/how fields (activation trigger + execution steps)
        if when_cond is None:
            m_fwhen = re.match(r'- \*\*when\*\*:\s*(.+)', sline)
            if m_fwhen:
                when_cond = m_fwhen.group(1).strip()
        if how_action is None:
            m_fhow = re.match(r'- \*\*how\*\*:\s*(.+)', sline)
            if m_fhow:
                how_action = m_fhow.group(1).strip()
        # Extract retired field
        if retired is None:
            m_fretired = re.match(r'- \*\*retired\*\*:\s*(.+)', sline)
            if m_fretired:
                retired = m_fretired.group(1).strip().lower() == 'true'
        # Extract target_files from **target_files** field
        if target_files is None:
            m_ftf = re.match(r'- \*\*target_files\*\*:\s*\[(.+)\]', sline)
            if m_ftf:
                target_files = [t.strip() for t in m_ftf.group(1).split(',')]
        # Extract retired_at field
        if retired_at is None:
            m_fretired_at = re.match(r'- \*\*retired_at\*\*:\s*(.+)', sline)
            if m_fretired_at:
                retired_at = m_fretired_at.group(1).strip()
        # Get summary from **発生**/**問題**/**課題** fields or plain content
        if len(summary_parts) < 2 and (sline.startswith('- **発生**:') or sline.startswith('- **問題**:') or sline.startswith('- **課題**:')):
            text = re.sub(r'^- \*\*[^*]+\*\*:\s*', '', sline)
            summary_parts.append(text)
        elif len(summary_parts) < 2 and sline and not sline.startswith('```') and not sline.startswith('|'):
            # Skip metadata fields for summary
            if not re.match(r'^- \*\*(日付|出典|記録者|status|deprecated_by|merged_from|tags|subdomain|target_files|when|how|if|then|because|retired|retired_at|原因|影響|対策|教訓|修正|参照|結果)\*\*:', sline):
                if sline.startswith('- '):
                    summary_parts.append(sline[2:])
                elif not sline.startswith('**') and not sline.startswith('#'):
                    summary_parts.append(sline)
        j += 1

    summary = ' '.join(summary_parts)[:200].strip() if summary_parts else title

    entry = {'id': lesson_id, 'title': title, 'summary': summary, 'category': current_category}
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
    if tags:
        entry['tags'] = tags
    if when_cond:
        entry['when'] = when_cond
    if how_action:
        entry['how'] = how_action
    if subdomain:
        entry['subdomain'] = subdomain
    if retired:
        entry['retired'] = True
    if retired_at:
        entry['retired_at'] = retired_at
    # IF-THEN形式フィールド
    if if_cond or then_action or because_reason:
        if_then = {}
        if if_cond:
            if_then['if'] = if_cond
        if then_action:
            if_then['then'] = then_action
        if because_reason:
            if_then['because'] = because_reason
        entry['if_then'] = if_then

    # 明示的target_files（markdownフィールド）を優先
    if target_files:
        entry['target_files'] = target_files

    # 忍者成長速度改善2: target_files自動抽出（教訓テキストからファイルパスを検出）
    if 'target_files' not in entry:
        _tf_text = f'{entry.get("title", "")} {entry.get("summary", "")}'
        _tf_found = list(dict.fromkeys(_tf_path_pat.findall(_tf_text)))
        if not _tf_found:
            _tf_basenames = _tf_file_pat.findall(_tf_text)
            _tf_found = [bn for bn in dict.fromkeys(_tf_basenames) if bn in _tf_file_cache]
        if _tf_found:
            entry['target_files'] = _tf_found[:5]

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

# Sync injection_count and reference_count from lesson_impact.tsv with project boundary isolation.
impact_injection_count = defaultdict(int)
impact_reference_count = defaultdict(int)
if os.path.exists(impact_file):
    with open(impact_file, encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f, delimiter='\t')
        for row in reader:
            if not isinstance(row, dict):
                continue
            if (row.get('project') or '').strip() != project_id:
                continue
            lesson_id = (row.get('lesson_id') or '').strip()
            if not re.match(r'^L\d+$', lesson_id):
                continue
            # injection_count: action=injected, result!=PENDING
            if (row.get('action') or '').strip().lower() == 'injected':
                if (row.get('result') or '').strip().upper() != 'PENDING':
                    impact_injection_count[lesson_id] += 1
            # reference_count: referenced=yes
            if (row.get('referenced') or '').strip().lower() == 'yes':
                impact_reference_count[lesson_id] += 1

# Preserve score fields from archive (primary) + index (fallback for lesson_update_score.sh writes)
score_data = {}
old_data = None
for _score_src in [archive_file, index_file]:
    try:
        with open(_score_src, encoding='utf-8') as cf:
            src_data = yaml.safe_load(cf)
        if old_data is None:
            old_data = src_data
        for old_lesson in (src_data or {}).get('lessons', []):
            lid = old_lesson.get('id')
            if not lid:
                continue
            if lid not in score_data:
                score_data[lid] = {
                    'helpful_count': to_int(old_lesson.get('helpful_count', 0)),
                    'harmful_count': to_int(old_lesson.get('harmful_count', 0)),
                    'injection_count': to_int(old_lesson.get('injection_count', 0)),
                    'reference_count': to_int(old_lesson.get('reference_count', 0)),
                    'last_referenced': old_lesson.get('last_referenced'),
                    'tags': old_lesson.get('tags'),
                    'subdomain': old_lesson.get('subdomain'),
                }
            else:
                # Merge: take max of each count (scores only go up)
                for _f in ('helpful_count', 'harmful_count', 'injection_count', 'reference_count'):
                    score_data[lid][_f] = max(
                        to_int(score_data[lid].get(_f, 0)),
                        to_int(old_lesson.get(_f, 0)),
                    )
                _old_ref = old_lesson.get('last_referenced')
                if _old_ref and (not score_data[lid]['last_referenced'] or str(_old_ref) > str(score_data[lid]['last_referenced'])):
                    score_data[lid]['last_referenced'] = _old_ref
    except FileNotFoundError:
        continue
    except Exception:
        continue

# Merge score fields into new lessons (preserve existing, default for new)
for lesson in lessons:
    lid = lesson.get('id')
    if lid in score_data:
        lesson['helpful_count'] = score_data[lid]['helpful_count']
        lesson['harmful_count'] = score_data[lid]['harmful_count']
        lesson['injection_count'] = max(
            to_int(score_data[lid]['injection_count']),
            impact_injection_count.get(lid, 0),
        )
        lesson['reference_count'] = max(
            to_int(score_data[lid]['reference_count']),
            impact_reference_count.get(lid, 0),
        )
        lesson['last_referenced'] = score_data[lid]['last_referenced']
        # Tags priority: SSOT > cache
        if 'tags' not in lesson and score_data[lid].get('tags'):
            lesson['tags'] = score_data[lid]['tags']
        if 'subdomain' not in lesson and score_data[lid].get('subdomain'):
            lesson['subdomain'] = score_data[lid]['subdomain']
    else:
        lesson['helpful_count'] = 0
        lesson['harmful_count'] = 0
        lesson['injection_count'] = impact_injection_count.get(lid, 0)
        lesson['reference_count'] = impact_reference_count.get(lid, 0)
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

# Report deletions: compare with existing archive before overwrite
new_ids = {l['id'] for l in lessons}
if old_data is not None:
    old_ids = {l['id'] for l in old_data.get('lessons', [])}
    deleted = old_ids - new_ids
    added = new_ids - old_ids
    if deleted:
        print(f'Deleted from archive: {sorted(deleted)}')
    if added:
        print(f'Added to archive: {sorted(added)}')

# Write ARCHIVE (full data)
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(archive_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(header)
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2, sort_keys=False)
    os.replace(tmp_path, archive_file)
except Exception:
    os.unlink(tmp_path)
    raise

# Write INDEX (active lessons only, compact Vercel-style, ≤500 lines)
active_lessons = [l for l in lessons
                  if str(l.get('status', 'confirmed')).lower() != 'deprecated'
                  and not l.get('deprecated')]

# Build index entries using yaml.dump for proper escaping
class FlowDict(dict): pass
class FlowList(list): pass
def _fd_rep(dumper, data):
    return dumper.represent_mapping('tag:yaml.org,2002:map', data, flow_style=True)
def _fl_rep(dumper, data):
    return dumper.represent_sequence('tag:yaml.org,2002:seq', data, flow_style=True)
yaml.add_representer(FlowDict, _fd_rep)
yaml.add_representer(FlowList, _fl_rep)

index_entries = []
for l in active_lessons:
    entry = FlowDict({
        'id': l['id'],
        'title': l.get('title', ''),
        'summary': (l.get('summary') or l.get('title', ''))[:80],
        'tags': FlowList(l.get('tags', ['universal'])),
    })
    if l.get('subdomain'):
        entry['subdomain'] = l['subdomain']
    if l.get('when'):
        entry['when'] = l['when']
    if l.get('how'):
        entry['how'] = l['how']
    if l.get('target_files'):
        entry['target_files'] = FlowList(l['target_files'])
    if l.get('retired'):
        entry['retired'] = True
    index_entries.append(entry)

index_data = {
    'ssot_path': ssot_file,
    'last_synced': datetime.now().strftime('%Y-%m-%dT%H:%M:%S'),
    'archive_path': archive_file,
    'lesson_count': len(index_entries),
    'lessons': index_entries,
}

index_header = (
    f'# Index — full detail in lessons_archive.yaml\n'
    f'# Auto-generated by sync_lessons.sh — DO NOT EDIT DIRECTLY\n'
)
tmp_fd2, tmp_path2 = tempfile.mkstemp(dir=os.path.dirname(index_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd2, 'w', encoding='utf-8') as f:
        f.write(index_header)
        yaml.dump(index_data, f, default_flow_style=False, allow_unicode=True, indent=2, sort_keys=False, width=10000)
    os.replace(tmp_path2, index_file)
except Exception:
    os.unlink(tmp_path2)
    raise

print(f'Synced {len(lessons)} lessons: archive={archive_file}, index={index_file} ({len(active_lessons)} active)')

# Category summary
cat_stats = defaultdict(lambda: {'total': 0, 'confirmed': 0, 'deprecated': 0, 'draft': 0})
for lesson in lessons:
    cat = lesson.get('category', '未分類')
    cat_stats[cat]['total'] += 1
    st = lesson.get('status', 'confirmed')
    if st in ('confirmed', 'deprecated', 'draft'):
        cat_stats[cat][st] += 1
    else:
        cat_stats[cat]['confirmed'] += 1

print('Category summary:')
for cat in sorted(cat_stats.keys()):
    s = cat_stats[cat]
    parts = []
    if s['confirmed']:
        parts.append(f"{s['confirmed']} confirmed")
    if s['deprecated']:
        parts.append(f"{s['deprecated']} deprecated")
    if s['draft']:
        parts.append(f"{s['draft']} draft")
    print(f"  {cat}: {s['total']}件 ({', '.join(parts)})")

# Postcondition: SSOT入力件数とYAML出力件数の乖離検知
try:
    _ssot_count = len(re.findall(r'^### L\d+', content, re.MULTILINE))
    _out_count = len(lessons)
    _div = abs(_ssot_count - _out_count) / _ssot_count * 100 if _ssot_count > 0 else 0.0
    if _div > 10:
        _msg = f'[sync_lessons] INFO: 教訓件数乖離 (expected={_ssot_count} actual={_out_count})'
        print(_msg, file=sys.stderr)
        try:
            import subprocess
            _script_dir = os.environ.get('SCRIPT_DIR', '')
            _ntfy = os.path.join(_script_dir, 'scripts', 'ntfy_batch.sh') if _script_dir else 'scripts/ntfy_batch.sh'
            subprocess.run(['bash', _ntfy, _msg], timeout=10)
        except Exception:
            pass
    elif _div > 0:
        print(f'[sync_lessons] WARN: 教訓件数乖離 (expected={_ssot_count} actual={_out_count})', file=sys.stderr)
except Exception as _e:
    print(f'[sync_lessons] WARN: postcondition failed: {_e}', file=sys.stderr)
PYEOF

) 200>"$LOCKFILE"
