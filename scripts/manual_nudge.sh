#!/usr/bin/env bash
# manual_nudge.sh — paste-buffer方式で手動nudgeを送信
# Usage: bash scripts/manual_nudge.sh <agent_id> [message]
# Codex CLIにはsend-keys直接ではEnterが届かない(2026-06-24実証)。
# inbox_watcherと同じpaste-buffer + send-keys Enter方式を使う。
set -euo pipefail

AGENT_ID="${1:?Usage: bash scripts/manual_nudge.sh <agent_id> [message]}"
MESSAGE="${2:-inbox1}"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/cli_adapter.sh" 2>/dev/null || true

# agent→pane target解決
PANE_TARGET=$(agent_pane_target "$AGENT_ID" 2>/dev/null || true)
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
