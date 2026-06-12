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
    if [ "$DETAIL" -eq 1 ]; then
        rg -n "${RG_COMMON_ARGS[@]}" "$needle" "${existing_search_paths[@]}" 2>/dev/null || true
    else
        rg -l "${RG_COMMON_ARGS[@]}" "$needle" "${existing_search_paths[@]}" 2>/dev/null || true
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
