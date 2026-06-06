#!/usr/bin/env bash
# @source: cmd_781 (PreToolUse/PostToolUse STALL誤判定防御hook)
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

# Read hook payload from stdin without forking cat subprocess
payload=$(</dev/stdin)

# Extract hookEventName using bash regex (avoids jq subprocess)
hook_event=""
if [[ "$payload" =~ \"hook_event_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    hook_event="${BASH_REMATCH[1]}"
elif [[ "$payload" =~ \"hookEventName\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    hook_event="${BASH_REMATCH[1]}"
fi

# Resolve pane target for this agent
pane="${TMUX_PANE:-}"
if [ -z "$pane" ]; then
    exit 0
fi

case "$hook_event" in
    PreToolUse)
        # Mark as bash_running + record timestamp for crash detection
        _ts="${EPOCHSECONDS:-}"
        if [ -z "$_ts" ]; then
            printf -v _ts '%(%s)T' -1
        fi
        set +e
        tmux set-option -p -t "$pane" @agent_state bash_running \; \
            set-option -p -t "$pane" @bash_running_since "$_ts" 2>/dev/null
        exit 0
        ;;
    PostToolUse)
        # Restore to active
        set +e
        tmux set-option -p -t "$pane" @agent_state active \; \
            set-option -p -t "$pane" @bash_running_since "" 2>/dev/null
        exit 0
        ;;
esac

exit 0
