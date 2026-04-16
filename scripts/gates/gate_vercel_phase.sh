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
ANY_EXTERNAL_EXISTS=false

# cmd_1976最適化: RESOLVE_BASES配列を事前構築しprocess substitutionを排除
declare -a RESOLVE_BASES=()

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

    # cmd_1976最適化: RESOLVE_BASES配列を事前構築（process substitutionをref毎に呼ぶ代わり）
    RESOLVE_BASES=("$SCRIPT_DIR")
    local ext_path
    for ext_path in "${EXTERNAL_REPO_PATHS[@]}"; do
        [ -d "${ext_path}/docs/research" ] && ANY_EXTERNAL_EXISTS=true
        RESOLVE_BASES+=("$ext_path")
    done

    build_file_cache

    # cmd_1976最適化: 全contextファイルを事前リスト化
    local -a ctx_files=()
    while IFS= read -r f; do
        ctx_files+=("$f")
    done < <(collect_context_files "$@")

    local scanned=${#ctx_files[@]}
    if [ "$scanned" -eq 0 ]; then
        echo "[ALERT] gate_vercel_phase: 0 context files scanned"
        return 1
    fi

    # cmd_1976最適化: grep単一起動で全contextファイルを一括処理(awk×43→grep×1)
    # grep -nHo: filename:lineno:match 形式で全マッチを出力(1行複数マッチも正常処理)
    # grep -E でdocs/research/参照を抽出; 未マッチファイルはexit 1→|| true で継続
    while IFS= read -r grep_line; do
        [ -n "$grep_line" ] || continue

        # 出力形式: /abs/path/file.md:LINENO:docs/research/something.md
        # ref は [a-zA-Z0-9_./*-]+ でコロンを含まないため末尾から安全に分割可能
        local ref="${grep_line##*:}"            # 最後の:以降 = ref
        local linenum_file="${grep_line%:*}"    # 最後の:より前 = path:lineno
        local line_no="${linenum_file##*:}"     # 最後の:以降 = lineno
        local context_file="${linenum_file%:*}" # 最後の:より前 = filepath

        local key="${context_file}|${ref}"
        if [[ -n "${SEEN_REFS[$key]:-}" ]]; then
            continue
        fi
        SEEN_REFS["$key"]=1
        # shellcheck disable=SC2034
        FIRST_ORIGIN["$key"]="${context_file#"$SCRIPT_DIR"/}:${line_no}"
        TOTAL_REFS=$((TOTAL_REFS + 1))

        local found=false
        local base_dir
        for base_dir in "${RESOLVE_BASES[@]}"; do
            [ -n "$base_dir" ] || continue
            if ref_exists_in_base "$base_dir" "$ref"; then
                found=true
                break
            fi
        done

        if [ "$found" = false ]; then
            # 外部リポが存在しない環境では外部リポ参照をスキップ（偽陽性防止）
            # 外部リポが存在する環境で見つからない場合のみFAIL（本物のリンク切れ）
            if [ "$ANY_EXTERNAL_EXISTS" = false ]; then
                TOTAL_REFS=$((TOTAL_REFS - 1))
                continue
            fi
            BROKEN_REFS=$((BROKEN_REFS + 1))
            local file_display="${context_file#"$SCRIPT_DIR"/}"
            BROKEN_DETAILS+=("  ${file_display}:${line_no} → ${ref} [NOT FOUND]")
        fi
    done < <(
        grep -nHo 'docs/research/[a-zA-Z0-9_./*-]\+' "${ctx_files[@]}" 2>/dev/null || true
    )

    if [ "$BROKEN_REFS" -eq 0 ]; then
        echo "[OK] gate_vercel_phase: ${TOTAL_REFS} refs checked, all exist"
        return 0
    fi

    echo "[ALERT] gate_vercel_phase: ${BROKEN_REFS} broken refs found"
    printf '%s\n' "${BROKEN_DETAILS[@]}"
    return 1
}

main "$@"
