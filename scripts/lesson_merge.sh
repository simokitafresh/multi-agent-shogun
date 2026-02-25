#!/bin/bash
# lesson_merge.sh — 2つの教訓を統合し、元教訓をdeprecatedにする
# Usage: bash scripts/lesson_merge.sh <project> <source_id_1> <source_id_2> "<merged_title>" "<merged_summary>"
# Example: bash scripts/lesson_merge.sh infra L025 L027 "統合タイトル" "統合サマリー"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${1:-}"
SOURCE_ID_1="${2:-}"
SOURCE_ID_2="${3:-}"
MERGED_TITLE="${4:-}"
MERGED_SUMMARY="${5:-}"

# ── 引数検証 ──
if [ -z "$PROJECT_ID" ] || [ -z "$SOURCE_ID_1" ] || [ -z "$SOURCE_ID_2" ] || [ -z "$MERGED_TITLE" ] || [ -z "$MERGED_SUMMARY" ]; then
    echo "Usage: lesson_merge.sh <project> <source_id_1> <source_id_2> \"<merged_title>\" \"<merged_summary>\"" >&2
    echo "Example: bash scripts/lesson_merge.sh infra L025 L027 \"統合タイトル\" \"統合サマリー\"" >&2
    exit 1
fi

if [ "$SOURCE_ID_1" == "$SOURCE_ID_2" ]; then
    echo "ERROR: source_id_1 and source_id_2 must be different (both are $SOURCE_ID_1)" >&2
    exit 1
fi

# ── プロジェクトパス取得 ──
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
if [ ! -f "$LESSONS_FILE" ]; then
    echo "ERROR: SSOT not found: $LESSONS_FILE" >&2
    exit 1
fi

# ── Step 1: ソースID存在確認 ──
for SID in "$SOURCE_ID_1" "$SOURCE_ID_2"; do
    if ! grep -qE "^### ${SID}:" "$LESSONS_FILE"; then
        echo "ERROR: $SID not found in $LESSONS_FILE" >&2
        exit 1
    fi
done

echo "[lesson_merge] Verified: $SOURCE_ID_1 and $SOURCE_ID_2 exist in SSOT"

# ── Step 2: lesson_write.sh経由で新教訓登録 ──
OUTPUT=$(bash "$SCRIPT_DIR/scripts/lesson_write.sh" \
    "$PROJECT_ID" \
    "$MERGED_TITLE" \
    "$MERGED_SUMMARY" \
    "merged(${SOURCE_ID_1}+${SOURCE_ID_2})" \
    "lesson_merge" \
    "" \
    --force 2>&1) || {
    echo "ERROR: lesson_write.sh failed:" >&2
    echo "$OUTPUT" >&2
    exit 1
}

# Extract new lesson ID (e.g., "L036 added to ...")
NEW_ID=$(echo "$OUTPUT" | grep -oP 'L\d+' | head -1)

if [ -z "$NEW_ID" ]; then
    echo "ERROR: Failed to extract new lesson ID from output:" >&2
    echo "$OUTPUT" >&2
    exit 1
fi

echo "[lesson_merge] Created: $NEW_ID via lesson_write.sh"

# ── Step 3: SSOTパッチ (merged_from + deprecated_by + status) ──
LOCKFILE="${LESSONS_FILE}.lock"
(
    flock -w 10 200 || { echo "ERROR: Could not acquire lock" >&2; exit 1; }

    export LESSONS_FILE NEW_ID SOURCE_ID_1 SOURCE_ID_2
    python3 << 'PYEOF'
import re, os

lessons_file = os.environ["LESSONS_FILE"]
new_id = os.environ["NEW_ID"]
source_id_1 = os.environ["SOURCE_ID_1"]
source_id_2 = os.environ["SOURCE_ID_2"]

with open(lessons_file, encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')
output = []
i = 0

while i < len(lines):
    line = lines[i]

    # ── 新統合教訓: status:confirmed + merged_from追加 ──
    if re.match(rf'^### {re.escape(new_id)}:\s', line):
        output.append(line)
        i += 1
        section_lines = []
        while i < len(lines):
            if lines[i].startswith('### ') or lines[i].startswith('## '):
                break
            section_lines.append(lines[i])
            i += 1

        last_meta_idx = -1
        has_status = False
        for idx, sl in enumerate(section_lines):
            if re.match(r'^- \*\*\w+\*\*:', sl):
                last_meta_idx = idx
                if re.match(r'^- \*\*status\*\*:', sl):
                    has_status = True

        insertions = []
        if not has_status:
            insertions.append('- **status**: confirmed')
        insertions.append(f'- **merged_from**: [{source_id_1}, {source_id_2}]')

        if last_meta_idx >= 0:
            for j, ins in enumerate(insertions):
                section_lines.insert(last_meta_idx + 1 + j, ins)
        else:
            section_lines = insertions + section_lines

        output.extend(section_lines)
        continue

    # ── ソース教訓: deprecated_by + status:deprecated ──
    if re.match(rf'^### ({re.escape(source_id_1)}|{re.escape(source_id_2)}):\s', line):
        output.append(line)
        i += 1
        section_lines = []
        while i < len(lines):
            if lines[i].startswith('### ') or lines[i].startswith('## '):
                break
            section_lines.append(lines[i])
            i += 1

        new_section = []
        has_status = False
        has_deprecated_by = False
        last_meta_idx = -1

        for idx, sl in enumerate(section_lines):
            if re.match(r'^- \*\*status\*\*:', sl):
                new_section.append('- **status**: deprecated')
                has_status = True
                last_meta_idx = len(new_section) - 1
            elif re.match(r'^- \*\*deprecated_by\*\*:', sl):
                new_section.append(f'- **deprecated_by**: {new_id}')
                has_deprecated_by = True
                last_meta_idx = len(new_section) - 1
            else:
                if re.match(r'^- \*\*\w+\*\*:', sl):
                    last_meta_idx = len(new_section)
                new_section.append(sl)

        insertions = []
        if not has_status:
            insertions.append('- **status**: deprecated')
        if not has_deprecated_by:
            insertions.append(f'- **deprecated_by**: {new_id}')

        if insertions:
            if last_meta_idx >= 0:
                for j, ins in enumerate(insertions):
                    new_section.insert(last_meta_idx + 1 + j, ins)
            else:
                new_section = insertions + new_section

        output.extend(new_section)
        continue

    output.append(line)
    i += 1

with open(lessons_file, 'w', encoding='utf-8') as f:
    f.write('\n'.join(output))

print(f'[lesson_merge] Patched SSOT: {new_id} (merged_from), {source_id_1} + {source_id_2} (deprecated)')
PYEOF

) 200>"$LOCKFILE"

# ── Step 4: YAML再同期 ──
bash "$SCRIPT_DIR/scripts/sync_lessons.sh" "$PROJECT_ID"

# ── Step 5: context索引注記 ──
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
            export CONTEXT_FULL_PATH SOURCE_ID_1 SOURCE_ID_2 NEW_ID
            python3 << 'CTXEOF'
import re, os

ctx_path = os.environ["CONTEXT_FULL_PATH"]
source_ids = [os.environ["SOURCE_ID_1"], os.environ["SOURCE_ID_2"]]
new_id = os.environ["NEW_ID"]

with open(ctx_path, encoding='utf-8') as f:
    content = f.read()

modified = False
for sid in source_ids:
    pattern = rf'^(- {re.escape(sid)}:.+?)$'
    matches = list(re.finditer(pattern, content, re.MULTILINE))
    for m in matches:
        old_line = m.group(1)
        annotation = f'[統合→{new_id}]'
        if annotation not in old_line:
            new_line = f'{old_line} {annotation}'
            content = content.replace(old_line, new_line, 1)
            modified = True
            print(f'[lesson_merge] context annotated: {sid} → +{annotation}')

if modified:
    with open(ctx_path, 'w', encoding='utf-8') as f:
        f.write(content)
else:
    for sid in source_ids:
        print(f'[lesson_merge] NOTE: {sid} not found in context — manual annotation may be needed')
CTXEOF
        ) 201>"${CONTEXT_FULL_PATH}.lock"
    fi
fi

echo "[lesson_merge] Complete: ${SOURCE_ID_1} + ${SOURCE_ID_2} → ${NEW_ID}"
