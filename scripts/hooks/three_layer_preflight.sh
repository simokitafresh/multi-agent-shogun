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

memory_timeout_fallback() {
    local query="$1" db_path="${MEMORY_DB_QUERY_DB:-$ROOT/data/multi_agent_shogun_memory.db}"
    timeout "${THREE_LAYER_FALLBACK_TIMEOUT_SECONDS:-5}s" python3 - "$db_path" "$query" <<'PY' >/dev/null 2>&1
import sqlite3, sys

db_path, query = sys.argv[1:]
needle = next((part for part in query.split() if part), query[:80])
with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=0.5) as conn:
    conn.execute("PRAGMA busy_timeout=500")
    conn.execute(
        "SELECT 1 FROM events WHERE summary LIKE ? OR detail LIKE ? LIMIT 1",
        (f"%{needle}%", f"%{needle}%"),
    ).fetchone()
PY
}

text_index_timeout_fallback() {
    local query="$1"; shift
    local fallback_timeout="${THREE_LAYER_FALLBACK_TIMEOUT_SECONDS:-5}"
    # In the real checkout, git's tracked-file index gives a bounded scan of
    # the same canonical paths without repeating rg's filesystem walk on 9P.
    # Test/isolated roots without a .git directory use the portable reader.
    if [[ -d "$ROOT/.git" ]]; then
        local -a relative_paths=() raw_path
        for raw_path in "$@"; do
            relative_paths+=("${raw_path#"$ROOT/"}")
        done
        local git_rc=0
        timeout "${fallback_timeout}s" git -C "$ROOT" grep -F -n -- "$query" -- "${relative_paths[@]}" >/dev/null 2>&1 || git_rc=$?
        [[ "$git_rc" == 1 ]] && git_rc=0
        return "$git_rc"
    fi
    timeout "${fallback_timeout}s" python3 - "$query" "$@" <<'PY' >/dev/null 2>&1
import os, pathlib, sys

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
for path in files:
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            if needle in chunk:
                break
PY
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
    mkdir -p "$EVIDENCE_DIR"
    if [[ -n "$prompt_arg" ]]; then
        prompt="$prompt_arg"
    else
        payload="$(cat)"
        prompt="$(prompt_from_payload "$payload")"
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
    local memory_rc=0 semantic_rc=0 obsidian_rc=0
    local memory_pid semantic_pid obsidian_pid=""

    local primary_timeout="${THREE_LAYER_PRIMARY_TIMEOUT_SECONDS:-5}"
    ( timeout "${primary_timeout}s" bash "$ROOT/scripts/memory_db_query.sh" --search "$prompt" >/dev/null 2>&1 ) &
    memory_pid=$!
    ( timeout "${primary_timeout}s" bash "$ROOT/scripts/semantic_search.sh" "$prompt" >/dev/null 2>&1 ) &
    semantic_pid=$!
    rg_cmd="$(resolve_rg 2>/dev/null || true)"
    if [[ -n "$rg_cmd" ]]; then
        # --no-mmap: WSL2's 9P-backed /mnt/c mount pays a large syscall
        # penalty for mmap'd reads across the ~2600 files under docs/;
        # buffered reads measured ~30% faster here (2026-07-10 benchmark).
        ( timeout "${primary_timeout}s" "$rg_cmd" --no-mmap -n --fixed-strings -- "$obsidian_query" "$ROOT/context/semantic-map.md" "$ROOT/docs" >/dev/null 2>&1 ) &
        obsidian_pid=$!
    fi

    wait "$memory_pid" || memory_rc=$?
    wait "$semantic_pid" || semantic_rc=$?
    # memory_db_query.sh returns 0 for a completed search, including NO_MATCH.
    # Preserve every non-zero result so missing/corrupt DBs and query failures
    # remain fail-closed instead of being mistaken for a successful lookup.
    # semantic_search.sh exit 1 means NO_MATCH (a completed search that found
    # nothing for this prompt text) in the common case, but it also uses
    # exit 1 if docs/semantic-index/index.md itself is missing. Only
    # normalize when the index file is actually present, so a genuinely
    # broken checkout still fails closed. Same reasoning as the Obsidian
    # layer below.
    [[ "$semantic_rc" == 1 && -f "$ROOT/docs/semantic-index/index.md" ]] && semantic_rc=0
    # Obsidian's causal index is the repository's [[link]] graph. rg exit 1
    # means no match, which is still a completed search; exit 2 is a failure.
    if [[ -n "$obsidian_pid" ]]; then
        wait "$obsidian_pid" || obsidian_rc=$?
    else
        obsidian_rc=127
    fi
    [[ "$obsidian_rc" == 1 ]] && obsidian_rc=0
    # A primary timeout is not proof that a search completed. Fall back to
    # bounded, read-only access to each layer's real canonical data. Only a
    # completed fallback becomes rc=0; missing/corrupt data or another timeout
    # remains non-zero and therefore fail-closed without reviving the old
    # all-tools deadlock-by-assumption.
    if [[ "$memory_rc" == 124 ]]; then
        memory_rc=124
        memory_timeout_fallback "$prompt" && memory_rc=0 || memory_rc=$?
    fi
    if [[ "$semantic_rc" == 124 ]]; then
        semantic_rc=124
        text_index_timeout_fallback "$prompt" "$ROOT/docs/semantic-index/index.md" && semantic_rc=0 || semantic_rc=$?
    fi
    if [[ "$obsidian_rc" == 124 ]]; then
        obsidian_rc=124
        text_index_timeout_fallback "$obsidian_query" "$ROOT/context/semantic-map.md" "$ROOT/docs" && obsidian_rc=0 || obsidian_rc=$?
    fi

    local status=success
    [[ "$memory_rc" == 0 && "$semantic_rc" == 0 && "$obsidian_rc" == 0 ]] || status=failed
    tmp_file="$(mktemp "$EVIDENCE_DIR/.evidence.XXXXXX")"
    {
        printf '{"agent_id":"%s","pane_id":"%s","prompt_hash":"%s","nonce":"%s","issued_at":"%s","memory_db":"%s","semantic":"%s","obsidian":"%s","status":"%s"}\n' \
            "$(json_escape "$agent_id")" "$(json_escape "$pane_id")" "$prompt_hash" "$nonce" "$issued_at" \
            "$memory_rc" "$semantic_rc" "$obsidian_rc" "$status"
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
    [[ "$status" == success ]] || {
        printf 'three_layer_preflight: %s evidence failed (memory=%s semantic=%s obsidian=%s)\n' "$agent_id" "$memory_rc" "$semantic_rc" "$obsidian_rc" >&2
        return 1
    }
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
