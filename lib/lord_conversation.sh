#!/usr/bin/env bash
# lord_conversation.sh — lord_conversation.jsonl 原子追記ライブラリ
#
# 提供関数:
#   append_lord_conversation <message> <direction> [agent] [source]
#     - message: 記録本文（必須）
#     - direction: inbound/outbound/prompt/response 等（必須）
#     - agent: 発話主体（任意）
#     - source: 由来チャネル（省略時 "ntfy"）
#
# 必須環境変数:
#   LORD_CONVERSATION — queue/lord_conversation.jsonl
#   LORD_CONVERSATION_LOCK — ロックファイル

append_lord_conversation() {
  local message="${1:?append_lord_conversation: message is required}"
  local direction="${2:?append_lord_conversation: direction is required}"
  local agent="${3:-}"
  local source="${4:-ntfy}"

  case "$direction" in
    ""|*[!a-z_]*)
      echo "ERROR: append_lord_conversation: direction must be lowercase snake_case, got '$direction'" >&2
      return 1
      ;;
  esac

  if [ -z "${LORD_CONVERSATION:-}" ]; then
    echo "ERROR: append_lord_conversation: LORD_CONVERSATION is not set" >&2
    return 1
  fi
  if [ -z "${LORD_CONVERSATION_LOCK:-}" ]; then
    echo "ERROR: append_lord_conversation: LORD_CONVERSATION_LOCK is not set" >&2
    return 1
  fi

  local timestamp legacy_yaml
  timestamp="$(date "+%Y-%m-%dT%H:%M:%S%:z")"
  legacy_yaml="${LORD_CONVERSATION%.jsonl}.yaml"

  mkdir -p "$(dirname "$LORD_CONVERSATION")"
  [ -f "$LORD_CONVERSATION" ] || : > "$LORD_CONVERSATION"

  if ! (
    flock -w 5 200 || exit 1
    CONV_PATH="$LORD_CONVERSATION" \
    CONV_LEGACY_PATH="$legacy_yaml" \
    CONV_TIMESTAMP="$timestamp" \
    CONV_DIRECTION="$direction" \
    CONV_AGENT="$agent" \
    CONV_SOURCE="$source" \
    CONV_MESSAGE="$message" \
    python3 - <<'PY'
import json
import os
import tempfile
from pathlib import Path

import yaml

MAX_ENTRIES = 500
SUMMARY_LIMIT = 140

path = Path(os.environ["CONV_PATH"])
legacy_path = Path(os.environ.get("CONV_LEGACY_PATH", ""))
timestamp = os.environ["CONV_TIMESTAMP"]
direction = os.environ["CONV_DIRECTION"]
agent = os.environ["CONV_AGENT"]
source = os.environ.get("CONV_SOURCE", "ntfy") or "ntfy"
message = os.environ["CONV_MESSAGE"]


def normalize_text(value: object) -> str:
    return str(value).replace("\r\n", "\n").replace("\r", "\n").strip()


def summarize(text: str) -> str:
    one_line = " ".join(text.split())
    if len(one_line) <= SUMMARY_LIMIT:
        return one_line
    return one_line[: SUMMARY_LIMIT - 1] + "…"


def load_jsonl(file_path: Path) -> list[dict]:
    entries: list[dict] = []
    if not file_path.exists():
        return entries
    with file_path.open("r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            try:
                parsed = json.loads(line)
            except json.JSONDecodeError:
                parsed = {
                    "ts": "",
                    "source": "parser",
                    "direction": "invalid",
                    "summary": "JSONL parse error",
                    "detail": line,
                }
            if isinstance(parsed, dict):
                entries.append(parsed)
    return entries


def load_legacy_yaml(file_path: Path) -> list[dict]:
    if not file_path.exists():
        return []
    try:
        with file_path.open("r", encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        return []
    if not isinstance(data, dict):
        return []
    raw_entries = data.get("entries")
    if not isinstance(raw_entries, list):
        return []
    converted: list[dict] = []
    for item in raw_entries:
        if not isinstance(item, dict):
            continue
        legacy_message = normalize_text(item.get("message", ""))
        if not legacy_message:
            continue
        legacy_source = str(item.get("channel", "legacy"))
        legacy_agent = str(item.get("agent", "")).strip()
        entry = {
            "ts": str(item.get("timestamp", "")),
            "source": legacy_source,
            "direction": str(item.get("direction", "legacy")),
            "summary": summarize(legacy_message),
            "detail": legacy_message,
        }
        if legacy_agent:
            entry["agent"] = legacy_agent
        converted.append(entry)
    return converted


entries = load_jsonl(path)
if not entries and str(path).endswith(".jsonl"):
    entries = load_legacy_yaml(legacy_path)

normalized_message = normalize_text(message)
if not normalized_message:
    raise SystemExit(0)

entry = {
    "ts": timestamp,
    "source": source,
    "direction": direction,
    "summary": summarize(normalized_message),
    "detail": normalized_message,
}
if agent:
    entry["agent"] = agent

entries.append(entry)
if len(entries) > MAX_ENTRIES:
    entries = entries[-MAX_ENTRIES:]

tmp_fd, tmp_path = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
try:
    with os.fdopen(tmp_fd, "w", encoding="utf-8", errors="replace") as f:
        for row in entries:
            f.write(json.dumps(row, ensure_ascii=False))
            f.write("\n")
    os.replace(tmp_path, path)
except Exception:
    os.unlink(tmp_path)
    raise
PY
  ) 200>"$LORD_CONVERSATION_LOCK"; then
    return 1
  fi
}
