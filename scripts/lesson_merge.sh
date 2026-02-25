#!/bin/bash
# lesson_merge.sh — 2教訓を統合し新教訓を生成、元教訓をdeprecated化
# Usage: bash scripts/lesson_merge.sh <project> <source_id_1> <source_id_2> "<merged_title>" "<merged_summary>"
# Example: bash scripts/lesson_merge.sh infra L006 L023 "教訓自動化は入力品質先行が必須" "lesson_candidateからの転記自動化が最適解..."

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${1:-}"
SRC1="${2:-}"
SRC2="${3:-}"
MERGED_TITLE="${4:-}"
MERGED_SUMMARY="${5:-}"

# Validate arguments
if [ -z "$PROJECT" ] || [ -z "$SRC1" ] || [ -z "$SRC2" ] || [ -z "$MERGED_TITLE" ] || [ -z "$MERGED_SUMMARY" ]; then
    echo "Usage: lesson_merge.sh <project> <source_id_1> <source_id_2> \"<merged_title>\" \"<merged_summary>\"" >&2
    exit 1
fi

# Normalize lesson IDs (accept L6 or L006)
SRC1=$(printf "L%03d" "$(echo "$SRC1" | sed -E 's/^L0*//')")
SRC2=$(printf "L%03d" "$(echo "$SRC2" | sed -E 's/^L0*//')")

# Get project path
PROJECT_PATH=$(python3 -c "
import yaml
with open('$SCRIPT_DIR/config/projects.yaml', encoding='utf-8') as f:
    cfg = yaml.safe_load(f)
for p in cfg.get('projects', []):
    if p['id'] == '$PROJECT':
        print(p['path'])
        break
")

if [ -z "$PROJECT_PATH" ]; then
    echo "ERROR: Project '$PROJECT' not found in config/projects.yaml" >&2
    exit 1
fi

SSOT="$PROJECT_PATH/tasks/lessons.md"
LOCKFILE="${SSOT}.lock"

if [ ! -f "$SSOT" ]; then
    echo "ERROR: SSOT not found: $SSOT" >&2
    exit 1
fi

# Verify source IDs exist and are not already deprecated
for sid in "$SRC1" "$SRC2"; do
    NUM=$(echo "$sid" | sed -E 's/^L0*//')
    if ! grep -qP "^### L0*${NUM}\s*[：:]" "$SSOT"; then
        echo "ERROR: $sid not found in $SSOT" >&2
        exit 1
    fi
done

echo "[lesson_merge] Merging: $SRC1 + $SRC2 → \"$MERGED_TITLE\""

# ── Step 1: Register new lesson via lesson_write.sh ──
OUTPUT=$(bash "$SCRIPT_DIR/scripts/lesson_write.sh" "$PROJECT" \
    "$MERGED_TITLE" "$MERGED_SUMMARY" "merge($SRC1+$SRC2)" "karo" "" --force)
echo "$OUTPUT"

# Extract new lesson ID
NEW_ID=$(echo "$OUTPUT" | grep -oP 'L\d+' | head -1)
if [ -z "$NEW_ID" ]; then
    echo "ERROR: Could not extract new lesson ID from lesson_write.sh output" >&2
    exit 1
fi
echo "[lesson_merge] New lesson created: $NEW_ID"

# ── Step 2: Add merged_from to new entry + deprecate sources (atomic, flock) ──
(
    flock -w 10 200 || { echo "ERROR: Could not acquire lock" >&2; exit 1; }

    export SSOT NEW_ID SRC1 SRC2
    python3 << 'PYEOF'
import re, os, sys, tempfile

ssot = os.environ["SSOT"]
new_id = os.environ["NEW_ID"]
src1 = os.environ["SRC1"]
src2 = os.environ["SRC2"]

with open(ssot, encoding='utf-8') as f:
    lines = f.readlines()

result = []
i = 0
while i < len(lines):
    line = lines[i]

    # Detect new entry heading → insert merged_from after it
    new_num = int(new_id.replace('L', ''))
    if re.match(rf'^### L0*{new_num}\s*[：:]', line):
        result.append(line)
        i += 1
        # Insert merged_from right after heading (before other metadata)
        result.append(f'- **merged_from**: [{src1}, {src2}]\n')
        continue

    # Detect source entries → insert deprecated_by + status: deprecated
    matched_src = False
    for src_id in [src1, src2]:
        src_num = int(src_id.replace('L', ''))
        if re.match(rf'^### L0*{src_num}\s*[：:]', line):
            result.append(line)
            i += 1
            # Insert deprecated_by and status: deprecated
            result.append(f'- **deprecated_by**: {new_id}\n')
            result.append(f'- **status**: deprecated\n')
            # Skip existing status/deprecated_by lines if any (avoid duplication)
            while i < len(lines):
                sline = lines[i]
                if re.match(r'^- \*\*(?:deprecated_by|status)\*\*:', sline):
                    i += 1  # skip old line
                    continue
                break
            matched_src = True
            break

    if not matched_src:
        # No match — pass through
        result.append(line)
        i += 1

new_content = ''.join(result)
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(ssot), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(new_content)
    os.replace(tmp_path, ssot)
except Exception:
    os.unlink(tmp_path)
    raise

print(f"[lesson_merge] Added merged_from to {new_id}, deprecated {src1} and {src2}")
PYEOF

) 200>"$LOCKFILE"

# ── Step 3: Annotate context index entries ──
CONTEXT_FILE=$(python3 -c "
import yaml
with open('$SCRIPT_DIR/config/projects.yaml', encoding='utf-8') as f:
    cfg = yaml.safe_load(f)
for p in cfg.get('projects', []):
    if p['id'] == '$PROJECT':
        cf = p.get('context_file', '')
        print(cf)
        for cfe in p.get('context_files', []):
            print(cfe['file'])
        break
")

if [ -n "$CONTEXT_FILE" ]; then
    for ctx_file in $CONTEXT_FILE; do
        CTX_FULL="$SCRIPT_DIR/$ctx_file"
        if [ ! -f "$CTX_FULL" ]; then continue; fi
        for SRC_ID in "$SRC1" "$SRC2"; do
            # Match only index lines starting with "- SRC_ID:" and not already annotated
            if grep -qP "^- ${SRC_ID}:.*(?<!\[統合→${NEW_ID}\])$" "$CTX_FULL"; then
                sed -i "/^- ${SRC_ID}:/s|$| [統合→${NEW_ID}]|" "$CTX_FULL"
                echo "[lesson_merge] Annotated $SRC_ID in $ctx_file"
            fi
        done
    done
fi

# ── Step 4: Re-sync YAML (picks up merged_from + deprecated_by + status) ──
echo "[lesson_merge] Syncing to YAML..."
bash "$SCRIPT_DIR/scripts/sync_lessons.sh" "$PROJECT"

echo "[lesson_merge] Complete: $SRC1 + $SRC2 → $NEW_ID"
