#!/usr/bin/env bash
# skill_execution_log.sh — skill execution outcome log.
# Usage:
#   bash scripts/skill_execution_log.sh summary
#   bash scripts/skill_execution_log.sh <skill> <executor> <result> <stumbling_points> [gate] [source] [skill_path] [used]

set -euo pipefail

REPO_ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_FILE="${SKILL_EXECUTION_LOG_FILE:-$REPO_ROOT/logs/skill_execution_log.yaml}"

usage() {
    echo "Usage: $0 summary | <skill> <executor> <result> <stumbling_points> [gate] [source] [skill_path] [used]" >&2
}

yaml_scalar() {
    python3 - "$1" <<'PY'
import sys
value = sys.argv[1]
value = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
print(f'"{value}"')
PY
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
try:
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except FileNotFoundError:
    sys.exit(0)

entries = data.get("executions") or []
stats = defaultdict(lambda: {"fail_count": 0, "last_fail": "", "points": Counter()})
for entry in entries:
    if not isinstance(entry, dict):
        continue
    result = str(entry.get("result") or "").strip().upper()
    if result != "FAIL":
        continue
    if str(entry.get("used", True)).strip().lower() == "false":
        continue
    skill_name = str(entry.get("skill") or "").strip()
    if not skill_name:
        continue
    item = stats[skill_name]
    item["fail_count"] += 1
    ts = str(entry.get("ts") or "").strip()
    if ts and ts >= item["last_fail"]:
        item["last_fail"] = ts
    point = str(entry.get("stumbling_points") or "").strip()
    if point:
        item["points"][point] += 1

rows = []
for skill_name, item in stats.items():
    top_point = ""
    if item["points"]:
        top_point = sorted(item["points"].items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
    rows.append((item["fail_count"], item["last_fail"], skill_name, top_point))

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

mkdir -p "$(dirname "$LOG_FILE")"
lock_file="${LOG_FILE}.lock"
ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"

(
    flock -w 10 200
    if [ ! -s "$LOG_FILE" ]; then
        printf 'executions:\n' > "$LOG_FILE"
    fi
    {
        printf -- '- ts: %s\n' "$(yaml_scalar "$ts")"
        printf '  skill: %s\n' "$(yaml_scalar "$skill")"
        printf '  executor: %s\n' "$(yaml_scalar "$executor")"
        printf '  result: %s\n' "$(yaml_scalar "$result")"
        printf '  used: %s\n' "$(yaml_scalar "$used")"
        printf '  stumbling_points: %s\n' "$(yaml_scalar "$stumbling_points")"
        [ -n "$gate" ] && printf '  gate: %s\n' "$(yaml_scalar "$gate")"
        [ -n "$source" ] && printf '  source: %s\n' "$(yaml_scalar "$source")"
        [ -n "$skill_path" ] && printf '  skill_path: %s\n' "$(yaml_scalar "$skill_path")"
    } >> "$LOG_FILE"
) 200>"$lock_file"

python3 - "$LOG_FILE" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding="utf-8") as fh:
    yaml.safe_load(fh)
PY
