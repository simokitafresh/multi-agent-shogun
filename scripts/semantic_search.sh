#!/usr/bin/env bash
# semantic_search.sh — Two-layer semantic-index search.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash scripts/semantic_search.sh [--llm] <query>

Search docs/semantic-index/index.md by concept label and aliases. If the
first layer has no match, fall back to LLM semantic matching. Use --llm to
skip the alias layer and run semantic matching directly.

Environment:
  SEMANTIC_INDEX_PATH  Override docs/semantic-index/index.md
  SEMANTIC_LLM_CMD     Override LLM command (default: claude --print)
  SEMANTIC_CACHE_DIR   LLM result cache dir (default: tmp/semantic_search_cache)
  SEMANTIC_NO_CACHE    Set to 1 to disable LLM cache lookup and writes
EOF
}

force_llm=false
query_parts=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --llm)
            force_llm=true
            shift
            ;;
        --)
            shift
            while [ "$#" -gt 0 ]; do
                query_parts+=("$1")
                shift
            done
            ;;
        -*)
            echo "ERROR: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            query_parts+=("$1")
            shift
            ;;
    esac
done

if [ "${#query_parts[@]}" -lt 1 ]; then
    usage >&2
    exit 2
fi

query="${query_parts[*]}"
if [[ -z "${query//[[:space:]]/}" ]]; then
    echo "ERROR: query is empty or whitespace only" >&2
    usage >&2
    exit 2
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
index_path="${SEMANTIC_INDEX_PATH:-$script_dir/docs/semantic-index/index.md}"

if [ ! -f "$index_path" ]; then
    echo "ERROR: semantic index not found: $index_path" >&2
    exit 1
fi

semantic_index_python() {
    local mode="$1"
    local mode_arg="${2:-}"
    python3 "$script_dir/scripts/semantic_index.py" "$index_path" "$query" "$mode" "$mode_arg"
}

first_layer_search() {
    local no_match_mode="${1:-print}"
    semantic_index_python first-layer "$no_match_mode"
}

llm_cache_key() {
    local llm_cmd="$1"
    {
        printf 'q=%s\n' "$query"
        printf 'cmd=%s\n' "$llm_cmd"
        cat "$index_path"
    } | sha256sum | awk '{print $1}'
}

llm_search() {
    local llm_cmd="${SEMANTIC_LLM_CMD:-claude --print}"
    local cache_dir="${SEMANTIC_CACHE_DIR:-$script_dir/tmp/semantic_search_cache}"
    local no_cache="${SEMANTIC_NO_CACHE:-0}"
    local cache_file=""

    if [ "$no_cache" != "1" ]; then
        local key
        key="$(llm_cache_key "$llm_cmd")"
        cache_file="$cache_dir/$key"
        if [ -f "$cache_file" ]; then
            cat "$cache_file"
            return 0
        fi
    fi

    local prompt_file output_file final_output
    prompt_file="$(mktemp)"
    output_file="$(mktemp)"
    final_output="$(mktemp)"
    trap 'rm -f "$prompt_file" "$output_file" "$final_output"' RETURN

    {
        cat <<EOF
You are matching a user query to a semantic index.

Query:
$query

Instructions:
- Choose up to 3 most related concepts from the index.
- Output each selected concept id on a line beginning with "MATCH: ".
- Add one short reason per match.
- Suggest alias candidates if the query uses wording that is missing from aliases.
- Use only concept ids that appear in the index.

Semantic index:
EOF
        cat "$index_path"
    } > "$prompt_file"

    if bash -c "$llm_cmd" < "$prompt_file" > "$output_file"; then
        :
    else
        local rc=$?
        echo "ERROR: LLM semantic search failed with exit code $rc" >&2
        echo "command: $llm_cmd" >&2
        return "$rc"
    fi

    {
        echo "LLM_MATCH: $query"
        echo ""
        cat "$output_file"
        echo ""
        semantic_index_python "render-llm-resources" "$output_file"
    } > "$final_output"

    cat "$final_output"

    if [ "$no_cache" != "1" ] && [ -n "$cache_file" ]; then
        mkdir -p "$cache_dir"
        local tmp_cache="${cache_file}.tmp.$$"
        if cp "$final_output" "$tmp_cache" 2>/dev/null; then
            mv "$tmp_cache" "$cache_file" 2>/dev/null || rm -f "$tmp_cache"
        fi
    fi
}

if [ "$force_llm" = false ]; then
    if first_layer_search silent; then
        exit 0
    else
        rc=$?
        if [ "$rc" -ne 1 ]; then
            exit "$rc"
        fi
    fi
fi

llm_search
