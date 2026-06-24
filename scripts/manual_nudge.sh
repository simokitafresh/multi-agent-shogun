#!/usr/bin/env bash
# manual_nudge.sh — paste-buffer方式で手動nudgeを送信
# Usage: bash scripts/manual_nudge.sh <agent_id> [message]
# Codex CLIにはsend-keys直接ではEnterが届かない(2026-06-24実証)。
# inbox_watcherと同じpaste-buffer + send-keys Enter方式を使う。
set -euo pipefail

AGENT_ID="${1:?Usage: bash scripts/manual_nudge.sh <agent_id> [message]}"
MESSAGE="${2:-inbox1}"

# agent→pane target解決 (inbox_write.sh resolve_agent_pane_targetと同一ロジック)
PANE_TARGET=$(tmux list-panes -a -F '#{session_name}:#{window_name}.#{pane_index} #{@agent_id}' 2>/dev/null \
    | awk -v agent="$AGENT_ID" '$2 == agent { print $1; exit }')
if [ -z "$PANE_TARGET" ]; then
    echo "ERROR: pane target not found for $AGENT_ID" >&2
    exit 1
fi

# paste-buffer + Enter (inbox_watcherと同一方式)
tmux set-buffer -b "manual_nudge_${AGENT_ID}" "$MESSAGE"
if ! timeout 5 tmux paste-buffer -t "$PANE_TARGET" -b "manual_nudge_${AGENT_ID}" -d 2>/dev/null; then
    echo "ERROR: paste-buffer timed out for $AGENT_ID" >&2
    exit 1
fi
sleep 0.5
if ! timeout 5 tmux send-keys -t "$PANE_TARGET" Enter 2>/dev/null; then
    echo "ERROR: send-keys Enter timed out for $AGENT_ID" >&2
    exit 1
fi

echo "OK: nudge sent to $AGENT_ID ($PANE_TARGET): $MESSAGE"
