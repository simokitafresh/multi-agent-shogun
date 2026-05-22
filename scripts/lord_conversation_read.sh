#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <agent_id> [limit]" >&2
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit 2
fi

agent_id="$1"
limit="${2:-5}"
conversation_file="${LORD_CONVERSATION_FILE:-queue/lord_conversation.jsonl}"

if [ -z "$agent_id" ]; then
  echo "FATAL: agent_id is required" >&2
  exit 2
fi

case "$limit" in
  ''|*[!0-9]*)
    echo "FATAL: limit must be a positive integer" >&2
    exit 2
    ;;
esac

if [ "$limit" -le 0 ]; then
  echo "FATAL: limit must be a positive integer" >&2
  exit 2
fi

if [ ! -f "$conversation_file" ]; then
  echo "FATAL: conversation file not found: $conversation_file" >&2
  exit 1
fi

python3 - "$agent_id" "$limit" "$conversation_file" <<'PY'
import json
import sys
from collections import deque

agent_id = sys.argv[1]
limit = int(sys.argv[2])
path = sys.argv[3]
matches = deque(maxlen=limit)

with open(path, "r", encoding="utf-8") as fh:
    for lineno, raw in enumerate(fh, 1):
        line = raw.rstrip("\n")
        if not line.strip():
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError as exc:
            print(f"FATAL: invalid JSONL at {path}:{lineno}: {exc}", file=sys.stderr)
            sys.exit(1)
        if not isinstance(entry, dict):
            print(f"FATAL: JSONL entry is not an object at {path}:{lineno}", file=sys.stderr)
            sys.exit(1)

        target = entry.get("target")
        agent = entry.get("agent")
        target_text = "" if target is None else str(target)
        agent_text = "" if agent is None else str(agent)

        if target_text == "" or target_text == agent_id or agent_text == agent_id:
            matches.append(line)

for line in matches:
    print(line)
PY
