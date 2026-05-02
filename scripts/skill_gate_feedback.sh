#!/usr/bin/env bash
# skill_gate_feedback.sh — identify the relevant skill for a gate failure and append a caution.
#
# Usage:
#   bash scripts/skill_gate_feedback.sh --gate <gate> --result FAIL --reason <reason> \
#       [--executor <agent>] [--source <path>] [--skill <name>]

set -euo pipefail

REPO_ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_SCRIPT="$REPO_ROOT/scripts/skill_execution_log.sh"

gate=""
result=""
reason=""
executor="${AGENT_ID:-${USER:-unknown}}"
source=""
explicit_skill=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --gate) gate="${2:-}"; shift 2 ;;
        --result) result="${2:-}"; shift 2 ;;
        --reason|--stumbling-points) reason="${2:-}"; shift 2 ;;
        --executor) executor="${2:-}"; shift 2 ;;
        --source) source="${2:-}"; shift 2 ;;
        --skill) explicit_skill="${2:-}"; shift 2 ;;
        -h|--help)
            sed -n '1,12p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown arg: $1" >&2
            exit 2
            ;;
    esac
done

if [ -z "$gate" ] || [ -z "$result" ]; then
    echo "Usage: $0 --gate <gate> --result <result> --reason <reason> [--executor <agent>] [--source <path>] [--skill <name>]" >&2
    exit 2
fi

skills_dirs="${SKILL_FEEDBACK_SKILLS_DIRS:-$HOME/.codex/skills:$HOME/.claude/skills}"

python3 - "$skills_dirs" "$explicit_skill" "$gate" "$result" "$reason" "$executor" "$source" "$LOG_SCRIPT" <<'PY'
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

skills_dirs, explicit_skill, gate, result, reason, executor, source, log_script = sys.argv[1:9]
haystack = " ".join([explicit_skill, gate, result, reason, source]).lower()


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


def trigger_terms(text):
    terms = []
    for line in text.splitlines()[:80]:
        if "TRIGGER:" not in line:
            continue
        rhs = line.split("TRIGGER:", 1)[1]
        for part in re.split(r"[、,，/()\s]+", rhs):
            part = part.strip("`'\"。:：")
            if len(part) >= 3:
                terms.append(part.lower())
    return terms


def score_skill(name, path):
    if explicit_skill and name == explicit_skill:
        return 10000
    text = path.read_text(encoding="utf-8", errors="ignore")
    score = 0
    name_l = name.lower()
    if name_l in haystack:
        score += 500 + len(name_l)
    for term in trigger_terms(text):
        if term in haystack:
            score += 100 + len(term)
    # Gate names often omit hyphens. Let "gate_report_format" match "report-format" style names.
    normalized_haystack = haystack.replace("_", "-")
    if name_l in normalized_haystack:
        score += 200 + len(name_l)
    return score


candidates = [(score_skill(name, path), name, path) for name, path in iter_skill_files()]
candidates = [item for item in candidates if item[0] > 0]
if not candidates:
    print("SKIP: skill not identified")
    raise SystemExit(0)

candidates.sort(key=lambda item: (item[0], len(item[1])), reverse=True)
_, skill, skill_file = candidates[0]
stumbling = reason or f"{gate} {result}"

if os.path.isfile(log_script) and os.access(log_script, os.X_OK):
    subprocess.run(
        ["bash", log_script, skill, executor, result, stumbling, gate, source, str(skill_file)],
        check=True,
    )

if result.upper() != "FAIL":
    print(f"LOGGED: {skill} {result}")
    raise SystemExit(0)

text = skill_file.read_text(encoding="utf-8", errors="ignore")
heading = "## 注意ポイント"
today = datetime.now().strftime("%Y-%m-%d")
reason_one = " ".join(stumbling.split())
if len(reason_one) > 180:
    reason_one = reason_one[:177] + "..."
bullet = f"- {today}: gate={gate} result=FAIL executor={executor} reason={reason_one}"

if bullet in text:
    print(f"UNCHANGED: {skill_file}")
    raise SystemExit(0)

if heading not in text:
    if text and not text.endswith("\n"):
        text += "\n"
    text += f"\n{heading}\n\n{bullet}\n"
else:
    lines = text.splitlines()
    out = []
    inserted = False
    for idx, line in enumerate(lines):
        out.append(line)
        if not inserted and line.strip() == heading:
            if idx + 1 >= len(lines) or lines[idx + 1].strip():
                out.append("")
            out.append(bullet)
            inserted = True
    text = "\n".join(out) + "\n"

fd, tmp = tempfile.mkstemp(dir=str(skill_file.parent), prefix=".SKILL.", suffix=".tmp")
os.close(fd)
Path(tmp).write_text(text, encoding="utf-8")
os.replace(tmp, skill_file)
print(f"UPDATED: {skill_file}")
PY

