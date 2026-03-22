#!/usr/bin/env bash
# post-edit-report-guard.sh — PostToolUse hook
# queue/reports/*_report_*.yaml へのEdit tool直接書込みを検出しWARNING表示。
# report_field_set.sh経由(Bash tool)は対象外。
#
# Mode: WARN (初期)。安定後にBLOCK昇格（PreToolUse deny化）。
# cmd_1265

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


def emit_context(text: str):
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": text,
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
# 正規化: パス末尾部分で判定
if not re.search(r"queue/reports/[^/]*_report_[^/]*\.yaml$", file_path):
    raise SystemExit(0)

# WARNING: report_field_set.sh経由を案内
msg = (
    "WARNING: 報告YAMLへの直接Edit/Write検出。\n"
    "WHY: 報告YAMLはreport_field_set.sh経由で更新せよ。flock排他制御+構造保全のため。\n"
    "FIX: bash scripts/report_field_set.sh <report_path> <dot.notation.key> <value>\n"
    "例: bash scripts/report_field_set.sh queue/reports/hanzo_report_cmd_100.yaml results.AC1.status PASS"
)
emit_context(msg)
PY
