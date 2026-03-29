#!/usr/bin/env bash
# log_terminal_response.sh — Stopフックで将軍の応答を記録
set -eu

AGENT_ID="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
[ "$AGENT_ID" = "shogun" ] || exit 0

HOOK_PAYLOAD="$(cat 2>/dev/null || true)"
# Early exit for empty payload
[ -n "$HOOK_PAYLOAD" ] || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/lord_conversation.sh"
export LORD_CONVERSATION="$SCRIPT_DIR/queue/lord_conversation.jsonl"
export LORD_CONVERSATION_LOCK="${LORD_CONVERSATION}.lock"

# Capture pane for fallback (fast: reads tmux buffer from memory)
PANE_CAPTURE="$(tmux capture-pane -t "$TMUX_PANE" -p -J -S -200 2>/dev/null || true)"

# Single python3 call: parse payload + decode + extract + compose DETAIL
DETAIL="$(HOOK_PAYLOAD="$HOOK_PAYLOAD" PANE_CAPTURE="$PANE_CAPTURE" python3 - <<'PY'
import json
import os
import re
import sys
from pathlib import Path

hook_payload = os.environ.get("HOOK_PAYLOAD", "")
pane_capture = os.environ.get("PANE_CAPTURE", "")

# --- parse_stop_payload ---
data = {}
if hook_payload:
    try:
        parsed = json.loads(hook_payload)
        if isinstance(parsed, dict):
            data = parsed
    except Exception:
        pass

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

# --- extract_from_transcript ---
if transcript_path:
    path = Path(transcript_path)
    if path.exists():
        last_text = ""
        last_stop_reason = ""
        with path.open("r", encoding="utf-8") as f:
            for raw_line in f:
                line = raw_line.strip()
                if not line:
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(record, dict) or record.get("type") != "assistant":
                    continue
                message = record.get("message")
                if not isinstance(message, dict) or message.get("role") != "assistant":
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
        if not stop_reason and last_stop_reason:
            stop_reason = last_stop_reason
        if not response and last_text:
            response = last_text

# --- extract_from_pane ---
if not response and pane_capture:
    lines = pane_capture.splitlines()
    last_prompt = -1
    prompt_pattern = re.compile(r"^\s*[›❯]")
    for idx, line in enumerate(lines):
        if prompt_pattern.match(line):
            last_prompt = idx
    candidate = lines[last_prompt + 1:] if last_prompt >= 0 else lines
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
        text = text[:2499] + "\u2026"
    response = text

if not response:
    sys.exit(1)

# --- compose DETAIL ---
detail = response
if stop_reason:
    detail += "\n\n[meta] stop_reason=" + stop_reason
if tool_result:
    snippet = " ".join(tool_result.split())
    if len(snippet) > 300:
        snippet = snippet[:299] + "\u2026"
    if snippet:
        detail += "\n[meta] tool_result=" + snippet

print(detail, end="")
PY
)" || exit 0

[ -n "$DETAIL" ] || exit 0

append_lord_conversation "$DETAIL" "response" "shogun" "terminal"

# Stopフック末尾で24h保持と索引更新をバックグラウンド実行
bash "$SCRIPT_DIR/scripts/conversation_retention.sh" &
