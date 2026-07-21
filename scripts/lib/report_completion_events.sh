#!/usr/bin/env bash
# test_necessity: report completion aliases must remain one shared contract for
# inbox acceptance and durable monitor evidence checks.

if ! declare -p REPORT_COMPLETION_EVENT_TYPES >/dev/null 2>&1; then
    readonly REPORT_COMPLETION_EVENT_TYPES="report_received report_submitted task_done report_completed report_done report_ready task_failed"
fi

report_completion_event_type() {
    local candidate="$1" event
    for event in $REPORT_COMPLETION_EVENT_TYPES; do
        [ "$candidate" = "$event" ] && return 0
    done
    return 1
}

report_completion_event_types_regex() {
    printf '%s' "$REPORT_COMPLETION_EVENT_TYPES" | tr ' ' '|'
}
