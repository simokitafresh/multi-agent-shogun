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

# nohup経由の非対話bashサブプロセスではPATHにrgが載らないCLI環境がある(rg実体は
# $HOME/.local/bin/rgに存在するがPATH外)。command not foundを2>/dev/null経由で
# 握り潰し常に0件scanned扱いになるsilent false-negative経路を防ぐため呼出前にrg解決を試みる
# (three_layer_preflight.shのresolve_rg/cmd_complete_gate.shのresolve_gate_rgと同じ考え方)。
resolve_vercel_phase_rg() {
    local rg_cmd
    rg_cmd="$(command -v rg 2>/dev/null || true)"
    if [[ -n "$rg_cmd" ]]; then
        printf '%s\n' "$rg_cmd"
        return 0
    fi
    if [[ -x "$HOME/.local/bin/rg" ]]; then
        printf '%s\n' "$HOME/.local/bin/rg"
        return 0
    fi
    return 1
}

RG_BIN="$(resolve_vercel_phase_rg)" || {
    echo "[ALERT] gate_vercel_phase: rg not found (PATH and \$HOME/.local/bin/rg both missing)"
    exit 1
}

# GA-579/580: shared with scripts/gates/gate_context_freshness.sh. See
# scripts/lib/external_project_ref_resolver.sh for canonical-scoping and
# git-tree-fallback rationale.
source "$SCRIPT_DIR/scripts/lib/external_project_ref_resolver.sh"

declare -A SEEN_REFS=()
# GA-580: per-context_file canonical-project scoping cache (see check_ref_record).
declare -A CONTEXT_CANONICAL_PROJECT=()
declare -A CONTEXT_CANONICAL_ROOT=()
declare -A CONTEXT_CANONICAL_COMPUTED=()
# shellcheck disable=SC2034  # FIRST_ORIGIN: kept for debugging broken refs
declare -A FIRST_ORIGIN=()
declare -a BROKEN_DETAILS=()
TOTAL_REFS=0
BROKEN_REFS=0
declare -a EXTERNAL_REPO_PATHS=()
# ANY_EXTERNAL_EXISTS: 外部リポ(docs/research/あり)が一つでも存在するか。main()で設定。
# check_context_file()が参照: false時は外部リポ参照をスキップ（偽陽性防止）
ANY_EXTERNAL_EXISTS=false
# GA-580: test-only override so isolated fixtures can register a canonical
# project (see external_ref_project_path) without touching config/projects.yaml.
VERCEL_PHASE_PROJECT_CONFIG="${VERCEL_PHASE_PROJECT_CONFIG:-$SCRIPT_DIR/config/projects.yaml}"

# cmd_1976最適化: RESOLVE_BASES配列を事前構築しprocess substitutionを排除
declare -a RESOLVE_BASES=()
declare -A FILE_CACHE=()
FILE_CACHE_READY=false

# cmd_4206: 500行超の既存6ファイルは移行中debtとして固定し、増加だけを
# fail-closeする。その他（新規を含む）は500行を上限とする。
declare -A CONTEXT_LINE_DEBT=(
    [senkyoku-log.md]=1489
    [dm-signal-ops.md]=1327
    [training-cycle.md]=1134
    [dm-signal-research.md]=807
    [l3-robustness.md]=782
    [dm-signal-core.md]=642
)

check_context_line_limits() {
    local file base count limit
    local violations=0
    for file in "$@"; do
        base="$(basename "$file")"
        count="$(wc -l < "$file")"
        limit="${CONTEXT_LINE_DEBT[$base]:-500}"
        if (( count > limit )); then
            echo "[ALERT] gate_vercel_phase: line limit exceeded: ${base}=${count} limit=${limit}"
            violations=$((violations + 1))
        fi
    done
    if (( violations > 0 )); then
        echo "GATE_REASON=vercel_phase:line_limit_exceeded"
    fi
    (( violations == 0 ))
}

load_external_repos() {
    # config/projects.yaml から当リポ以外の全プロジェクトパスを動的に読む
    local path resolved
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        # A self-referential project entry is commonly written as ".".  Raw
        # string comparison treated it as an external repository, making CI
        # scan the current checkout as an external source and turning missing
        # external references into an expensive candidate search.  Compare
        # canonical paths so the external-repo set is portable across runners.
        resolved="$(realpath -m -- "$path" 2>/dev/null || true)"
        [[ -n "$resolved" && "$resolved" != "$SCRIPT_DIR" ]] || continue
        EXTERNAL_REPO_PATHS+=("$resolved")
    done < <(
        grep -E '^ {4}path:' "$VERCEL_PHASE_PROJECT_CONFIG" 2>/dev/null | \
        sed 's/^[[:space:]]*path:[[:space:]]*//' | tr -d '"'
    )
}

is_glob_ref() {
    local ref="$1"
    [[ "$ref" == *"*"* || "$ref" == *"?"* || "$ref" == *"["* ]]
}

# GA-579/580: external_ref_canonical_project_id, external_ref_project_path
# and external_ref_exists_via_git are defined in
# scripts/lib/external_project_ref_resolver.sh (sourced above) and shared
# with scripts/gates/gate_context_freshness.sh.

build_file_cache() {
    [ "$FILE_CACHE_READY" = true ] && return 0
    local filepath base
    for base in "$SCRIPT_DIR" "${EXTERNAL_REPO_PATHS[@]}"; do
        [ -d "${base}/docs/research" ] || continue
        while IFS= read -r filepath; do
            FILE_CACHE["$filepath"]=1
        done < <(find "${base}/docs/research" \( -type f -o -type d \) 2>/dev/null)
    done
    FILE_CACHE_READY=true
}

ref_exists_in_base() {
    local base_dir="$1"
    local ref="$2"
    # 末尾スラッシュを除去(ディレクトリ参照対応)
    ref="${ref%/}"
    if is_glob_ref "$ref"; then
        compgen -G "${base_dir}/${ref}" > /dev/null
    else
        [[ -e "${base_dir}/${ref}" ]]
    fi
}

candidate_display_path() {
    local path="$1"
    local base_dir
    if [[ "$path" == "$SCRIPT_DIR/"* ]]; then
        printf '%s\n' "${path#"$SCRIPT_DIR"/}"
        return 0
    fi
    for base_dir in "${EXTERNAL_REPO_PATHS[@]}"; do
        if [[ "$path" == "$base_dir/"* ]]; then
            printf '%s:%s\n' "$(basename "$base_dir")" "${path#"$base_dir"/}"
            return 0
        fi
    done
    printf '%s\n' "$path"
}

suggest_ref_candidates() {
    local ref="$1"
    # Tests that exercise reason classification do not need the expensive
    # fuzzy candidate scan; reference existence and failure classification
    # remain fully exercised.
    [ "${VERCEL_PHASE_SKIP_CANDIDATE_SUGGESTIONS:-0}" = "1" ] && return 0
    build_file_cache
    local ref_base ref_stem ref_stem_lc tokens
    ref_base="$(basename "$ref")"
    ref_stem="${ref_base%.*}"
    ref_stem_lc="$(printf '%s\n' "$ref_stem" | tr '[:upper:]' '[:lower:]')"
    tokens="$(printf '%s\n' "$ref_stem_lc" | tr -cs '[:alnum:]' '\n' | awk 'length($0) >= 3')"

    local path cand_base cand_stem_lc score token
    for path in "${!FILE_CACHE[@]}"; do
        [ -f "$path" ] || continue
        cand_base="$(basename "$path")"
        cand_stem_lc="$(printf '%s\n' "${cand_base%.*}" | tr '[:upper:]' '[:lower:]')"
        score=0
        if [[ -n "$ref_stem_lc" && "$cand_stem_lc" == *"$ref_stem_lc"* ]]; then
            score=$((score + 100))
        fi
        while IFS= read -r token; do
            [ -n "$token" ] || continue
            [[ "$cand_stem_lc" == *"$token"* ]] && score=$((score + 1))
        done <<< "$tokens"
        if [ "$score" -gt 0 ]; then
            printf '%03d\t%s\n' "$score" "$(candidate_display_path "$path")"
        fi
    done | sort -rn | awk -F'\t' '!seen[$2]++ {print $2; if (++n >= 5) exit}'
}

check_ref_record() {
    local context_file="$1"
    local line_no="$2"
    local raw_ref="$3"
    # cmd_1976最適化: display_path subshell排除 → bash文字列演算でインライン化
    local file_display="${context_file#"$SCRIPT_DIR"/}"

    [ -n "$raw_ref" ] || return 0

    # cmd_1976最適化: normalize_ref(sed×268回)排除
    local ref="$raw_ref"
    local key="${context_file}|${ref}"
    if [[ -n "${SEEN_REFS[$key]:-}" ]]; then
        return 0
    fi
    SEEN_REFS["$key"]=1
    # shellcheck disable=SC2034
    FIRST_ORIGIN["$key"]="${file_display}:${line_no}"
    TOTAL_REFS=$((TOTAL_REFS + 1))

    # GA-580: scope resolution to the file's single canonical project (when
    # it has one) instead of every registered project, so a same-named path
    # that coincidentally exists under an unrelated project cannot be
    # mistaken for the intended target. Cache per context_file since this is
    # evaluated once per distinct ref already (SEEN_REFS dedupe above).
    local -a bases=()
    if [[ -z "${CONTEXT_CANONICAL_COMPUTED[$context_file]:-}" ]]; then
        local ctx_project="" ctx_root=""
        ctx_project="$(external_ref_canonical_project_id "$file_display" 2>/dev/null || true)"
        if [[ -n "$ctx_project" ]]; then
            ctx_root="$(external_ref_project_path "$ctx_project" "$VERCEL_PHASE_PROJECT_CONFIG" 2>/dev/null || true)"
        fi
        CONTEXT_CANONICAL_PROJECT["$context_file"]="$ctx_project"
        CONTEXT_CANONICAL_ROOT["$context_file"]="$ctx_root"
        CONTEXT_CANONICAL_COMPUTED["$context_file"]=1
    fi
    if [[ -n "${CONTEXT_CANONICAL_PROJECT[$context_file]:-}" ]]; then
        bases=("$SCRIPT_DIR")
        [[ -n "${CONTEXT_CANONICAL_ROOT[$context_file]:-}" ]] && bases+=("${CONTEXT_CANONICAL_ROOT[$context_file]}")
    else
        bases=("${RESOLVE_BASES[@]}")
    fi

    local found=false
    local base_dir
    for base_dir in "${bases[@]}"; do
        [ -n "$base_dir" ] || continue
        if ref_exists_in_base "$base_dir" "$ref"; then
            found=true
            break
        fi
        if [[ "$base_dir" != "$SCRIPT_DIR" ]] \
            && external_ref_exists_via_git "$base_dir" "$ref" "${VERCEL_PHASE_GIT_TIMEOUT:-10}"; then
            found=true
            break
        fi
    done

    if [ "$found" = false ]; then
        if [ "$ANY_EXTERNAL_EXISTS" = false ] \
            && [[ "$context_file" == "$SCRIPT_DIR/context/"* ]]; then
            TOTAL_REFS=$((TOTAL_REFS - 1))
            return 0
        fi
        BROKEN_REFS=$((BROKEN_REFS + 1))
        local _candidates=""
        _candidates="$(suggest_ref_candidates "$ref")"
        if [ -n "$_candidates" ]; then
            BROKEN_DETAILS+=("  ${file_display}:${line_no} → ${ref} [NOT FOUND] candidates: $(printf '%s\n' "$_candidates" | awk 'NR == 1 { out = $0; next } { out = out ", " $0 } END { print out }')")
        else
            BROKEN_DETAILS+=("  ${file_display}:${line_no} → ${ref} [NOT FOUND]")
        fi
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
    # cmd_1976最適化: RESOLVE_BASES配列を事前構築（resolve_context_basesのprocess substitutionを排除）
    RESOLVE_BASES=("$SCRIPT_DIR")
    local ext_path
    for ext_path in "${EXTERNAL_REPO_PATHS[@]}"; do
        [ -d "${ext_path}/docs/research" ] && ANY_EXTERNAL_EXISTS=true
        RESOLVE_BASES+=("$ext_path")
    done

    local -a context_files=()
    mapfile -t context_files < <(collect_context_files "$@")
    local scanned="${#context_files[@]}"

    if [ "$scanned" -eq 0 ]; then
        echo "[ALERT] gate_vercel_phase: 0 context files scanned"
        return 1
    fi

    check_context_line_limits "${context_files[@]}" || return 1

    while IFS=$'\t' read -r context_file line_no raw_ref; do
        [ -n "$context_file" ] || continue
        check_ref_record "$context_file" "$line_no" "$raw_ref"
    done < <(
        "$RG_BIN" -n -o --with-filename --no-heading 'docs/research/[^\s\x60\[\]()\x27"<>,;{}|。、）（」「]+?\.(md|json\.gz|json|yaml|py|sh|txt)' "${context_files[@]}" 2>/dev/null \
            | awk -F: '{
                if ($0 ~ /XXX|YYY|ZZZ|\{.*\}/) next
                file = $1
                line = $2
                ref = $0
                sub(/^[^:]+:[0-9]+:/, "", ref)
                printf "%s\t%s\t%s\n", file, line, ref
            }'
    )

    if [ "$BROKEN_REFS" -eq 0 ]; then
        echo "[OK] gate_vercel_phase: ${TOTAL_REFS} refs checked, all exist"
        return 0
    fi

    echo "[ALERT] gate_vercel_phase: ${BROKEN_REFS} broken refs found"
    printf '%s\n' "${BROKEN_DETAILS[@]}"
    echo "GATE_REASON=vercel_phase:broken_references"
    return 1
}

main "$@"
