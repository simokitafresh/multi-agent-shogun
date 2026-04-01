#!/bin/bash
# auto_draft_lesson.sh — 報告YAMLのlesson_candidateからdraft教訓を自動登録
# Usage: bash scripts/auto_draft_lesson.sh <report_yaml_path>
# - found: true → lesson_write.sh --status draft で登録
# - found: false → 何もしない (exit 0)
# - 重複チェック: 同一title+source_cmdが既存ならスキップ (L006対応)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_PATH="${1:-}"

if [ -z "$REPORT_PATH" ] || [ ! -f "$REPORT_PATH" ]; then
    echo "[auto_draft] Usage: auto_draft_lesson.sh <report_yaml_path>" >&2
    exit 1
fi

# Extract lesson_candidate fields from report YAML
export REPORT_PATH
extract_result=$(python3 << 'PYEOF'
import yaml, os, sys, json

report_path = os.environ["REPORT_PATH"]
with open(report_path, encoding='utf-8') as f:
    data = yaml.safe_load(f)

if not data:
    print(json.dumps({"action": "skip", "reason": "no_data"}))
    sys.exit(0)

lc = data.get("lesson_candidate", {})
if not isinstance(lc, dict) or not lc.get("found"):
    print(json.dumps({"action": "skip", "reason": "not_found"}))
    sys.exit(0)

title = lc.get("title", "").strip()
detail = lc.get("detail", "").strip()
project = lc.get("project", "").strip()

if not title or not detail:
    print(json.dumps({"action": "skip", "reason": "no_title_or_detail"}))
    sys.exit(0)

if not project:
    print(json.dumps({"action": "skip", "reason": "no_project"}))
    sys.exit(0)

# Get source cmd from report
source_cmd = data.get("parent_cmd", data.get("task_id", ""))
worker_id = data.get("worker_id", "auto_draft")

# Extract tags if present in lesson_candidate
tags = lc.get("tags", "")
if isinstance(tags, list):
    tags = ",".join(str(t) for t in tags)

# Extract if_then if present in lesson_candidate
if_then = lc.get("if_then", {})
if not isinstance(if_then, dict):
    if_then = {}

print(json.dumps({
    "action": "register",
    "project": project,
    "title": title,
    "detail": detail,
    "source_cmd": source_cmd,
    "author": worker_id,
    "tags": tags,
    "if_cond": if_then.get("if", ""),
    "then_action": if_then.get("then", ""),
    "because_reason": if_then.get("because", "")
}))
PYEOF
)

# Parse JSON result
action=$(echo "$extract_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('action','skip'))")

if [ "$action" = "skip" ]; then
    reason=$(echo "$extract_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('reason',''))")
    echo "[auto_draft] Skipped: ${reason} (${REPORT_PATH})"
    exit 0
fi

# Extract all fields in a single python3 call (9→1 process spawn)
eval "$(echo "$extract_result" | python3 -c "
import json, sys, shlex
d = json.load(sys.stdin)
for name, key, default in [
    ('PROJECT', 'project', 'unknown'),
    ('TITLE', 'title', 'unknown'),
    ('DETAIL', 'detail', ''),
    ('SOURCE_CMD', 'source_cmd', 'unknown'),
    ('AUTHOR', 'author', 'unknown'),
    ('TAGS', 'tags', ''),
    ('IF_COND', 'if_cond', ''),
    ('THEN_ACTION', 'then_action', ''),
    ('BECAUSE_REASON', 'because_reason', ''),
]:
    print(f'{name}={shlex.quote(str(d.get(key, default)))}')
")"

# Duplicate check: same title + source_cmd in SSOT (L006対応)
export SCRIPT_DIR PROJECT
PROJECT_PATH=$(python3 -c "
import yaml, os
script_dir = os.environ['SCRIPT_DIR']
project = os.environ['PROJECT']
with open(os.path.join(script_dir, 'config', 'projects.yaml'), encoding='utf-8') as f:
    cfg = yaml.safe_load(f)
for p in cfg.get('projects', []):
    if p['id'] == project:
        print(p['path'])
        break
")

if [ -z "$PROJECT_PATH" ]; then
    echo "[auto_draft] ERROR: Project '$PROJECT' not found in config/projects.yaml" >&2
    exit 1
fi

LESSONS_FILE="$PROJECT_PATH/tasks/lessons.md"

if [ -f "$LESSONS_FILE" ]; then
    export LESSONS_FILE TITLE SOURCE_CMD
    dup_check=$(python3 << 'PYEOF'
import re, os, sys
from difflib import SequenceMatcher

lessons_file = os.environ["LESSONS_FILE"]
title = os.environ["TITLE"]
source_cmd = os.environ["SOURCE_CMD"]

with open(lessons_file, encoding='utf-8') as f:
    content = f.read()

# Parse existing lessons: extract title and source_cmd
for m in re.finditer(r'^### L(\d+): (.+)$', content, re.MULTILINE):
    existing_id = f'L{int(m.group(1)):03d}'
    existing_title = m.group(2).strip()

    # Find source_cmd (出典) in the lines following the heading
    start = m.end()
    block = content[start:start+500]
    src_match = re.search(r'\*\*出典\*\*:\s*(\S+)', block)
    existing_source = src_match.group(1).strip() if src_match else ""

    # Check: same source_cmd AND similar title
    if source_cmd and existing_source == source_cmd:
        ratio = SequenceMatcher(None, title, existing_title).ratio()
        if ratio > 0.6:
            print(f'DUP:{existing_id}:{existing_title}')
            sys.exit(0)

print('OK')
PYEOF
    )

    if [[ "$dup_check" == DUP:* ]]; then
        echo "[auto_draft] Duplicate found: ${dup_check#DUP:} — skipping (${REPORT_PATH})"
        exit 0
    fi
fi

# Call lesson_write.sh with --status draft
echo "[auto_draft] Registering draft lesson: project=$PROJECT title=$TITLE source=$SOURCE_CMD"
EXTRA_FLAGS=()
if [ -n "$TAGS" ]; then
    EXTRA_FLAGS+=(--tags "$TAGS")
fi
if [ -n "$IF_COND" ]; then
    EXTRA_FLAGS+=(--if "$IF_COND")
fi
if [ -n "$THEN_ACTION" ]; then
    EXTRA_FLAGS+=(--then "$THEN_ACTION")
fi
if [ -n "$BECAUSE_REASON" ]; then
    EXTRA_FLAGS+=(--because "$BECAUSE_REASON")
fi
bash "$SCRIPT_DIR/scripts/lesson_write.sh" "$PROJECT" "$TITLE" "$DETAIL" "$SOURCE_CMD" "$AUTHOR" "" --status draft "${EXTRA_FLAGS[@]}"

echo "[auto_draft] Draft lesson registered successfully"
