#!/usr/bin/env bash
# pre-edit-workaround-deny.sh — PreToolUse hook
# logs/karo_workarounds.yaml へのEdit/Write tool直接書込みをDENY。
# karo_workaround_log.sh経由(Bash tool)は対象外（Bash toolはマッチしない）。
#
# GP-055: 教訓→gate昇格パイプラインの強制。
# 根拠: karo_workaround_log.shに3件ALERTメカニズムが実装済みだが、
# 家老がEdit toolで直接編集→ALERTが一度も発火しなかった（deepdive 2026-03-24発見）。
# count_category_entries()バグ修正と併せて、script使用を強制する。

set -eu

payload="$(cat 2>/dev/null || true)"
if [ -z "${payload//[[:space:]]/}" ]; then
    exit 0
fi

HOOK_PAYLOAD="$payload" python3 - <<'PY'
import json
import os
import re
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


def extract_file_path(data: dict) -> str:
    tool_input = data.get("tool_input") or data.get("toolInput") or {}
    if not isinstance(tool_input, dict):
        return ""
    for key in ("file_path", "filePath", "path"):
        value = tool_input.get(key)
        if isinstance(value, str) and value:
            return value
    return ""


def emit_deny(file_path: str):
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                f"BLOCKED: karo_workarounds.yamlへの直接Edit/Write禁止。\n"
                f"対象: {file_path}\n"
                f"WHY: karo_workaround_log.sh経由でのみ記録可。"
                f"ALERTメカニズム(3件同一カテゴリでntfy通知)が発火するために必須。\n"
                f"WA記録: bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> "
                f'"<修正内容>" "<根本原因>"\n'
                f"CLEAN記録: bash scripts/karo_workaround_log.sh --clean <cmd_id> <ninja_name> "
                f'"<詳細>"'
            ),
        }
    }
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


data = load_payload(os.environ.get("HOOK_PAYLOAD", ""))
tool_name = extract_tool_name(data)

# Edit/Write のみ対象
if tool_name not in ("Edit", "Write"):
    raise SystemExit(0)

file_path = extract_file_path(data)
if not file_path:
    raise SystemExit(0)

# パターン: logs/karo_workarounds.yaml
if not re.search(r"logs/karo_workarounds\.yaml$", file_path):
    raise SystemExit(0)

# DENY: 直接Edit/Writeを拒否
emit_deny(file_path)
raise SystemExit(1)
PY
