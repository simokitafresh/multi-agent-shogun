#!/usr/bin/env bash
# causal_backlinks.sh — Obsidian-style backlink lookup for [[ID]] causal links.
# --detail: show origin/causal_chain context lines alongside file paths
# --semantic: also show matching semantic-index concepts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

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

if [ "$DETAIL" -eq 1 ]; then
    # Show file path + origin/causal_chain context
    rg --fixed-strings --hidden -n \
        --glob '!.git/**' \
        --glob '!queue/archive/**' \
        --glob '!archive/**' \
        --glob '!node_modules/**' \
        --glob '!__pycache__/**' \
        "$needle" . 2>/dev/null | grep -E 'origin:|causal_chain:|→ \[\[' | head -20
else
    rg -l --fixed-strings --hidden \
        --glob '!.git/**' \
        --glob '!queue/archive/**' \
        --glob '!archive/**' \
        --glob '!node_modules/**' \
        --glob '!__pycache__/**' \
        "$needle" . 2>/dev/null
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
