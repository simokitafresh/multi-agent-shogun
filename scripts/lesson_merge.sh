#!/bin/bash
# lesson_merge.sh — 2教訓を1つに統合するスクリプト（排他ロック付き）
# Usage: bash scripts/lesson_merge.sh <project> <source_id_1> <source_id_2> "<merged_title>" "<merged_summary>"
# Example: bash scripts/lesson_merge.sh infra L026 L033 "SSOT陳腐化防止" "追加onlyの教訓蓄積は陳腐化を招く。deprecation連鎖で管理せよ"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${1:-}"
SOURCE_ID_1="${2:-}"
SOURCE_ID_2="${3:-}"
MERGED_TITLE="${4:-}"
MERGED_SUMMARY="${5:-}"

# Validate arguments
if [ -z "$PROJECT_ID" ] || [ -z "$SOURCE_ID_1" ] || [ -z "$SOURCE_ID_2" ] || [ -z "$MERGED_TITLE" ] || [ -z "$MERGED_SUMMARY" ]; then
    echo "Usage: lesson_merge.sh <project> <source_id_1> <source_id_2> \"<merged_title>\" \"<merged_summary>\"" >&2
    echo "Example: bash scripts/lesson_merge.sh infra L026 L033 \"統合タイトル\" \"統合サマリー\"" >&2
    exit 1
fi

# Normalize IDs (accept L026 or L26 → L026)
normalize_id() {
    local raw="$1"
    python3 -c "s='$raw'; n=int(s.replace('L','')); print(f'L{n:03d}')"
}
SOURCE_ID_1=$(normalize_id "$SOURCE_ID_1")
SOURCE_ID_2=$(normalize_id "$SOURCE_ID_2")

if [ "$SOURCE_ID_1" == "$SOURCE_ID_2" ]; then
    echo "ERROR: source_id_1 と source_id_2 が同じ ($SOURCE_ID_1)" >&2
    exit 1
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
    exit 1
fi

LESSONS_FILE="$PROJECT_PATH/tasks/lessons.md"
LOCKFILE="${LESSONS_FILE}.lock"

if [ ! -f "$LESSONS_FILE" ]; then
    echo "ERROR: $LESSONS_FILE not found." >&2
    exit 1
fi

TIMESTAMP=$(date "+%Y-%m-%d")

# Temp file for passing new lesson ID out of flock subshell
NEW_ID_FILE=$(mktemp)
trap 'rm -f "$NEW_ID_FILE"' EXIT

# Atomic merge with flock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 10 200 || exit 1

        export LESSONS_FILE TIMESTAMP MERGED_TITLE MERGED_SUMMARY SOURCE_ID_1 SOURCE_ID_2 NEW_ID_FILE
        python3 << 'PYEOF'
import re, os, sys

lessons_file = os.environ["LESSONS_FILE"]
timestamp = os.environ["TIMESTAMP"]
merged_title = os.environ["MERGED_TITLE"]
merged_summary = os.environ["MERGED_SUMMARY"]
source_id_1 = os.environ["SOURCE_ID_1"]
source_id_2 = os.environ["SOURCE_ID_2"]
new_id_file = os.environ["NEW_ID_FILE"]

with open(lessons_file, encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')

# ── Step 1: Find max ID ──
max_id = 0
for m in re.finditer(r'^## (\d+)\.', content, re.MULTILINE):
    num = int(m.group(1))
    if num > max_id:
        max_id = num
for m in re.finditer(r'^### L(\d+):', content, re.MULTILINE):
    num = int(m.group(1))
    if num > max_id:
        max_id = num

new_id_num = max_id + 1
new_id_str = f'L{new_id_num:03d}'

# ── Step 2: Verify source entries exist and are not already deprecated ──
def find_entry_idx(lines, lesson_id):
    """Find lesson entry start line index."""
    pattern = rf'^### {re.escape(lesson_id)}[:：]\s*'
    for i, line in enumerate(lines):
        if re.match(pattern, line):
            return i
    return None

idx_1 = find_entry_idx(lines, source_id_1)
idx_2 = find_entry_idx(lines, source_id_2)

if idx_1 is None:
    print(f'ERROR: {source_id_1} が SSOT に見つからない', file=sys.stderr)
    sys.exit(1)
if idx_2 is None:
    print(f'ERROR: {source_id_2} が SSOT に見つからない', file=sys.stderr)
    sys.exit(1)

def check_deprecated(lines, start_idx):
    """Check if entry already has status: deprecated."""
    j = start_idx + 1
    while j < len(lines):
        sline = lines[j].strip()
        if sline.startswith('### ') or sline.startswith('## '):
            break
        if re.match(r'^- \*\*status\*\*:\s*deprecated', sline):
            return True
        j += 1
    return False

if check_deprecated(lines, idx_1):
    print(f'ERROR: {source_id_1} は既にdeprecated', file=sys.stderr)
    sys.exit(1)
if check_deprecated(lines, idx_2):
    print(f'ERROR: {source_id_2} は既にdeprecated', file=sys.stderr)
    sys.exit(1)

# ── Step 3: Mark source entries as deprecated ──
# Process the one with higher index first to avoid line-shift issues
def deprecate_entry(lines, start_idx, new_id):
    """Add deprecated_by and set status to deprecated."""
    j = start_idx + 1
    has_status = False
    last_meta = start_idx  # Track last metadata line position

    # First pass: find metadata boundaries and status field
    while j < len(lines):
        sline = lines[j].strip()
        if sline.startswith('### ') or sline.startswith('## '):
            break
        if re.match(r'^- \*\*[^*]+\*\*:', sline):
            last_meta = j
            if re.match(r'^- \*\*status\*\*:', sline):
                lines[j] = '- **status**: deprecated'
                has_status = True
        j += 1

    # Insert deprecated_by after last metadata line
    dep_line = f'- **deprecated_by**: {new_id}'
    lines.insert(last_meta + 1, dep_line)

    # If no status field existed, insert it too
    if not has_status:
        lines.insert(last_meta + 1, '- **status**: deprecated')

    return lines

# Process higher index first to avoid shift issues
if idx_1 > idx_2:
    lines = deprecate_entry(lines, idx_1, new_id_str)
    lines = deprecate_entry(lines, idx_2, new_id_str)
else:
    lines = deprecate_entry(lines, idx_2, new_id_str)
    lines = deprecate_entry(lines, idx_1, new_id_str)

# ── Step 4: Build and append new merged entry ──
entry = f'\n### {new_id_str}: {merged_title}\n'
entry += f'- **status**: confirmed\n'
entry += f'- **日付**: {timestamp}\n'
entry += f'- **出典**: lesson_merge({source_id_1}+{source_id_2})\n'
entry += f'- **記録者**: karo\n'
entry += f'- **merged_from**: [{source_id_1}, {source_id_2}]\n'
entry += f'- {merged_summary}\n'

new_content = '\n'.join(lines)
new_content = new_content.rstrip('\n') + '\n' + entry

with open(lessons_file, 'w', encoding='utf-8') as f:
    f.write(new_content)

with open(new_id_file, 'w') as f:
    f.write(new_id_str)

print(f'[lesson_merge] {source_id_1} + {source_id_2} → {new_id_str} ({merged_title})')
print(f'[lesson_merge] {source_id_1}: deprecated_by={new_id_str}')
print(f'[lesson_merge] {source_id_2}: deprecated_by={new_id_str}')
PYEOF

    ) 200>"$LOCKFILE"; then

        NEW_LESSON_ID=""
        if [ -f "$NEW_ID_FILE" ]; then
            NEW_LESSON_ID=$(cat "$NEW_ID_FILE")
        fi

        # Sync SSOT → YAML cache
        bash "$SCRIPT_DIR/scripts/sync_lessons.sh" "$PROJECT_ID"

        # Context索引更新: 旧エントリに[統合→新ID]注釈 + 新エントリ追記
        if [ -n "$NEW_LESSON_ID" ]; then
            CONTEXT_FILE=$(python3 -c "
import yaml
with open('$SCRIPT_DIR/config/projects.yaml', encoding='utf-8') as f:
    cfg = yaml.safe_load(f)
for p in cfg.get('projects', []):
    if p['id'] == '$PROJECT_ID':
        print(p.get('context_file', ''))
        break
")
            if [ -n "$CONTEXT_FILE" ]; then
                CONTEXT_FULL_PATH="$SCRIPT_DIR/$CONTEXT_FILE"
                if [ -f "$CONTEXT_FULL_PATH" ]; then
                    (
                        flock -w 10 201 || { echo "WARN: context lock timeout" >&2; exit 0; }
                        export CONTEXT_FULL_PATH NEW_LESSON_ID SOURCE_ID_1 SOURCE_ID_2 MERGED_TITLE
                        python3 << 'CTXEOF'
import re, os

ctx_path = os.environ["CONTEXT_FULL_PATH"]
new_id = os.environ["NEW_LESSON_ID"]
src_1 = os.environ["SOURCE_ID_1"]
src_2 = os.environ["SOURCE_ID_2"]
title = os.environ["MERGED_TITLE"]

with open(ctx_path, encoding='utf-8') as f:
    content = f.read()

changed = False

# Annotate old entries with [統合→新ID]
for src_id in [src_1, src_2]:
    pattern = rf'^(- {re.escape(src_id)}:.+)$'
    def annotate(m, tag=f'[統合→{new_id}]'):
        line = m.group(1)
        if tag in line:
            return line
        return f'{line} {tag}'
    new_content = re.sub(pattern, annotate, content, flags=re.MULTILINE)
    if new_content != content:
        content = new_content
        changed = True

# Add new merged entry to lessons section (dedup)
if f'- {new_id}:' not in content:
    entry = f"- {new_id}: {title}（{src_1}+{src_2}統合）"

    section_pattern = re.compile(r'^(##\s+.*(?:教訓|[Ll]esson).*)', re.MULTILINE)
    matches = list(section_pattern.finditer(content))

    if matches:
        last_match = matches[-1]
        after_section = content[last_match.end():]
        next_heading = re.search(r'^## ', after_section, re.MULTILINE)
        if next_heading:
            insert_pos = last_match.end() + next_heading.start()
            content = content[:insert_pos].rstrip('\n') + '\n' + entry + '\n\n' + content[insert_pos:]
        else:
            content = content.rstrip('\n') + '\n' + entry + '\n'
    else:
        content = content.rstrip('\n') + '\n\n## 教訓索引（自動追記）\n\n' + entry + '\n'
    changed = True

if changed:
    with open(ctx_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"[lesson_merge] context updated: {ctx_path}")
else:
    print(f"[lesson_merge] context: no changes needed")
CTXEOF
                    ) 201>"${CONTEXT_FULL_PATH}.lock"
                fi
            fi
        fi

        echo "[lesson_merge] Done. New lesson: ${NEW_LESSON_ID}"
        exit 0
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[lesson_merge] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[lesson_merge] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
