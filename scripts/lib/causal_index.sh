#!/usr/bin/env bash
# Build and query reverse indexes for Obsidian-style [[links]].
set -euo pipefail

_ci_self="${BASH_SOURCE[0]}"
[[ "$_ci_self" != /* ]] && _ci_self="$PWD/$_ci_self"
SCRIPT_DIR="$(cd "${_ci_self%/scripts/lib/causal_index.sh}" && pwd)"
DEFAULT_CACHE="$SCRIPT_DIR/.cache/causal_index.tsv"

usage() {
    cat <<'EOF'
Usage:
  causal_index.sh build [cache_path]
  causal_index.sh lookup <target> [cache_path]
  causal_index.sh --lookup <target> [cache_path]

Cache format: link_target<TAB>source_file
EOF
}

normalize_target() {
    local target="$1"
    target="${target#[[}"
    target="${target%]]}"
    target="${target%%|*}"
    target="${target%%#*}"
    target="${target#"${target%%[![:space:]]*}"}"
    target="${target%"${target##*[![:space:]]}"}"
    printf '%s' "$target"
}

build_index() {
    local cache="${1:-$DEFAULT_CACHE}" tmp
    mkdir -p "${cache%/*}"
    # §3.2: TTLキャッシュ(300秒=5分)。キャッシュが新しければスキップ
    local ttl="${CAUSAL_INDEX_TTL:-300}"
    if [ -f "$cache" ]; then
        local age=$(( $(date +%s) - $(stat -c '%Y' "$cache" 2>/dev/null || echo 0) ))
        if [ "$age" -lt "$ttl" ]; then
            printf '%s\n' "$cache"
            return 0
        fi
    fi
    tmp="$(mktemp "${cache}.tmp.XXXXXX")"

    rg --hidden --no-heading --line-number --glob '!.git/**' --glob '!node_modules/**' \
        --glob '!logs/**' --glob '!data/**' --glob '!.cache/**' \
        '\[\[[^\[\]]+\]\]' "$SCRIPT_DIR" \
        | awk -v root="$SCRIPT_DIR/" '
            {
                file = $0
                sub(/:[0-9]+:.*/, "", file)
                rel = file
                sub("^" root, "", rel)
                text = $0
                sub(/^[^:]+:[0-9]+:/, "", text)
                while (match(text, /\[\[[^][]+\]\]/)) {
                    link = substr(text, RSTART + 2, RLENGTH - 4)
                    sub(/\|.*/, "", link)
                    sub(/#.*/, "", link)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", link)
                    if (link != "") {
                        key = link "\t" rel
                        if (!seen[key]++) print key
                    }
                    text = substr(text, RSTART + RLENGTH)
                }
            }
        ' > "$tmp"
    mv "$tmp" "$cache"
    printf '%s\n' "$cache"
}

lookup_target() {
    local target="$1" cache="${2:-$DEFAULT_CACHE}" rel base stem normalized
    normalized="$(normalize_target "$target")"
    rel="$normalized"
    [[ "$rel" == "$SCRIPT_DIR/"* ]] && rel="${rel#"$SCRIPT_DIR/"}"
    base="${rel##*/}"
    stem="${base%.*}"

    [[ -f "$cache" ]] || build_index "$cache" >/dev/null
    awk -F '\t' -v rel="$rel" -v base="$base" -v stem="$stem" '
        $1 == rel || $1 == base || $1 == stem {
            if ($2 != "" && !seen[$2]++) print $2
        }
    ' "$cache"
}

cmd="${1:-}"
case "$cmd" in
    build)
        build_index "${2:-$DEFAULT_CACHE}"
        ;;
    lookup|--lookup)
        [[ -n "${2:-}" ]] || { usage >&2; exit 2; }
        lookup_target "$2" "${3:-$DEFAULT_CACHE}"
        ;;
    ""|-h|--help)
        usage
        ;;
    *)
        lookup_target "$cmd" "${2:-$DEFAULT_CACHE}"
        ;;
esac
