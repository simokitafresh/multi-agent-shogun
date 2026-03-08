#!/usr/bin/env bash
# Minimal mock CLI used by E2E tests.
# State machine: IDLE -> BUSY -> IDLE, plus /clear handling.

set -euo pipefail

trap '' INT  # inbox_watcherのC-cを握りつぶす

AGENT_ID="${MOCK_AGENT_ID:-}"
if [ -z "$AGENT_ID" ] && [ -n "${TMUX_PANE:-}" ]; then
    AGENT_ID="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
fi
AGENT_ID="${AGENT_ID:-mock_agent}"

PROCESSING_DELAY="${MOCK_PROCESSING_DELAY:-1}"
PROJECT_ROOT="${MOCK_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

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
    if [ -n "${TMUX_PANE:-}" ]; then
        if [ "$state" = "IDLE" ]; then
            tmux set-option -p -t "$TMUX_PANE" @agent_state idle 2>/dev/null || true
        else
            tmux set-option -p -t "$TMUX_PANE" @agent_state active 2>/dev/null || true
        fi
    fi
    log "STATE $state"
}

mark_unread_messages_read() {
    INBOX_PATH="$INBOX_FILE" python3 - <<'PY'
import os
import tempfile
import yaml

inbox_path = os.environ["INBOX_PATH"]
if not os.path.exists(inbox_path):
    print("0")
    raise SystemExit(0)

with open(inbox_path, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

messages = data.get("messages", [])
unread_count = 0
for msg in messages:
    if not msg.get("read", False):
        msg["read"] = True
        unread_count += 1

data["messages"] = messages

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix=".tmp")
try:
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
    os.replace(tmp_path, inbox_path)
finally:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)

print(str(unread_count))
PY
}

update_task_and_write_report() {
    local processed_count="$1"
    AGENT_ID="$AGENT_ID" TASK_PATH="$TASK_FILE" REPORT_DIR="$REPORT_DIR" PROCESSED_COUNT="$processed_count" python3 - <<'PY'
import datetime as dt
import os
import tempfile
import yaml

agent_id = os.environ["AGENT_ID"]
task_path = os.environ["TASK_PATH"]
report_dir = os.environ["REPORT_DIR"]
processed_count = int(os.environ.get("PROCESSED_COUNT", "0"))

parent_cmd = "cmd_mock"
task_id = "subtask_mock"
report_filename = f"{agent_id}_mock_report.yaml"

if os.path.exists(task_path):
    with open(task_path, encoding="utf-8") as f:
        task_data = yaml.safe_load(f) or {}

    task = task_data.get("task")
    if isinstance(task, dict):
        parent_cmd = task.get("parent_cmd", parent_cmd)
        task_id = task.get("subtask_id", task_id)
        report_filename = task.get("report_filename", f"{agent_id}_report_{parent_cmd}.yaml")

        if task.get("status") == "assigned":
            task["status"] = "acknowledged"
        task["status"] = "in_progress"
        task["status"] = "done"

        progress = task.get("progress")
        if not isinstance(progress, list):
            progress = []
        progress.append(f"mock_cli processed {processed_count} message(s)")
        task["progress"] = progress
        task_data["task"] = task

        tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_path), suffix=".tmp")
        try:
            with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
                yaml.dump(task_data, f, default_flow_style=False, allow_unicode=True, indent=2)
            os.replace(tmp_path, task_path)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

os.makedirs(report_dir, exist_ok=True)
report_path = os.path.join(report_dir, report_filename)
report_payload = {
    "worker_id": agent_id,
    "task_id": task_id,
    "parent_cmd": parent_cmd,
    "timestamp": dt.datetime.now().isoformat(timespec="seconds"),
    "status": "done",
    "result": {
        "summary": f"mock_cli processed {processed_count} unread message(s)",
        "details": "E2E mock run",
    },
}

with open(report_path, "w", encoding="utf-8") as f:
    yaml.dump(report_payload, f, default_flow_style=False, allow_unicode=True, indent=2)

print(report_path)
PY
}

handle_inbox_event() {
    local event="$1"
    set_agent_state "BUSY"
    sleep "$PROCESSING_DELAY"

    local processed_count
    processed_count="$(mark_unread_messages_read)"
    update_task_and_write_report "$processed_count" >/dev/null

    set_agent_state "IDLE"
    log "PROCESSED ${event} unread=${processed_count}"
}

handle_clear() {
    log "CLEAR"
    set_agent_state "IDLE"
}

trap 'set_agent_state "IDLE"' EXIT

set_agent_state "IDLE"
log "READY"

while IFS= read -r line; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue

    if [[ "$line" =~ ^inbox[0-9]+$ ]]; then
        log "EVENT $line"
        handle_inbox_event "$line"
        continue
    fi

    case "$line" in
        /clear|/new)
            handle_clear
            ;;
        *)
            log "INPUT $line"
            ;;
    esac
done

