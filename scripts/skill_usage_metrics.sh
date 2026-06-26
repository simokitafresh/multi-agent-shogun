#!/usr/bin/env bash
# skill_usage_metrics.sh — Measure skill usage and stale SKILL.md intent debt.
# Usage:
#   bash scripts/skill_usage_metrics.sh [--recommend-log PATH] [--skills-dir DIR] [--stale-days N] [--now ISO_OR_EPOCH]

set -euo pipefail

REPO_ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RECOMMEND_LOG="${SKILL_RECOMMEND_LOG_FILE:-$REPO_ROOT/logs/skill_recommend_log.yaml}"
SKILLS_DIR="${SKILL_USAGE_SKILLS_DIR:-$REPO_ROOT/skills}"
STALE_DAYS="${SKILL_USAGE_STALE_DAYS:-30}"
NOW_VALUE="${SKILL_USAGE_NOW:-}"

usage() {
    sed -n '1,5p' "$0" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --recommend-log) RECOMMEND_LOG="${2:-}"; shift 2 ;;
        --skills-dir) SKILLS_DIR="${2:-}"; shift 2 ;;
        --stale-days) STALE_DAYS="${2:-}"; shift 2 ;;
        --now) NOW_VALUE="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown arg: $1" >&2
            usage
            exit 2
            ;;
    esac
done

python3 - "$SKILLS_DIR" "$RECOMMEND_LOG" "$STALE_DAYS" "$NOW_VALUE" <<'PY'
import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

skills_dir, recommend_log, stale_days_raw, now_raw = sys.argv[1:5]

try:
    stale_days = float(stale_days_raw)
except ValueError:
    stale_days = 30.0
if stale_days < 0:
    stale_days = 0.0


def parse_now(value):
    text = str(value or "").strip()
    if not text:
        return time.time()
    try:
        return float(text)
    except ValueError:
        pass
    normalized = re.sub(r"([+-]\d{2})(\d{2})$", r"\1:\2", text)
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(normalized).timestamp()
    except ValueError:
        return time.time()


def unquote(value):
    return str(value or "").strip().strip("\"'")


def discover_skills(root):
    base = Path(os.path.expanduser(root))
    skills = {}
    if not base.is_dir():
        return skills
    for skill_file in sorted(base.glob("*/SKILL.md")):
        name = skill_file.parent.name
        try:
            with skill_file.open(encoding="utf-8", errors="ignore") as fh:
                for line in fh:
                    match = re.match(r"^name:\s*(.*?)\s*$", line)
                    if match:
                        name = unquote(match.group(1))
                        break
        except OSError:
            pass
        try:
            mtime = skill_file.stat().st_mtime
        except OSError:
            mtime = 0.0
        skills[name] = {
            "path": str(skill_file),
            "mtime": int(mtime),
            "mtime_iso": datetime.fromtimestamp(mtime).isoformat() if mtime else "",
            "recommend_count": 0,
        }
    return skills


def load_recommend_counts(path):
    counts = {}
    try:
        fh = open(path, encoding="utf-8", errors="ignore")
    except FileNotFoundError:
        return counts
    in_recommended = False
    with fh:
        for raw in fh:
            line = raw.rstrip("\n")
            stripped = line.strip()
            if line.startswith("- "):
                in_recommended = False
                continue
            if not line.startswith("  "):
                in_recommended = False
                continue
            if stripped.startswith("recommended_skills:"):
                in_recommended = True
                tail = stripped.split(":", 1)[1].strip()
                if tail.startswith("[") and tail.endswith("]"):
                    for item in tail[1:-1].split(","):
                        skill = unquote(item)
                        if skill:
                            counts[skill] = counts.get(skill, 0) + 1
                continue
            if in_recommended and stripped.startswith("- "):
                skill = unquote(stripped[2:])
                if skill:
                    counts[skill] = counts.get(skill, 0) + 1
                continue
            if in_recommended and stripped and not stripped.startswith("- "):
                in_recommended = False
    return counts


now = parse_now(now_raw)
skills = discover_skills(skills_dir)
recommend_counts = load_recommend_counts(recommend_log)

for skill, count in recommend_counts.items():
    if skill in skills:
        skills[skill]["recommend_count"] = count

items = []
unused = 0
stale = 0
for skill in sorted(skills):
    item = skills[skill]
    is_unused = item["recommend_count"] == 0
    age_days = ((now - item["mtime"]) / 86400.0) if item["mtime"] else None
    is_stale = bool(age_days is not None and age_days > stale_days)
    unused += 1 if is_unused else 0
    stale += 1 if is_stale else 0
    items.append({
        "skill": skill,
        "path": item["path"],
        "recommend_count": item["recommend_count"],
        "unused": is_unused,
        "skill_mtime": item["mtime_iso"],
        "age_days": round(age_days, 2) if age_days is not None else None,
        "stale": is_stale,
    })

total = len(items)
json.dump({
    "total_skills": total,
    "used_skill_count": total - unused,
    "unused_skill_count": unused,
    "stale_skill_count": stale,
    "unused_rate": round((unused / total), 4) if total else 0.0,
    "stale_rate": round((stale / total), 4) if total else 0.0,
    "stale_days_threshold": stale_days,
    "recommend_log": recommend_log,
    "skills_dir": skills_dir,
    "skills": items,
}, sys.stdout, ensure_ascii=False, sort_keys=True)
sys.stdout.write("\n")
PY
