#!/usr/bin/env bash
# causal_backlinks.sh — Obsidian-style backlink lookup for [[ID]] causal links.

set -euo pipefail

usage() {
    echo "Usage: causal_backlinks.sh <ID|[[ID]]>" >&2
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

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

rg -l --fixed-strings --hidden \
    --glob '!.git/**' \
    --glob '!queue/archive/**' \
    --glob '!archive/**' \
    --glob '!node_modules/**' \
    --glob '!__pycache__/**' \
    "$needle" .
