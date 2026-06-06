#!/bin/bash
# checklist_update.sh — 段取りリストの項目更新（flock排他制御+進捗自動再計算）
# Usage: bash scripts/checklist_update.sh <checklist_file> <item_number> <status> <result> <ninja_name>
#
# 段取りリストのMarkdownテーブル行を更新し、先頭の進捗行を再計算する。
# flock排他制御で複数忍者からの同時更新に対応。

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHECKLIST_FILE="$1"
ITEM_NUMBER="$2"
STATUS="$3"
RESULT="$4"
NINJA_NAME="$5"

if [ -z "$CHECKLIST_FILE" ] || [ -z "$ITEM_NUMBER" ] || [ -z "$STATUS" ] || [ -z "$RESULT" ] || [ -z "$NINJA_NAME" ]; then
    echo "Usage: checklist_update.sh <checklist_file> <item_number> <status> <result> <ninja_name>" >&2
    exit 1
fi

# Resolve relative paths from project root
case "$CHECKLIST_FILE" in
    /*) ;;
    *) CHECKLIST_FILE="$SCRIPT_DIR/$CHECKLIST_FILE" ;;
esac

# Ensure queue/checklists/ directory exists
CHECKLIST_DIR="$(dirname "$CHECKLIST_FILE")"
mkdir -p "$CHECKLIST_DIR"

if [ ! -f "$CHECKLIST_FILE" ]; then
    echo "FATAL: checklist_update: file not found: $CHECKLIST_FILE" >&2
    exit 1
fi

LOCKFILE="${CHECKLIST_FILE}.lock"

attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    (
        flock -w 10 200 || exit 100

        if ! [[ "$ITEM_NUMBER" =~ ^[0-9]+$ ]]; then
            echo "FATAL: checklist_update: item_number must be an integer: $ITEM_NUMBER" >&2
            exit 2
        fi

        tmp_path="$(mktemp "$CHECKLIST_DIR/.checklist_tmp_XXXXXX")"
        summary_path="${tmp_path}.summary"
        if ! awk \
            -v item_number="$ITEM_NUMBER" \
            -v status="$STATUS" \
            -v result="$RESULT" \
            -v ninja_name="$NINJA_NAME" \
            -v summary_path="$summary_path" \
            '
function trim(s) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    return s
}
function lower_trim(s) {
    return tolower(trim(s))
}
function split_markdown_row(line, cells,    s,i,char,current,n,escaped) {
    delete cells
    s = trim(line)
    current = ""
    n = 1
    escaped = 0
    for (i = 1; i <= length(s); i++) {
        char = substr(s, i, 1)
        if (char == "|" && !escaped) {
            cells[n++] = current
            current = ""
            escaped = 0
            continue
        }
        current = current char
        if (char == "\\" && !escaped) {
            escaped = 1
        } else if (char != "\\") {
            escaped = 0
        }
    }
    cells[n] = current
    return n
}
function markdown_cell(value,    out) {
    out = value
    gsub(/\r/, " ", out)
    gsub(/\n/, " ", out)
    gsub(/\|/, "\\|", out)
    return out
}
function join_cells(cells, n,    i,out) {
    out = cells[1]
    for (i = 2; i <= n; i++) {
        out = out "|" cells[i]
    }
    return out
}
function is_table_separator(line) {
    return trim(line) ~ /^\|[[:space:]]*:?-{2,}:?[[:space:]]*(\|[[:space:]]*:?-{2,}:?[[:space:]]*)+\|?$/
}
function is_checklist_header(line,    cells,n,start,end,len) {
    n = split_markdown_row(line, cells)
    start = 1
    end = n
    if (trim(cells[start]) == "") start++
    if (trim(cells[end]) == "") end--
    len = end - start + 1
    if (len < 8) return 0
    return (lower_trim(cells[start]) == "#" || lower_trim(cells[start]) == "no") &&
        (lower_trim(cells[start + 1]) == "target" || lower_trim(cells[start + 1]) == "対象") &&
        (lower_trim(cells[start + 4]) == "status" || lower_trim(cells[start + 4]) == "状態") &&
        (lower_trim(cells[start + 5]) == "result" || lower_trim(cells[start + 5]) == "結果") &&
        (lower_trim(cells[start + 6]) == "owner" || lower_trim(cells[start + 6]) == "担当") &&
        (lower_trim(cells[start + 7]) == "actual" || lower_trim(cells[start + 7]) == "実績")
}
{
    lines[NR] = $0
    if (is_checklist_header($0)) checklist_header_seen = 1
}
END {
    updated = 0
    in_checklist_table = 0
    for (i = 1; i <= NR; i++) {
        stripped = trim(lines[i])
        if (is_checklist_header(stripped)) {
            in_checklist_table = 1
            new_lines[++new_count] = lines[i]
            continue
        }
        if (in_checklist_table && stripped !~ /^\|/) {
            in_checklist_table = 0
        }
        should_process_row = (in_checklist_table || !checklist_header_seen) && !is_table_separator(stripped)
        if (should_process_row && match(stripped, /^\|[[:space:]]*[0-9]+[[:space:]]*\|/)) {
            row_num = substr(stripped, RSTART, RLENGTH)
            gsub(/[^0-9]/, "", row_num)
            n = split_markdown_row(stripped, cells)
            if (n >= 9 && row_num + 0 == item_number + 0) {
                cells[6] = " " markdown_cell(status) " "
                cells[7] = " " markdown_cell(result) " "
                cells[8] = " " markdown_cell(ninja_name) " "
                new_lines[++new_count] = join_cells(cells, n)
                updated = 1
                continue
            }
        }
        new_lines[++new_count] = lines[i]
    }

    if (!updated) {
        print "FATAL: checklist_update: item_number " item_number " not found" > "/dev/stderr"
        exit 2
    }

    done_count = 0
    total_count = 0
    in_checklist_table = 0
    for (i = 1; i <= new_count; i++) {
        stripped = trim(new_lines[i])
        if (is_checklist_header(stripped)) {
            in_checklist_table = 1
            continue
        }
        if (in_checklist_table && stripped !~ /^\|/) {
            in_checklist_table = 0
        }
        should_count_row = (in_checklist_table || !checklist_header_seen) && !is_table_separator(stripped)
        if (should_count_row && match(stripped, /^\|[[:space:]]*[0-9]+[[:space:]]*\|/)) {
            n = split_markdown_row(stripped, cells)
            if (n >= 9) {
                total_count++
                cell_status = lower_trim(cells[6])
                if (cell_status == "done" || cell_status == "pass" || cell_status == "o" || cell_status == "ok") {
                    done_count++
                }
            }
        }
    }

    pct = total_count > 0 ? int(done_count * 100 / total_count) : 0
    progress_updated = 0
    for (i = 1; i <= new_count; i++) {
        if (!progress_updated && new_lines[i] ~ /^# 進捗:/) {
            print "# 進捗: " done_count "/" total_count " (" pct "%)"
            progress_updated = 1
        } else {
            print new_lines[i]
        }
    }
    print "[checklist_update] Updated item " item_number ": status=" status " result=" result " ninja=" ninja_name " progress=" done_count "/" total_count " (" pct "%)" > summary_path
}
' "$CHECKLIST_FILE" > "$tmp_path"; then
            rm -f "$tmp_path" "$summary_path"
            exit 2
        fi
        mv "$tmp_path" "$CHECKLIST_FILE"
        cat "$summary_path"
        rm -f "$summary_path"
    ) 200>"$LOCKFILE"
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        exit 0
    fi

    # exit 100 = flock timeout (transient, worth retrying)
    # other codes = Python error (non-transient, fail immediately)
    if [ $exit_code -ne 100 ]; then
        exit $exit_code
    fi

    attempt=$((attempt + 1))
    if [ $attempt -lt $max_attempts ]; then
        echo "[checklist_update] flock timeout, retrying ($attempt/$max_attempts)..." >&2
        sleep 1
    fi
done

echo "FATAL: checklist_update: flock failed after $max_attempts attempts" >&2
exit 1
