#!/usr/bin/env bash
# ninja_done.sh — done通知前に報告YAMLのsummary記入を強制する
# Usage: bash scripts/ninja_done.sh <ninja_name> <parent_cmd>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTS_DIR="$SCRIPT_DIR/queue/reports"
ARCHIVE_REPORT_DIR="$SCRIPT_DIR/queue/archive/reports"

usage() {
    echo "Usage: bash scripts/ninja_done.sh <ninja_name> <parent_cmd>" >&2
    echo "Example: bash scripts/ninja_done.sh hayate cmd_795" >&2
    echo "Note: parent_cmd must be cmd_XXX (digits only). task_id like cmd_795_review is invalid." >&2
}

show_help() {
    echo "Usage: bash scripts/ninja_done.sh <ninja_name> <parent_cmd>"
    echo "Example: bash scripts/ninja_done.sh hayate cmd_795"
    echo "Note: parent_cmd must be cmd_XXX (digits only). task_id like cmd_795_review is invalid."
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
    local path=""

    for path in "${archived_paths[@]}"; do
        if [ -z "$latest_path" ] || [ "$path" -nt "$latest_path" ]; then
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

    summary=$(
        awk '
            function trim(s) {
                sub(/^[[:space:]]+/, "", s)
                sub(/[[:space:]]+$/, "", s)
                return s
            }
            function unquote(s, q) {
                q = substr(s, 1, 1)
                if ((q == "\"" || q == "'\''") && substr(s, length(s), 1) == q) {
                    return substr(s, 2, length(s) - 2)
                }
                return s
            }
            function indent_of(line) {
                if (match(line, /[^ ]/)) {
                    return RSTART - 1
                }
                return length(line)
            }
            /^[[:space:]]*#/ { next }
            {
                if (!seen_summary && $0 ~ /^[[:space:]]*summary:[[:space:]]*/) {
                    seen_summary = 1
                    base_indent = indent_of($0)
                    line = $0
                    sub(/^[[:space:]]*summary:[[:space:]]*/, "", line)
                    line = trim(line)

                    if (line == "|" || line == "|-" || line == ">" || line == ">-") {
                        in_block = 1
                        next
                    }

                    print unquote(line)
                    exit
                }

                if (in_block) {
                    if ($0 ~ /^[[:space:]]*$/) {
                        next
                    }

                    if (indent_of($0) <= base_indent) {
                        exit
                    }

                    print trim($0)
                    exit
                }
            }
        ' "$report_file"
    )
    trimmed="${summary//$'\r'/}"
    trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

    if [ -z "$trimmed" ]; then
        return 1
    fi

    case "$trimmed" in
        null|'|'|'>'|'|-'|'>-')
            return 1
            ;;
    esac

    return 0
}

main() {
    local ninja_name="${1:-}"
    local parent_cmd="${2:-}"
    local report_file=""

    if [ "${ninja_name:-}" = "--help" ] || [ "${ninja_name:-}" = "-h" ]; then
        show_help
        exit 0
    fi

    if [ -z "$ninja_name" ] || [ -z "$parent_cmd" ]; then
        usage
        exit 1
    fi

    if [[ ! "$parent_cmd" =~ ^cmd_[0-9]+$ ]]; then
        echo "ERROR: parent_cmd は cmd_XXX 形式（数字のみ。task_id/cmd_XXX_suffix不可）で指定せよ: $parent_cmd" >&2
        exit 1
    fi

    report_file=$(resolve_report_file "$ninja_name" "$parent_cmd") || {
        echo "ERROR: report YAML not found for ${ninja_name}/${parent_cmd}. 報告を先に書け。" >&2
        exit 1
    }

    if ! summary_is_present "$report_file"; then
        echo "ERROR: result.summary is empty in $report_file. 報告を先に書け。" >&2
        exit 1
    fi

    # cmd_1254: gate_report_format.sh — 家老への報告送信前にフォーマット検証
    local gate_output
    gate_output=$(bash "$SCRIPT_DIR/scripts/gates/gate_report_format.sh" "$report_file" 2>&1) || {
        echo "ERROR: gate_report_format.sh FAIL — 報告YAMLを修正して再実行せよ。" >&2
        echo "  対象: $report_file" >&2
        echo "  詳細: $gate_output" >&2
        exit 1
    }

    bash "$SCRIPT_DIR/scripts/inbox_write.sh" \
        karo \
        "${ninja_name}、任務完了。報告YAML確認されたし。" \
        report_received \
        "$ninja_name"
}

main "$@"
