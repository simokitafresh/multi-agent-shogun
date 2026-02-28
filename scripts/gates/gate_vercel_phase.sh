#!/usr/bin/env bash
# ============================================================
# gate_vercel_phase.sh
# context/*.md 内の docs/research/ 参照に対するリンク存在ゲート
#
# Usage:
#   bash scripts/gates/gate_vercel_phase.sh [context_file]
#   引数なし: context/*.md を全走査
#   引数あり: 指定ファイルのみ走査
#
# Exit code:
#   0: OK (全参照が存在)
#   1: ALERT (1件以上のリンク切れ)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DM_SIGNAL_DIR="/mnt/c/Python_app/DM-signal"

declare -A SEEN_REFS=()
declare -A FIRST_ORIGIN=()
declare -a BROKEN_DETAILS=()
TOTAL_REFS=0
BROKEN_REFS=0

normalize_ref() {
    local raw="$1"
    local cleaned
    cleaned="$(printf '%s' "$raw" | sed -E \
        -e 's/[[:space:]]*\|.*$//' \
        -e 's/[[:space:]]*§.*$//' \
        -e 's/[`"'"'"']//g' \
        -e 's/[),.;:]+$//')"
    printf '%s' "$cleaned"
}

is_glob_ref() {
    local ref="$1"
    [[ "$ref" == *"*"* || "$ref" == *"?"* || "$ref" == *"["* ]]
}

ref_exists_in_base() {
    local base_dir="$1"
    local ref="$2"
    if is_glob_ref "$ref"; then
        compgen -G "${base_dir}/${ref}" > /dev/null
    else
        [ -f "${base_dir}/${ref}" ]
    fi
}

resolve_context_bases() {
    local context_file="$1"
    local base_name
    base_name="$(basename "$context_file")"

    if [[ "$base_name" == dm-signal* ]]; then
        # task仕様に合わせてDM-signal優先。ただし既存配置差異に備えrepo rootも見る。
        printf '%s\n' "$DM_SIGNAL_DIR" "$SCRIPT_DIR"
    else
        printf '%s\n' "$SCRIPT_DIR" "$DM_SIGNAL_DIR"
    fi
}

display_path() {
    local file="$1"
    if [[ "$file" == "$SCRIPT_DIR/"* ]]; then
        printf '%s' "${file#$SCRIPT_DIR/}"
    else
        printf '%s' "$file"
    fi
}

check_context_file() {
    local context_file="$1"
    local file_display
    file_display="$(display_path "$context_file")"

    while IFS=$'\t' read -r line_no raw_ref; do
        [ -n "$raw_ref" ] || continue

        local ref
        ref="$(normalize_ref "$raw_ref")"
        [[ "$ref" == docs/research/* ]] || continue

        local key="${context_file}|${ref}"
        if [[ -n "${SEEN_REFS[$key]:-}" ]]; then
            continue
        fi
        SEEN_REFS["$key"]=1
        FIRST_ORIGIN["$key"]="${file_display}:${line_no}"
        TOTAL_REFS=$((TOTAL_REFS + 1))

        local found=false
        while IFS= read -r base_dir; do
            [ -n "$base_dir" ] || continue
            if ref_exists_in_base "$base_dir" "$ref"; then
                found=true
                break
            fi
        done < <(resolve_context_bases "$context_file")

        if [ "$found" = false ]; then
            BROKEN_REFS=$((BROKEN_REFS + 1))
            BROKEN_DETAILS+=("  ${file_display}:${line_no} → ${ref} [NOT FOUND]")
        fi
    done < <(
        awk '
            {
                s = $0
                while (match(s, /docs\/research\/[^`|[:space:]]+/)) {
                    ref = substr(s, RSTART, RLENGTH)
                    printf "%d\t%s\n", NR, ref
                    s = substr(s, RSTART + RLENGTH)
                }
            }
        ' "$context_file"
    )
}

collect_context_files() {
    if [ "$#" -eq 0 ]; then
        find "$SCRIPT_DIR/context" -maxdepth 1 -type f -name '*.md' | sort
        return 0
    fi

    local arg="$1"
    if [ -f "$arg" ]; then
        realpath "$arg"
        return 0
    fi
    if [ -f "$SCRIPT_DIR/$arg" ]; then
        realpath "$SCRIPT_DIR/$arg"
        return 0
    fi

    echo "ERROR: context file not found: $arg" >&2
    return 1
}

main() {
    local context_file
    local scanned=0
    while IFS= read -r context_file; do
        [ -n "$context_file" ] || continue
        scanned=$((scanned + 1))
        check_context_file "$context_file"
    done < <(collect_context_files "$@")

    if [ "$scanned" -eq 0 ]; then
        echo "[ALERT] gate_vercel_phase: 0 context files scanned"
        return 1
    fi

    if [ "$BROKEN_REFS" -eq 0 ]; then
        echo "[OK] gate_vercel_phase: ${TOTAL_REFS} refs checked, all exist"
        return 0
    fi

    echo "[ALERT] gate_vercel_phase: ${BROKEN_REFS} broken refs found"
    printf '%s\n' "${BROKEN_DETAILS[@]}"
    return 1
}

main "$@"
