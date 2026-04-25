#!/usr/bin/env bash
# hybrid_search.sh — merge repository keyword search with optional MCP export hits.
#
# MCP Memory is restricted to shogun. This script never calls MCP directly; pass
# an exported result file with --mcp-file or MCP_SEARCH_FILE when available.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ROOT="$REPO_ROOT"
LIMIT=20
MCP_FILE="${MCP_SEARCH_FILE:-}"
QUERY=""

usage() {
    cat <<'USAGE'
Usage: bash scripts/hybrid_search.sh [options] QUERY

Options:
  --root DIR       Repository/root to search. Default: current repository.
  --limit N        Maximum merged results. Default: 20.
  --mcp-file FILE  Optional shogun-exported MCP hits.
  -h, --help       Show this help.

MCP file formats accepted:
  source|path|snippet
  path:line:snippet
USAGE
}

die() {
    echo "ERROR: $*" >&2
    exit 2
}

is_positive_int() {
    [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            ROOT="${2:-}"
            [[ -n "$ROOT" ]] || die "--root requires a value"
            shift 2
            ;;
        --limit)
            LIMIT="${2:-}"
            is_positive_int "$LIMIT" || die "--limit must be a positive integer"
            shift 2
            ;;
        --mcp-file)
            MCP_FILE="${2:-}"
            [[ -n "$MCP_FILE" ]] || die "--mcp-file requires a value"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            QUERY="$*"
            break
            ;;
        -*)
            die "unknown option: $1"
            ;;
        *)
            QUERY="${QUERY:+$QUERY }$1"
            shift
            ;;
    esac
done

[[ -n "$QUERY" ]] || die "QUERY is required"
[[ -d "$ROOT" ]] || die "search root not found: $ROOT"

tmp_keyword="$(mktemp)"
tmp_mcp="$(mktemp)"
tmp_merged="$(mktemp)"
trap 'rm -f "$tmp_keyword" "$tmp_mcp" "$tmp_merged"' EXIT

if command -v rg >/dev/null 2>&1; then
    rg --fixed-strings --ignore-case --line-number --no-heading \
        --glob '!/.git/**' \
        --glob '!/.codex_tmp/**' \
        --glob '!queue/archive/**' \
        --glob '!node_modules/**' \
        --glob '!__pycache__/**' \
        "$QUERY" "$ROOT" 2>/dev/null \
        | head -n "$((LIMIT * 3))" \
        | awk -F: -v root="$ROOT" '
            {
                path=$1
                line=$2
                $1=""; $2=""
                sub(/^::?/, "", $0)
                if (index(path, root "/") == 1) {
                    path=substr(path, length(root) + 2)
                }
                printf "keyword\t%d\t%s:%s\t%s\n", 100 - NR, path, line, $0
            }
        ' > "$tmp_keyword"
else
    grep -RIn --exclude-dir=.git --exclude-dir=.codex_tmp --exclude-dir=node_modules \
        -- "$QUERY" "$ROOT" 2>/dev/null \
        | head -n "$((LIMIT * 3))" \
        | awk -F: -v root="$ROOT" '
            {
                path=$1
                line=$2
                $1=""; $2=""
                sub(/^::?/, "", $0)
                if (index(path, root "/") == 1) {
                    path=substr(path, length(root) + 2)
                }
                printf "keyword\t%d\t%s:%s\t%s\n", 100 - NR, path, line, $0
            }
        ' > "$tmp_keyword"
fi

if [[ -n "$MCP_FILE" && -f "$MCP_FILE" ]]; then
    awk -v query="$QUERY" '
        NF == 0 { next }
        index($0, "|") > 0 {
            split($0, parts, "|")
            source=parts[1]
            path=parts[2]
            snippet=parts[3]
            for (i=4; i<=length(parts); i++) snippet=snippet "|" parts[i]
            if (source == "") source="mcp"
            if (path == "") path="mcp"
            printf "%s\t90\t%s\t%s\n", source, path, snippet
            next
        }
        {
            printf "mcp\t90\tmcp\t%s\n", $0
        }
    ' "$MCP_FILE" > "$tmp_mcp"
fi

cat "$tmp_keyword" "$tmp_mcp" \
    | awk -F'\t' '
        {
            key=$3
            if (seen[key]++) next
            print
        }
    ' \
    | sort -t $'\t' -k2,2nr \
    | head -n "$LIMIT" > "$tmp_merged"

count="$(wc -l < "$tmp_merged" | tr -d ' ')"
echo "HYBRID_SEARCH query=${QUERY} results=${count} root=${ROOT}"
if [[ -n "$MCP_FILE" ]]; then
    if [[ -f "$MCP_FILE" ]]; then
        echo "MCP source=${MCP_FILE}"
    else
        echo "MCP source=${MCP_FILE} status=missing fallback=keyword-only"
    fi
else
    echo "MCP source=none fallback=keyword-only"
fi

if [[ "$count" -eq 0 ]]; then
    echo "NO_RESULTS"
    exit 1
fi

awk -F'\t' '{printf "%02d. [%s] score=%s %s\n    %s\n", NR, $1, $2, $3, $4}' "$tmp_merged"
