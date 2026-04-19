#!/usr/bin/env bash
# @source: initial (pre-compact state save hook)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Read compact metadata from stdin JSON (best effort fallback on parse errors).
payload="$(cat 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  payload='{}'
fi

# Parse trigger and session_id via bash regex (no jq subprocess)
if [[ "$payload" =~ \"trigger\":\"([^\"]+)\" ]]; then
  compact_trigger="${BASH_REMATCH[1]}"
else
  compact_trigger="manual"
fi
if [[ "$payload" =~ \"session_id\":\"([^\"]+)\" ]]; then
  session_id="${BASH_REMATCH[1]}"
else
  session_id=""
fi

agent_id=""
current_task=""

if command -v tmux >/dev/null 2>&1; then
  if [[ -n "${TMUX_PANE:-}" ]]; then
    # Single tmux call to fetch both variables (tab-delimited)
    tmux_out="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}	#{@current_task}' 2>/dev/null || true)"
    agent_id="${tmux_out%%	*}"
    current_task="${tmux_out##*	}"
  elif [[ -n "${TMUX:-}" ]]; then
    tmux_out="$(tmux display-message -p '#{@agent_id}	#{@current_task}' 2>/dev/null || true)"
    agent_id="${tmux_out%%	*}"
    current_task="${tmux_out##*	}"
  fi
fi

if [[ -z "$agent_id" ]]; then
  agent_id="unknown"
fi

safe_agent_id="$(printf '%s' "$agent_id" | tr -cd '[:alnum:]_.-')"
if [[ -z "$safe_agent_id" ]]; then
  safe_agent_id="unknown"
fi

mkdir -p "$ROOT_DIR/queue/compact_state"

state_file="$ROOT_DIR/queue/compact_state/${safe_agent_id}.yaml"
timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat > "$state_file" <<EOF
agent: $agent_id
timestamp: '$timestamp'
compact_trigger: $compact_trigger
current_task: $current_task
session_id: $session_id
EOF

exit 0
