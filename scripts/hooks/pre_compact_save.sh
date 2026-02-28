#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Read compact metadata from stdin JSON (best effort fallback on parse errors).
payload="$(cat 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  payload='{}'
fi

compact_trigger="$(printf '%s' "$payload" | jq -r '.trigger // "manual"' 2>/dev/null || echo "manual")"
session_id="$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null || echo "")"

agent_id=""
current_task=""

if command -v tmux >/dev/null 2>&1; then
  if [[ -n "${TMUX_PANE:-}" ]]; then
    agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    current_task="$(tmux display-message -t "$TMUX_PANE" -p '#{@current_task}' 2>/dev/null || true)"
  elif [[ -n "${TMUX:-}" ]]; then
    agent_id="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || true)"
    current_task="$(tmux display-message -p '#{@current_task}' 2>/dev/null || true)"
  fi
fi

if [[ -z "$agent_id" ]]; then
  agent_id="unknown"
fi

safe_agent_id="$(printf '%s' "$agent_id" | tr -cd '[:alnum:]_.-')"
if [[ -z "$safe_agent_id" ]]; then
  safe_agent_id="unknown"
fi

mkdir -p "$ROOT_DIR/scripts/hooks"
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
