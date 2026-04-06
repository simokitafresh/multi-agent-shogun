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

declare -A SEEN_REFS=()
# shellcheck disable=SC2034  # FIRST_ORIGIN: kept for debugging broken refs
declare -A FIRST_ORIGIN=()
declare -a BROKEN_DETAILS=()
TOTAL_REFS=0
BROKEN_REFS=0
declare -a EXTERNAL_REPO_PATHS=()
# ANY_EXTERNAL_EXISTS: 外部リポ(docs/research/あり)が一つでも存在するか。main()で設定。
# check_context_file()が参照: false時は外部リポ参照をスキップ（偽陽性防止）
ANY_EXTERNAL_EXISTS=false

load_external_repos() {
    # config/projects.yaml から当リポ以外の全プロジェクトパスを動的に読む
    local path
    while IFS= read -r path; do
        [[ -n "$path" && "$path" != "$SCRIPT_DIR" ]] || continue
        EXTERNAL_REPO_PATHS+=("$path")
    done < <(
        grep -E '^ {4}path:' "$SCRIPT_DIR/config/projects.yaml" 2>/dev/null | \
        sed 's/^[[:space:]]*path:[[:space:]]*//' | tr -d '"'
    )
}

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

declare -A FILE_CACHE=()

build_file_cache() {
    local filepath base
    for base in "$SCRIPT_DIR" "${EXTERNAL_REPO_PATHS[@]}"; do
        [ -d "${base}/docs/research" ] || continue
        while IFS= read -r filepath; do
            FILE_CACHE["$filepath"]=1
        done < <(find "${base}/docs/research" -type f 2>/dev/null)
    done
}

ref_exists_in_base() {
    local base_dir="$1"
    local ref="$2"
    if is_glob_ref "$ref"; then
        compgen -G "${base_dir}/${ref}" > /dev/null
    else
        [[ -n "${FILE_CACHE[${base_dir}/${ref}]:-}" ]]
    fi
}

resolve_context_bases() {
    # 当リポ + 全外部リポを返す（ファイル名ベースの判定を廃止）
    printf '%s\n' "$SCRIPT_DIR"
    local ext
    for ext in "${EXTERNAL_REPO_PATHS[@]}"; do
        printf '%s\n' "$ext"
    done
}

display_path() {
    local file="$1"
    if [[ "$file" == "$SCRIPT_DIR/"* ]]; then
        printf '%s' "${file#"$SCRIPT_DIR"/}"
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
        # shellcheck disable=SC2034
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
            # 外部リポが存在しない環境では外部リポ参照をスキップ（偽陽性防止）
            # 外部リポが存在する環境で見つからない場合のみFAIL（本物のリンク切れ）
            if [ "$ANY_EXTERNAL_EXISTS" = false ]; then
                TOTAL_REFS=$((TOTAL_REFS - 1))
                continue
            fi
            BROKEN_REFS=$((BROKEN_REFS + 1))
            BROKEN_DETAILS+=("  ${file_display}:${line_no} → ${ref} [NOT FOUND]")
        fi
    done < <(
        awk '
            {
                s = $0
                while (match(s, /docs\/research\/[a-zA-Z0-9_./*-]+/)) {
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
        # lord-conversation-index.md は auto-generated 会話ログ。参照チェック対象外
        find "$SCRIPT_DIR/context" -maxdepth 1 -type f -name '*.md' \
            ! -name 'lord-conversation-index.md' | sort
        return 0
    fi

    # 複数ファイル引数対応（cmd_complete_gate.shからcmd変更context fileのみ渡される）
    local arg
    for arg in "$@"; do
        if [ -f "$arg" ]; then
            realpath "$arg"
        elif [ -f "$SCRIPT_DIR/$arg" ]; then
            realpath "$SCRIPT_DIR/$arg"
        else
            echo "ERROR: context file not found: $arg" >&2
            return 1
        fi
    done
}

main() {
    load_external_repos
    # 外部リポが一つでも存在するかを事前計算（check_context_file内で参照）
    local ext_path
    for ext_path in "${EXTERNAL_REPO_PATHS[@]}"; do
        [ -d "${ext_path}/docs/research" ] && ANY_EXTERNAL_EXISTS=true && break
    done
    build_file_cache
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
