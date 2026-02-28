#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

payload="$(cat 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  exit 0
fi

if ! printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

agent_id=""
if command -v tmux >/dev/null 2>&1; then
  if [[ -n "${TMUX_PANE:-}" ]]; then
    agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
  elif [[ -n "${TMUX:-}" ]]; then
    agent_id="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || true)"
  fi
fi

if [[ -z "$agent_id" || "$agent_id" == "shogun" ]]; then
  exit 0
fi

idle_flag="/tmp/shogun_idle_${agent_id}"

stop_hook_active="$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
if [[ "$stop_hook_active" == "true" ]]; then
  touch "$idle_flag"
  exit 0
fi

inbox_file="$SCRIPT_DIR/queue/inbox/${agent_id}.yaml"
if [[ ! -f "$inbox_file" ]]; then
  exit 0
fi

unread_count="$(awk '/^[[:space:]]*read:[[:space:]]*false[[:space:]]*$/{c++} END{print c+0}' "$inbox_file" 2>/dev/null || echo 0)"
if [[ ! "$unread_count" =~ ^[0-9]+$ ]]; then
  unread_count=0
fi

if (( unread_count > 0 )); then
  rm -f "$idle_flag"
  printf '{"decision":"block","reason":"inbox未読%d件"}\n' "$unread_count"
else
  touch "$idle_flag"
fi

exit 0
