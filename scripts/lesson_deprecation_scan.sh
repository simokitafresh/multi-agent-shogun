#!/bin/bash
# lesson_deprecation_scan.sh - deprecation候補を自動検出+自動退役する
# cmd_531: ファイル消滅教訓・有効率10%未満×注入10回以上の教訓を自動deprecated化
# Usage: bash scripts/lesson_deprecation_scan.sh [--project dm-signal|infra|all]
# Default: --project all

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/projects.yaml"
TRACKING_TSV="$SCRIPT_DIR/logs/lesson_tracking.tsv"
IMPACT_TSV="$SCRIPT_DIR/logs/lesson_impact.tsv"

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

export SCRIPT_DIR CONFIG_FILE TRACKING_TSV IMPACT_TSV PROJECT_FILTER

python3 << 'PYEOF'
import os
import sys
import re
import yaml
import subprocess
from pathlib import Path

SCRIPT_DIR = Path(os.environ["SCRIPT_DIR"])
CONFIG_FILE = Path(os.environ["CONFIG_FILE"])
TRACKING_TSV = Path(os.environ["TRACKING_TSV"])
IMPACT_TSV = Path(os.environ["IMPACT_TSV"])
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


# --- Load lesson_impact.tsv for injection/helpful counts ---
# Columns: timestamp  cmd_id  ninja  lesson_id  action  result  referenced  project  task_type  bloom_level
tsv_injection_count = {}  # lesson_id -> count
tsv_helpful_count = {}    # lesson_id -> count

if IMPACT_TSV.exists():
    with open(IMPACT_TSV, encoding="utf-8") as f:
        for i, line in enumerate(f):
            line = line.strip()
            if i == 0 or not line:
                continue
            parts = line.split("\t")
            if len(parts) < 7:
                continue
            lesson_id_tsv = parts[3]
            action = parts[4]
            referenced = parts[6]
            if action == "injected" and re.match(r'^L\d+$', lesson_id_tsv):
                tsv_injection_count[lesson_id_tsv] = tsv_injection_count.get(lesson_id_tsv, 0) + 1
                if referenced == "yes":
                    tsv_helpful_count[lesson_id_tsv] = tsv_helpful_count.get(lesson_id_tsv, 0) + 1


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
global_max_id = 0  # track max lesson ID across all projects for checkpoint
confirmed = []  # (project_id, lesson_id, reason)
review = []     # (project_id, lesson_id, title_snip, related, last_ref)
eff_confirmed = []  # (project_id, lesson_id, title_snip, inj_count, hlp_count)
eff_review = []     # (project_id, lesson_id, title_snip, inj_count, hlp_count, rate)

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
        m_id = re.match(r'^L(\d+)$', lesson_id)
        if m_id:
            global_max_id = max(global_max_id, int(m_id.group(1)))
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

        # (c) Effectiveness rate check
        # Prefer YAML injection_count if > 0, else fallback to TSV
        yaml_inj = lesson.get("injection_count", 0) or 0
        yaml_hlp = lesson.get("helpful_count", 0) or 0
        if yaml_inj > 0:
            inj_count = yaml_inj
            hlp_count = yaml_hlp
        else:
            inj_count = tsv_injection_count.get(lesson_id, 0)
            hlp_count = tsv_helpful_count.get(lesson_id, 0)

        # (c-1) Confirmed: injection >= 5 and effectiveness == 0%
        if inj_count >= 5 and hlp_count == 0:
            title_snip = (title or summary)[:60]
            eff_confirmed.append((project_id, lesson_id, title_snip, inj_count, hlp_count))
        # (c-2) Review: injection >= 10 and effectiveness < 10%
        elif inj_count >= 10:
            rate = hlp_count / inj_count * 100
            if rate < 10:
                title_snip = (title or summary)[:60]
                eff_review.append((project_id, lesson_id, title_snip, inj_count, hlp_count, rate))

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

print()
print("=== 有効率0% 確定candidate (注入N≥5) ===")
if eff_confirmed:
    for proj, lid, title_snip, inj, hlp in eff_confirmed:
        print(f"  [{proj}] {lid}: {title_snip} (injected={inj}, helpful=0)")
else:
    print("  (なし)")

print()
print("=== 有効率<10% 自動退役対象 (注入N≥10) ===")
if eff_review:
    for proj, lid, title_snip, inj, hlp, rate in eff_review:
        print(f"  [{proj}] {lid}: {title_snip} (injected={inj}, helpful={hlp}, rate={rate:.0f}%)")
else:
    print("  (なし)")

# cmd_531: 自動退役実行
deprecate_script = str(SCRIPT_DIR / "scripts" / "lesson_deprecate.sh")
auto_deprecated_count = 0

print()
print("=== 自動退役実行 ===")

# AC5: ファイル消滅教訓の自動退役
for proj, lid, reason in confirmed:
    if "ファイル消滅" in reason:
        result = subprocess.run(
            ["bash", deprecate_script, proj, lid, f"AUTO-DEPRECATE(file_missing): {reason}"],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            print(f"  [AUTO] DEPRECATED: [{proj}] {lid} ({reason})")
            auto_deprecated_count += 1
        else:
            print(f"  [AUTO] WARN: {lid} deprecation failed: {result.stderr.strip()}", file=sys.stderr)

# AC4: 有効率10%未満 × 注入10回以上の自動退役
for proj, lid, title_snip, inj, hlp in eff_confirmed:
    if inj >= 10:
        result = subprocess.run(
            ["bash", deprecate_script, proj, lid, f"AUTO-DEPRECATE(low_effectiveness): rate=0% injected={inj} helpful=0"],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            print(f"  [AUTO] DEPRECATED: [{proj}] {lid} (rate=0%, injected={inj})")
            auto_deprecated_count += 1
        else:
            print(f"  [AUTO] WARN: {lid} deprecation failed: {result.stderr.strip()}", file=sys.stderr)

for proj, lid, title_snip, inj, hlp, rate in eff_review:
    result = subprocess.run(
        ["bash", deprecate_script, proj, lid, f"AUTO-DEPRECATE(low_effectiveness): rate={rate:.0f}% injected={inj} helpful={hlp}"],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        print(f"  [AUTO] DEPRECATED: [{proj}] {lid} (rate={rate:.0f}%, injected={inj})")
        auto_deprecated_count += 1
    else:
        print(f"  [AUTO] WARN: {lid} deprecation failed: {result.stderr.strip()}", file=sys.stderr)

print(f"  合計: {auto_deprecated_count}件 自動退役")

# --- Checkpoint update ---
if global_max_id > 0:
    checkpoint_path = SCRIPT_DIR / "queue" / "lesson_deprecation_checkpoint.txt"
    with open(checkpoint_path, "w") as f:
        f.write(f"L{global_max_id}\n")
    print(f"\nCheckpoint updated: L{global_max_id}")
PYEOF
