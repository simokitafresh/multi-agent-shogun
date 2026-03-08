#!/usr/bin/env bash
# Flexible mock CLI for E2E tests.

set -euo pipefail

trap '' INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mock_behaviors/common.sh"

CLI_TYPE="${MOCK_CLI_TYPE:-codex}"
case "$CLI_TYPE" in
    claude) source "$SCRIPT_DIR/mock_behaviors/claude_behavior.sh" ;;
    *)      source "$SCRIPT_DIR/mock_behaviors/codex_behavior.sh" ;;
esac

AGENT_ID="${MOCK_AGENT_ID:-}"
if [ -z "$AGENT_ID" ] && [ -n "${TMUX_PANE:-}" ]; then
    AGENT_ID="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
fi
AGENT_ID="${AGENT_ID:-mock_agent}"

PROCESSING_DELAY="${MOCK_PROCESSING_DELAY:-1}"
PROJECT_ROOT="${MOCK_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

INBOX_FILE="$PROJECT_ROOT/queue/inbox/${AGENT_ID}.yaml"
TASK_FILE="$PROJECT_ROOT/queue/tasks/${AGENT_ID}.yaml"
REPORT_DIR="$PROJECT_ROOT/queue/reports"

mkdir -p "$(dirname "$INBOX_FILE")" "$(dirname "$TASK_FILE")" "$REPORT_DIR"
[ -f "$INBOX_FILE" ] || echo "messages: []" > "$INBOX_FILE"

log() {
    printf '[mock_cli:%s] %s\n' "$AGENT_ID" "$1"
}

set_agent_state() {
    local state="$1"
    local label="BUSY"
    if [ -n "${TMUX_PANE:-}" ]; then
        tmux set-option -p -t "$TMUX_PANE" @agent_state "$state" 2>/dev/null || true
    fi
    if [ "$state" = "idle" ]; then
        label="IDLE"
        ensure_idle_flag "$CLI_TYPE" "$AGENT_ID"
        render_idle_prompt "$CLI_TYPE"
    else
        clear_idle_flag "$AGENT_ID"
        render_busy_prompt "$CLI_TYPE" "$PROCESSING_DELAY"
    fi
    log "STATE $label"
}

process_task_if_available() {
    if [ ! -f "$TASK_FILE" ]; then
        log "NO TASK FILE"
        return 0
    fi

    local status
    status="$(yaml_read "$TASK_FILE" "task.status" || true)"
    case "$status" in
        assigned|acknowledged|in_progress)
            sleep "$PROCESSING_DELAY"
            complete_mock_task "$AGENT_ID" "$TASK_FILE" "$REPORT_DIR" "$CLI_TYPE" "processed via mock_cli"
            log "TASK COMPLETE"
            ;;
        *)
            log "TASK SKIPPED status=${status:-none}"
            ;;
    esac
}

handle_inbox_event() {
    local event="$1"
    set_agent_state active
    inbox_mark_all_read "$INBOX_FILE" >/dev/null
    process_task_if_available
    set_agent_state idle
    log "EVENT ${event}"
}

handle_clear() {
    local cmd="$1"
    set_agent_state active
    case "$CLI_TYPE" in
        claude)
            claude_startup_banner
            claude_handle_clear "$AGENT_ID" "$PROJECT_ROOT" || true
            ;;
        *)
            codex_startup_banner
            codex_handle_clear "$AGENT_ID" "$PROJECT_ROOT" || true
            ;;
    esac
    process_task_if_available
    set_agent_state idle
    log "CLEAR ${cmd}"
}

handle_busy_hold() {
    local seconds="$1"
    set_agent_state active
    sleep "$seconds"
    set_agent_state idle
    log "BUSY HOLD ${seconds}"
}

handle_input() {
    local line="$1"

    if [[ "$line" =~ ^inbox[0-9]+$ ]]; then
        handle_inbox_event "$line"
        return 0
    fi

    if [[ "$line" =~ ^busy_hold[[:space:]]+([0-9]+)$ ]]; then
        handle_busy_hold "${BASH_REMATCH[1]}"
        return 0
    fi

    case "$line" in
        /clear|/new)
            handle_clear "$line"
            ;;
        *)
            log "Processed input: $line"
            ;;
    esac
}

trap 'set_agent_state idle' EXIT

case "$CLI_TYPE" in
    claude) claude_startup_banner ;;
    *)      codex_startup_banner ;;
esac
set_agent_state idle
log "READY"

while IFS= read -r line; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    handle_input "$line"
done
