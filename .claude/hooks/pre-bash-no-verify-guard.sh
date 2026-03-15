#!/usr/bin/env bash
set -eu

payload="$(cat 2>/dev/null || true)"
if [ -z "${payload//[[:space:]]/}" ]; then
    exit 0
fi

HOOK_PAYLOAD="$payload" python3 - <<'PY'
import json
import os
import shlex
import sys


def load_payload(raw: str) -> dict:
    try:
        data = json.loads(raw)
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def extract_tool_name(data: dict) -> str:
    value = data.get("tool_name") or data.get("toolName") or ""
    return value if isinstance(value, str) else ""


def extract_command(data: dict) -> str:
    tool_input = data.get("tool_input") or data.get("toolInput") or {}
    if not isinstance(tool_input, dict):
        return ""
    value = tool_input.get("command") or tool_input.get("cmd") or ""
    return value if isinstance(value, str) else ""


def emit_deny() -> None:
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "BLOCKED: git commit --no-verify is forbidden. Fix hooks, do not bypass them.",
        }
    }
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


data = load_payload(os.environ.get("HOOK_PAYLOAD", ""))
if extract_tool_name(data) != "Bash":
    raise SystemExit(0)

command = extract_command(data)
if not command:
    raise SystemExit(0)

try:
    tokens = shlex.split(command, posix=True)
except ValueError:
    raise SystemExit(0)

if len(tokens) >= 2 and tokens[0] == "git" and tokens[1] == "commit":
    if "--no-verify" in tokens or "-n" in tokens:
        emit_deny()
        raise SystemExit(1)

raise SystemExit(0)
PY
