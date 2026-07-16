#!/usr/bin/env bash
# Report document completion and task outcome are separate dimensions.
# Print one of: CLOSED_BLOCKED, SUCCESS, OPEN, UNKNOWN.
report_terminal_state() {
    local report_file="$1"
    local status verdict status_detail

    [ -f "$report_file" ] || { printf '%s\n' "UNKNOWN"; return 0; }
    read -r status verdict status_detail < <(awk '
        /^status:/ && status=="" { status=$0; sub(/^[^:]*:[[:space:]]*/, "", status); gsub(/["'"'"'[:space:]]/, "", status) }
        /^verdict:/ && verdict=="" { verdict=$0; sub(/^[^:]*:[[:space:]]*/, "", verdict); gsub(/["'"'"'[:space:]]/, "", verdict) }
        /^status_detail:/ && detail=="" { detail=$0; sub(/^[^:]*:[[:space:]]*/, "", detail); gsub(/["'"'"'[:space:]]/, "", detail) }
        END { print status, verdict, detail }
    ' "$report_file" 2>/dev/null)

    [ "$status" = "completed" ] || { printf '%s\n' "OPEN"; return 0; }
    if [ "$verdict" = "FAIL" ] || [ "$status_detail" = "BLOCKED" ]; then
        printf '%s\n' "CLOSED_BLOCKED"
    elif [ "$verdict" = "PASS" ] || [ "$verdict" = "PASS_NO_IMPROVEMENT" ]; then
        printf '%s\n' "SUCCESS"
    else
        printf '%s\n' "UNKNOWN"
    fi
}
