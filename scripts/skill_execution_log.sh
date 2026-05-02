#!/usr/bin/env bash
# skill_execution_log.sh — skill execution outcome log.
# Usage:
#   bash scripts/skill_execution_log.sh <skill> <executor> <result> <stumbling_points> [gate] [source] [skill_path]

set -euo pipefail

REPO_ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_FILE="${SKILL_EXECUTION_LOG_FILE:-$REPO_ROOT/logs/skill_execution_log.yaml}"

usage() {
    echo "Usage: $0 <skill> <executor> <result> <stumbling_points> [gate] [source] [skill_path]" >&2
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
executor="${2:-}"
result="${3:-}"
stumbling_points="${4:-}"
gate="${5:-}"
source="${6:-}"
skill_path="${7:-}"

if [ -z "$skill" ] || [ -z "$executor" ] || [ -z "$result" ]; then
    usage
    exit 2
fi

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

