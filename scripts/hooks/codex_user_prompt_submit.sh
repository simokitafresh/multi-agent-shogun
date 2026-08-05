#!/usr/bin/env bash
# Codex UserPromptSubmit adapter.
# Codex runs multiple hooks for one event concurrently, so sequence-dependent
# actions must be composed in one adapter instead of listed as separate hooks.
set -euo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
ROOT="${_self%/scripts/hooks/codex_user_prompt_submit.sh}"

CODEX_USER_PROMPT_SUBMIT_TOTAL_T0_US="${EPOCHREALTIME/./}"
CODEX_USER_PROMPT_SUBMIT_TOTAL_T0_US="${CODEX_USER_PROMPT_SUBMIT_TOTAL_T0_US:0:16}"
DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-$ROOT}"
if [[ -f "$ROOT/scripts/lib/defense_overhead_writer.sh" ]]; then
    source "$ROOT/scripts/lib/defense_overhead_writer.sh"
else
    defense_overhead_write_async() { return 0; }
fi
CODEX_USER_PROMPT_SUBMIT_TOTAL_RECORDED=0
codex_user_prompt_submit_record_total() {
    local rc="${1:-0}" now_us wall_ms verdict
    [ "${CODEX_USER_PROMPT_SUBMIT_TOTAL_RECORDED:-0}" -eq 0 ] || return 0
    CODEX_USER_PROMPT_SUBMIT_TOTAL_RECORDED=1
    now_us="${EPOCHREALTIME/./}"
    now_us="${now_us:0:16}"
    wall_ms=$(( (now_us - CODEX_USER_PROMPT_SUBMIT_TOTAL_T0_US + 999) / 1000 ))
    verdict=PASS
    [ "$rc" -eq 0 ] || verdict=FAIL
    defense_overhead_write_async codex_user_prompt_submit codex_user_prompt_submit_total "$wall_ms" "$verdict" \
        "codex-user-prompt-submit-${BASHPID}-${CODEX_USER_PROMPT_SUBMIT_TOTAL_T0_US}" || true
}
codex_user_prompt_submit_cleanup() {
    local rc=$?
    rm -f "$payload_file"
    codex_user_prompt_submit_record_total "$rc"
    return "$rc"
}

payload_file="$(mktemp "${TMPDIR:-/tmp}/codex_user_prompt_submit.XXXXXX.json")"
trap codex_user_prompt_submit_cleanup EXIT
cat >"$payload_file"

# Privacy-safe one-shot audit for the real Codex hook envelope.  Arming is an
# explicit file operation; the first invocation consumes the arm atomically,
# records only field names/types and identity candidates, then stops auditing.
# The prompt value is never persisted.
audit_agent="$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || true)"
audit_arm="${CODEX_PROMPT_AUDIT_ARM:-$ROOT/logs/codex_prompt_identity_audit.${audit_agent:-unknown}.arm}"
audit_log="${CODEX_PROMPT_AUDIT_LOG:-$ROOT/logs/codex_prompt_identity_audit.jsonl}"
audit_claim="${audit_arm}.claimed"
if mv "$audit_arm" "$audit_claim" 2>/dev/null; then
    mkdir -p "${audit_log%/*}"
    pane_agent="$audit_agent"
    jq -c --arg ts "$(date -Iseconds)" --arg pane "${TMUX_PANE:-}" --arg pane_agent "$pane_agent" --arg hook_pid "$$" '
      def scalar_candidate($key):
        if has($key) and (.[$key] | type) == "string" and (.[$key] | length) > 0
        then {key:$key, value:.[$key]} else empty end;
      {
        ts:$ts,
        hook_process_pid:$hook_pid,
        pane:$pane,
        pane_agent:$pane_agent,
        payload_keys:(keys | sort),
        payload_types:(to_entries | map({key:.key,type:(.value|type)}) | sort_by(.key)),
        identity_candidates:[
          scalar_candidate("source_event_id"), scalar_candidate("event_id"),
          scalar_candidate("prompt_id"), scalar_candidate("turn_id"),
          scalar_candidate("thread_id"), scalar_candidate("session_id")
        ],
        prompt_present:(has("prompt")),
        prompt_length:(if (.prompt|type) == "string" then (.prompt|length) else 0 end)
      }
    ' "$payload_file" >>"$audit_log" 2>/dev/null || true
    rm -f "$audit_claim"
fi

# Log first, then inject context. Neither step may block Codex prompt handling.
bash "$ROOT/scripts/log_terminal_input.sh" <"$payload_file" >/dev/null 2>&1 || true
bash "$ROOT/scripts/hooks/prompt_state_inject.sh" <"$payload_file" || true
