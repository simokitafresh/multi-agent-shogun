#!/usr/bin/env bash
# bash_state_hook.sh - PreToolUse/PostToolUse hook for Bash tool
# Sets @agent_state=bash_running on pre, restores to active on post.
# This prevents ninja_monitor from misdetecting idle during long bash runs.
#
# Usage (in ~/.claude/settings.json hooks):
#   PreToolUse:  matcher="Bash" -> bash_state_hook.sh
#   PostToolUse: matcher="Bash" -> bash_state_hook.sh
#
# The hook reads JSON payload from stdin and determines pre/post from hookEventName.
set -eu

# Read hook payload from stdin
payload="$(cat)"
if [ -z "${payload//[[:space:]]/}" ]; then
    exit 0
fi

# Determine pre or post from hookEventName in the payload
hook_event="$(printf '%s' "$payload" | jq -r '.hook_event_name // .hookEventName // empty' 2>/dev/null || true)"

# Resolve pane target for this agent
pane="${TMUX_PANE:-}"
if [ -z "$pane" ]; then
    exit 0
fi

case "$hook_event" in
    PreToolUse)
        # Mark as bash_running + record timestamp for crash detection
        tmux set-option -p -t "$pane" @agent_state bash_running 2>/dev/null || true
        tmux set-option -p -t "$pane" @bash_running_since "$(date +%s)" 2>/dev/null || true
        ;;
    PostToolUse)
        # Restore to active
        tmux set-option -p -t "$pane" @agent_state active 2>/dev/null || true
        tmux set-option -p -t "$pane" @bash_running_since "" 2>/dev/null || true
        ;;
esac

exit 0
