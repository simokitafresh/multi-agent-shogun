#!/usr/bin/env bash
# Codex UserPromptSubmit adapter.
# Codex runs multiple hooks for one event concurrently, so sequence-dependent
# actions must be composed in one adapter instead of listed as separate hooks.
set -euo pipefail

# Prompt injection is display/mechanism enforcement, not structural safety.
exit 0

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
ROOT="${_self%/scripts/hooks/codex_user_prompt_submit.sh}"

payload_file="$(mktemp "${TMPDIR:-/tmp}/codex_user_prompt_submit.XXXXXX.json")"
trap 'rm -f "$payload_file"' EXIT
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
