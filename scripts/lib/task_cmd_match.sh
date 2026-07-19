#!/usr/bin/env bash
# Exact task-to-command matching shared by lifecycle tools.

task_cmd_regex_escape() {
    printf '%s' "$1" | sed 's/[][\\.^$*+?{}()|/]/\\&/g'
}

task_file_matches_cmd() {
    local task_file="$1"
    local cmd_id="$2"
    local escaped
    escaped=$(task_cmd_regex_escape "$cmd_id")

    # parent_cmd is the lifecycle SSOT for current-format task files.  Idle
    # reset deliberately clears it while compatibility metadata such as
    # cmd_id/issued_cmd_id may remain for chronology.  Falling back to that
    # stale cmd_id made a completed command rediscover an idle worker and its
    # old pending report, permanently blocking two-phase review.
    if grep -qE "^[[:space:]]*parent_cmd:" "$task_file" 2>/dev/null; then
        grep -qE "^[[:space:]]*parent_cmd:[[:space:]]*['\"]?${escaped}['\"]?[[:space:]]*(#.*)?$" "$task_file" 2>/dev/null
        return
    fi

    # Legacy task documents without a parent_cmd field retain cmd_id support.
    grep -qE "^[[:space:]]*cmd_id:[[:space:]]*['\"]?${escaped}['\"]?[[:space:]]*(#.*)?$" "$task_file" 2>/dev/null
}

list_task_files_for_cmd() {
    local tasks_dir="$1"
    local cmd_id="$2"
    local task_file
    for task_file in "$tasks_dir"/*.yaml; do
        [ -f "$task_file" ] || continue
        task_file_matches_cmd "$task_file" "$cmd_id" && printf '%s\n' "$task_file"
    done
    return 0
}
