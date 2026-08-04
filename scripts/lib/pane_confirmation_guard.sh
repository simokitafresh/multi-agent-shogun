#!/usr/bin/env bash
# Shared guard for CLI confirmation prompts.
# A nudge sent while this prompt is active can be consumed as the choice
# itself, so callers must defer delivery and preserve the unread message.

# Return 0 when the pane is waiting for an authorized confirmation decision.
_pane_has_confirmation_prompt() {
    local pane_target="$1"
    local capture
    capture=$(tmux capture-pane -t "$pane_target" -p -S -30 2>/dev/null || true)
    [ -n "$capture" ] || return 1
    printf '%s\n' "$capture" | grep -Eiq \
        'Do you want to proceed\?|[[:space:]]1\.[[:space:]]*Yes|[[:space:]]2\.[[:space:]]*No|confirm(ation)? required|approval required'
}
