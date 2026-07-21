#!/usr/bin/env bash
# Report document completion and task outcome are separate dimensions.
# Print one of: CLOSED_BLOCKED, SUCCESS, OPEN, UNKNOWN.
report_terminal_state() {
    local report_file="$1"
    local status verdict status_detail

    [ -f "$report_file" ] || { printf '%s\n' "UNKNOWN"; return 0; }
    # A report containing an unfilled template marker is not terminal evidence,
    # even when its status fields happen to look terminal.
    if grep -q 'FILL_THIS' "$report_file" 2>/dev/null; then
        printf '%s\n' "OPEN"
        return 0
    fi
    IFS='|' read -r status verdict status_detail < <(awk '
        /^status:/ && status=="" { status=$0; sub(/^[^:]*:[[:space:]]*/, "", status); gsub(/["'"'"'[:space:]]/, "", status) }
        /^verdict:/ && verdict=="" { verdict=$0; sub(/^[^:]*:[[:space:]]*/, "", verdict); gsub(/["'"'"'[:space:]]/, "", verdict) }
        /^status_detail:/ && detail=="" { detail=$0; sub(/^[^:]*:[[:space:]]*/, "", detail); gsub(/["'"'"'[:space:]]/, "", detail) }
        END { print status "|" verdict "|" detail }
    ' "$report_file" 2>/dev/null)

    # report_field_set.sh normalizes a terminal report containing a failed
    # binary check to status=failed/verdict=FAIL.  That document is complete;
    # "failed" describes the task outcome, not an unfinished report.
    if { [ "$status" = "completed" ] || [ "$status" = "failed" ]; } &&
       { [ "$verdict" = "FAIL" ] || [ "$status_detail" = "BLOCKED" ]; }; then
        printf '%s\n' "CLOSED_BLOCKED"
    elif [ "$status" = "completed" ] &&
         { [ "$verdict" = "PASS" ] || [ "$verdict" = "PASS_NO_IMPROVEMENT" ]; }; then
        printf '%s\n' "SUCCESS"
    elif [ -z "$status" ]; then
        printf '%s\n' "UNKNOWN"
    else
        printf '%s\n' "OPEN"
    fi
}
