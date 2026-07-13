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
    grep -qE "^[[:space:]]*(parent_cmd|cmd_id):[[:space:]]*['\"]?${escaped}['\"]?[[:space:]]*(#.*)?$" "$task_file" 2>/dev/null
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
