#!/usr/bin/env bash
# tmux pane helpers for E2E tests.

send_to_pane() {
    local pane="$1"
    local text="$2"
    tmux send-keys -t "$pane" "$text"
    sleep 0.3
    tmux send-keys -t "$pane" Enter
}

capture_pane() {
    local pane="$1"
    tmux capture-pane -t "$pane" -p -J -S - 2>/dev/null
}

pane_target() {
    local index="$1"
    echo "${E2E_SESSION}:agents.${index}"
}

pane_is_idle() {
    local pane="$1"
    local content
    content="$(capture_pane "$pane" | tail -8)"
    echo "$content" | grep -qE '(❯|›|\? for shortcuts)'
}

wait_for_pane_idle() {
    local pane="$1"
    local timeout="${2:-30}"
    local elapsed=0

    while [ "$elapsed" -lt "$timeout" ]; do
        if pane_is_idle "$pane"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "TIMEOUT: pane $pane not idle after ${timeout}s" >&2
    capture_pane "$pane" >&2 || true
    return 1
}

dump_pane_for_debug() {
    local pane="$1"
    local label="${2:-pane}"
    echo "=== DEBUG: $label ($pane) ===" >&2
    capture_pane "$pane" >&2 || echo "(capture failed)" >&2
    echo "=== END: $label ===" >&2
}
