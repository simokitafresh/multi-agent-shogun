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

skills_dirs="${SKILL_FEEDBACK_SKILLS_DIRS:-${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/skills:$HOME/.codex/skills:$HOME/.claude/skills}"

python3 - "$skills_dirs" "$explicit_skill" "$gate" "$result" "$reason" "$executor" "$source" "$LOG_SCRIPT" <<'PY'
import os
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

import yaml

skills_dirs, explicit_skill, gate, result, reason, executor, source, log_script = sys.argv[1:9]


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


def skill_log_file():
    env_path = os.environ.get("SKILL_EXECUTION_LOG_FILE")
    if env_path:
        return Path(env_path)
    return Path(log_script).resolve().parent.parent / "logs" / "skill_execution_log.yaml"


def load_skill_log():
    path = skill_log_file()
    if not path.is_file():
        return []
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception:
        return []
    entries = data.get("executions") or []
    return [entry for entry in entries if isinstance(entry, dict)]


def latest_fail_entry():
    matches = []
    for entry in load_skill_log():
        if str(entry.get("result", "")).strip().upper() != "FAIL":
            continue
        if str(entry.get("used", True)).strip().lower() == "false":
            continue
        entry_gate = str(entry.get("gate") or "").strip()
        entry_source = str(entry.get("source") or "").strip()
        entry_points = str(entry.get("stumbling_points") or "").strip()
        if gate and entry_gate != gate:
            continue
        if source and entry_source == source:
            matches.append((3, entry))
            continue
        if reason and entry_points == reason:
            matches.append((2, entry))
            continue
        matches.append((1, entry))
    if not matches:
        return None
    best_priority = max(priority for priority, _ in matches)
    best = [entry for priority, entry in matches if priority == best_priority]
    return best[-1]


def exact_skill_file(skill_name, logged_path=""):
    if logged_path:
        path = Path(os.path.expanduser(str(logged_path)))
        if path.is_file():
            return path
    for name, path in iter_skill_files():
        if name == skill_name:
            return path
    return None


def has_duplicate_failure(skill_name, gate_name, stumbling_points):
    for entry in load_skill_log():
        if (
            str(entry.get("skill", "")) == skill_name
            and str(entry.get("gate", "")) == gate_name
            and str(entry.get("stumbling_points", "")) == stumbling_points
        ):
            return True
    return False


def has_duplicate_caution(text, gate_name, reason_text):
    for line in text.splitlines():
        if line.lstrip().startswith("- ") and f"gate={gate_name}" in line and f"reason={reason_text}" in line:
            return True
    return False


logged_entry = None if explicit_skill else latest_fail_entry()
logged_skill = ""
logged_skill_path = ""
if logged_entry:
    logged_skill = str(logged_entry.get("skill") or "").strip()
    logged_skill_path = str(logged_entry.get("skill_path") or "").strip()

skill = explicit_skill or logged_skill
skill_file = exact_skill_file(skill, logged_skill_path)
if not skill or not skill_file:
    print("SKIP: skill not identified")
    raise SystemExit(0)

stumbling = str(logged_entry.get("stumbling_points") or "").strip() if logged_entry else ""
if not stumbling:
    stumbling = reason or f"{gate} {result}"

if not logged_entry and result.upper() == "FAIL" and has_duplicate_failure(skill, gate, stumbling):
    print(f"DUPLICATE: {skill} gate={gate}")
    raise SystemExit(0)

if not logged_entry and os.path.isfile(log_script) and os.access(log_script, os.X_OK):
    subprocess.run(
        ["bash", log_script, skill, executor, result, stumbling, gate, source, str(skill_file), "false"],
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

if has_duplicate_caution(text, gate, reason_one):
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
