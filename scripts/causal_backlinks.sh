#!/usr/bin/env bash
# semantic-links: [[セマンティック因果自動化]], [[因果辺トラバース統合パイプライン(Obsidian×セマンティック)]], [[教訓ライフサイクル管理]]
# causal_backlinks.sh — Obsidian-style backlink lookup for [[ID]] causal links.
# --detail: show origin/causal_chain context lines alongside file paths
# --semantic: also show matching semantic-index concepts

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
[[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$PWD/$SCRIPT_PATH"
SCRIPT_DIR="${SCRIPT_PATH%/scripts/causal_backlinks.sh}"

usage() {
    echo "Usage: causal_backlinks.sh [--detail] [--semantic] <ID|[[ID]]>" >&2
}

# nohup経由の非対話bashサブプロセスではPATHにrgが載らないCLI環境がある(rg実体は
# $HOME/.local/bin/rgに存在するがPATH外)。command not foundを2>/dev/null+||trueで
# 握り潰し常に0件扱いになるsilent false-negative経路を防ぐため呼出前にrg解決を試みる
# (three_layer_preflight.shのresolve_rg/cmd_complete_gate.shのresolve_gate_rgと同じ考え方)。
resolve_backlinks_rg() {
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

RG_BIN="$(resolve_backlinks_rg)" || {
    echo "ERROR: rg not found (PATH and \$HOME/.local/bin/rg both missing)" >&2
    exit 1
}

DETAIL=0
SEMANTIC=0
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --detail) DETAIL=1; shift ;;
        --semantic) SEMANTIC=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) break ;;
    esac
done

if [ $# -ne 1 ]; then
    usage
    exit 1
fi

id="${1#\[\[}"
id="${id%\]\]}"

if [ -z "$id" ]; then
    echo "ERROR: ID is empty" >&2
    exit 1
fi

needle="[[$id]]"

SEARCH_PATHS=(
    AGENTS.md
    instructions
    context
    projects
    skills
    scripts
    docs
    tasks
)

existing_search_paths=()
for _cbl_path in "${SEARCH_PATHS[@]}"; do
    [ -e "$_cbl_path" ] && existing_search_paths+=("$_cbl_path")
done

RG_COMMON_ARGS=(
    --fixed-strings
    --hidden
    --glob '!.git/**'
    --glob '!node_modules/**'
    --glob '!__pycache__/**'
    --glob '!docs/obsidian-promoted/**'
    --glob '!*.cache.json'
    --glob '!*.pyc'
    --glob '!*.lock'
)

run_backlink_search() {
    local _cbl_path

    if [ "$DETAIL" -eq 1 ]; then
        for _cbl_path in "${existing_search_paths[@]}"; do
            "$RG_BIN" -n "${RG_COMMON_ARGS[@]}" "$needle" "$_cbl_path" 2>/dev/null || true
        done | sort -u
    else
        for _cbl_path in "${existing_search_paths[@]}"; do
            "$RG_BIN" -l "${RG_COMMON_ARGS[@]}" "$needle" "$_cbl_path" 2>/dev/null || true
        done | sort -u
    fi
}

if [ "$DETAIL" -eq 1 ]; then
    # Show file path + origin/causal_chain context
    run_backlink_search \
        | grep -E 'origin:|causal_chain:|→ \[\[' \
        | head -20 \
        || true
else
    run_backlink_search
fi

# Semantic concept reverse lookup
if [ "$SEMANTIC" -eq 1 ]; then
    local_index="$SCRIPT_DIR/docs/semantic-index/index.md"
    if [ -f "$local_index" ]; then
        matches="$(grep -i "$id" "$local_index" 2>/dev/null | head -5)" || true
        if [ -n "$matches" ]; then
            echo "--- semantic concepts ---"
            echo "$matches"
        fi
    fi
fi
