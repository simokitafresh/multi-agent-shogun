#!/usr/bin/env bash
# One atomic status/identity boundary for task YAML idle transitions.
_TL_SELF="${BASH_SOURCE[0]}"
[[ "$_TL_SELF" != /* ]] && _TL_SELF="$PWD/$_TL_SELF"
_TL_ROOT="${_TL_SELF%/scripts/lib/task_lifecycle.sh}"
declare -F yaml_field_set_batch >/dev/null 2>&1 || source "$_TL_ROOT/scripts/lib/yaml_field_set.sh"
declare -F field_get >/dev/null 2>&1 || source "$_TL_ROOT/scripts/lib/field_get.sh"

task_lifecycle_set_idle() {
    local file="${1:-}" reason="${2:-idle_transition}" status task_id parent_cmd ac_task_id report_path report_filename at
    [ -f "$file" ] || return 1
    status="$(FIELD_GET_NO_LOG=1 field_get "$file" status "" 2>/dev/null || true)"
    case "$status" in assigned|acknowledged|in_progress|pending|done|completed|failed|idle|"") ;; *) return 1 ;; esac
    if ! awk '/^task:[[:space:]]*$/ { found=1; exit } END { exit(found ? 0 : 1) }' "$file"; then
        # Legacy flat fixtures have no nested identity contract; preserve their
        # compatibility status-only transition through the canonical setter.
        yaml_field_set "$file" "" status idle
        return $?
    fi
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$file" task_id parent_cmd _ac_task_id report_path report_filename 2>/dev/null)" || true
    printf -v at '%(%Y-%m-%dT%H:%M:%S%z)T' -1
    yaml_field_set_batch "$file" task \
        status=idle task_id= parent_cmd= _ac_task_id= report_path= report_filename= \
        "last_task_id=${task_id:-}" "last_parent_cmd=${parent_cmd:-}" \
        "last_ac_task_id=${_ac_task_id:-}" "last_report_path=${report_path:-}" \
        "last_report_filename=${report_filename:-}" "lifecycle_transition_at=$at" \
        "lifecycle_transition_reason=$reason"
}
