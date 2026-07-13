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

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
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
    # Invalidate before parsing or searching: a malformed/failed new prompt
    # must not inherit the previous prompt's proof.
    mkdir -p "$EVIDENCE_DIR"
    rm -f "$evidence_file" "$nonce_file"
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

    ( timeout 5s bash "$ROOT/scripts/memory_db_query.sh" --search "$prompt" >/dev/null 2>&1 ) &
    memory_pid=$!
    ( timeout 5s bash "$ROOT/scripts/semantic_search.sh" "$prompt" >/dev/null 2>&1 ) &
    semantic_pid=$!
    rg_cmd="$(resolve_rg 2>/dev/null || true)"
    if [[ -n "$rg_cmd" ]]; then
        # --no-mmap: WSL2's 9P-backed /mnt/c mount pays a large syscall
        # penalty for mmap'd reads across the ~2600 files under docs/;
        # buffered reads measured ~30% faster here (2026-07-10 benchmark).
        ( "$rg_cmd" --no-mmap -n --fixed-strings -- "$obsidian_query" "$ROOT/context/semantic-map.md" "$ROOT/docs" >/dev/null 2>&1 ) &
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

    local status=success
    [[ "$memory_rc" == 0 && "$semantic_rc" == 0 && "$obsidian_rc" == 0 ]] || status=failed
    tmp_file="$(mktemp "$EVIDENCE_DIR/.evidence.XXXXXX")"
    {
        printf '{"agent_id":"%s","pane_id":"%s","prompt_hash":"%s","nonce":"%s","issued_at":"%s","memory_db":"%s","semantic":"%s","obsidian":"%s","status":"%s"}\n' \
            "$(json_escape "$agent_id")" "$(json_escape "$pane_id")" "$prompt_hash" "$nonce" "$issued_at" \
            "$memory_rc" "$semantic_rc" "$obsidian_rc" "$status"
    } >"$tmp_file"
    mv -f "$tmp_file" "$evidence_file"
    printf '%s\n' "$nonce" >"${nonce_file}.tmp"
    mv -f "${nonce_file}.tmp" "$nonce_file"
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
    [[ -s "$evidence_file" ]] || {
        echo "BLOCK: 三層preflight証跡なし。UserPromptSubmit後に記憶DB・semantic・Obsidian検索を完了せよ。復旧: bash scripts/hooks/three_layer_preflight.sh issue \"<今の作業内容1行>\"" >&2
        return 1
    }
    parsed_status="$(python3 - "$evidence_file" "$nonce_file" "${THREE_LAYER_PREACTION_MAX_AGE_SECONDS:-14400}" <<'PY'
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
