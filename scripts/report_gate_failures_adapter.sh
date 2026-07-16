#!/usr/bin/env bash
# report_gate_failures_adapter.sh — campaign-lane adapter for report gate failure reduction
# Reads gate_metrics.log to find top failure reasons and select improvement targets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE_LOG="$PROJECT_DIR/logs/gate_fire_log.yaml"
MEASUREMENT_LOG="$PROJECT_DIR/logs/report_gate_failure_measurements.jsonl"

_get_failure_targets() {
    [ -f "$GATE_LOG" ] || return 0
    # Log format: single-line with gate: "gate_report_format", result: FAIL, reasons: "field1; field2"
    grep 'gate_report_format.*result: FAIL' "$GATE_LOG" 2>/dev/null | \
        sed 's/.*reasons: "\(.*\)"/\1/' | tr ';' '\n' | \
        sed 's/^[[:space:]]*//' | grep -v '^$' | \
        sed 's/\([^:]*\):.*/\1/' | sort | uniq -c | sort -rn | \
        awk '{count=$1; $1=""; sub(/^ /, ""); printf "%s|%d\n", $0, count}'
}

cmd_next() {
    local targets
    targets=$(_get_failure_targets)
    if [ -z "$targets" ]; then
        echo '{"status":"no_target","reason":"no recurring report gate failures"}'
        return 0
    fi
    local first reason count total
    first=$(echo "$targets" | head -1)
    reason="${first%%|*}"
    count="${first##*|}"
    total=$(echo "$targets" | wc -l)
    echo "{\"status\":\"target_found\",\"target\":\"$reason\",\"occurrences\":$count,\"remaining\":$total}"
}

cmd_status() {
    local targets
    targets=$(_get_failure_targets)
    local count=0
    [ -n "$targets" ] && count=$(echo "$targets" | wc -l)
    echo "failure_reason_count: $count"
    if [ "$count" -gt 0 ]; then
        echo "targets:"
        echo "$targets" | head -10 | while IFS='|' read -r reason cnt; do
            echo "  - reason: \"$reason\""
            echo "    occurrences: $cnt"
        done
    fi
}

cmd_record() {
    local reason="${1:?reason required}"
    local result="${2:?pass|fail required}"
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
    mkdir -p "$(dirname "$MEASUREMENT_LOG")"
    (
        flock -w 5 9 || exit 1
        printf '{"target":"%s","status":"%s","measured_at":"%s"}\n' \
            "$reason" "$result" "$ts" >> "$MEASUREMENT_LOG"
    ) 9>"${MEASUREMENT_LOG}.lock"
    echo "RECORDED: $reason $result at $ts"
}

case "${1:-}" in
    next)    cmd_next ;;
    status)  cmd_status ;;
    record)  cmd_record "${2:-}" "${3:-}" ;;
    *)       echo "Usage: $0 {next|status|record <reason> <pass|fail>}"; exit 1 ;;
esac
