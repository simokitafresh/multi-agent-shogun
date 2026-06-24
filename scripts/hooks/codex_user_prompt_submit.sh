#!/usr/bin/env bash
# Codex UserPromptSubmit adapter.
# Codex runs multiple hooks for one event concurrently, so sequence-dependent
# actions must be composed in one adapter instead of listed as separate hooks.
set -euo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
ROOT="${_self%/scripts/hooks/codex_user_prompt_submit.sh}"

payload_file="$(mktemp "${TMPDIR:-/tmp}/codex_user_prompt_submit.XXXXXX.json")"
trap 'rm -f "$payload_file"' EXIT
cat >"$payload_file"

# Log first, then inject context. Neither step may block Codex prompt handling.
bash "$ROOT/scripts/log_terminal_input.sh" <"$payload_file" >/dev/null 2>&1 || true
bash "$ROOT/scripts/hooks/prompt_state_inject.sh" <"$payload_file" || true
