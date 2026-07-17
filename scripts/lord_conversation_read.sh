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
if [ -n "${LORD_CONVERSATION_FILE:-}" ]; then
  conversation_file="$LORD_CONVERSATION_FILE"
elif [ -f "queue/lord_conversation.jsonl" ]; then
  conversation_file="queue/lord_conversation.jsonl"
else
  script_dir="$(cd "$(dirname "$0")/.." && pwd)"
  conversation_file="$script_dir/queue/lord_conversation.jsonl"
fi

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

jq -Rr --arg agent_id "$agent_id" '
  select(test("\\S")) as $line
  | ($line | fromjson) as $entry
  | if ($entry | type) != "object" then
      error("JSONL entry is not an object")
    else
      select(
        (($entry.target // "") | tostring) == $agent_id
        or (($entry.agent // "") | tostring) == $agent_id
      )
      # Codex unified-exec continuations retain session_id until a terminal
      # exit_code is observed.  Do not let a generic "completed" label on an
      # intermediate envelope masquerade as process completion.
      | if (($entry.session_id // "") | tostring | length) > 0 then
          $entry + {
            execution_state: (
              if (($entry.exit_code? != null)
                  or (($entry.detail // "") | tostring | test("(^|[[:space:]])exit[_ -]?code[=: ]+[0-9]+"; "i")))
              then "finished"
              else "running"
              end
            )
          }
          | tojson
        else
          $line
        end
    end
' "$conversation_file" | tail -n "$limit"
