#!/usr/bin/env bash
# detector_fp_adapter.sh — campaign-lane adapter for detector false-positive reduction
# Reads detector_fp_rate.yaml to select highest-FP detectors as improvement targets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FP_FILE="$PROJECT_DIR/logs/detector_fp_rate.yaml"
MEASUREMENT_LOG="$PROJECT_DIR/logs/detector_fp_measurements.jsonl"
MIN_FIRES=3  # ignore detectors with <3 fires (sample too small)

_get_fp_targets() {
    [ -f "$FP_FILE" ] || return 0
    awk -v min="$MIN_FIRES" '
        /^  - detector:/ { det=$3; gsub(/"/, "", det) }
        /fires:/ { fires=$2 }
        /false_positive:/ { fp=$2 }
        /fp_rate:/ {
            rate=$2;
            if (fires+0 >= min+0 && rate+0 > 0)
                printf "%s|%.1f|%d|%d\n", det, rate, fp, fires
        }
    ' "$FP_FILE" | sort -t'|' -k2 -rn
}

cmd_next() {
    local targets
    targets=$(_get_fp_targets)
    if [ -z "$targets" ]; then
        echo '{"status":"no_target","reason":"no detector exceeds FP threshold with sufficient samples"}'
        return 0
    fi
    local first det rate fp fires count
    first=$(echo "$targets" | head -1)
    IFS='|' read -r det rate fp fires <<< "$first"
    count=$(echo "$targets" | wc -l)
    echo "{\"status\":\"target_found\",\"target\":\"$det\",\"fp_rate\":$rate,\"false_positives\":$fp,\"fires\":$fires,\"remaining\":$count}"
}

cmd_status() {
    local targets
    targets=$(_get_fp_targets)
    local count=0
    [ -n "$targets" ] && count=$(echo "$targets" | wc -l)
    echo "fp_detector_count: $count"
    if [ "$count" -gt 0 ]; then
        echo "targets:"
        echo "$targets" | while IFS='|' read -r det rate fp fires; do
            echo "  - detector: $det"
            echo "    fp_rate: $rate"
            echo "    false_positives: $fp"
            echo "    fires: $fires"
        done
    fi
}

cmd_record() {
    local detector="${1:?detector required}"
    local result="${2:?pass|fail required}"
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
    mkdir -p "$(dirname "$MEASUREMENT_LOG")"
    (
        flock -w 5 9 || exit 1
        printf '{"target":"%s","status":"%s","measured_at":"%s"}\n' \
            "$detector" "$result" "$ts" >> "$MEASUREMENT_LOG"
    ) 9>"${MEASUREMENT_LOG}.lock"
    echo "RECORDED: $detector $result at $ts"
}

case "${1:-}" in
    next)    cmd_next ;;
    status)  cmd_status ;;
    record)  cmd_record "${2:-}" "${3:-}" ;;
    *)       echo "Usage: $0 {next|status|record <detector> <pass|fail>}"; exit 1 ;;
esac
