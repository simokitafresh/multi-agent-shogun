#!/usr/bin/env bash
set -euo pipefail

# Codex has no dedicated Read tool, while inbox_mark_read's safety guard
# requires a read receipt.  This helper makes the read observable and records
# the receipt only after the inbox contents were emitted successfully.

if (( $# < 1 || $# > 2 )); then
  echo "Usage: $0 <agent_id> [--triage]" >&2
  exit 2
fi

agent_id="$1"
mode="${2:-}"
if [[ -n "$mode" && "$mode" != "--triage" ]]; then
  echo "ERROR: invalid mode: $mode" >&2
  exit 2
fi
if [[ ! "$agent_id" =~ ^[a-z_]+$ ]]; then
  echo "ERROR: invalid agent_id: $agent_id" >&2
  exit 2
fi

repo_root="${SHOGUN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
relative_inbox="queue/inbox/${agent_id}.yaml"
inbox_file="${repo_root}/${relative_inbox}"
read_log_dir="${INBOX_READ_LOG_DIR:-/tmp}"
read_log="${read_log_dir}/claude_read_log_${agent_id}.txt"

if [[ ! -f "$inbox_file" ]]; then
  echo "ERROR: inbox not found: $relative_inbox" >&2
  exit 1
fi

if [[ "$mode" == "--triage" ]]; then
  # Parse before emitting anything: malformed operational YAML must fail closed
  # and must never create a read receipt.
  python3 - "$inbox_file" <<'PY'
import datetime as dt
import hashlib
import os
import sys

import yaml

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as fh:
        document = yaml.safe_load(fh)
except (OSError, yaml.YAMLError) as exc:
    print(f"ERROR: malformed inbox YAML: {exc}", file=sys.stderr)
    raise SystemExit(1)

if not isinstance(document, dict) or not isinstance(document.get("messages"), list):
    print("ERROR: malformed inbox YAML: messages must be a list", file=sys.stderr)
    raise SystemExit(1)

now_text = os.environ.get("INBOX_TRIAGE_NOW")
try:
    now = dt.datetime.fromisoformat(now_text) if now_text else dt.datetime.now()
except ValueError:
    print("ERROR: invalid INBOX_TRIAGE_NOW", file=sys.stderr)
    raise SystemExit(2)

p0_types = {"escalation", "blocker", "decision_required", "clear_command", "model_switch"}
p1_types = {"task_assigned", "task_supplement", "review_request", "verify_request", "report_received"}

def parsed_time(value):
    try:
        return dt.datetime.fromisoformat(str(value))
    except (TypeError, ValueError):
        return now

def priority(message):
    explicit = str(message.get("priority", "")).upper()
    if explicit in {"P0", "P1", "P2"}:
        level = int(explicit[1])
    elif message.get("action_required") is True or message.get("type") in p0_types:
        level = 0
    elif message.get("type") in p1_types:
        level = 1
    else:
        level = 2
    if message.get("read") is not True:
        age = max(0.0, (now - parsed_time(message.get("timestamp"))).total_seconds())
        if level == 2 and age >= 24 * 3600:
            level = 1
        elif level == 1 and age >= 4 * 3600:
            level = 0
    return level

indexed = []
for index, message in enumerate(document["messages"]):
    if not isinstance(message, dict) or not message.get("id"):
        print(f"ERROR: malformed inbox YAML: messages[{index}] requires id", file=sys.stderr)
        raise SystemExit(1)
    level = priority(message)
    indexed.append((level, str(message.get("timestamp", "")), str(message["id"]), message))
indexed.sort(key=lambda item: (item[0], item[1], item[2]))

headers = []
for level, _, _, message in indexed:
    content = str(message.get("content", ""))
    headers.append({
        "id": message["id"],
        "priority": f"P{level}",
        "timestamp": message.get("timestamp"),
        "type": message.get("type", "unknown"),
        "from": message.get("from"),
        "action": message.get("action"),
        "action_required": message.get("action_required", False),
        "content_sha256": hashlib.sha256(content.encode()).hexdigest(),
    })

# One compact snapshot first; the complete original document follows unchanged
# so IDs/content and the established read-side contract remain lossless.
sys.stdout.write(yaml.safe_dump({"triage_snapshot": headers}, sort_keys=False, allow_unicode=True))
sys.stdout.write("---\n")
sys.stdout.write(yaml.safe_dump(document, sort_keys=False, allow_unicode=True))
PY
else
  cat -- "$inbox_file"
fi
mkdir -p -- "$read_log_dir"
printf '%s\n' "$relative_inbox" >> "$read_log"
