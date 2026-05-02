#!/usr/bin/env bash
# skill_auto_improve.sh — convert skill FAIL patterns into SKILL.md prevention steps.
#
# Usage:
#   bash scripts/skill_auto_improve.sh [--top 3] [--apply] [--skill <name>]

set -euo pipefail

REPO_ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_FILE="${SKILL_EXECUTION_LOG_FILE:-$REPO_ROOT/logs/skill_execution_log.yaml}"
SKILLS_DIRS="${SKILL_AUTO_IMPROVE_SKILLS_DIRS:-$REPO_ROOT/skills:$HOME/.codex/skills:$HOME/.claude/skills}"
top_n=3
apply=false
skill_filter=""

usage() {
    sed -n '1,7p' "$0" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --log) LOG_FILE="${2:-}"; shift 2 ;;
        --skills-dirs) SKILLS_DIRS="${2:-}"; shift 2 ;;
        --top) top_n="${2:-}"; shift 2 ;;
        --skill) skill_filter="${2:-}"; shift 2 ;;
        --apply) apply=true; shift ;;
        --dry-run) apply=false; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown arg: $1" >&2
            usage
            exit 2
            ;;
    esac
done

python3 - "$LOG_FILE" "$SKILLS_DIRS" "$top_n" "$apply" "$skill_filter" <<'PY'
import hashlib
import os
import re
import sys
import tempfile
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

import yaml

log_file, skills_dirs, top_n_raw, apply_raw, skill_filter = sys.argv[1:6]
try:
    top_n = int(top_n_raw)
except ValueError:
    print("--top must be an integer", file=sys.stderr)
    raise SystemExit(2)
if top_n < 1:
    print("--top must be >= 1", file=sys.stderr)
    raise SystemExit(2)
apply_changes = apply_raw.lower() == "true"


def load_entries(path):
    try:
        with open(path, encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
    except FileNotFoundError:
        return []
    entries = data.get("executions") or []
    return [entry for entry in entries if isinstance(entry, dict)]


def iter_skill_files():
    seen = set()
    for raw_dir in skills_dirs.split(":"):
        if not raw_dir:
            continue
        root = Path(os.path.expanduser(raw_dir))
        if not root.is_dir():
            continue
        for child in sorted(root.iterdir(), key=lambda p: p.name):
            skill_file = child / "SKILL.md"
            try:
                resolved = skill_file.resolve()
            except OSError:
                resolved = skill_file
            if not skill_file.is_file() or resolved in seen:
                continue
            seen.add(resolved)
            yield child.name, skill_file


def skill_file_for(skill_name, logged_path):
    if logged_path:
        path = Path(os.path.expanduser(str(logged_path)))
        if path.is_file():
            return path
    for name, path in iter_skill_files():
        if name == skill_name:
            return path
    return None


def normalize_reason(value):
    return " ".join(str(value or "").split())


def shorten(value, limit=180):
    if len(value) <= limit:
        return value
    return value[: limit - 3] + "..."


def marker_for(skill_name, reason):
    digest = hashlib.sha1(f"{skill_name}\0{reason}".encode("utf-8")).hexdigest()[:12]
    return f"<!-- skill-auto-improve:{digest} -->"


def prevention_line(skill_name, reason, gate, count, last_fail):
    marker = marker_for(skill_name, reason)
    compact_reason = shorten(reason)
    gate_text = gate or "unknown_gate"
    return (
        f"- {marker} 自動防止: gate={gate_text} のTop FAIL理由「{compact_reason}」"
        f"(count={count}, last={last_fail or 'unknown'})を避けるため、該当Step完了直後に同条件を確認し、"
        "FAILなら次へ進まず修正する。"
    )


def existing_auto_section_insert_index(lines):
    for idx, line in enumerate(lines):
        if line.strip() != "### 自動防止ステップ":
            continue
        insert = idx + 1
        while insert < len(lines) and not lines[insert].startswith("#"):
            insert += 1
        return insert
    return None


def procedure_insertion_index(lines):
    heading_re = re.compile(r"^##\s+.*(手順|実行フロー|Workflow|Procedure|Steps|使い方|commit手順)")
    fallback_re = re.compile(r"^##\s+注意ポイント\s*$")
    for idx, line in enumerate(lines):
        if heading_re.search(line):
            insert = idx + 1
            while insert < len(lines) and lines[insert].strip() == "":
                insert += 1
            return insert
    for idx, line in enumerate(lines):
        if fallback_re.search(line):
            return idx
    return len(lines)


def apply_prevention_steps(skill_path, rows):
    text = skill_path.read_text(encoding="utf-8", errors="ignore")
    additions = []
    for row in rows:
        marker = marker_for(row["skill"], row["reason"])
        if marker in text:
            continue
        additions.append(prevention_line(row["skill"], row["reason"], row["gate"], row["count"], row["last_fail"]))
    if not additions:
        return False

    lines = text.splitlines()
    auto_idx = existing_auto_section_insert_index(lines)
    if auto_idx is None:
        block = ["### 自動防止ステップ", *additions, ""]
        idx = procedure_insertion_index(lines)
    else:
        block = additions
        idx = auto_idx
    new_lines = lines[:idx] + block + lines[idx:]
    new_text = "\n".join(new_lines).rstrip() + "\n"

    fd, tmp = tempfile.mkstemp(dir=str(skill_path.parent), prefix=".SKILL.", suffix=".tmp")
    os.close(fd)
    Path(tmp).write_text(new_text, encoding="utf-8")
    os.replace(tmp, skill_path)
    return True


stats = defaultdict(lambda: {"counter": Counter(), "last": {}, "gate": {}, "path": ""})
for entry in load_entries(log_file):
    if str(entry.get("result", "")).strip().upper() != "FAIL":
        continue
    skill = str(entry.get("skill") or "").strip()
    if not skill:
        continue
    if skill_filter and skill != skill_filter:
        continue
    reason = normalize_reason(entry.get("stumbling_points"))
    if not reason:
        continue
    stats[skill]["counter"][reason] += 1
    ts = str(entry.get("ts") or "").strip()
    if ts >= stats[skill]["last"].get(reason, ""):
        stats[skill]["last"][reason] = ts
        stats[skill]["gate"][reason] = str(entry.get("gate") or "").strip()
    logged_path = str(entry.get("skill_path") or "").strip()
    if logged_path:
        stats[skill]["path"] = logged_path

print("skill | rank | fail_count | last_fail | gate | top_fail_reason")
apply_plan = defaultdict(list)
for skill in sorted(stats):
    top_rows = sorted(stats[skill]["counter"].items(), key=lambda kv: (-kv[1], kv[0]))[:top_n]
    for rank, (reason, count) in enumerate(top_rows, start=1):
        row = {
            "skill": skill,
            "rank": rank,
            "count": count,
            "last_fail": stats[skill]["last"].get(reason, ""),
            "gate": stats[skill]["gate"].get(reason, ""),
            "reason": reason,
        }
        print(
            f"{skill} | {rank} | {count} | {row['last_fail']} | {row['gate']} | {shorten(reason, 220)}"
        )
        apply_plan[skill].append(row)

if not apply_changes:
    raise SystemExit(0)

updated = 0
for skill, rows in apply_plan.items():
    path = skill_file_for(skill, stats[skill]["path"])
    if not path:
        print(f"SKIP: {skill} SKILL.md not found")
        continue
    if apply_prevention_steps(path, rows):
        updated += 1
        print(f"UPDATED: {path}")
    else:
        print(f"UNCHANGED: {path}")

print(f"updated_skills={updated} generated_at={datetime.now().strftime('%Y-%m-%dT%H:%M:%S')}")
PY
