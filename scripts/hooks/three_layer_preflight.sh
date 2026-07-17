#!/usr/bin/env bash
# Three-layer pre-action evidence issuer/verifier.
# A prompt creates one atomic current evidence record per agent/pane. Mutating
# repo tools must consume that record before they are allowed to run.
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
[[ "$SELF" == /* ]] || SELF="$PWD/$SELF"
ROOT="${SELF%/scripts/hooks/three_layer_preflight.sh}"
EVIDENCE_DIR="${THREE_LAYER_PREACTION_EVIDENCE_DIR:-$ROOT/logs/preaction_memory}"

agent_id="${THREE_LAYER_AGENT_ID:-${PROMPT_STATE_AGENT_ID:-}}"
if [[ -z "$agent_id" ]] && command -v tmux >/dev/null 2>&1; then
    agent_id="$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || true)"
fi
agent_id="${agent_id:-unknown}"
pane_id="${TMUX_PANE:-default}"
safe_key="${agent_id}_${pane_id}"
safe_key="${safe_key//[^A-Za-z0-9_.-]/_}"
evidence_file="$EVIDENCE_DIR/evidence_${safe_key}.json"
nonce_file="$evidence_file.current"
publish_lock="${evidence_file}.publish.lock"

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

is_git_checkout() {
    git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1
}

memory_timeout_fallback() {
    local query="$1" timeout_seconds="${2:-${THREE_LAYER_FALLBACK_TIMEOUT_SECONDS:-10}}" result_file="${3:-/dev/null}"
    local db_path="${MEMORY_DB_QUERY_DB:-$ROOT/data/multi_agent_shogun_memory.db}"
    timeout "${timeout_seconds}s" python3 - "$db_path" "$query" <<'PY' >"$result_file" 2>/dev/null
import datetime, pathlib, re, sqlite3, sys

db_path, query = sys.argv[1:]
aliases = {"quality_throughput": ["品質合格スループット", "growth_loop"], "growth_loop": ["品質合格スループット", "quality_throughput"], "品質合格スループット": ["quality_throughput", "growth_loop"]}
candidates = [query.strip()]
for key, values in aliases.items():
    if key.lower() in query.lower(): candidates.extend(values)
candidates.extend(re.findall(r"[A-Za-z_]{4,}|[一-龥ぁ-んァ-ヶ]{4,}", query))
count, used, ts = 0, "-", ""
with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=0.5) as conn:
    conn.execute("PRAGMA busy_timeout=500")
    for needle in dict.fromkeys(c[:200] for c in candidates if c.strip()):
        phrase = '"' + needle.replace('"', '""') + '"'
        row = conn.execute("SELECT e.ts FROM events_fts JOIN events e ON e.rowid=events_fts.rowid WHERE events_fts MATCH ? LIMIT 1", (phrase,)).fetchone()
        if row: count, ts, used = 1, str(row[0]), needle; break
print(f"{count}\t{used}\t{db_path}\t{ts or datetime.datetime.fromtimestamp(pathlib.Path(db_path).stat().st_mtime, datetime.timezone.utc).isoformat()}")
PY
}

text_index_timeout_fallback() {
    local query="$1" fallback_timeout="$2" result_file="$3"; shift 3
    # In the real checkout, git's tracked-file index gives a bounded scan of
    # the same canonical paths without repeating rg's filesystem walk on 9P.
    # Test/isolated roots without a .git directory use the portable reader.
    if is_git_checkout; then
        local -a relative_paths=() raw_path
        for raw_path in "$@"; do
            relative_paths+=("${raw_path#"$ROOT/"}")
        done
        local git_rc=0
        local match
        match="$(timeout "${fallback_timeout}s" git -C "$ROOT" grep -F -n -- "$query" -- "${relative_paths[@]}" 2>/dev/null | head -1)" || git_rc=$?
        [[ "$git_rc" == 1 ]] && git_rc=0
        if [[ "$git_rc" == 0 && -n "$match" ]]; then
            local source="${match%%:*}" ts
            ts="$(date -r "$ROOT/$source" -Iseconds 2>/dev/null || date -Iseconds)"
            printf '1\t%s\t%s\t%s\n' "$query" "$ROOT/$source" "$ts" >"$result_file"
        fi
        return "$git_rc"
    fi
    timeout "${fallback_timeout}s" python3 - "$query" "$@" <<'PY' >"$result_file" 2>/dev/null
import datetime, os, pathlib, sys

query, *paths = sys.argv[1:]
needle = next((part for part in query.split() if part), query[:80]).encode()
files = []
for raw_path in paths:
    path = pathlib.Path(raw_path)
    if path.is_file():
        files.append(path)
    elif path.is_dir():
        for dirpath, _, names in os.walk(path):
            files.extend(pathlib.Path(dirpath, name) for name in names if name.endswith(".md"))
    else:
        raise SystemExit(2)
if not files:
    raise SystemExit(2)
count, source, newest = 0, "", 0.0
for path in files:
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            if needle in chunk: count = 1; source = str(path); newest = path.stat().st_mtime; break
        if count: break
if not source:
    source = str(files[0])
    newest = max(path.stat().st_mtime for path in files)
print(f"{count}\t{needle.decode(errors='replace') if count else '-'}\t{source}\t{datetime.datetime.fromtimestamp(newest, datetime.timezone.utc).isoformat()}")
PY
}

memory_cache_is_healthy() {
    local source_db="$1" cache_path="$2" boot_id="$3"
    [[ "$source_db" == "$ROOT/data/multi_agent_shogun_memory.db" ]] || return 1
    [[ -s "$cache_path" && -f "${cache_path}.boot_id" ]] || return 1
    [[ "$(cat "${cache_path}.boot_id" 2>/dev/null || true)" == "$boot_id" ]] || return 1
    timeout 0.4s python3 - "$cache_path" <<'PY' >/dev/null 2>&1
import sqlite3, sys
with sqlite3.connect(f"file:{sys.argv[1]}?mode=ro&immutable=1", uri=True, timeout=0.2) as conn:
    tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    required = {"events", "events_fts"}
    if not required.issubset(tables):
        raise SystemExit(1)
    row = conn.execute("SELECT rowid FROM events_fts LIMIT 1").fetchone()
    if row is None or conn.execute("SELECT 1 FROM events WHERE rowid=?", row).fetchone() is None:
        raise SystemExit(1)
PY
}

resolve_memory_cache_path() {
    local source_db="$1" repo_key
    if [[ -n "${SHOGUN_MEMORY_DB_CACHE_PATH:-}" ]]; then
        printf '%s\n' "$SHOGUN_MEMORY_DB_CACHE_PATH"
        return 0
    fi
    repo_key="${ROOT//\//_}"
    printf '%s/%s_%s\n' "${SHOGUN_MEMORY_DB_CACHE_DIR:-/tmp/shogun_memory_db_cache}" "$repo_key" "${source_db##*/}"
}

batch_index_search() {
    local query="$1" timeout_seconds="$2" result_file="$3"
    local source_db="${MEMORY_DB_QUERY_DB:-$ROOT/data/multi_agent_shogun_memory.db}"
    local read_db="$source_db"
    local cache_path
    cache_path="$(resolve_memory_cache_path "$source_db")"
    # A previous-boot cache can be a large but empty/WAL-inconsistent SQLite
    # file.  Size alone is not health.  Accept only this boot's schema-valid,
    # immutable main snapshot with at least one event; normal RO WAL/SHM
    # sidecars are allowed because immutable readers intentionally ignore them.
    local boot_id
    boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf unknown)"
    memory_cache_is_healthy "$source_db" "$cache_path" "$boot_id" && read_db="$cache_path"
    local use_immutable=0
    [[ "$read_db" == "$cache_path" ]] && use_immutable=1
    local semantic_index="${THREE_LAYER_SEMANTIC_INDEX:-$ROOT/docs/semantic-index/index.md}"
    timeout "${timeout_seconds}s" python3 - "$read_db" "$semantic_index" "$query" "$use_immutable" <<'PY' >"$result_file"
import datetime, pathlib, re, sqlite3, sys

db_path, semantic_path, query, use_immutable = sys.argv[1:]
aliases = {
    "quality_throughput": ["品質合格スループット", "growth_loop"],
    "growth_loop": ["品質合格スループット", "quality_throughput"],
    "品質合格スループット": ["quality_throughput", "growth_loop"],
}
candidates = [query.strip()]
for key, values in aliases.items():
    if key.lower() in query.lower():
        candidates.extend(values)
candidates.extend(re.findall(r"[A-Za-z_]{4,}|[一-龥ぁ-んァ-ヶ]{4,}", query))
candidates = list(dict.fromkeys(c[:200] for c in candidates if c.strip()))
memory_rc = semantic_rc = 0
memory_count = semantic_count = 0
memory_query = semantic_query = "-"
memory_ts = datetime.datetime.fromtimestamp(pathlib.Path(db_path).stat().st_mtime, datetime.timezone.utc).isoformat()
semantic_ts = ""
try:
    immutable = "&immutable=1" if use_immutable == "1" else ""
    with sqlite3.connect(f"file:{db_path}?mode=ro{immutable}", uri=True, timeout=0.5) as conn:
        conn.execute("PRAGMA busy_timeout=500")
        for needle in candidates:
            phrase = '"' + needle.replace('"', '""') + '"'
            row = conn.execute("SELECT e.ts FROM events_fts JOIN events e ON e.rowid=events_fts.rowid WHERE events_fts MATCH ? LIMIT 1", (phrase,)).fetchone()
            if row:
                memory_count, memory_ts, memory_query = 1, str(row[0]), needle
                break
except Exception:
    memory_rc = 2
try:
    path = pathlib.Path(semantic_path)
    if not path.is_file():
        raise FileNotFoundError(path)
    for needle in candidates:
        encoded = needle.encode()
        with path.open("rb") as handle:
            while chunk := handle.read(1024 * 1024):
                if encoded in chunk:
                    semantic_count, semantic_query = 1, needle
                    break
        if semantic_count: break
    semantic_ts = datetime.datetime.fromtimestamp(path.stat().st_mtime, datetime.timezone.utc).isoformat()
except Exception:
    semantic_rc = 2
print("\t".join(map(str, (memory_rc, semantic_rc, memory_count, semantic_count,
                              memory_query, semantic_query, memory_ts, semantic_ts))))
raise SystemExit(0 if memory_rc == semantic_rc == 0 else 1)
PY
}

obsidian_cached_search() {
    local query="$1" timeout_seconds="$2" result_file="$3"
    local cache_path="${THREE_LAYER_CAUSAL_INDEX_CACHE:-$ROOT/.cache/causal_index.tsv}"
    local built_cache rc=0
    if [[ -s "$cache_path" ]] && awk -F '\t' 'NF >= 2 { found=1; exit } END { exit !found }' "$cache_path"; then
        built_cache="$cache_path"
        # Serve the last atomic snapshot first. TTL maintenance is detached
        # and single-flight, so cache freshness never enters UserPromptSubmit
        # latency and a slow refresh cannot erase usable evidence.
        if [[ "${THREE_LAYER_CAUSAL_REFRESH_DISABLED:-0}" != 1 ]]; then
            setsid -f flock -n "${cache_path}.refresh.lock" \
                bash "$ROOT/scripts/lib/causal_index.sh" build "$cache_path" >/dev/null 2>&1 </dev/null
        fi
    else
        built_cache="$(timeout "${timeout_seconds}s" bash "$ROOT/scripts/lib/causal_index.sh" build "$cache_path")" || rc=$?
        if [[ "$rc" != 0 || ! -s "$built_cache" ]]; then
            [[ "$rc" != 0 ]] && return "$rc"
            return 1
        fi
    fi
    QUERY="$query" CACHE="$built_cache" python3 - <<'PY' >"$result_file"
import datetime, os, pathlib, re
query = os.environ["QUERY"]
path = pathlib.Path(os.environ["CACHE"])
aliases = {"quality_throughput": ["品質合格スループット", "growth_loop"], "growth_loop": ["品質合格スループット", "quality_throughput"], "品質合格スループット": ["quality_throughput", "growth_loop"]}
candidates = [query.strip()]
for key, values in aliases.items():
    if key.lower() in query.lower(): candidates.extend(values)
candidates.extend(re.findall(r"[A-Za-z_]{4,}|[一-龥ぁ-んァ-ヶ]{4,}", query))
count, used = 0, "-"
for candidate in dict.fromkeys(c[:200] for c in candidates if c.strip()):
    encoded = candidate.encode()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            if encoded in chunk: count, used = 1, candidate; break
    if count: break
ts = datetime.datetime.fromtimestamp(path.stat().st_mtime, datetime.timezone.utc).isoformat()
print(f"{count}\t{used}\t{path}\t{ts}")
PY
}

prewarm_memory_cache_async() {
    local source_db="$1" cache_path="$2" boot_id="$3"
    local refresh_lock="${cache_path}.refresh.lock"
    [[ -f "$source_db" && -f "$ROOT/scripts/lib/memory_db_cache.sh" ]] || return 0
    mkdir -p "${cache_path%/*}" 2>/dev/null || return 0
    # create_memory_db_cache publishes with os.replace().  A non-blocking
    # generation lock makes boot recovery single-flight across all panes.
    export -f memory_cache_is_healthy
    setsid -f flock -n "$refresh_lock" bash -c '
            ROOT="$1"
            if memory_cache_is_healthy "$2" "$3" "$4"; then exit 0; fi
            export SHOGUN_MEMORY_DB_CACHE_PATH="$3"
            source "$1/scripts/lib/memory_db_cache.sh"
            export -f create_memory_db_cache
            if timeout -k 1 "${SHOGUN_MEMORY_DB_CACHE_REFRESH_TIMEOUT:-300}" bash -c '\''create_memory_db_cache "$1" "$2"'\'' _ "$1" "$2"; then
                printf "%s\n" "$4" >"$3.boot_id.tmp"
                mv -f "$3.boot_id.tmp" "$3.boot_id"
            fi
        ' _ "$ROOT" "$source_db" "$cache_path" "$boot_id" >/dev/null 2>&1 </dev/null
}

prompt_from_payload() {
    local payload="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -r 'try (.prompt // "") catch ""' <<<"$payload" 2>/dev/null || true
    else
        printf '%s' "$payload" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p'
    fi
}

issue() {
    local prompt_arg="${1:-}"
    local payload prompt prompt_hash issued_at tmp_file rg_cmd
    local started_ms deadline_ms global_budget_ms="${THREE_LAYER_GLOBAL_BUDGET_MS:-2800}"
    started_ms="$(date +%s%3N)"
    local causal_cache="${THREE_LAYER_CAUSAL_INDEX_CACHE:-$ROOT/.cache/causal_index.tsv}" cold_cache=0
    [[ -s "$causal_cache" ]] || cold_cache=1
    local source_db="${MEMORY_DB_QUERY_DB:-$ROOT/data/multi_agent_shogun_memory.db}" memory_cache boot_id memory_cache_cold=0
    boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf unknown)"
    if is_git_checkout && [[ -f "$ROOT/scripts/memory_db_live_insert.py" ]]; then
        memory_cache="$(resolve_memory_cache_path "$source_db")"
        memory_cache_is_healthy "$source_db" "$memory_cache" "$boot_id" || memory_cache_cold=1
        [[ "$memory_cache_cold" == 1 && "$source_db" == "$ROOT/data/multi_agent_shogun_memory.db" ]] && prewarm_memory_cache_async "$source_db" "$memory_cache" "$boot_id"
    fi
    [[ "$memory_cache_cold" == 1 ]] && cold_cache=1
    [[ "$cold_cache" == 1 && -z "${THREE_LAYER_GLOBAL_BUDGET_MS+x}" ]] && global_budget_ms="${THREE_LAYER_COLD_CACHE_BUDGET_MS:-8500}"
    deadline_ms=$((started_ms + global_budget_ms))
    mkdir -p "$EVIDENCE_DIR"
    if [[ -n "$prompt_arg" ]]; then
        prompt="$prompt_arg"
    else
        payload="$(cat)"
        prompt="$(prompt_from_payload "$payload")"
    fi
    if [[ -z "${prompt//[[:space:]]/}" ]]; then
        printf 'three_layer_preflight: empty prompt\n' >&2
        return 1
    fi
    issued_at="$(date -Iseconds)"
    prompt_hash="$(printf '%s\n%s\n%s' "$prompt" "$issued_at" "${RANDOM:-0}" | sha256sum | awk '{print $1}')"
    local nonce
    nonce="$(printf '%s\n%s\n%s' "$prompt_hash" "$issued_at" "${RANDOM:-0}" | sha256sum | awk '{print $1}')"
    local nonce_tmp
    nonce_tmp="$(mktemp "$EVIDENCE_DIR/.nonce.XXXXXX")"
    printf '%s\n' "$nonce" >"$nonce_tmp"
    # Publish this generation marker before searching.  A newer issue replaces
    # it immediately, so an older slow search can never resurrect its proof.
    # Evidence stays absent until the current generation completes successfully.
    (
        flock -x 9
        rm -f "$evidence_file"
        mv -f "$nonce_tmp" "$nonce_file"
    ) 9>"$publish_lock"

    # rg --fixed-strings cannot handle a pattern with an embedded newline: it
    # exits 2 (a real error, not "no match"), which fails the whole evidence
    # record closed even when the other two layers genuinely succeeded.
    # Multi-line prompts recurred 3x on 2026-07-10 and locked agents out of
    # every tool for the evidence TTL. Obsidian only ever needs a short
    # literal to search for, so give it the prompt's first line, CR-stripped
    # and capped; this does not change what memory_db_query.sh/semantic_search.sh
    # receive (their own query parsers already tokenize multi-line input safely).
    local obsidian_query="${prompt%%$'\n'*}"
    obsidian_query="${obsidian_query//$'\r'/}"
    obsidian_query="${obsidian_query:0:200}"

    # The three layers are independent reads; run them concurrently instead
    # of back-to-back (sequential baseline: median 2.76s / p95 3.22s per
    # UserPromptSubmit) and collect each exit code individually so a slow or
    # failing layer cannot mask another layer's real result.
    local memory_rc=0 semantic_rc=0 obsidian_rc=0 memory_count=0 semantic_count=0 obsidian_count=0
    local memory_query="" semantic_query="" obsidian_used_query="" memory_ts="" semantic_ts="" obsidian_ts="" obsidian_source=""
    local memory_pid="" semantic_pid="" obsidian_pid="" batch_pid="" batch_result="" obsidian_result=""

    local primary_timeout="${THREE_LAYER_PRIMARY_TIMEOUT_SECONDS:-2.2}" obsidian_timeout
    [[ "$memory_cache_cold" == 1 && -z "${THREE_LAYER_PRIMARY_TIMEOUT_SECONDS+x}" ]] && primary_timeout="${THREE_LAYER_COLD_CACHE_TIMEOUT_SECONDS:-7}"
    obsidian_timeout="$primary_timeout"
    [[ "$cold_cache" == 1 ]] && obsidian_timeout="${THREE_LAYER_COLD_CACHE_TIMEOUT_SECONDS:-7}"
    if is_git_checkout && [[ "${THREE_LAYER_BATCH_PRIMARY:-1}" == 1 ]]; then
        batch_result="$(mktemp "$EVIDENCE_DIR/.batch-result.XXXXXX")"
        ( batch_index_search "$prompt" "$primary_timeout" "$batch_result" >/dev/null 2>&1 ) &
        batch_pid=$!
    else
        ( timeout "${primary_timeout}s" bash "$ROOT/scripts/memory_db_query.sh" --search "$prompt" >/dev/null 2>&1 ) &
        memory_pid=$!
        ( timeout "${primary_timeout}s" bash "$ROOT/scripts/semantic_search.sh" "$prompt" >/dev/null 2>&1 ) &
        semantic_pid=$!
    fi
    # Root cause fix: rg fs-walk on 9P (/mnt/c) times out under IO saturation
    # (6 ninjas concurrent). git grep uses git's in-memory index, bypassing
    # 9P filesystem walk entirely. Fallback to rg only if .git is absent.
    if is_git_checkout && [[ -x "$ROOT/scripts/lib/causal_index.sh" ]]; then
        obsidian_result="$(mktemp "$EVIDENCE_DIR/.obsidian-result.XXXXXX")"
        ( obsidian_cached_search "$obsidian_query" "$obsidian_timeout" "$obsidian_result" >/dev/null 2>&1 ) &
        obsidian_pid=$!
    else
        rg_cmd="$(resolve_rg 2>/dev/null || true)"
        if [[ -n "$rg_cmd" ]]; then
            ( timeout "${primary_timeout}s" "$rg_cmd" --no-mmap -n --fixed-strings -- "$obsidian_query" "$ROOT/context/semantic-map.md" "$ROOT/docs" >/dev/null 2>&1 ) &
            obsidian_pid=$!
        fi
    fi

    if [[ -n "$batch_pid" ]]; then
        local batch_rc=0
        wait "$batch_pid" || batch_rc=$?
        if [[ -s "$batch_result" ]]; then
            IFS=$'\t' read -r memory_rc semantic_rc memory_count semantic_count memory_query semantic_query memory_ts semantic_ts <"$batch_result"
        else
            memory_rc="$batch_rc"
            semantic_rc="$batch_rc"
        fi
        rm -f "$batch_result"
    else
        wait "$memory_pid" || memory_rc=$?
        wait "$semantic_pid" || semantic_rc=$?
        # Portable isolated roots expose only command completion, not the
        # indexed hit metadata available in the production batch reader.
        [[ "$memory_rc" == 0 ]] && { memory_count=1; memory_query="$prompt"; memory_ts="$issued_at"; }
        [[ "$semantic_rc" == 0 ]] && { semantic_count=1; semantic_query="$prompt"; semantic_ts="$issued_at"; }
    fi
    # memory_db_query.sh returns 0 for a completed search, including NO_MATCH.
    # Preserve every non-zero result so missing/corrupt DBs and query failures
    # remain fail-closed instead of being mistaken for a successful lookup.
    # semantic_search.sh exit 1 means NO_MATCH (a completed search that found
    # nothing for this prompt text) in the common case, but it also uses
    # exit 1 if docs/semantic-index/index.md itself is missing. Only
    # normalize when the index file is actually present, so a genuinely
    # broken checkout still fails closed. Same reasoning as the Obsidian
    # layer below.
    local semantic_index="${THREE_LAYER_SEMANTIC_INDEX:-$ROOT/docs/semantic-index/index.md}"
    [[ "$semantic_rc" == 1 && -f "$semantic_index" ]] && semantic_rc=0
    # Obsidian's causal index is the repository's [[link]] graph. rg exit 1
    # means no match, which is still a completed search; exit 2 is a failure.
    if [[ -n "$obsidian_pid" ]]; then
        wait "$obsidian_pid" || obsidian_rc=$?
        if [[ -s "$obsidian_result" ]]; then
            IFS=$'\t' read -r obsidian_count obsidian_used_query obsidian_source obsidian_ts <"$obsidian_result"
        fi
        rm -f "$obsidian_result"
    else
        obsidian_rc=127
    fi
    [[ "$obsidian_rc" == 1 ]] && obsidian_rc=0
    if [[ "$obsidian_rc" == 0 && "$obsidian_count" -eq 0 ]] && ! is_git_checkout; then
        obsidian_count=1
        obsidian_used_query="$obsidian_query"
        obsidian_source="$ROOT/context/semantic-map.md"
        obsidian_ts="$issued_at"
    fi
    # A primary timeout is not proof that a search completed. Fall back to
    # bounded, read-only access to each layer's real canonical data. Only a
    # completed fallback becomes rc=0; missing/corrupt data or another timeout
    # remains non-zero and therefore fail-closed without reviving the old
    # all-tools deadlock-by-assumption.
    # Primary and fallback share one UserPromptSubmit deadline.  Timed-out
    # layers retry concurrently; the old sequential 5s + 10s + 10s + 10s
    # path exceeded the hook's fixed 10-second budget and caused the next
    # prompt to supersede a generation that could never publish in time.
    local remaining_ms=$((deadline_ms - $(date +%s%3N)))
    local fallback_seconds fallback_memory_pid="" fallback_semantic_pid="" fallback_obsidian_pid=""
    local fallback_memory_result="" fallback_semantic_result="" fallback_obsidian_result=""
    if (( remaining_ms > 0 )); then
        fallback_seconds="$(awk -v ms="$remaining_ms" 'BEGIN { printf "%.3f", ms / 1000 }')"
        [[ "$memory_rc" == 124 ]] && { fallback_memory_result="$(mktemp "$EVIDENCE_DIR/.memory-fallback.XXXXXX")"; memory_timeout_fallback "$prompt" "$fallback_seconds" "$fallback_memory_result" & fallback_memory_pid=$!; }
        [[ "$semantic_rc" == 124 ]] && { fallback_semantic_result="$(mktemp "$EVIDENCE_DIR/.semantic-fallback.XXXXXX")"; text_index_timeout_fallback "$prompt" "$fallback_seconds" "$fallback_semantic_result" "$semantic_index" & fallback_semantic_pid=$!; }
        [[ "$obsidian_rc" == 124 ]] && { fallback_obsidian_result="$(mktemp "$EVIDENCE_DIR/.obsidian-fallback.XXXXXX")"; text_index_timeout_fallback "$obsidian_query" "$fallback_seconds" "$fallback_obsidian_result" "$ROOT/context/semantic-map.md" "$ROOT/docs" & fallback_obsidian_pid=$!; }
        if [[ -n "$fallback_memory_pid" ]]; then wait "$fallback_memory_pid" && memory_rc=0 || memory_rc=$?; [[ -s "$fallback_memory_result" ]] && IFS=$'\t' read -r memory_count memory_query _memory_source memory_ts <"$fallback_memory_result"; rm -f "$fallback_memory_result"; fi
        if [[ -n "$fallback_semantic_pid" ]]; then wait "$fallback_semantic_pid" && semantic_rc=0 || semantic_rc=$?; [[ -s "$fallback_semantic_result" ]] && IFS=$'\t' read -r semantic_count semantic_query _semantic_source semantic_ts <"$fallback_semantic_result"; rm -f "$fallback_semantic_result"; fi
        if [[ -n "$fallback_obsidian_pid" ]]; then wait "$fallback_obsidian_pid" && obsidian_rc=0 || obsidian_rc=$?; [[ -s "$fallback_obsidian_result" ]] && IFS=$'\t' read -r obsidian_count obsidian_used_query obsidian_source obsidian_ts <"$fallback_obsidian_result"; rm -f "$fallback_obsidian_result"; fi
    fi

    local status=success
    # A completed zero-match search is evidence, not a missing search.  In the
    # production checkout each layer must prove completion with its canonical
    # source timestamp. Portable isolated roots retain the stricter historical
    # hit requirement because their stub rc alone cannot prove a real search.
    local completion_metadata=0
    if [[ "$source_db" == "$ROOT/data/multi_agent_shogun_memory.db" && -n "$memory_ts" && -n "$semantic_ts" && -n "$obsidian_ts" && -n "$obsidian_source" ]] && is_git_checkout; then
        completion_metadata=1
    fi
    if [[ "$memory_rc" != 0 || "$semantic_rc" != 0 || "$obsidian_rc" != 0 ]]; then
        status=failed
    elif [[ "$completion_metadata" != 1 && ( "$memory_count" -le 0 || "$semantic_count" -le 0 || "$obsidian_count" -le 0 ) ]]; then
        status=failed
    fi
    if [[ "$status" != success ]]; then
        printf 'three_layer_preflight: %s evidence failed (memory=%s/%s semantic=%s/%s obsidian=%s/%s)\n' "$agent_id" "$memory_rc" "$memory_count" "$semantic_rc" "$semantic_count" "$obsidian_rc" "$obsidian_count" >&2
        return 1
    fi
    tmp_file="$(mktemp "$EVIDENCE_DIR/.evidence.XXXXXX")"
    {
        printf '{"agent_id":"%s","pane_id":"%s","prompt_hash":"%s","nonce":"%s","issued_at":"%s","memory_db":"%s","semantic":"%s","obsidian":"%s","memory_count":"%s","semantic_count":"%s","obsidian_count":"%s","memory_source":"%s","semantic_source":"%s","obsidian_source":"%s","memory_timestamp":"%s","semantic_timestamp":"%s","obsidian_timestamp":"%s","memory_query":"%s","semantic_query":"%s","obsidian_query":"%s","status":"%s"}\n' \
            "$(json_escape "$agent_id")" "$(json_escape "$pane_id")" "$prompt_hash" "$nonce" "$issued_at" \
            "$memory_rc" "$semantic_rc" "$obsidian_rc" "$memory_count" "$semantic_count" "$obsidian_count" \
            "$(json_escape "${MEMORY_DB_QUERY_DB:-$ROOT/data/multi_agent_shogun_memory.db}")" "$(json_escape "$semantic_index")" "$(json_escape "$obsidian_source")" \
            "$(json_escape "$memory_ts")" "$(json_escape "$semantic_ts")" "$(json_escape "$obsidian_ts")" \
            "$(json_escape "$memory_query")" "$(json_escape "$semantic_query")" "$(json_escape "$obsidian_used_query")" "$status"
    } >"$tmp_file"
    # Publish only if no newer issue superseded this generation.  The shared
    # lock also makes the evidence/current pair atomic to verify readers.
    local publish_rc=0
    (
        flock -x 9
        if [[ "$(cat "$nonce_file" 2>/dev/null || true)" == "$nonce" ]]; then
            mv -f "$tmp_file" "$evidence_file"
        else
            rm -f "$tmp_file"
            exit 75
        fi
    ) 9>"$publish_lock" || publish_rc=$?
    if [[ "$publish_rc" -eq 75 ]]; then
        printf 'three_layer_preflight: %s generation superseded before publish\n' "$agent_id" >&2
        return 75
    fi
    [[ "$publish_rc" -eq 0 ]] || return "$publish_rc"
    printf '%s\n' "$evidence_file"
}

is_allowed_read_only_bash() {
    COMMAND_TEXT="$1" python3 - <<'PY'
import os, shlex, sys

command = os.environ.get("COMMAND_TEXT", "")
# Any shell grammar means the whole command needs proof. This closes redirect,
# substitution, backtick, pipeline, list, and compound-command bypasses.
if any(token in command for token in (";", "&&", "||", "|", ">", "<", "`", "$(", "${")):
    raise SystemExit(1)
try:
    tokens = shlex.split(command, posix=True)
except ValueError:
    raise SystemExit(1)
if not tokens:
    raise SystemExit(1)
base = os.path.basename(tokens[0])
if base in {"cat", "head", "tail", "ls", "pwd", "printf", "rg", "grep"}:
    raise SystemExit(0)
if base == "git" and len(tokens) >= 2 and tokens[1] in {"status", "diff", "log", "show"}:
    raise SystemExit(0)
if base == "bash" and len(tokens) >= 2 and tokens[1].endswith(("memory_db_query.sh", "semantic_search.sh", "three_layer_preflight.sh")):
    raise SystemExit(0)
if base == "bash" and len(tokens) >= 2 and tokens[1].endswith(("inbox_mark_read.sh", "inbox_write.sh", "bulletin_write.sh")):
    raise SystemExit(0)
if base == "bash" and len(tokens) >= 3 and tokens[1].endswith("causal_index.sh") and tokens[2] == "build":
    raise SystemExit(0)
raise SystemExit(1)
PY
}

resolve_rg() {
    local rg_cmd
    rg_cmd="$(command -v rg 2>/dev/null || true)"
    if [[ -n "$rg_cmd" ]]; then
        printf '%s\n' "$rg_cmd"
    elif [[ -x "$HOME/.local/bin/rg" ]]; then
        printf '%s\n' "$HOME/.local/bin/rg"
    elif [[ "${THREE_LAYER_DISABLE_SYSTEM_RG:-0}" != "1" && -x /usr/bin/rg ]]; then
        printf '%s\n' /usr/bin/rg
    else
        return 1
    fi
}

verify() {
    local tool_name="$1" target="${2:-}" command="${3:-}" parsed_status
    if [[ "$tool_name" == "Bash" ]] && is_allowed_read_only_bash "$command"; then
        return 0
    fi
    [[ "$tool_name" == "Read" ]] && return 0
    local root_real target_real
    root_real="$(realpath -m -- "$ROOT")"
    if [[ "$tool_name" != "Bash" ]]; then
        target_real="$(realpath -m -- "$target")"
        [[ "$target_real" == "$root_real"/* ]] || return 0
    fi
    # Read the two-file generation under the same lock used by invalidation and
    # publish.  This prevents verify from observing the rename boundary between
    # evidence JSON and its nonce while concurrent issue calls are active.
    parsed_status="$(
      {
        flock -s 9
        [[ -s "$evidence_file" && -s "$nonce_file" ]] || exit 4
        python3 - "$evidence_file" "$nonce_file" "${THREE_LAYER_PREACTION_MAX_AGE_SECONDS:-14400}" <<'PY'
import json, sys
from datetime import datetime, timezone
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    nonce = open(sys.argv[2], encoding="utf-8").read().strip()
except Exception:
    raise SystemExit(2)
required = ("agent_id", "pane_id", "prompt_hash", "nonce", "issued_at", "memory_db", "semantic", "obsidian", "status")
if any(not str(data.get(key, "")).strip() for key in required):
    raise SystemExit(2)
if nonce != data.get("nonce"):
    raise SystemExit(2)
try:
    issued = datetime.fromisoformat(data["issued_at"].replace("Z", "+00:00"))
    age = (datetime.now(timezone.utc) - issued).total_seconds()
except Exception:
    raise SystemExit(2)
if age < -5 or age > float(sys.argv[3]):
    raise SystemExit(2)
if data.get("status") != "success" or any(str(data.get(key)) != "0" for key in ("memory_db", "semantic", "obsidian")):
    raise SystemExit(3)
print("success")
PY
      } 9>"$publish_lock"
    )" || {
        echo "BLOCK: 三層preflight証跡が無効または失敗状態。復旧: bash scripts/hooks/three_layer_preflight.sh issue \"<今の作業内容1行>\" で再発行せよ" >&2
        return 1
    }
    [[ "$parsed_status" == success ]]
}

case "${1:-}" in
    issue) shift; issue "${1:-}" ;;
    resolve-rg) resolve_rg ;;
    verify) shift; verify "$@" ;;
    *) echo "Usage: $0 issue|verify <tool_name> [target] [command]" >&2; exit 2 ;;
esac
