#!/bin/bash
# auto_draft_lesson.sh — 報告YAMLのlesson_candidateからconfirmed教訓を自動登録
# Usage: bash scripts/auto_draft_lesson.sh <report_yaml_path>
# - found: true → lesson_write.sh --status confirmed で登録
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

print(json.dumps({
    "action": "register",
    "project": project,
    "title": title,
    "detail": detail,
    "source_cmd": source_cmd,
    "author": worker_id,
    "tags": tags
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

# Extract fields
PROJECT=$(echo "$extract_result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('project','unknown'))")
TITLE=$(echo "$extract_result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('title','unknown'))")
DETAIL=$(echo "$extract_result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('detail',''))")
SOURCE_CMD=$(echo "$extract_result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('source_cmd','unknown'))")
AUTHOR=$(echo "$extract_result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('author','unknown'))")
TAGS=$(echo "$extract_result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tags',''))")

# Duplicate check: same title + source_cmd in SSOT (L006対応)
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

# Call lesson_write.sh with --status confirmed
echo "[auto_draft] Registering confirmed lesson: project=$PROJECT title=$TITLE source=$SOURCE_CMD"
TAGS_FLAG=""
if [ -n "$TAGS" ]; then
    TAGS_FLAG="--tags $TAGS"
fi
bash "$SCRIPT_DIR/scripts/lesson_write.sh" "$PROJECT" "$TITLE" "$DETAIL" "$SOURCE_CMD" "$AUTHOR" "" --status confirmed $TAGS_FLAG

echo "[auto_draft] Confirmed lesson registered successfully"
