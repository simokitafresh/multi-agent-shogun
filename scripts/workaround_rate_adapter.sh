#!/usr/bin/env bash
# workaround_rate_adapter.sh — campaign-lane adapter for workaround rate reduction
# Reads karo_workarounds.yaml to find top root_signature categories.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WA_FILE="$PROJECT_DIR/logs/karo_workarounds.yaml"
MEASUREMENT_LOG="$PROJECT_DIR/logs/workaround_rate_measurements.jsonl"

_get_wa_targets() {
    [ -f "$WA_FILE" ] || return 0
    grep "root_signature:" "$WA_FILE" 2>/dev/null | \
        sed "s/.*root_signature: ['\"]*\([^'\"]*\)['\"]*$/\1/" | \
        sort | uniq -c | sort -rn | \
        awk '$1 >= 2 {count=$1; $1=""; sub(/^ /, ""); printf "%s|%d\n", $0, count}'
}

cmd_next() {
    local targets
    targets=$(_get_wa_targets)
    if [ -z "$targets" ]; then
        echo '{"status":"no_target","reason":"no recurring workaround categories (min 2)"}'
        return 0
    fi
    local first cat count total
    first=$(echo "$targets" | head -1)
    cat="${first%%|*}"
    count="${first##*|}"
    total=$(echo "$targets" | wc -l)
    echo "{\"status\":\"target_found\",\"target\":\"$cat\",\"occurrences\":$count,\"remaining\":$total}"
}

cmd_status() {
    local targets
    targets=$(_get_wa_targets)
    local count=0
    if [ -n "$targets" ]; then
        count=$(echo "$targets" | wc -l)
    fi
    echo "recurring_wa_count: $count"
    if [ "$count" -gt 0 ]; then
        echo "targets:"
        echo "$targets" | while IFS='|' read -r cat cnt; do
            echo "  - category: \"$cat\""
            echo "    occurrences: $cnt"
        done
    fi
}

cmd_record() {
    local category="${1:?category required}"
    local result="${2:?pass|fail required}"
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
    mkdir -p "$(dirname "$MEASUREMENT_LOG")"
    (
        flock -w 5 9 || exit 1
        printf '{"target":"%s","status":"%s","measured_at":"%s"}\n' \
            "$category" "$result" "$ts" >> "$MEASUREMENT_LOG"
    ) 9>"${MEASUREMENT_LOG}.lock"
    echo "RECORDED: $category $result at $ts"
}

case "${1:-}" in
    next)    cmd_next ;;
    status)  cmd_status ;;
    record)  cmd_record "${2:-}" "${3:-}" ;;
    *)       echo "Usage: $0 {next|status|record <category> <pass|fail>}"; exit 1 ;;
esac
