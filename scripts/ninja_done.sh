#!/usr/bin/env bash
# ninja_done.sh — done通知前に報告YAMLのsummary記入を強制する
# Usage: bash scripts/ninja_done.sh <ninja_name> <parent_cmd>

set -euo pipefail

SCRIPT_DIR=""
REPORTS_DIR=""
ARCHIVE_REPORT_DIR=""

init_paths() {
    [ -n "$SCRIPT_DIR" ] && return 0

    # cmd_2063: SCRIPT_DIR をサブシェル不要な純bash文字列演算で解決 (~5ms節約)
    local _self="${BASH_SOURCE[0]}"
    SCRIPT_DIR="${_self%/*}/.."
    [[ "$SCRIPT_DIR" != /* ]] && SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
    REPORTS_DIR="$SCRIPT_DIR/queue/reports"
    ARCHIVE_REPORT_DIR="$SCRIPT_DIR/queue/archive/reports"
}

usage() {
    echo "Usage: bash scripts/ninja_done.sh <ninja_name> <parent_cmd>" >&2
    echo "Example: bash scripts/ninja_done.sh hayate cmd_795" >&2
    echo "Note: parent_cmd must be cmd_XXX (digits only). task_id like cmd_795_review is invalid." >&2
}

show_help() {
    usage 2>&1
}

resolve_report_file() {
    local ninja_name="$1"
    local cmd_id="$2"
    init_paths

    local primary_path="$REPORTS_DIR/${ninja_name}_report_${cmd_id}.yaml"

    if [ -f "$primary_path" ]; then
        printf '%s\n' "$primary_path"
        return 0
    fi

    # cmd_2082: date-trial (printf %T builtin) でglobを回避 (~66ms→~3ms)
    # archiveファイル名: ${ninja}_report_${cmd_id}_${YYYYMMDD}.yaml
    local _epoch _date_str _candidate _d
    # L37: date +%s(subprocess)→printf -v(bashビルトイン)。L39の%(%Y%m%d)T同パターンで統一(0 subprocess)
    printf -v _epoch '%(%s)T' -1
    for _d in 0 1 2 3 4 5 6 7 8 9 10 11 12 13; do
        printf -v _date_str '%(%Y%m%d)T' $(( _epoch - _d * 86400 ))
        _candidate="$ARCHIVE_REPORT_DIR/${ninja_name}_report_${cmd_id}_${_date_str}.yaml"
        if [ -f "$_candidate" ]; then
            printf '%s\n' "$_candidate"
            return 0
        fi
    done

    # 14日超の古いreportへのfallback (稀ケース)
    shopt -s nullglob
    local archived_paths=("$ARCHIVE_REPORT_DIR/${ninja_name}_report_${cmd_id}_"*.yaml)
    shopt -u nullglob

    if [ "${#archived_paths[@]}" -eq 0 ]; then
        return 1
    fi

    local latest_path="" path
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
    local line raw base_indent=0 indent in_block=0

    while IFS= read -r line || [ -n "$line" ]; do
        raw="${line#"${line%%[![:space:]]*}"}"
        [[ "$raw" == \#* ]] && continue

        if [ "$in_block" -eq 0 ]; then
            case "$raw" in
                summary:*)
                    base_indent=$((${#line} - ${#raw}))
                    summary="${raw#summary:}"
                    summary="${summary#"${summary%%[![:space:]]*}"}"
                    summary="${summary%"${summary##*[![:space:]]}"}"

                    case "$summary" in
                        "|"|"|-"|">"|">-")
                            in_block=1
                            continue
                            ;;
                    esac

                    if [ "${#summary}" -ge 2 ]; then
                        case "$summary" in
                            \"*\") summary="${summary#\"}"; summary="${summary%\"}" ;;
                            \'*\') summary="${summary#\'}"; summary="${summary%\'}" ;;
                        esac
                    fi
                    break
                    ;;
            esac
            continue
        fi

        raw="${line#"${line%%[![:space:]]*}"}"
        [ -z "$raw" ] && continue
        indent=$((${#line} - ${#raw}))
        [ "$indent" -le "$base_indent" ] && break
        summary="${raw%"${raw##*[![:space:]]}"}"
        break
    done < "$report_file"

    trimmed="${summary//$'\r'/}"
    trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

    if [ -z "$trimmed" ]; then
        return 1
    fi

    case "$trimmed" in
        null|'|'|'>'|'|-'|'>-'|*FILL_THIS*)
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
    init_paths
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
        "$ninja_name" \
        notify_karo
}

main "$@"
