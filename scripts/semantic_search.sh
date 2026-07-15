#!/usr/bin/env bash
# semantic-links: [[因果辺トラバース統合パイプライン(Obsidian×セマンティック)]]
# semantic_search.sh — Two-layer semantic-index search.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash scripts/semantic_search.sh [--llm] <query>

Search docs/semantic-index/index.md by concept label and aliases. If the
first layer has no match, fall back to memory DB FTS5 concept matching.
Use --llm to skip the alias layer and run semantic matching directly.
related_concepts accepts legacy concept_id entries and concept_id(relation_type=...)
entries; relation_type is rendered as metadata and does not control expansion.

Environment:
  SEMANTIC_INDEX_PATH  Override docs/semantic-index/index.md
  SEMANTIC_SOURCE_MAP_PATH
                       Override context/semantic-map.md source fallback
  SEMANTIC_LLM_CMD     Override LLM command (default: claude --print)
  SEMANTIC_DISABLE_LLM Set to 1 to stop after the alias layer
  SEMANTIC_ENABLE_LLM_FALLBACK
                       Set to 1 to allow LLM after first-layer and memory DB
                       fallback both miss. Default is 0.
  SEMANTIC_MEMORY_DB_PATH
                       Override data/multi_agent_shogun_memory.db for FTS fallback
  SEMANTIC_MEMORY_DB_CACHE_PATH
                       Override ext4 cache path used for the memory DB fallback
  SEMANTIC_MEMORY_DB_CACHE_DIR
                       Override ext4 cache dir (default: /tmp/shogun_memory_db_cache)
  SEMANTIC_DISABLE_MEMORY_DB_CACHE
                       Set to 1 to read SEMANTIC_MEMORY_DB_PATH directly
  SEMANTIC_DISABLE_MEMORY_DB
                       Set to 1 to skip memory DB FTS fallback
  SEMANTIC_MEMORY_DB_LIMIT
                       Maximum memory DB fallback rows (default: 10)
  SEMANTIC_MEMORY_DB_TIMEOUT
                       Maximum seconds for memory DB FTS fallback (default: 5)
  SEMANTIC_MEMORY_DB_TARGET
                       Override memory DB target filter (default: current agent_id)
  SEMANTIC_CONCEPT_EXPANSION_LIMIT
                       Maximum depth=1 event_links concept expansion count (default: 20)
  SEMANTIC_RELATED_CONCEPT_LIMIT
                       Maximum index.md related_concepts neighbors to render per single
                       first-layer concept match (default: 8)
  SEMANTIC_CACHE_DIR   LLM result cache dir (default: tmp/semantic_search_cache)
  SEMANTIC_INDEX_CACHE_DIR
                       Parsed index JSON cache dir (default: tmp/semantic_index_cache)
  SEMANTIC_NO_CACHE    Set to 1 to disable LLM cache lookup and writes
  SEMANTIC_DISABLE_CAUSAL
                       Set to 1 to suppress causal backlink expansion
  SEMANTIC_CAUSAL_EXPANSION_LIMIT
                       Maximum causal links to expand (default: 2)
  SEMANTIC_CAUSAL_BACKLINK_TIMEOUT
                       Maximum seconds per causal_backlinks lookup (default: 1)
  SEMANTIC_CAUSAL_ROOT Override backlink search root (default: repository root)
  SEMANTIC_DISABLE_SEARCH_LOG
                       Set to 1 to skip search_logs recording
  SEMANTIC_SEARCH_LOG_DB_PATH
                       Override SQLite DB used for search_logs
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
current_epoch_ms() {
    local value
    value="$(date +%s%3N 2>/dev/null || true)"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$value"
        return 0
    fi
    python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}

search_started_ms="$(current_epoch_ms)"
_semantic_self="${BASH_SOURCE[0]:-$0}"
[[ "$_semantic_self" != /* ]] && _semantic_self="$PWD/$_semantic_self"
script_dir="${_semantic_self%/scripts/semantic_search.sh}"
index_path="${SEMANTIC_INDEX_PATH:-$script_dir/docs/semantic-index/index.md}"
source_map_path="${SEMANTIC_SOURCE_MAP_PATH:-$script_dir/context/semantic-map.md}"

if [ ! -f "$index_path" ]; then
    echo "ERROR: semantic index not found: $index_path" >&2
    exit 1
fi

default_memory_db_path="$script_dir/data/multi_agent_shogun_memory.db"
memory_db_source_path="${SEMANTIC_MEMORY_DB_PATH:-$default_memory_db_path}"
# Use the same atomic snapshot/single-flight refresh contract as
# memory_db_query.sh. The former local implementation launched a plain
# background subshell from command substitution; bash retained that child and
# semantic preflight waited for a full 622MB refresh under concurrent writes.
export SHOGUN_MEMORY_DB_CACHE_PATH="${SEMANTIC_MEMORY_DB_CACHE_PATH:-${SHOGUN_MEMORY_DB_CACHE_PATH:-}}"
export SHOGUN_MEMORY_DB_CACHE_DIR="${SEMANTIC_MEMORY_DB_CACHE_DIR:-${SHOGUN_MEMORY_DB_CACHE_DIR:-/tmp/shogun_memory_db_cache}}"
export SHOGUN_MEMORY_DB_QUERY_CACHE_NONDEFAULT=1
if [ "${SEMANTIC_DISABLE_MEMORY_DB_CACHE:-0}" = "1" ]; then
    export SHOGUN_MEMORY_DB_QUERY_DISABLE_CACHE=1
fi
memory_db_cache_helper="$script_dir/scripts/lib/memory_db_cache.sh"
if [ -f "$memory_db_cache_helper" ]; then
    # shellcheck source=lib/memory_db_cache.sh
    source "$memory_db_cache_helper"
    memory_db_path="$(prepare_memory_db_for_read "$script_dir" "$memory_db_source_path" "$default_memory_db_path")"
else
    # semantic_search.sh is also copied with semantic_index.py into bounded
    # helper fixtures/installations. Preserve that existing standalone
    # contract; absence of the optional cache helper must not abort an
    # alias-only semantic search or its search-log write.
    memory_db_path="$memory_db_source_path"
fi

semantic_index_python() {
    local mode="$1"
    local mode_arg="${2:-}"
    SEMANTIC_INDEX_CACHE_DIR="${SEMANTIC_INDEX_CACHE_DIR:-$script_dir/tmp/semantic_index_cache}" \
        SEMANTIC_MEMORY_DB_PATH="$memory_db_path" \
        python3 "$script_dir/scripts/semantic_index.py" "$index_path" "$query" "$mode" "$mode_arg"
}

search_log_hit_count() {
    local output_file="$1"
    local count

    if grep -q '^NO_MATCH:' "$output_file" 2>/dev/null; then
        printf '0\n'
        return 0
    fi

    count="$(grep -c '^MATCH: ' "$output_file" 2>/dev/null || true)"
    if [ "${count:-0}" -gt 0 ]; then
        printf '%s\n' "$count"
        return 0
    fi

    count="$(grep -c '^## ' "$output_file" 2>/dev/null || true)"
    printf '%s\n' "${count:-0}"
}

record_search_log() {
    local output_file="$1"
    local rc="$2"

    [ "${SEMANTIC_DISABLE_SEARCH_LOG:-0}" != "1" ] || return 0
    if [ -n "${BATS_TEST_FILENAME:-}" ] && [ -z "${SEMANTIC_SEARCH_LOG_DB_PATH:-}" ]; then
        return 0
    fi
    [ -f "$script_dir/scripts/search_log_write.sh" ] || return 0

    local hit_count no_match elapsed_ms now_ms
    hit_count="$(search_log_hit_count "$output_file")"
    no_match=0
    if grep -q '^NO_MATCH:' "$output_file" 2>/dev/null; then
        no_match=1
    fi
    now_ms="$(current_epoch_ms)"
    elapsed_ms=$((now_ms - search_started_ms))
    if [ "$elapsed_ms" -lt 0 ]; then
        elapsed_ms=0
    fi

    # バックグラウンド化: ログ書込みはメイン出力をブロックしない（-141ms）
    bash "$script_dir/scripts/search_log_write.sh" \
        --caller semantic_search \
        --elapsed-ms "$elapsed_ms" \
        --exit-code "$rc" \
        "$query" "$hit_count" "$no_match" >/dev/null 2>&1 || true &
}

emit_search_output() {
    local output_file="$1"
    local rc="$2"

    cat "$output_file"
    record_search_log "$output_file" "$rc"
}

first_layer_search() {
    local no_match_mode="${1:-print}"
    semantic_index_python first-layer "$no_match_mode"
}

source_map_search() {
    [ -f "$source_map_path" ] || return 1
    semantic_index_python "source-map-first-layer" "$source_map_path"
}

try_source_map_fallback() {
    local output_file="$1"
    if source_map_search > "$output_file"; then
        emit_search_output "$output_file" 0
        return 0
    fi
    return 1
}

memory_db_search() {
    [ "${SEMANTIC_DISABLE_MEMORY_DB:-0}" != "1" ] || return 1

    local search_timeout="${SEMANTIC_MEMORY_DB_TIMEOUT:-5}"
    local target="${SEMANTIC_MEMORY_DB_TARGET:-${AGENT_ID:-}}"
    local db_path="$memory_db_path"
    [ -f "$db_path" ] || return 1

    if [ -z "$target" ] && [ -n "${TMUX_PANE:-}" ]; then
        target="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    fi

    local mode_arg=""
    if [ -n "$target" ] && [ "$target" != "unknown" ]; then
        mode_arg="$target"
    fi
    set +e
    timeout "$search_timeout" env \
        SEMANTIC_INDEX_CACHE_DIR="${SEMANTIC_INDEX_CACHE_DIR:-$script_dir/tmp/semantic_index_cache}" \
        SEMANTIC_MEMORY_DB_PATH="$db_path" \
        python3 "$script_dir/scripts/semantic_index.py" "$index_path" "$query" \
        "memory-db-fts-concept-search" "$mode_arg"
    local rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        if [ "$rc" -eq 124 ]; then
            echo "WARN: memory DB FTS fallback timed out after ${search_timeout}s" >&2
        fi
        return 1
    fi

    return 0
}

append_causal_expansion() {
    local search_output="$1"
    local links

    [ "${SEMANTIC_DISABLE_CAUSAL:-0}" != "1" ] || return 0
    local expansion_limit="${SEMANTIC_CAUSAL_EXPANSION_LIMIT:-2}"
    local backlink_timeout="${SEMANTIC_CAUSAL_BACKLINK_TIMEOUT:-1}"
    case "$expansion_limit" in
        ''|*[!0-9]*) expansion_limit=2 ;;
    esac
    case "$backlink_timeout" in
        ''|*[!0-9]*) backlink_timeout=1 ;;
    esac
    [ "$expansion_limit" -gt 0 ] 2>/dev/null || return 0

    # sed+head を awk 内に統合: subprocess 2個削減（L324原則: pipe fork最小化）
    links=$(
        grep -oE '\[\[[^]]+\]\]|cmd_[A-Za-z0-9_-]+|L[0-9][0-9A-Za-z_-]*|LS-[A-Za-z0-9_-]+|PI-[A-Za-z0-9_-]+|LK[0-9][0-9A-Za-z_-]*' "$search_output" 2>/dev/null \
            | awk -v limit="$expansion_limit" '{
                sub(/^\[\[/, ""); sub(/\]\]$/, "")
                if (!$0 || seen[$0]++) next
                if ($0 ~ /^cmd_/) {
                    print
                    if (++n >= limit) exit
                    next
                }
                deferred[++d] = $0
            }
            END {
                for (i = 1; i <= d && n < limit; i++) {
                    print deferred[i]
                    n++
                }
            }' \
        || true
    )
    [ -n "$links" ] || return 0

    echo ""
    echo "causal_expansion:"
    # 並列化: 全causal_backlinksをバックグラウンド起動→wait→順序通り出力（N×T→max(T)）
    mapfile -t _cb_link_ids <<< "$links"
    local _cb_tmpdir
    _cb_tmpdir="$(mktemp -d)"
    local _idx=0
    for _cb_link_id in "${_cb_link_ids[@]}"; do
        [ -n "$_cb_link_id" ] || { ((_idx++)) || true; continue; }
        (
            if cd "${SEMANTIC_CAUSAL_ROOT:-$script_dir}" 2>/dev/null; then
                timeout "$backlink_timeout" bash "$script_dir/scripts/causal_backlinks.sh" "$_cb_link_id" 2>/dev/null \
                    | head -10 || true
            fi
        ) > "$_cb_tmpdir/$_idx" 2>/dev/null &
        ((_idx++)) || true
    done
    wait
    _idx=0
    for _cb_link_id in "${_cb_link_ids[@]}"; do
        [ -n "$_cb_link_id" ] || { ((_idx++)) || true; continue; }
        echo "- link: [[$_cb_link_id]]"
        if [ -s "$_cb_tmpdir/$_idx" ]; then
            while IFS= read -r resource; do
                [ -n "$resource" ] || continue
                echo "  - resource: $resource"
            done < "$_cb_tmpdir/$_idx"
        else
            echo "  - resource: none"
        fi
        ((_idx++)) || true
    done
    rm -rf "$_cb_tmpdir"
}

llm_cache_key() {
    local llm_cmd="$1"
    local _key
    # cat "$index_path"→sha256sum を stat(mtime+size)に置換（L508: WSL2 NTFS I/O削減）
    # インデックス全量read(O(file_size))→1 statコール(O(1))。同サイズ変更はSEMANTIC_NO_CACHE=1で回避可能
    _key=$({
        printf 'q=%s\n' "$query"
        printf 'cmd=%s\n' "$llm_cmd"
        stat -c '%Y %s' "$index_path" 2>/dev/null \
            || stat -f '%m %z' "$index_path" 2>/dev/null \
            || printf 'fallback\n'
    } | sha256sum)
    printf '%s' "${_key%% *}"
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
            append_causal_expansion "$cache_file"
            return 0
        fi
    fi

    local prompt_file="" output_file="" final_output=""
    trap 'rm -f "${prompt_file:-}" "${output_file:-}" "${final_output:-}"' RETURN
    prompt_file="$(mktemp)"
    output_file="$(mktemp)"
    final_output="$(mktemp)"

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
    append_causal_expansion "$final_output"

    if [ "$no_cache" != "1" ] && [ -n "$cache_file" ]; then
        mkdir -p "$cache_dir"
        local tmp_cache="${cache_file}.tmp.$$"
        if cp "$final_output" "$tmp_cache" 2>/dev/null; then
            mv "$tmp_cache" "$cache_file" 2>/dev/null || rm -f "$tmp_cache"
        fi
    fi
}

if [ "$force_llm" = false ]; then
    if [ "${SEMANTIC_DISABLE_CAUSAL:-0}" = "1" ]; then
        first_output="$(mktemp)"
        trap 'rm -f "$first_output"' EXIT
        if first_layer_search silent > "$first_output"; then
            emit_search_output "$first_output" 0
            exit 0
        else
            rc=$?
            if [ "$rc" -ne 1 ]; then
                exit "$rc"
            fi
            source_output="$(mktemp)"
            trap 'rm -f "$first_output" "$source_output"' EXIT
            if try_source_map_fallback "$source_output"; then
                exit 0
            fi
            if [ "${SEMANTIC_DISABLE_LLM:-0}" = "1" ]; then
                memory_output="$(mktemp)"
                trap 'rm -f "$first_output" "$memory_output"' EXIT
                if memory_db_search > "$memory_output"; then
                    emit_search_output "$memory_output" 0
                    exit 0
                else
                    exit $?
                fi
            fi
        fi
    else
        first_output="$(mktemp)"
        trap 'rm -f "$first_output"' EXIT
        if first_layer_search silent > "$first_output"; then
            causal_output="$(mktemp)"
            trap 'rm -f "$first_output" "$causal_output"' EXIT
            cat "$first_output" > "$causal_output"
            append_causal_expansion "$first_output" >> "$causal_output"
            emit_search_output "$causal_output" 0
            exit 0
        else
            rc=$?
            if [ "$rc" -ne 1 ]; then
                exit "$rc"
            fi
            source_output="$(mktemp)"
            trap 'rm -f "$first_output" "$source_output"' EXIT
            if try_source_map_fallback "$source_output"; then
                exit 0
            fi
            if [ "${SEMANTIC_DISABLE_LLM:-0}" = "1" ]; then
                memory_output="$(mktemp)"
                trap 'rm -f "$first_output" "$memory_output"' EXIT
                if memory_db_search > "$memory_output"; then
                    emit_search_output "$memory_output" 0
                    exit 0
                else
                    exit $?
                fi
            fi
        fi
    fi
fi

if [ "$force_llm" = false ]; then
    memory_output="$(mktemp)"
    trap 'rm -f "$memory_output"' EXIT
    if memory_db_search > "$memory_output"; then
        emit_search_output "$memory_output" 0
        exit 0
    fi
fi

if [ "$force_llm" = false ] && [ "${SEMANTIC_ENABLE_LLM_FALLBACK:-0}" != "1" ]; then
    no_match_output="$(mktemp)"
    trap 'rm -f "$no_match_output"' EXIT
    echo "NO_MATCH: $query" > "$no_match_output"
    emit_search_output "$no_match_output" 1
    echo "WARN: LLM fallback disabled by default. Use --llm or SEMANTIC_ENABLE_LLM_FALLBACK=1 to enable semantic LLM matching." >&2
    exit 1
fi

llm_output="$(mktemp)"
trap 'rm -f "$llm_output"' EXIT
if llm_search > "$llm_output"; then
    emit_search_output "$llm_output" 0
    exit 0
else
    rc=$?
    exit "$rc"
fi
