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
        skill_files = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames.sort()
            if "SKILL.md" in filenames:
                skill_files.append(Path(dirpath) / "SKILL.md")
        for skill_file in sorted(skill_files):
            try:
                resolved = skill_file.resolve()
            except OSError:
                resolved = skill_file
            if resolved in seen_paths:
                continue
            seen_paths.add(resolved)
            skill_name = skill_file.parent.name
            found_name = False
            metric = ""
            with skill_file.open(encoding="utf-8", errors="ignore") as fh:
                for line in fh:
                    if not metric:
                        match = re.match(r'^quality_metric:\s*["\']?(.*?)["\']?\s*$', line)
                        if match:
                            metric = match.group(1).strip()
                    if not found_name:
                        name_match = re.match(r"^name:\s*([^\n]+?)\s*$", line)
                        if name_match:
                            skill_name = name_match.group(1).strip().strip('"\'')
                            found_name = True
                    if metric and found_name:
                        break
            if not metric:
                continue
            skills.setdefault(skill_name, {"metric": metric, "path": str(skill_file)})
    return skills


def parse_scalar(raw):
    value = raw.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
        if raw.strip().startswith('"'):
            value = value.replace('\\"', '"').replace("\\\\", "\\")
    return value


def load_entries(path):
    try:
        fh = open(path, encoding="utf-8", errors="ignore")
    except FileNotFoundError:
        return []
    entries = []
    current = None
    wanted = {"ts", "skill", "result", "used"}
    with fh:
        for line in fh:
            if line.startswith("- "):
                if current is not None:
                    entries.append(current)
                current = {}
                body = line[2:].strip()
                if ":" in body:
                    key, value = body.split(":", 1)
                    key = key.strip()
                    if key in wanted:
                        current[key] = parse_scalar(value)
                continue
            if current is None or not line.startswith("  ") or line.startswith("    "):
                continue
            body = line.strip()
            if ":" not in body:
                continue
            key, value = body.split(":", 1)
            key = key.strip()
            if key in wanted:
                current[key] = parse_scalar(value)
    if current is not None:
        entries.append(current)
    return entries


skills = load_quality_metrics(skills_dirs)
counts = defaultdict(lambda: {"PASS": 0, "FAIL": 0, "OTHER": 0, "last_ts": "", "last_result": ""})

for entry in load_entries(log_file):
    skill = str(entry.get("skill") or "").strip()
    if not skill:
        continue
    result = str(entry.get("result") or "").strip().upper()
    if result == "FAIL" and str(entry.get("used", True)).strip().lower() == "false":
        continue
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
