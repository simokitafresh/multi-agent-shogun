#!/usr/bin/env bash
# lord_conversation.sh — lord_conversation.yaml 原子追記ライブラリ
# cmd_546: ntfy.sh/ntfy_listener.shの重複ロジックを集約
#
# 提供関数:
#   append_lord_conversation <message> <direction> [agent]
#     - message: 記録するメッセージ（必須）
#     - direction: "outbound" or "inbound"（必須）
#     - agent: エージェントID（省略時はエントリに含めない）
#
# 必須環境変数:
#   LORD_CONVERSATION — lord_conversation.yaml のパス
#   LORD_CONVERSATION_LOCK — ロックファイルのパス
#
# 原子書込み: flock + Python yaml.safe_load + tempfile.mkstemp + os.replace

append_lord_conversation() {
  local message="${1:?append_lord_conversation: message is required}"
  local direction="${2:?append_lord_conversation: direction is required}"
  local agent="${3:-}"

  if [ "$direction" != "outbound" ] && [ "$direction" != "inbound" ]; then
    echo "ERROR: append_lord_conversation: direction must be 'outbound' or 'inbound', got '$direction'" >&2
    return 1
  fi

  if [ -z "${LORD_CONVERSATION:-}" ]; then
    echo "ERROR: append_lord_conversation: LORD_CONVERSATION is not set" >&2
    return 1
  fi
  if [ -z "${LORD_CONVERSATION_LOCK:-}" ]; then
    echo "ERROR: append_lord_conversation: LORD_CONVERSATION_LOCK is not set" >&2
    return 1
  fi

  local timestamp
  timestamp="$(date "+%Y-%m-%dT%H:%M:%S%:z")"

  if [ ! -f "$LORD_CONVERSATION" ]; then
    mkdir -p "$(dirname "$LORD_CONVERSATION")"
    echo "entries: []" > "$LORD_CONVERSATION"
  fi

  if ! (
    flock -w 5 200 || exit 1
    CONV_PATH="$LORD_CONVERSATION" CONV_TIMESTAMP="$timestamp" \
    CONV_DIRECTION="$direction" CONV_AGENT="$agent" CONV_MESSAGE="$message" \
    python3 - <<'PY'
import os
import tempfile

import yaml

path = os.environ["CONV_PATH"]
timestamp = os.environ["CONV_TIMESTAMP"]
direction = os.environ["CONV_DIRECTION"]
agent = os.environ["CONV_AGENT"]
message = os.environ["CONV_MESSAGE"]

try:
    with open(path) as f:
        data = yaml.safe_load(f)
except FileNotFoundError:
    data = {}

if not isinstance(data, dict):
    data = {}

entries = data.get("entries")
if not isinstance(entries, list):
    entries = []

entry = {
    "timestamp": timestamp,
    "direction": direction,
    "channel": "ntfy",
    "message": message,
}
if agent:
    entry["agent"] = agent

entries.append(entry)
data["entries"] = entries

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
try:
    with os.fdopen(tmp_fd, "w") as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
    os.replace(tmp_path, path)
except Exception:
    os.unlink(tmp_path)
    raise
PY
  ) 200>"$LORD_CONVERSATION_LOCK"; then
    return 1
  fi
}
