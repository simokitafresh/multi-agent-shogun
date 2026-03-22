#!/bin/bash
# lesson_write.sh — SSOT (DM-signal/tasks/lessons.md) への教訓追記（排他ロック付き）
# Usage: bash scripts/lesson_write.sh <project_id> "<title>" "<detail>" "<source_cmd>" "<author>" [cmd_id] [--strategic] [--tags "db,api"] [--if "condition"] [--then "action"] [--because "reason"]
# Tags: --tags "tag1,tag2" (explicit) or auto-inferred from title/detail. Default: universal
# Example: bash scripts/lesson_write.sh dm-signal "本番DBはPostgreSQL" "SQLiteに書くな" "cmd_079" "karo"
# Example: bash scripts/lesson_write.sh infra "Gate改修" "ゲート検証" "cmd_100" "saizo" "" --tags "gate,process"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${1:-}"
TITLE="${2:-}"
DETAIL="${3:-}"
SOURCE_CMD="${4:-}"
AUTHOR="${5:-karo}"
CMD_ID="${6:-""}"
STRATEGIC="${7:-""}"

# Scan for --force flag (bypasses duplicate check)
FORCE=0
for arg in "$@"; do
    if [ "$arg" == "--force" ]; then FORCE=1; fi
done

# Scan for --status flag (draft/confirmed, default: confirmed)
STATUS="confirmed"
prev_arg=""
for arg in "$@"; do
    if [ "$prev_arg" == "--status" ]; then STATUS="$arg"; fi
    prev_arg="$arg"
done
if [ "$STATUS" != "draft" ] && [ "$STATUS" != "confirmed" ]; then
    echo "ERROR: --status must be 'draft' or 'confirmed' (got: $STATUS)" >&2
    exit 1
fi

# Scan for --tags flag (comma-separated, e.g. "db,api,deploy". Default: auto-infer or universal)
TAGS=""
prev_arg=""
for arg in "$@"; do
    if [ "$prev_arg" == "--tags" ]; then TAGS="$arg"; fi
    prev_arg="$arg"
done

# Scan for --if/--then/--because flags (IF-THEN形式教訓, all optional)
IF_COND=""
THEN_ACTION=""
BECAUSE_REASON=""
prev_arg=""
for arg in "$@"; do
    if [ "$prev_arg" == "--if" ]; then IF_COND="$arg"; fi
    if [ "$prev_arg" == "--then" ]; then THEN_ACTION="$arg"; fi
    if [ "$prev_arg" == "--because" ]; then BECAUSE_REASON="$arg"; fi
    prev_arg="$arg"
done

# Scan for --retire flag (retire existing lesson)
RETIRE_ID=""
prev_arg=""
for arg in "$@"; do
    if [ "$prev_arg" == "--retire" ]; then RETIRE_ID="$arg"; fi
    prev_arg="$arg"
done

# ─── Retire mode: mark existing lesson as retired ───
if [ -n "$RETIRE_ID" ]; then
    if [ -z "$PROJECT_ID" ]; then
        echo "Usage: lesson_write.sh <project_id> --retire <lesson_id>" >&2
        exit 1
    fi

    if [[ "$PROJECT_ID" == cmd_* ]]; then
        echo "ERROR: 第1引数はproject_id（例: infra, dm-signal）。cmd_idではない。" >&2
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

    # Atomic modify with flock
    (
        flock -w 10 200 || { echo "ERROR: Could not acquire lock" >&2; exit 1; }

        export LESSONS_FILE RETIRE_ID TIMESTAMP
        python3 << 'RETIREPY'
import re, os, sys

lessons_file = os.environ["LESSONS_FILE"]
retire_id = os.environ["RETIRE_ID"]
timestamp = os.environ["TIMESTAMP"]

with open(lessons_file, encoding='utf-8') as f:
    content = f.read()

# Normalize lesson ID to LXXX format
m_id = re.match(r'^L?(\d+)$', retire_id)
if m_id:
    num = int(m_id.group(1))
    retire_id = f'L{num:03d}'

lines = content.split('\n')

# Find the lesson heading: ### LXXX: title
heading_idx = None
for i, line in enumerate(lines):
    if re.match(rf'^### {re.escape(retire_id)}\s*[:：]', line):
        heading_idx = i
        break

if heading_idx is None:
    print(f'ERROR: {retire_id} not found in {lessons_file}', file=sys.stderr)
    sys.exit(1)

# Find the last metadata line after the heading (lines starting with - **)
insert_idx = heading_idx + 1
already_retired = False
for j in range(heading_idx + 1, len(lines)):
    stripped = lines[j].strip()
    if stripped.startswith('- **'):
        insert_idx = j + 1
        if '**retired**' in stripped:
            already_retired = True
    elif stripped == '':
        continue
    else:
        break

if already_retired:
    print(f'{retire_id} is already retired')
    sys.exit(0)

# Insert retired fields after last metadata line
retired_lines = [f'- **retired**: true', f'- **retired_at**: {timestamp}']
new_lines = lines[:insert_idx] + retired_lines + lines[insert_idx:]

with open(lessons_file, 'w', encoding='utf-8') as f:
    f.write('\n'.join(new_lines))

print(f'{retire_id} retired in {lessons_file}')
RETIREPY

    ) 200>"$LOCKFILE"

    # Re-sync YAML cache
    bash "$SCRIPT_DIR/scripts/sync_lessons.sh" "$PROJECT_ID"

    echo "[lesson_write] $RETIRE_ID retired successfully"
    exit 0
fi

# Validate arguments
if [ -z "$PROJECT_ID" ] || [ -z "$TITLE" ] || [ -z "$DETAIL" ]; then
    echo "Usage: lesson_write.sh <project_id> <title> <detail> [source_cmd] [author]" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

if [[ "$PROJECT_ID" == cmd_* ]]; then
    echo "ERROR: 第1引数はproject_id（例: infra, dm-signal）。cmd_idではない。" >&2
    echo "Usage: lesson_write.sh <project_id> <title> <detail> [source_cmd] [author]" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

# Summary quality gate (cmd_158)
DETAIL_LEN=${#DETAIL}
if [ "$DETAIL_LEN" -lt 10 ]; then
    echo "ERROR: summary(detail)が10文字未満 (${DETAIL_LEN}文字)。具体的な内容を記載せよ" >&2
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

# Verify lessons file exists
if [ ! -f "$LESSONS_FILE" ]; then
    echo "ERROR: $LESSONS_FILE not found." >&2
    exit 1
fi

TIMESTAMP=$(date "+%Y-%m-%d")

# Temp file for passing lesson ID out of flock subshell
LESSON_ID_FILE=$(mktemp)
trap 'rm -f "$LESSON_ID_FILE"' EXIT

# Atomic append with flock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 10 200 || exit 1

        # Find max ID and append new entry
        export LESSONS_FILE TIMESTAMP TITLE DETAIL SOURCE_CMD AUTHOR FORCE LESSON_ID_FILE STATUS TAGS SCRIPT_DIR IF_COND THEN_ACTION BECAUSE_REASON
        python3 << 'PYEOF'
import re, os, sys, yaml
from difflib import SequenceMatcher

lessons_file = os.environ["LESSONS_FILE"]
timestamp = os.environ["TIMESTAMP"]
title = os.environ["TITLE"]
detail = os.environ["DETAIL"]
source_cmd = os.environ["SOURCE_CMD"]
author = os.environ["AUTHOR"]

with open(lessons_file, encoding='utf-8') as f:
    content = f.read()

# Find max numeric ID from:
#   ## N. pattern → N
#   ### L{N}: pattern → N
max_id = 0

for m in re.finditer(r'^## (\d+)\.', content, re.MULTILINE):
    num = int(m.group(1))
    if num > max_id:
        max_id = num

for m in re.finditer(r'^### L(\d+):', content, re.MULTILINE):
    num = int(m.group(1))
    if num > max_id:
        max_id = num

new_id = max_id + 1
new_id_str = f'L{new_id:03d}'

# Duplicate title check (bypass with --force)
existing = []
for m in re.finditer(r'^### L(\d+): (.+)$', content, re.MULTILINE):
    existing.append((f'L{int(m.group(1)):03d}', m.group(2)))

# Tag inference (AC1: config/lesson_tags.yaml辞書参照)
tags_str = os.environ.get("TAGS", "")
if not tags_str:
    # (AC1-a) config/lesson_tags.yaml から辞書読み込み
    script_dir = os.environ.get("SCRIPT_DIR", "")
    tags_yaml_path = os.path.join(script_dir, "config", "lesson_tags.yaml") if script_dir else ""
    tag_rules = []
    if tags_yaml_path and os.path.exists(tags_yaml_path):
        try:
            with open(tags_yaml_path, encoding='utf-8') as tf:
                tdata = yaml.safe_load(tf)
            for rule in (tdata or {}).get("tag_rules", []):
                tag = rule.get("tag", "")
                patterns = rule.get("patterns", [])
                if tag and patterns:
                    for pat in patterns:
                        tag_rules.append((pat, tag))
        except Exception:
            tag_rules = []

    # Fallback: YAML不在または空の場合、従来のハードコード値
    if not tag_rules:
        tag_rules = [
            (r'(?i)db|database|SQL|PostgreSQL', 'db'),
            (r'(?i)api|endpoint|http|rest', 'api'),
            (r'(?i)frontend|react|component|ui|visibility|dashboard', 'frontend'),
            (r'(?i)deploy|production|本番|render', 'deploy'),
            (r'(?i)pipeline|recalculate|signal|momentum|parity|パリティ', 'pipeline'),
            (r'(?i)test|parity|verify|検証|パリティ', 'testing'),
            (r'(?i)review|レビュー', 'review'),
            (r'(?i)偵察|scout|調査|investigation', 'recon'),
            (r'(?i)process|workflow|フロー|手順', 'process'),
            (r'(?i)inbox|ntfy|notification|通知', 'communication'),
            (r'(?i)gate|ゲート', 'gate'),
        ]

    text = " " + (title + " " + detail).lower() + " "
    inferred = []
    for pat, tag in tag_rules:
        if tag not in inferred and re.search(pat, text):
            inferred.append(tag)
    tags = inferred if inferred else ["universal"]
else:
    # (AC1-b) --tags引数が指定されていればそのまま使用
    tags = [t.strip() for t in tags_str.split(",") if t.strip()]
    if not tags:
        tags = ["universal"]
tags_yaml = "[" + ", ".join(tags) + "]"

force = os.environ.get("FORCE", "") == "1"
if not force:
    for eid, etitle in existing:
        ratio = SequenceMatcher(None, title, etitle).ratio()
        if ratio > 0.75:
            print(f'ERROR: 類似教訓あり: {eid}: {etitle} (類似度: {ratio:.0%})', file=sys.stderr)
            print(f'強制登録: --force フラグを追加', file=sys.stderr)
            sys.exit(1)

# Build new entry
status = os.environ.get("STATUS", "confirmed")
entry = f'\n### {new_id_str}: {title}\n'
entry += f'- **日付**: {timestamp}\n'
if source_cmd:
    entry += f'- **出典**: {source_cmd}\n'
entry += f'- **記録者**: {author}\n'
if status == "draft":
    entry += f'- **status**: draft\n'
entry += f'- **tags**: {tags_yaml}\n'

# IF-THEN形式フィールド（指定されたもののみ追記）
if_cond = os.environ.get("IF_COND", "")
then_action = os.environ.get("THEN_ACTION", "")
because_reason = os.environ.get("BECAUSE_REASON", "")
if if_cond or then_action or because_reason:
    if if_cond:
        entry += f'- **if**: {if_cond}\n'
    if then_action:
        entry += f'- **then**: {then_action}\n'
    if because_reason:
        entry += f'- **because**: {because_reason}\n'

entry += f'- {detail}\n'

# Append to file
with open(lessons_file, 'a', encoding='utf-8') as f:
    f.write(entry)

print(f'{new_id_str} added to {lessons_file}')

# Write lesson ID to temp file for post-flock --strategic processing
id_file = os.environ.get("LESSON_ID_FILE", "")
if id_file:
    with open(id_file, 'w') as f:
        f.write(new_id_str)
PYEOF

    ) 200>"$LOCKFILE"; then
        # AC3: Auto-call sync_lessons.sh after write
        bash "$SCRIPT_DIR/scripts/sync_lessons.sh" "$PROJECT_ID"
        # Context索引自動追記 (cmd_300)
        NEW_LESSON_ID=""
        if [ -f "$LESSON_ID_FILE" ]; then
            NEW_LESSON_ID=$(cat "$LESSON_ID_FILE")
        fi
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
                    # AC2: dedup — 同一LESSON_IDがあればスキップ (L006教訓)
                    if ! grep -qF -- "- ${NEW_LESSON_ID}:" "$CONTEXT_FULL_PATH"; then
                        (
                            flock -w 10 201 || { echo "WARN: context lock timeout" >&2; exit 0; }
                            export CONTEXT_FULL_PATH NEW_LESSON_ID TITLE SOURCE_CMD
                            python3 << 'CTXEOF'
import re, os

ctx_path = os.environ["CONTEXT_FULL_PATH"]
lesson_id = os.environ["NEW_LESSON_ID"]
title = os.environ["TITLE"]
source_cmd = os.environ.get("SOURCE_CMD", "")

with open(ctx_path, encoding='utf-8') as f:
    content = f.read()

entry = f"- {lesson_id}: {title}"
if source_cmd:
    entry += f"\uFF08{source_cmd}\uFF09"

# Find the last lessons section
# Patterns: "## ...教訓..." or "## ...Lesson..."
section_pattern = re.compile(r'^(##\s+.*(?:教訓|[Ll]esson).*)', re.MULTILINE)
matches = list(section_pattern.finditer(content))

if matches:
    last_match = matches[-1]
    after_section = content[last_match.end():]
    next_heading = re.search(r'^## ', after_section, re.MULTILINE)
    if next_heading:
        insert_pos = last_match.end() + next_heading.start()
        new_content = content[:insert_pos].rstrip('\n') + '\n' + entry + '\n\n' + content[insert_pos:]
    else:
        new_content = content.rstrip('\n') + '\n' + entry + '\n'
else:
    new_content = content.rstrip('\n') + '\n\n## 教訓索引（自動追記）\n\n' + entry + '\n'

# Update sync marker: <!-- last_synced_lesson: LXXX -->
marker_pattern = re.compile(r'<!--\s*last_synced_lesson:\s*L\d+\s*-->')
new_marker = f'<!-- last_synced_lesson: {lesson_id} -->'

if marker_pattern.search(new_content):
    # AC2: Marker exists — update the number
    new_content = marker_pattern.sub(new_marker, new_content)
else:
    # AC2: Marker absent — add after last lesson entry in the section
    # Insert before the next heading or at EOF
    if matches:
        last_match_recheck = matches[-1]
        after_recheck = new_content[last_match_recheck.end():]
        next_h = re.search(r'^## ', after_recheck, re.MULTILINE)
        if next_h:
            marker_pos = last_match_recheck.end() + next_h.start()
            new_content = new_content[:marker_pos].rstrip('\n') + '\n' + new_marker + '\n\n' + new_content[marker_pos:].lstrip('\n')
        else:
            new_content = new_content.rstrip('\n') + '\n' + new_marker + '\n'
    else:
        new_content = new_content.rstrip('\n') + '\n' + new_marker + '\n'

with open(ctx_path, 'w', encoding='utf-8') as f:
    f.write(new_content)

print(f"[lesson_write] {lesson_id} appended to {ctx_path}")
print(f"[lesson_write] sync marker updated: {new_marker}")
CTXEOF
                        ) 201>"${CONTEXT_FULL_PATH}.lock"
                    else
                        echo "[lesson_write] ${NEW_LESSON_ID} already in $CONTEXT_FILE, skipping context append"
                    fi
                else
                    echo "WARN: context file not found: $CONTEXT_FULL_PATH" >&2
                fi
            fi
        fi
        # --strategic: Register as pending decision (replaces direct dashboard.md editing)
        if [ "$STRATEGIC" == "--strategic" ]; then
            NEW_LESSON_ID=""
            if [ -f "$LESSON_ID_FILE" ]; then
                NEW_LESSON_ID=$(cat "$LESSON_ID_FILE")
            fi
            if [ -n "$NEW_LESSON_ID" ]; then
                if [ -f "$SCRIPT_DIR/scripts/pending_decision_write.sh" ]; then
                    bash "$SCRIPT_DIR/scripts/pending_decision_write.sh" create \
                        "MCP昇格候補: $NEW_LESSON_ID — $TITLE（将軍確認待ち）" \
                        "$SOURCE_CMD" "skill_candidate" "$AUTHOR"
                else
                    echo "WARN: pending_decision_write.sh not found, skipping strategic registration" >&2
                fi
            fi
        fi
        # cmd_108: Write .done flag for cmd_complete_gate
        if [ -n "$CMD_ID" ]; then
            gates_dir="$SCRIPT_DIR/queue/gates/${CMD_ID}"
            mkdir -p "$gates_dir"
            echo "timestamp: $(date +%Y-%m-%dT%H:%M:%S)" > "$gates_dir/lesson.done"
            echo "source: lesson_write" >> "$gates_dir/lesson.done"
        fi
        # REFLUX_CHECK: 穴検出3問チェック (cmd_1088)
        # 教訓登録=一回失敗=周辺に穴。キーワードでPI/ランブック/instructionsをgrep、還流漏れを検出
        REFLUX_LESSON_ID=""
        if [ -f "$LESSON_ID_FILE" ]; then
            REFLUX_LESSON_ID=$(cat "$LESSON_ID_FILE")
        fi
        if [ -n "$REFLUX_LESSON_ID" ]; then
            REFLUX_KEYWORDS=$(TITLE="$TITLE" DETAIL="$DETAIL" python3 << 'REFLUX_KWEOF'
import re, os
title = os.environ.get("TITLE", "")
detail = os.environ.get("DETAIL", "")
text = title + " " + detail
# Extract meaningful tokens: English words (3+ chars), Kanji chunks (2+), Katakana chunks (2+)
tokens = re.findall(r'[a-zA-Z_]{3,}|[\u4e00-\u9fff]{2,}|[\u30a0-\u30ff]{2,}', text)
seen = set()
unique = []
for t in tokens:
    tl = t.lower()
    if tl not in seen:
        seen.add(tl)
        unique.append(t)
# Output top 3 keywords as grep -E alternation pattern
print("|".join(unique[:3]))
REFLUX_KWEOF
            ) || true

            REFLUX_PI="MISSING"
            REFLUX_RUNBOOK="MISSING"
            REFLUX_INSTRUCTIONS="MISSING"

            if [ -n "$REFLUX_KEYWORDS" ]; then
                # (1) PI check: projects/{project}.yaml の production_invariants 関連
                PI_FILE="$SCRIPT_DIR/projects/${PROJECT_ID}.yaml"
                if [ -f "$PI_FILE" ] && grep -qE "$REFLUX_KEYWORDS" "$PI_FILE" 2>/dev/null; then
                    REFLUX_PI="FOUND"
                fi

                # (2) Runbook check: docs/rule/*.md
                if [ -d "$SCRIPT_DIR/docs/rule" ]; then
                    if grep -rlE "$REFLUX_KEYWORDS" "$SCRIPT_DIR/docs/rule/"*.md >/dev/null 2>&1; then
                        REFLUX_RUNBOOK="FOUND"
                    fi
                fi

                # (3) Instructions check: instructions/*.md
                if grep -rlE "$REFLUX_KEYWORDS" "$SCRIPT_DIR/instructions/"*.md >/dev/null 2>&1; then
                    REFLUX_INSTRUCTIONS="FOUND"
                fi
            fi

            echo "REFLUX_CHECK: (1)PI=$REFLUX_PI (2)RUNBOOK=$REFLUX_RUNBOOK (3)INSTRUCTIONS=$REFLUX_INSTRUCTIONS"
            if [ "$REFLUX_PI" = "MISSING" ] || [ "$REFLUX_RUNBOOK" = "MISSING" ] || [ "$REFLUX_INSTRUCTIONS" = "MISSING" ]; then
                echo "WARN: 還流漏れの可能性あり。MISSING箇所にこの教訓の知見を反映すべきか検討せよ"
            fi
        fi
        exit 0
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[lesson_write] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[lesson_write] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
