#!/usr/bin/env bash
# Common helpers shared by E2E mock CLIs.

set -euo pipefail

yaml_read() {
    local file="$1"
    local key_path="$2"
    YAML_FILE="$file" YAML_KEY="$key_path" python3 - <<'PY' 2>/dev/null
import os
import yaml

path = os.environ["YAML_FILE"]
key = os.environ["YAML_KEY"]

try:
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except Exception:
    raise SystemExit(1)

value = data
for part in key.split("."):
    if isinstance(value, dict):
        value = value.get(part)
    elif isinstance(value, list) and part.isdigit():
        idx = int(part)
        value = value[idx] if idx < len(value) else None
    else:
        value = None
        break

if value is None:
    raise SystemExit(1)

print(value)
PY
}

inbox_mark_all_read() {
    local inbox_file="$1"
    INBOX_FILE="$inbox_file" python3 - <<'PY'
import os
import tempfile
import yaml

inbox = os.environ["INBOX_FILE"]
if not os.path.exists(inbox):
    print("0")
    raise SystemExit(0)

with open(inbox, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

messages = data.get("messages", [])
count = 0
for message in messages:
    if not message.get("read", False):
        message["read"] = True
        count += 1

data["messages"] = messages

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(inbox), suffix=".tmp")
try:
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as fh:
        yaml.dump(data, fh, default_flow_style=False, allow_unicode=True, indent=2)
    os.replace(tmp_path, inbox)
finally:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)

print(count)
PY
}

ensure_idle_flag() {
    local cli_type="$1"
    local agent_id="$2"
    local state_dir="${SHOGUN_STATE_DIR:-/tmp}"
    mkdir -p "$state_dir"
    if [ "$cli_type" = "claude" ]; then
        touch "${state_dir}/shogun_idle_${agent_id}" 2>/dev/null || true
    fi
}

clear_idle_flag() {
    local agent_id="$1"
    local state_dir="${SHOGUN_STATE_DIR:-/tmp}"
    rm -f "${state_dir}/shogun_idle_${agent_id}" 2>/dev/null || true
}

render_idle_prompt() {
    local cli_type="$1"
    case "$cli_type" in
        claude)
            printf '\n❯ '
            ;;
        *)
            printf '\n? for shortcuts                100%% context left\n› '
            ;;
    esac
}

render_busy_prompt() {
    local cli_type="$1"
    local seconds="$2"
    case "$cli_type" in
        claude)
            printf 'Working on task (%ss • esc to interrupt)\n' "$seconds"
            ;;
        *)
            printf 'Thinking about approach (%ss • esc to interrupt)\n' "$seconds"
            ;;
    esac
}

complete_mock_task() {
    local agent_id="$1"
    local task_file="$2"
    local report_dir="$3"
    local cli_type="$4"
    local summary="$5"

    AGENT_ID="$agent_id" TASK_FILE="$task_file" REPORT_DIR="$report_dir" CLI_TYPE="$cli_type" SUMMARY="$summary" python3 - <<'PY'
import datetime as dt
import os
import tempfile
import yaml

agent_id = os.environ["AGENT_ID"]
task_file = os.environ["TASK_FILE"]
report_dir = os.environ["REPORT_DIR"]
cli_type = os.environ["CLI_TYPE"]
summary = os.environ["SUMMARY"]

with open(task_file, encoding="utf-8") as fh:
    payload = yaml.safe_load(fh) or {}

task = payload.get("task") or {}
status = str(task.get("status", ""))
if status not in {"assigned", "acknowledged", "in_progress"}:
    raise SystemExit(0)

task["status"] = "done"
progress = task.get("progress")
if isinstance(progress, list):
    progress_list = progress
elif progress in (None, ""):
    progress_list = []
else:
    progress_list = [str(progress)]
progress_list.append(f"{cli_type} mock completed task")
task["progress"] = progress_list
payload["task"] = task

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix=".tmp")
try:
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as fh:
        yaml.dump(payload, fh, default_flow_style=False, allow_unicode=True, indent=2)
    os.replace(tmp_path, task_file)
finally:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)

report_name = task.get("report_filename") or f"{agent_id}_report.yaml"
report_path = os.path.join(report_dir, report_name)
os.makedirs(report_dir, exist_ok=True)
report = {
    "worker_id": agent_id,
    "task_id": task.get("subtask_id") or task.get("task_id") or "mock_task",
    "parent_cmd": task.get("parent_cmd", "cmd_mock"),
    "timestamp": dt.datetime.now().isoformat(timespec="seconds"),
    "status": "done",
    "result": {
        "summary": summary,
        "details": f"{cli_type} mock execution",
    },
}

with open(report_path, "w", encoding="utf-8") as fh:
    yaml.dump(report, fh, default_flow_style=False, allow_unicode=True, indent=2)
PY
}
