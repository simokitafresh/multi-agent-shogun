#!/usr/bin/env bash
# semantic-links: [[Skill設計ルール]]
# skill_execution_log.sh — skill execution outcome log.
# Usage:
#   bash scripts/skill_execution_log.sh summary
#   bash scripts/skill_execution_log.sh <skill> <executor> <result> <stumbling_points> [gate] [source] [skill_path] [used]

set -euo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
REPO_ROOT="${SHOGUN_REPO_ROOT:-${_self%/scripts/skill_execution_log.sh}}"
LOG_FILE="${SKILL_EXECUTION_LOG_FILE:-$REPO_ROOT/logs/skill_execution_log.yaml}"

usage() {
    echo "Usage: $0 summary | <skill> <executor> <result> <stumbling_points> [gate] [source] [skill_path] [used]" >&2
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
