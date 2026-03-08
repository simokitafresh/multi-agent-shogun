#!/usr/bin/env bash
# agent_state.sh - shared busy/idle detection for tmux agents
#
# API:
#   check_agent_busy <pane_target> <agent_id>
# Returns:
#   0 = idle
#   1 = busy
#   2 = unknown

AGENT_STATE_DEFAULT_BUSY_PATTERN="esc to interrupt|Running|Streaming|background terminal running|thinking|thought for"
AGENT_STATE_DEFAULT_IDLE_PATTERN="❯|›"

_agent_state_profile_get() {
    local agent_id="$1"
    local key="$2"

    if command -v cli_profile_get >/dev/null 2>&1; then
        cli_profile_get "$agent_id" "$key"
        return 0
    fi

    echo ""
}

check_agent_busy() {
    local pane_target="$1"
    local agent_id="$2"

    if [ -z "$pane_target" ] || [ -z "$agent_id" ]; then
        return 2
    fi

    local idle_flag="/tmp/shogun_idle_${agent_id}"
    local agent_state
    agent_state=$(tmux display-message -t "$pane_target" -p '#{@agent_state}' 2>/dev/null || true)

    if [ "$agent_state" = "idle" ]; then
        [ ! -f "$idle_flag" ] && touch "$idle_flag"
        return 0
    fi

    local output
    output=$(tmux capture-pane -t "$pane_target" -p -J -S -8 2>/dev/null) || return 2

    local busy_pat
    local idle_pat
    busy_pat=$(_agent_state_profile_get "$agent_id" "busy_patterns")
    idle_pat=$(_agent_state_profile_get "$agent_id" "idle_pattern")

    [ -z "$busy_pat" ] && busy_pat="$AGENT_STATE_DEFAULT_BUSY_PATTERN"
    [ -z "$idle_pat" ] && idle_pat="$AGENT_STATE_DEFAULT_IDLE_PATTERN"

    if echo "$output" | grep -qE "$busy_pat"; then
        return 1
    fi

    if echo "$output" | grep -qE "$idle_pat"; then
        tmux set-option -p -t "$pane_target" @agent_state idle 2>/dev/null || true
        [ ! -f "$idle_flag" ] && touch "$idle_flag"
        return 0
    fi

    return 2
}
