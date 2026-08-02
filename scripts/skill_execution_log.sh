#!/usr/bin/env bash
# semantic-links: [[Skill設計ルール]]
# skill_execution_log.sh — skill execution outcome log.
# Usage:
#   bash scripts/skill_execution_log.sh summary
#   bash scripts/skill_execution_log.sh source-summary
#   bash scripts/skill_execution_log.sh role-summary
#   bash scripts/skill_execution_log.sh repair
#   bash scripts/skill_execution_log.sh <skill> <executor> <result> <stumbling_points> [gate] [source] [skill_path] [used]

set -euo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
REPO_ROOT="${SHOGUN_REPO_ROOT:-${_self%/scripts/skill_execution_log.sh}}"
LOG_FILE="${SKILL_EXECUTION_LOG_FILE:-$REPO_ROOT/logs/skill_execution_log.yaml}"

usage() {
    echo "Usage: $0 summary | source-summary | role-summary | repair | <skill> <executor> <result> <stumbling_points> [gate] [source] [skill_path] [used]" >&2
}

_yaml_val=""
yaml_scalar() {
    _yaml_val="${1:-}"
    _yaml_val="${_yaml_val//\\/\\\\}"
    _yaml_val="${_yaml_val//\"/\\\"}"
    _yaml_val="${_yaml_val//$'\n'/\\n}"
}

_normalized_source=""
normalize_skill_source() {
    local source_value="${1:-}"
    local base

    if [[ -z "$source_value" ]]; then
        _normalized_source=""
        return 0
    fi

    base="${source_value##*/}"
    if [[ "$base" =~ _report_(cmd_[A-Za-z0-9_.-]+)\.ya?ml$ ]]; then
        _normalized_source="${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ "$source_value" =~ (^|[[:space:]/])(cmd_[A-Za-z0-9_.-]+)([[:space:]]|$) ]]; then
        _normalized_source="${BASH_REMATCH[2]}"
        return 0
    fi

    _normalized_source="$source_value"
}

skill="${1:-}"
if [ "$skill" = "repair" ]; then
    if [ "${2:-}" ]; then
        usage
        exit 2
    fi
    lock_file="${LOG_FILE}.lock"
    (
        flock -w 30 200
        python3 - "$LOG_FILE" <<'PY'
import os
import re
import sys
import tempfile

import yaml

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
before = text
repairs = 0
while True:
    try:
        data = yaml.safe_load(text) or {}
        entries = data.get("executions") or []
        break
    except yaml.YAMLError as exc:
        mark = getattr(exc, "problem_mark", None)
        if mark is None:
            raise SystemExit("BLOCK: YAML parse failed without a repairable line")
        lines = text.splitlines(keepends=True)
        line = lines[mark.line]
        match = re.match(r'^(  [A-Za-z_][A-Za-z0-9_]*: ")(.*)("\r?\n?)$', line)
        if not match:
            raise SystemExit(f"BLOCK: non-scalar YAML damage at line {mark.line + 1}")
        body = match.group(2)
        repaired = re.sub(r'(?<!\\)"', r'\\"', body)
        if repaired == body:
            raise SystemExit(f"BLOCK: no unescaped quote found at line {mark.line + 1}")
        lines[mark.line] = match.group(1) + repaired + match.group(3)
        text = "".join(lines)
        repairs += 1

if repairs == 0:
    print(f"repair_count=0 entries={len(entries)}")
    raise SystemExit(0)

fd, tmp = tempfile.mkstemp(prefix=".skill_execution_log.", dir=os.path.dirname(path), text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)
        fh.flush()
        os.fsync(fh.fileno())
    if len(text) < len(before):
        raise SystemExit("BLOCK: repair unexpectedly reduced ledger bytes")
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
print(f"repair_count={repairs} entries={len(entries)} bytes_before={len(before.encode())} bytes_after={len(text.encode())}")
PY
    ) 200>"$lock_file"
    exit 0
fi
if [ "$skill" = "role-summary" ]; then
    if [ "${2:-}" ]; then
        usage
        exit 2
    fi
    python3 - "$LOG_FILE" <<'PY'
import sys
from collections import Counter

import yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
entries = data.get("executions") or []
ninja = {"hayate", "kagemaru", "hanzo", "saizo", "kotaro", "tobisaru", "sasuke", "kirimaru"}
known = {"shogun", "karo", "gunshi"}
counts = {role: Counter() for role in ("shogun", "karo", "gunshi", "ninja", "system", "unknown", "missing")}

for entry in entries:
    if not isinstance(entry, dict):
        continue
    executor = str(entry.get("executor") or "").strip().lower()
    if not executor:
        role = "missing"
    elif executor in known:
        role = executor
    elif executor in ninja:
        role = "ninja"
    elif executor in {"system", "simokitafresh"}:
        role = "system"
    else:
        role = "unknown"
    result = str(entry.get("result") or "").strip().upper()
    used = str(entry.get("used", True)).strip().lower() != "false"
    counts[role]["executions"] += 1
    counts[role]["used"] += int(used)
    counts[role]["pass"] += int(result == "PASS")
    counts[role]["fail"] += int(result == "FAIL")

print("role\texecutions\tpass\tfail\tused_numerator\tusage_denominator\tusage_rate")
for role in ("shogun", "karo", "gunshi", "ninja", "system", "unknown", "missing"):
    row = counts[role]
    denominator = row["executions"]
    rate = 100 * row["used"] / denominator if denominator else 0
    print(f'{role}\t{denominator}\t{row["pass"]}\t{row["fail"]}\t{row["used"]}\t{denominator}\t{rate:.2f}%')
PY
    exit 0
fi
if [ "$skill" = "source-summary" ]; then
    if [ "${2:-}" ]; then
        usage
        exit 2
    fi
    python3 - "$LOG_FILE" <<'PY'
import re
import sys
from collections import defaultdict

import yaml

path = sys.argv[1]

def scalar(raw):
    value = str(raw or "").strip()
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1].replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    return value

def load_lenient(log_path):
    entries, current = [], None
    try:
        lines = open(log_path, encoding="utf-8", errors="replace").read().splitlines()
    except FileNotFoundError:
        return entries
    for line in lines:
        if line.startswith("- "):
            if isinstance(current, dict):
                entries.append(current)
            current = {}
            rest = line[2:]
            if ":" in rest:
                key, value = rest.split(":", 1)
                current[key.strip()] = scalar(value)
        elif current is not None and line.startswith("  ") and ":" in line:
            key, value = line.strip().split(":", 1)
            current[key.strip()] = scalar(value)
    if isinstance(current, dict):
        entries.append(current)
    return entries

try:
    data = yaml.safe_load(open(path, encoding="utf-8")) or {}
    entries = data.get("executions") or []
except (FileNotFoundError, yaml.YAMLError, AttributeError):
    entries = load_lenient(path)

def cmd_id(entry):
    for text in (str(entry.get("source") or ""), str(entry.get("stumbling_points") or "")):
        match = re.search(r"\bcmd=([^ \t]+)", text)
        if match:
            return match.group(1).strip().strip('"')
    source = str(entry.get("source") or "").strip().strip('"')
    if source.startswith("cmd_"):
        return source.split()[0]
    match = re.search(r"(?:^|\s)(cmd_[A-Za-z0-9_-]+)(?:\s|$)", source)
    return match.group(1) if match else ""

def excluded(entry):
    if str(entry.get("used", True)).strip().lower() == "false":
        return True
    command = cmd_id(entry)
    if command.startswith(("cmd_test_", "cmd_training_speed_")):
        return True
    skill_name = str(entry.get("skill") or "").strip()
    if skill_name == "dashboard-update":
        if command in ("", "<empty>") or command.startswith("-"):
            return True
        if command.startswith("cmd_"):
            full = re.match(r"^cmd_\d+$", command) or re.search(r"_\d{8,}(?:_|$)", command)
            if not full:
                return True
    stumbling = str(entry.get("stumbling_points") or "")
    if skill_name == "note-draft" and re.search(
        r"reCAPTCHA challenge was not so|reCAPTCHA challenge was not solved|External reCAPTCHA challenge|reCAPTCHA image challenge blocked|LS029 Level4 guard",
        stumbling, re.I,
    ):
        return True
    return False

by_skill = defaultdict(list)
for index, entry in enumerate(entries):
    if not isinstance(entry, dict):
        continue
    # Non-executed/inferred records are outside the aggregation contract.  Drop
    # them before the last-50 window and source collapse so they cannot evict a
    # real attempt or overwrite its final result for the same source.
    if str(entry.get("used", True)).strip().lower() == "false":
        continue
    skill_name = str(entry.get("skill") or "").strip()
    result = str(entry.get("result") or "").strip().upper()
    if skill_name and result in ("PASS", "FAIL"):
        item = dict(entry)
        item["_index"] = index
        by_skill[skill_name].append(item)

print("skill\tfail_rate\tfail_count\ttotal\tsuccess_streak\tlast_result\tlast_ts")
for skill_name in sorted(by_skill):
    recent = by_skill[skill_name][-50:]
    latest = {}
    empty_seq = 0
    for entry in recent:
        source = str(entry.get("source") or "").strip()
        # An absent source cannot safely identify a retry, so it remains one attempt.
        if not source:
            empty_seq += 1
            source = f"__empty_source_{empty_seq}"
        latest[source] = entry
    final = sorted(latest.values(), key=lambda item: item["_index"])
    # Benchmark/training and malformed invocation exclusions remain observable in
    # the source denominator, but can never become unresolved operational FAILs.
    effective = ["PASS" if excluded(item) else str(item.get("result") or "").upper() for item in final]
    fail = sum(result == "FAIL" for result in effective)
    total = len(final)
    streak = 0
    for result in reversed(effective):
        if result != "PASS":
            break
        streak += 1
    last = final[-1] if final else {}
    last_result = effective[-1] if effective else ""
    rate = int(round(100 * fail / total)) if total else 0
    print(f"{skill_name}\t{rate}\t{fail}\t{total}\t{streak}\t{last_result}\t{last.get('ts', '')}")
PY
    exit 0
fi
if [ "$skill" = "summary" ]; then
    if [ "${2:-}" ]; then
        usage
        exit 2
    fi
    python3 - "$LOG_FILE" <<'PY'
import sys
from collections import Counter, defaultdict

import yaml

path = sys.argv[1]
print("skill | fail_count | last_fail | top_stumbling_point")

def parse_log_scalar(raw):
    value = str(raw or "").strip()
    if not value:
        return ""
    if value.startswith('"'):
        body = value[1:]
        if body.endswith('"'):
            body = body[:-1]
        return body.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    return value

def load_entries_lenient(log_path):
    entries = []
    current = None
    try:
        with open(log_path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except FileNotFoundError:
        return entries
    for line in lines:
        if line.startswith("- "):
            if isinstance(current, dict):
                entries.append(current)
            current = {}
            rest = line[2:]
            if ":" in rest:
                key, value = rest.split(":", 1)
                current[key.strip()] = parse_log_scalar(value)
            continue
        if current is None or not line.startswith("  ") or ":" not in line:
            continue
        key, value = line.strip().split(":", 1)
        current[key.strip()] = parse_log_scalar(value)
    if isinstance(current, dict):
        entries.append(current)
    return entries

try:
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    entries = data.get("executions") or []
except yaml.YAMLError:
    entries = load_entries_lenient(path)
except FileNotFoundError:
    sys.exit(0)

latest = {}
passes_by_skill = defaultdict(set)
for entry in entries:
    if not isinstance(entry, dict):
        continue
    if str(entry.get("used", True)).strip().lower() == "false":
        continue
    skill_name = str(entry.get("skill") or "").strip()
    if not skill_name:
        continue
    result = str(entry.get("result") or "").strip().upper()
    source = str(entry.get("source") or "").strip()
    if result == "PASS" and source:
        passes_by_skill[skill_name].add(source)
    ts = str(entry.get("ts") or "").strip()
    if skill_name not in latest or ts >= str(latest[skill_name].get("ts") or ""):
        latest[skill_name] = entry

rows = []
for skill_name, entry in latest.items():
    result = str(entry.get("result") or "").strip().upper()
    if result != "FAIL":
        continue
    fail_source = str(entry.get("source") or "").strip()
    if fail_source:
        source_resolved = any(
            pass_source == fail_source
            or pass_source.startswith(fail_source + "_")
            or fail_source.startswith(pass_source + "_")
            for pass_source in passes_by_skill.get(skill_name, set())
        )
        if source_resolved:
            continue
    last_fail = str(entry.get("ts") or "").strip()
    top_point = str(entry.get("stumbling_points") or "").strip()
    rows.append((1, last_fail, skill_name, top_point))

for fail_count, last_fail, skill_name, top_point in sorted(rows, key=lambda row: (-row[0], row[2])):
    print(f"{skill_name} | {fail_count} | {last_fail} | {top_point}")
PY
    exit 0
fi
executor="${2:-}"
result="${3:-}"
stumbling_points="${4:-}"
gate="${5:-}"
source="${6:-}"
skill_path="${7:-}"
used="${8:-true}"

if [ -z "$skill" ] || [ -z "$executor" ] || [ -z "$result" ]; then
    usage
    exit 2
fi

case "$source" in
    tests/*|*/tests/*)
        exit 0
        ;;
esac
normalize_skill_source "$source"
source="$_normalized_source"

mkdir -p "$(dirname "$LOG_FILE")"
lock_file="${LOG_FILE}.lock"
TZ=JST-9 printf -v ts '%(%Y-%m-%dT%H:%M:%S+0900)T' -1

(
    flock -w 5 200
    if [ ! -s "$LOG_FILE" ]; then
        printf 'executions:\n' > "$LOG_FILE"
    fi
    yaml_scalar "$ts";              printf -- '- ts: "%s"\n'             "$_yaml_val"
    yaml_scalar "$skill";           printf   '  skill: "%s"\n'           "$_yaml_val"
    yaml_scalar "$executor";        printf   '  executor: "%s"\n'        "$_yaml_val"
    yaml_scalar "$result";          printf   '  result: "%s"\n'          "$_yaml_val"
    yaml_scalar "$used";            printf   '  used: "%s"\n'            "$_yaml_val"
    yaml_scalar "$stumbling_points"; printf  '  stumbling_points: "%s"\n' "$_yaml_val"
    if [ -n "$gate" ]; then
        yaml_scalar "$gate"; printf '  gate: "%s"\n' "$_yaml_val"
    fi
    if [ -n "$source" ]; then
        yaml_scalar "$source"; printf '  source: "%s"\n' "$_yaml_val"
    fi
    if [ -n "$skill_path" ]; then
        yaml_scalar "$skill_path"; printf '  skill_path: "%s"\n' "$_yaml_val"
    fi
) >> "$LOG_FILE" 200>"$lock_file"
