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
    local payload prompt prompt_hash issued_at tmp_file rg_cmd
    payload="$(cat)"
    prompt="$(prompt_from_payload "$payload")"
    issued_at="$(date -Iseconds)"
    prompt_hash="$(printf '%s\n%s\n%s' "$prompt" "$issued_at" "${RANDOM:-0}" | sha256sum | awk '{print $1}')"
    mkdir -p "$EVIDENCE_DIR"
    # Invalidate the prior prompt before any new search starts. A failed or
    # interrupted search must never leave an older prompt's proof consumable.
    rm -f "$evidence_file"

    local memory_rc=0 semantic_rc=0 obsidian_rc=0
    timeout 5s bash "$ROOT/scripts/memory_db_query.sh" --search "$prompt" >/dev/null 2>&1 || memory_rc=$?
    timeout 5s bash "$ROOT/scripts/semantic_search.sh" "$prompt" >/dev/null 2>&1 || semantic_rc=$?
    # Obsidian's causal index is the repository's [[link]] graph. rg exit 1
    # means no match, which is still a completed search; exit 2 is a failure.
    rg_cmd="$(command -v rg 2>/dev/null || true)"
    if [[ -z "$rg_cmd" && -x "$HOME/.local/bin/rg" ]]; then
        rg_cmd="$HOME/.local/bin/rg"
    elif [[ -z "$rg_cmd" && -x /usr/bin/rg ]]; then
        rg_cmd=/usr/bin/rg
    fi
    if [[ -n "$rg_cmd" ]]; then
        "$rg_cmd" -n --fixed-strings -- "$prompt" "$ROOT/context/semantic-map.md" "$ROOT/docs" >/dev/null 2>&1 || obsidian_rc=$?
    else
        obsidian_rc=127
    fi
    [[ "$obsidian_rc" == 1 ]] && obsidian_rc=0

    local status=success
    [[ "$memory_rc" == 0 && "$semantic_rc" == 0 && "$obsidian_rc" == 0 ]] || status=failed
    tmp_file="$(mktemp "$EVIDENCE_DIR/.evidence.XXXXXX")"
    {
        printf '{"agent_id":"%s","pane_id":"%s","prompt_hash":"%s","issued_at":"%s","memory_db":"%s","semantic":"%s","obsidian":"%s","status":"%s"}\n' \
            "$(json_escape "$agent_id")" "$(json_escape "$pane_id")" "$prompt_hash" "$issued_at" \
            "$memory_rc" "$semantic_rc" "$obsidian_rc" "$status"
    } >"$tmp_file"
    mv -f "$tmp_file" "$evidence_file"
    [[ "$status" == success ]] || {
        printf 'three_layer_preflight: %s evidence failed (memory=%s semantic=%s obsidian=%s)\n' "$agent_id" "$memory_rc" "$semantic_rc" "$obsidian_rc" >&2
        return 1
    }
    printf '%s\n' "$evidence_file"
}

is_allowed_read_only_bash() {
    local command="$1"
    [[ "$command" =~ (^|[[:space:];|&])(cat|head|tail|ls|pwd|printf|echo|rg|grep|git[[:space:]]+(status|diff|log|show)|bats|bash[[:space:]].*(memory_db_query|semantic_search|three_layer_preflight)\.sh)($|[[:space:];|&]) ]] && return 0
    return 1
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
        echo "BLOCK: 三層preflight証跡なし。UserPromptSubmit後に記憶DB・semantic・Obsidian検索を完了せよ" >&2
        return 1
    }
    parsed_status="$(python3 - "$evidence_file" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    raise SystemExit(2)
required = ("agent_id", "pane_id", "prompt_hash", "issued_at", "memory_db", "semantic", "obsidian", "status")
if any(not str(data.get(key, "")).strip() for key in required):
    raise SystemExit(2)
if data.get("status") != "success" or any(str(data.get(key)) != "0" for key in ("memory_db", "semantic", "obsidian")):
    raise SystemExit(3)
print("success")
PY
    )" || {
        echo "BLOCK: 三層preflight証跡が無効または失敗状態" >&2
        return 1
    }
    if [[ -n "${THREE_LAYER_EXPECTED_PROMPT_HASH:-}" ]] && \
       ! grep -q '"prompt_hash":"'"$THREE_LAYER_EXPECTED_PROMPT_HASH"'"' "$evidence_file"; then
        echo "BLOCK: 三層preflight証跡が別promptのもの" >&2
        return 1
    fi
    [[ "$parsed_status" == success ]]
}

case "${1:-}" in
    issue) issue ;;
    verify) shift; verify "$@" ;;
    *) echo "Usage: $0 issue|verify <tool_name> [target] [command]" >&2; exit 2 ;;
esac
