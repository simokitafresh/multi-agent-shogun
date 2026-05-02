#!/usr/bin/env bash
# skill_metrics.sh — calculate per-skill quality scores from SKILL.md quality_metric and execution log.
#
# Usage:
#   bash scripts/skill_metrics.sh [--log logs/skill_execution_log.yaml] [--skills-dirs skills[:...]]

set -euo pipefail

REPO_ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_FILE="${SKILL_EXECUTION_LOG_FILE:-$REPO_ROOT/logs/skill_execution_log.yaml}"
SKILLS_DIRS="${SKILL_METRICS_SKILLS_DIRS:-$REPO_ROOT/skills:$HOME/.codex/skills:$HOME/.claude/skills}"

usage() {
    sed -n '1,5p' "$0" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --log) LOG_FILE="${2:-}"; shift 2 ;;
        --skills-dirs) SKILLS_DIRS="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown arg: $1" >&2
            usage
            exit 2
            ;;
    esac
done

python3 - "$LOG_FILE" "$SKILLS_DIRS" <<'PY'
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

import yaml

log_file, skills_dirs = sys.argv[1:3]


def load_quality_metrics(raw_dirs):
    skills = {}
    seen_paths = set()
    for raw_dir in raw_dirs.split(":"):
        if not raw_dir:
            continue
        root = Path(os.path.expanduser(raw_dir))
        if not root.is_dir():
            continue
        for skill_file in sorted(root.rglob("SKILL.md")):
            try:
                resolved = skill_file.resolve()
            except OSError:
                resolved = skill_file
            if resolved in seen_paths:
                continue
            seen_paths.add(resolved)
            text = skill_file.read_text(encoding="utf-8", errors="ignore")
            match = re.search(r'^quality_metric:\s*["\']?(.*?)["\']?\s*$', text, re.MULTILINE)
            if not match:
                continue
            name_match = re.search(r"^name:\s*([^\n]+?)\s*$", text, re.MULTILINE)
            skill_name = name_match.group(1).strip().strip('"\'') if name_match else skill_file.parent.name
            metric = match.group(1).strip()
            skills.setdefault(skill_name, {"metric": metric, "path": str(skill_file)})
    return skills


def load_entries(path):
    try:
        with open(path, encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
    except FileNotFoundError:
        return []
    entries = data.get("executions") or []
    return [entry for entry in entries if isinstance(entry, dict)]


skills = load_quality_metrics(skills_dirs)
counts = defaultdict(lambda: {"PASS": 0, "FAIL": 0, "OTHER": 0, "last_ts": "", "last_result": ""})

for entry in load_entries(log_file):
    skill = str(entry.get("skill") or "").strip()
    if not skill:
        continue
    result = str(entry.get("result") or "").strip().upper()
    bucket = result if result in {"PASS", "FAIL"} else "OTHER"
    counts[skill][bucket] += 1
    ts = str(entry.get("ts") or "").strip()
    if ts >= counts[skill]["last_ts"]:
        counts[skill]["last_ts"] = ts
        counts[skill]["last_result"] = result or "UNKNOWN"

print("skill | quality_score | pass | fail | total | last_result | quality_metric")
for skill in sorted(skills):
    stat = counts[skill]
    passed = stat["PASS"]
    failed = stat["FAIL"]
    total = passed + failed
    score = "N/A" if total == 0 else f"{(passed * 100.0 / total):.1f}%"
    last_result = stat["last_result"] or "N/A"
    metric = skills[skill]["metric"]
    print(f"{skill} | {score} | {passed} | {failed} | {total} | {last_result} | {metric}")
PY
