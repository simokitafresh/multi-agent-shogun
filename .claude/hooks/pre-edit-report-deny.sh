#!/usr/bin/env bash
# pre-edit-report-deny.sh — PreToolUse hook
# queue/reports/*_report_*.yaml へのEdit/Write tool直接書込みをDENY。
# report_field_set.sh経由(Bash tool)は対象外（Bash toolはマッチしない）。
#
# GP-047: PostToolUse WARN(GP-032/041/043-046)→PreToolUse DENY昇格。
# 根拠: PostToolUse WARNINGを忍者が無視 → WA率低下が頭打ち。
# deepdive Phase 4: 「WARNINGは強制ではない。自動化×強制が唯一の解」
#
# 昇格元: post-edit-report-guard.sh (cmd_1265, Mode: WARN)
# 本hookはDENY(BLOCK)モード。PostToolUseのWARN hookは併存（検出ログ用）。

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
                f"BLOCKED: 報告YAMLへの直接Edit/Write禁止。\n"
                f"対象: {file_path}\n"
                f"WHY: report_field_set.sh経由でのみ更新可。flock排他制御+構造保全のため。\n"
                f"FIX: bash scripts/report_field_set.sh {file_path} <dot.notation.key> <value>\n"
                f"例: bash scripts/report_field_set.sh {file_path} result.summary \"検証完了。全5体PASS\"\n"
                f"例: bash scripts/report_field_set.sh {file_path} binary_checks.AC1 "
                f"'[{{check: \"確認内容\", result: \"yes\"}}]'\n"
                f"例: bash scripts/report_field_set.sh {file_path} verdict PASS"
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

# パターン: queue/reports/*_report_*.yaml
if not re.search(r"queue/reports/[^/]*_report_[^/]*\.yaml$", file_path):
    raise SystemExit(0)

# DENY: 直接Edit/Writeを拒否
emit_deny(file_path)
raise SystemExit(1)
PY
