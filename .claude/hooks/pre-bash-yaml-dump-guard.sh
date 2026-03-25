#!/usr/bin/env bash
set -eu

payload="$(cat 2>/dev/null || true)"
if [ -z "${payload//[[:space:]]/}" ]; then
    exit 0
fi

HOOK_PAYLOAD="$payload" python3 - <<'PY'
import json
import os
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


def emit_deny(reason: str) -> None:
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


data = load_payload(os.environ.get("HOOK_PAYLOAD", ""))
if extract_tool_name(data) != "Bash":
    raise SystemExit(0)

command = extract_command(data)
if not command:
    raise SystemExit(0)

# Detect yaml.dump / yaml.safe_dump in Python execution targeting operational YAML files
# Only block when Python is being invoked (not when yaml.dump appears as text in bash args)
invokes_python = any(tok in command for tok in ["python3", "python ", "python\t", "python -"])
has_yaml_dump = "yaml.dump" in command or "yaml.safe_dump" in command
targets_operational = any(
    pattern in command
    for pattern in [
        "queue/",
        "tasks/",
        "shogun_to_karo",
        "karo_snapshot",
        "inbox/",
        "reports/",
    ]
)

if invokes_python and has_yaml_dump and targets_operational:
    emit_deny(
        "BLOCKED: yaml.dump on operational YAML is forbidden (data loss risk). "
        "Use: bash scripts/lib/yaml_field_set.sh <file> <block_id> <field> <value>"
    )
    raise SystemExit(1)

raise SystemExit(0)
PY
