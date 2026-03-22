#!/usr/bin/env bash
# lesson_harvest.sh — アーカイブ済み報告からlesson_candidate未登録候補をスキャン
# Usage: bash scripts/lesson_harvest.sh
# Output: cmd_id | ninja | title | detail(先頭60文字)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ARCHIVE_DIR="$REPO_ROOT/queue/archive/reports"
PROJECTS_DIR="$REPO_ROOT/projects"

if [[ ! -d "$ARCHIVE_DIR" ]]; then
    echo "アーカイブディレクトリが存在しません: $ARCHIVE_DIR" >&2
    exit 1
fi

export REPO_ROOT

python3 - "$ARCHIVE_DIR" "$PROJECTS_DIR" << 'PYEOF'
import yaml
import os
import glob
import sys

archive_dir = sys.argv[1]
projects_dir = sys.argv[2]

# Step 1: Collect all registered lesson titles from all lessons.yaml
registered_titles = set()
for lessons_file in glob.glob(os.path.join(projects_dir, "*/lessons.yaml")):
    try:
        with open(lessons_file) as f:
            data = yaml.safe_load(f)
        if data and isinstance(data, dict):
            # L063: lessons.yaml top-level is dict, lessons key has list
            for lesson in data.get("lessons", []):
                if isinstance(lesson, dict) and lesson.get("title"):
                    registered_titles.add(lesson["title"].strip())
    except Exception:
        pass

# Also check lessons_archive.yaml
for archive_file in glob.glob(os.path.join(projects_dir, "*/lessons_archive.yaml")):
    try:
        with open(archive_file) as f:
            data = yaml.safe_load(f)
        if data and isinstance(data, dict):
            for lesson in data.get("lessons", []):
                if isinstance(lesson, dict) and lesson.get("title"):
                    registered_titles.add(lesson["title"].strip())
    except Exception:
        pass

# Step 2: Scan archive reports
candidates = []
for report_file in sorted(glob.glob(os.path.join(archive_dir, "*.yaml"))):
    try:
        with open(report_file) as f:
            data = yaml.safe_load(f)
        if not data or not isinstance(data, dict):
            continue

        lc = data.get("lesson_candidate")
        if not lc or not isinstance(lc, dict):
            continue
        if lc.get("found") is not True:
            continue

        title = lc.get("title", "")
        # Handle various formats (dict, list, string)
        if isinstance(title, dict):
            title = title.get("content", "") or title.get("id", "") or str(title)
        if isinstance(title, list):
            title = str(title[0]) if title else ""
        title = str(title).strip()

        if not title:
            continue

        # Check if already registered
        if title in registered_titles:
            continue

        # Extract metadata
        cmd_id = data.get("parent_cmd", "") or data.get("task_id", "") or ""
        worker = data.get("worker_id", "")
        detail = lc.get("detail", "")
        if isinstance(detail, dict):
            detail = detail.get("content", "") or str(detail)
        if isinstance(detail, list):
            detail = str(detail[0]) if detail else ""
        detail = str(detail).strip().replace("\n", " ")[:60]

        candidates.append((str(cmd_id), str(worker), title, detail))
    except Exception:
        pass

# Step 3: Output
if not candidates:
    print("未登録候補なし")
else:
    print(f"未登録候補: {len(candidates)}件")
    print("-" * 100)
    for cmd_id, worker, title, detail in candidates:
        print(f"{cmd_id} | {worker} | {title} | {detail}")
PYEOF
