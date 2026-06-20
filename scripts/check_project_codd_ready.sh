#!/usr/bin/env bash
set -euo pipefail

# check_project_codd_ready.sh — Verify CoDD initialization for a registered project.
# Usage:
#   bash scripts/check_project_codd_ready.sh <project-id>
#   bash scripts/check_project_codd_ready.sh --path <project-path> [project-id]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECTS_YAML="$REPO_ROOT/config/projects.yaml"
CODD_BIN="${CODD_BIN:-${HOME}/.codd-venv/bin/codd}"

usage() {
    echo "Usage: $0 <project-id> | --path <project-path> [project-id]" >&2
}

resolve_project_path() {
    local project_id="$1"
    awk -v target="$project_id" '
        /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/ {
            value = $0
            sub(/^[^:]*:[[:space:]]*/, "", value)
            gsub(/["'\''"]/, "", value)
            in_project = (value == target)
            next
        }
        in_project && /^[[:space:]]*path:[[:space:]]*/ {
            value = $0
            sub(/^[^:]*:[[:space:]]*/, "", value)
            gsub(/["'\''"]/, "", value)
            print value
            exit
        }
    ' "$PROJECTS_YAML"
}

if [[ $# -lt 1 ]]; then
    usage
    exit 2
fi

PROJECT_ID=""
PROJECT_PATH=""

if [[ "${1:-}" == "--path" ]]; then
    if [[ $# -lt 2 ]]; then
        usage
        exit 2
    fi
    PROJECT_PATH="$2"
    PROJECT_ID="${3:-unknown}"
else
    PROJECT_ID="$1"
    PROJECT_PATH="$(resolve_project_path "$PROJECT_ID")"
fi

if [[ -z "$PROJECT_PATH" ]]; then
    echo "ALERT: codd prerequisite check failed for ${PROJECT_ID}: project path not found in config/projects.yaml" >&2
    exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "ALERT: codd prerequisite check failed for ${PROJECT_ID}: project path missing: ${PROJECT_PATH}" >&2
    exit 1
fi

if [[ ! -f "$PROJECT_PATH/codd/codd.yaml" && ! -f "$PROJECT_PATH/codd.yaml" ]]; then
    echo "ALERT: codd not initialized for ${PROJECT_ID}: run codd init --suggest-lexicons --llm-enhanced --dest ${PROJECT_PATH}" >&2
    exit 1
fi

if [[ ! -x "$CODD_BIN" ]]; then
    echo "ALERT: codd prerequisite check failed for ${PROJECT_ID}: codd binary missing: ${CODD_BIN}" >&2
    exit 1
fi

# Fast path: read project_lexicon.yaml directly instead of running codd lexicon list.
# codd stores installed lexicons in project_lexicon.yaml `extends:` list.
LEXICON_FILE="$PROJECT_PATH/project_lexicon.yaml"
if [[ -f "$LEXICON_FILE" ]]; then
    installed_count="$(awk '
        /^extends:/ { inext=1; next }
        inext && /^[[:space:]]*-/ { count++ }
        inext && /^[^[:space:]]/ { exit }
        END { print count+0 }
    ' "$LEXICON_FILE")"
else
    installed_count=0
fi

if [[ -z "$installed_count" || "$installed_count" -lt 1 ]]; then
    echo "ALERT: codd lexicon not installed for ${PROJECT_ID}: run codd lexicon install --path ${PROJECT_PATH} shogun_core" >&2
    exit 1
fi

echo "OK: codd ready for ${PROJECT_ID} (${PROJECT_PATH}); installed_lexicons=${installed_count}"
