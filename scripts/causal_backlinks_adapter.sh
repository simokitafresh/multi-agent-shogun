#!/usr/bin/env bash
# causal_backlinks_adapter.sh — campaign-lane adapter for backlinks=0 resolution
# Reads causal_backlink_counts.sh to find zero-backlink files and select targets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COUNTER="$SCRIPT_DIR/causal_backlink_counts.sh"
MEASUREMENT_LOG="$PROJECT_DIR/logs/causal_backlinks_measurements.jsonl"

_get_zero_backlink() {
    bash "$COUNTER" 2>/dev/null | awk '$1 == 0 {print $2 "|" $3}'
}

cmd_next() {
    local targets
    targets=$(_get_zero_backlink)
    if [ -z "$targets" ]; then
        echo '{"status":"no_target","reason":"all files have backlinks"}'
        return 0
    fi
    local first file_path link_id count
    first=$(echo "$targets" | head -1)
    file_path="${first%%|*}"
    link_id="${first##*|}"
    count=$(echo "$targets" | wc -l)
    echo "{\"status\":\"target_found\",\"target\":\"$file_path\",\"link_id\":\"$link_id\",\"remaining\":$count}"
}

cmd_status() {
    local targets
    targets=$(_get_zero_backlink)
    local count=0
    [ -n "$targets" ] && count=$(echo "$targets" | wc -l)
    echo "zero_backlink_count: $count"
    if [ "$count" -gt 0 ]; then
        echo "targets:"
        echo "$targets" | while IFS='|' read -r fpath lid; do
            echo "  - file: $fpath"
            echo "    link_id: $lid"
        done
    fi
}

cmd_record() {
    local file_path="${1:?file_path required}"
    local result="${2:?pass|fail required}"
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
    mkdir -p "$(dirname "$MEASUREMENT_LOG")"
    (
        flock -w 5 9 || exit 1
        printf '{"target":"%s","status":"%s","value":%d,"measured_at":"%s"}\n' \
            "$file_path" "$result" "$([ "$result" = "pass" ] && echo 0 || echo 1)" "$ts" \
            >> "$MEASUREMENT_LOG"
    ) 9>"${MEASUREMENT_LOG}.lock"
    echo "RECORDED: $file_path $result at $ts"
}

case "${1:-}" in
    next)    cmd_next ;;
    status)  cmd_status ;;
    record)  cmd_record "${2:-}" "${3:-}" ;;
    *)       echo "Usage: $0 {next|status|record <path> <pass|fail>}"; exit 1 ;;
esac
