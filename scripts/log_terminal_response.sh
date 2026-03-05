#!/usr/bin/env bash
# log_terminal_response.sh — Stopフックで将軍の応答を記録
set -eu

AGENT_ID="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
[ "$AGENT_ID" = "shogun" ] || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/lord_conversation.sh"
export LORD_CONVERSATION="$SCRIPT_DIR/queue/lord_conversation.jsonl"
export LORD_CONVERSATION_LOCK="${LORD_CONVERSATION}.lock"

decode_b64() {
  python3 - "$1" <<'PY'
import base64
import sys

payload = sys.argv[1] if len(sys.argv) > 1 else ""
if not payload:
    print("")
    raise SystemExit(0)
try:
    print(base64.b64decode(payload.encode("ascii")).decode("utf-8"))
except Exception:
    print("")
PY
}

parse_stop_payload() {
  HOOK_PAYLOAD="$1" python3 - <<'PY'
import base64
import json
import os

raw = (os.environ.get("HOOK_PAYLOAD") or "").strip()
data = {}
if raw:
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            data = parsed
    except Exception:
        data = {}

transcript_path = data.get("transcript_path") or data.get("transcriptPath") or ""
if not isinstance(transcript_path, str):
    transcript_path = ""

stop_reason = data.get("stop_reason") or data.get("stopReason") or ""
if not isinstance(stop_reason, str):
    stop_reason = ""

tool_result = data.get("tool_result")
if tool_result is None:
    tool_result = data.get("toolUseResult")
if isinstance(tool_result, (dict, list)):
    tool_result = json.dumps(tool_result, ensure_ascii=False, separators=(",", ":"))
elif not isinstance(tool_result, str):
    tool_result = ""

response = ""
last_msg = data.get("last_assistant_message")
if isinstance(last_msg, dict):
    sr = last_msg.get("stop_reason")
    if isinstance(sr, str) and sr:
        stop_reason = sr
    content = last_msg.get("content")
    if isinstance(content, list):
        texts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                text = block.get("text")
                if isinstance(text, str) and text.strip():
                    texts.append(text.strip())
        response = "\n".join(texts).strip()

def enc(value: str) -> str:
    return base64.b64encode(value.encode("utf-8")).decode("ascii") if value else ""

print(
    "\t".join(
        [
            transcript_path.replace("\t", " ").replace("\n", " "),
            stop_reason.replace("\t", " ").replace("\n", " "),
            enc(tool_result),
            enc(response),
        ]
    )
)
PY
}

extract_from_transcript() {
  python3 - "$1" <<'PY'
import base64
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    print("\t")
    raise SystemExit(0)

last_text = ""
last_stop_reason = ""

with path.open("r", encoding="utf-8") as f:
    for raw in f:
        line = raw.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(record, dict):
            continue
        if record.get("type") != "assistant":
            continue
        message = record.get("message")
        if not isinstance(message, dict):
            continue
        if message.get("role") != "assistant":
            continue
        sr = message.get("stop_reason")
        if isinstance(sr, str) and sr:
            last_stop_reason = sr
        content = message.get("content")
        if not isinstance(content, list):
            continue
        texts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                text = block.get("text")
                if isinstance(text, str) and text.strip():
                    texts.append(text.strip())
        if texts:
            last_text = "\n".join(texts).strip()

encoded = base64.b64encode(last_text.encode("utf-8")).decode("ascii") if last_text else ""
print(f"{last_stop_reason}\t{encoded}")
PY
}

extract_from_pane() {
  RAW="$1" python3 - <<'PY'
import os
import re

raw = os.environ.get("RAW", "")
if not raw:
    print("")
    raise SystemExit(0)

lines = raw.splitlines()
last_prompt = -1
prompt_pattern = re.compile(r"^\s*[›❯]")

for idx, line in enumerate(lines):
    if prompt_pattern.match(line):
        last_prompt = idx

candidate = lines[last_prompt + 1 :] if last_prompt >= 0 else lines
filtered = []
for line in candidate:
    stripped = line.strip()
    if not stripped:
        continue
    if prompt_pattern.match(stripped):
        continue
    filtered.append(line.rstrip())

text = "\n".join(filtered).strip()
if len(text) > 2500:
    text = text[:2499] + "…"
print(text)
PY
}

HOOK_PAYLOAD="$(cat 2>/dev/null || true)"

PAYLOAD_LINE="$(parse_stop_payload "$HOOK_PAYLOAD")"
IFS=$'\t' read -r TRANSCRIPT_PATH STOP_REASON TOOL_RESULT_B64 RESPONSE_B64 <<EOF
$PAYLOAD_LINE
EOF

TOOL_RESULT="$(decode_b64 "$TOOL_RESULT_B64")"
RESPONSE="$(decode_b64 "$RESPONSE_B64")"

if [ -n "$TRANSCRIPT_PATH" ]; then
  TRANSCRIPT_LINE="$(extract_from_transcript "$TRANSCRIPT_PATH")"
  IFS=$'\t' read -r TRANSCRIPT_STOP_REASON TRANSCRIPT_RESPONSE_B64 <<EOF
$TRANSCRIPT_LINE
EOF
  TRANSCRIPT_RESPONSE="$(decode_b64 "$TRANSCRIPT_RESPONSE_B64")"
  if [ -z "$STOP_REASON" ] && [ -n "$TRANSCRIPT_STOP_REASON" ]; then
    STOP_REASON="$TRANSCRIPT_STOP_REASON"
  fi
  if [ -z "$RESPONSE" ] && [ -n "$TRANSCRIPT_RESPONSE" ]; then
    RESPONSE="$TRANSCRIPT_RESPONSE"
  fi
fi

if [ -z "$RESPONSE" ]; then
  RAW="$(tmux capture-pane -t "$TMUX_PANE" -p -S -200 2>/dev/null || true)"
  RESPONSE="$(extract_from_pane "$RAW")"
fi

[ -n "$RESPONSE" ] || exit 0

DETAIL="$RESPONSE"
if [ -n "$STOP_REASON" ]; then
  DETAIL="${DETAIL}"$'\n\n'"[meta] stop_reason=$STOP_REASON"
fi
if [ -n "$TOOL_RESULT" ]; then
  TOOL_RESULT_SNIPPET="$(TOOL_RESULT="$TOOL_RESULT" python3 - <<'PY'
import os

text = " ".join((os.environ.get("TOOL_RESULT") or "").split())
if len(text) > 300:
    text = text[:299] + "…"
print(text)
PY
)"
  if [ -n "$TOOL_RESULT_SNIPPET" ]; then
    DETAIL="${DETAIL}"$'\n'"[meta] tool_result=$TOOL_RESULT_SNIPPET"
  fi
fi

append_lord_conversation "$DETAIL" "response" "shogun" "terminal"

# Stopフック末尾で24h保持と索引更新を実行（失敗時は記録処理を継続）
if ! bash "$SCRIPT_DIR/scripts/conversation_retention.sh"; then
  echo "[log_terminal_response] WARN: conversation_retention.sh failed" >&2
fi
