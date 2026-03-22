#!/usr/bin/env bash
set -euo pipefail

# task_queue_status.sh — タスクキュー状態一覧表示
# Usage: bash scripts/task_queue_status.sh [--cmd <cmd_id>] [--help]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$SCRIPT_DIR/queue/tasks"

usage() {
    cat <<'EOF'
Usage: bash scripts/task_queue_status.sh [OPTIONS]

Options:
  --cmd <cmd_id>   Show only tasks for the specified cmd (e.g. cmd_323)
  --help           Show this help message

Output: Column-aligned table of all task YAML files in queue/tasks/
EOF
    exit 0
}

# Parse arguments
CMD_FILTER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cmd)
            [[ $# -lt 2 ]] && { echo "Error: --cmd requires an argument" >&2; exit 1; }
            CMD_FILTER="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            usage
            ;;
    esac
done

# Extract a YAML field value from a file (2-space indented, under task:)
# L034: Use flexible whitespace matching, not fixed indent
# L010: grep -m1 to avoid matching nested fields
extract_field() {
    local file="$1"
    local field="$2"
    grep -m1 "^[[:space:]]*${field}:" "$file" 2>/dev/null \
        | sed "s/^[[:space:]]*${field}:[[:space:]]*//" \
        | sed 's/^["'"'"']\(.*\)["'"'"']$/\1/' \
        | sed 's/[[:space:]]*$//'
}

# Counters for summary
declare -A STATUS_COUNT
STATUS_COUNT[assigned]=0
STATUS_COUNT[acknowledged]=0
STATUS_COUNT[in_progress]=0
STATUS_COUNT[done]=0

# Header
echo "=== Task Queue Status ==="
printf "%-11s %-32s %-14s %-10s %s\n" "NINJA" "TASK_ID" "STATUS" "CMD" "TYPE"
echo "─────────────────────────────────────────────────────────────────────────────────"

ROW_COUNT=0

for yaml_file in "$TASKS_DIR"/*.yaml; do
    [[ ! -f "$yaml_file" ]] && continue

    ninja=$(extract_field "$yaml_file" "assigned_to")
    task_id=$(extract_field "$yaml_file" "task_id")
    status=$(extract_field "$yaml_file" "status")
    parent_cmd=$(extract_field "$yaml_file" "parent_cmd")
    task_type=$(extract_field "$yaml_file" "task_type")

    # Skip files with missing essential fields
    [[ -z "$ninja" || -z "$task_id" ]] && continue

    # Apply --cmd filter
    if [[ -n "$CMD_FILTER" && "$parent_cmd" != "$CMD_FILTER" ]]; then
        continue
    fi

    printf "%-11s %-32s %-14s %-10s %s\n" \
        "$ninja" "$task_id" "$status" "$parent_cmd" "$task_type"

    ROW_COUNT=$((ROW_COUNT + 1))

    # Increment status counter
    if [[ -n "$status" && -v "STATUS_COUNT[$status]" ]]; then
        STATUS_COUNT[$status]=$(( ${STATUS_COUNT[$status]} + 1 ))
    fi
done

echo ""
echo "Summary: assigned=${STATUS_COUNT[assigned]}, acknowledged=${STATUS_COUNT[acknowledged]}, in_progress=${STATUS_COUNT[in_progress]}, done=${STATUS_COUNT[done]} (total=${ROW_COUNT})"
