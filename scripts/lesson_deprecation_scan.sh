#!/bin/bash
# lesson_deprecation_scan.sh - deprecation候補を自動検出する（read-only）
# Usage: bash scripts/lesson_deprecation_scan.sh [--project dm-signal|infra|all]
# Default: --project all

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/projects.yaml"
TRACKING_TSV="$SCRIPT_DIR/logs/lesson_tracking.tsv"

# --- Argument Parsing ---
PROJECT_FILTER="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --project requires a value (dm-signal|infra|all)" >&2
        exit 1
      fi
      PROJECT_FILTER="$2"
      shift 2
      ;;
    *)
      echo "Usage: bash scripts/lesson_deprecation_scan.sh [--project dm-signal|infra|all]" >&2
      exit 1
      ;;
  esac
done

export SCRIPT_DIR CONFIG_FILE TRACKING_TSV PROJECT_FILTER

python3 << 'PYEOF'
import os
import sys
import re
import yaml
from pathlib import Path

SCRIPT_DIR = Path(os.environ["SCRIPT_DIR"])
CONFIG_FILE = Path(os.environ["CONFIG_FILE"])
TRACKING_TSV = Path(os.environ["TRACKING_TSV"])
PROJECT_FILTER = os.environ["PROJECT_FILTER"]

# --- Load projects ---
with open(CONFIG_FILE, encoding="utf-8") as f:
    config = yaml.safe_load(f)
all_projects = config.get("projects", [])

if PROJECT_FILTER == "all":
    projects = all_projects
else:
    projects = [p for p in all_projects if p["id"] == PROJECT_FILTER]
    if not projects:
        print(f"ERROR: project '{PROJECT_FILTER}' not found", file=sys.stderr)
        sys.exit(1)

# --- Load lesson_tracking.tsv for last_referenced_cmd ---
# Columns: timestamp  cmd_id  ninja  gate_result  injected_ids  referenced_ids
lesson_last_cmd = {}  # lesson_id -> last cmd_num (int)
max_cmd_num = 0

if TRACKING_TSV.exists():
    with open(TRACKING_TSV, encoding="utf-8") as f:
        for i, line in enumerate(f):
            line = line.strip()
            if i == 0 or not line:
                continue
            parts = line.split("\t")
            if len(parts) < 6:
                continue
            cmd_id = parts[1]
            referenced_str = parts[5] if len(parts) > 5 else ""
            m = re.match(r'cmd_(\d+)$', cmd_id)
            if not m:
                continue
            cmd_num = int(m.group(1))
            if cmd_num >= 900:  # skip test cmds (cmd_999 etc.)
                continue
            max_cmd_num = max(max_cmd_num, cmd_num)
            if referenced_str and referenced_str != "none":
                for lid in referenced_str.split(","):
                    lid = lid.strip()
                    if re.match(r'^L\d+$', lid):
                        prev = lesson_last_cmd.get(lid, 0)
                        if cmd_num > prev:
                            lesson_last_cmd[lid] = cmd_num


def last_ref_text(lesson_id):
    """Format last-referenced info as 'Ncmd前(cmd_NNN)' or '参照なし'."""
    last = lesson_last_cmd.get(lesson_id)
    if last is None:
        return "参照なし"
    diff = max_cmd_num - last
    if diff == 0:
        return f"最新cmd(cmd_{last})で参照済み"
    return f"{diff}cmd前(cmd_{last})"


def is_deprecated(lesson):
    """Check if lesson is already deprecated (skip these)."""
    return bool(lesson.get("deprecated", False)) or lesson.get("status") == "deprecated"


def find_file_refs(text):
    """Find explicit repo file path references (e.g. scripts/xxx.sh, queue/xxx.yaml).
    Use ASCII-only char class to avoid matching Japanese text after file extensions."""
    pattern = (
        r'\b((?:scripts|queue|config|projects|logs|context|tasks|docs)'
        r'/[a-zA-Z0-9_/.-]+\.[a-zA-Z0-9]+)'
    )
    return re.findall(pattern, text)


def find_script_names(text):
    """Find bare .sh script name mentions."""
    return re.findall(r'\b([\w_-]+\.sh)\b', text)


# --- Main scan ---
confirmed = []  # (project_id, lesson_id, reason)
review = []     # (project_id, lesson_id, title_snip, related, last_ref)

for project in projects:
    project_id = project["id"]
    project_status = project.get("status", "active")
    lessons_file = SCRIPT_DIR / "projects" / project_id / "lessons.yaml"

    if not lessons_file.exists():
        continue

    with open(lessons_file, encoding="utf-8") as f:
        data = yaml.safe_load(f)
    if not isinstance(data, dict):
        continue
    lessons = data.get("lessons", [])
    if not isinstance(lessons, list):
        continue

    for lesson in lessons:
        if not isinstance(lesson, dict):
            continue
        if is_deprecated(lesson):
            continue  # already deprecated: skip

        lesson_id = lesson.get("id", "?")
        title = lesson.get("title", "")
        summary = lesson.get("summary", "")
        full_text = f"{title} {summary}"

        # (a-1) Confirmed: lesson belongs to an archived project
        if project_status == "archived":
            confirmed.append((project_id, lesson_id, f"{project_id}プロジェクト(archived)"))
            continue

        # (a-2) Confirmed: explicit file path in text -> file no longer exists
        added_confirmed = False
        for ref in find_file_refs(full_text):
            target = SCRIPT_DIR / ref
            if not target.exists():
                confirmed.append((project_id, lesson_id, f"{ref}参照（ファイル消滅）"))
                added_confirmed = True
                break

        if added_confirmed:
            continue

        # (b) Review recommended: .sh script name mentioned + that script exists in scripts/
        for sname in find_script_names(full_text):
            spath = SCRIPT_DIR / "scripts" / sname
            if spath.exists():
                title_snip = (title or summary)[:60]
                lref = last_ref_text(lesson_id)
                review.append((
                    project_id, lesson_id,
                    f'"{title_snip}"',
                    f"scripts/{sname} 現存(仕組み化済みの可能性)",
                    lref,
                ))
                break

# --- Output ---
print("=== 確定candidate（自動） ===")
if confirmed:
    for proj, lid, reason in confirmed:
        print(f"  [{proj}] {lid}: {reason}")
else:
    print("  (なし)")

print()
print("=== 審査推奨（材料提示のみ） ===")
if review:
    for proj, lid, title_snip, related, lref in review:
        print(f"  [{proj}] {lid}: {title_snip}")
        print(f"        → 関連: {related}")
        print(f"        → 最終参照: {lref}")
        print(f"        ★ 構造防止済みの可能性あり。家老判断を推奨")
else:
    print("  (なし)")
PYEOF
