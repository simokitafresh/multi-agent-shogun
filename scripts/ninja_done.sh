#!/usr/bin/env bash
# ninja_done.sh — done通知前に報告YAMLのsummary記入を強制する
# Usage: bash scripts/ninja_done.sh <ninja_name> <cmd_id>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTS_DIR="$SCRIPT_DIR/queue/reports"
ARCHIVE_REPORT_DIR="$SCRIPT_DIR/queue/archive/reports"

source "$SCRIPT_DIR/scripts/lib/field_get.sh"

usage() {
    echo "Usage: bash scripts/ninja_done.sh <ninja_name> <cmd_id>" >&2
    echo "Example: bash scripts/ninja_done.sh hayate cmd_795" >&2
}

resolve_report_file() {
    local ninja_name="$1"
    local cmd_id="$2"
    local primary_path="$REPORTS_DIR/${ninja_name}_report_${cmd_id}.yaml"

    if [ -f "$primary_path" ]; then
        printf '%s\n' "$primary_path"
        return 0
    fi

    shopt -s nullglob
    local archived_paths=("$ARCHIVE_REPORT_DIR/${ninja_name}_report_${cmd_id}_"*.yaml)
    shopt -u nullglob

    if [ "${#archived_paths[@]}" -eq 0 ]; then
        return 1
    fi

    local latest_path=""
    local latest_mtime=0
    local path=""
    local mtime=0

    for path in "${archived_paths[@]}"; do
        mtime=$(stat -c '%Y' "$path" 2>/dev/null || echo 0)
        if [ "$mtime" -gt "$latest_mtime" ]; then
            latest_mtime="$mtime"
            latest_path="$path"
        fi
    done

    if [ -n "$latest_path" ]; then
        printf '%s\n' "$latest_path"
        return 0
    fi

    return 1
}

summary_is_present() {
    local report_file="$1"
    local summary=""
    local trimmed=""

    summary=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "summary" "" 2>/dev/null || true)
    trimmed=$(printf '%s' "$summary" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

    if [ -z "$trimmed" ]; then
        return 1
    fi

    if [ "$trimmed" = "null" ]; then
        return 1
    fi

    return 0
}

main() {
    local ninja_name="${1:-}"
    local cmd_id="${2:-}"
    local report_file=""

    if [ -z "$ninja_name" ] || [ -z "$cmd_id" ]; then
        usage
        exit 1
    fi

    if [[ "$cmd_id" != cmd_* ]]; then
        echo "ERROR: cmd_id は cmd_XXX 形式で指定せよ: $cmd_id" >&2
        exit 1
    fi

    report_file=$(resolve_report_file "$ninja_name" "$cmd_id") || {
        echo "ERROR: report YAML not found for ${ninja_name}/${cmd_id}. 報告を先に書け。" >&2
        exit 1
    }

    if ! summary_is_present "$report_file"; then
        echo "ERROR: result.summary is empty in $report_file. 報告を先に書け。" >&2
        exit 1
    fi

    bash "$SCRIPT_DIR/scripts/inbox_write.sh" \
        karo \
        "${ninja_name}、任務完了。報告YAML確認されたし。" \
        report_received \
        "$ninja_name"
}

main "$@"
