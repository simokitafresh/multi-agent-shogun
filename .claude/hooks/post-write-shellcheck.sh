#!/usr/bin/env bash
# PostToolUse hook — WARN mode. Must NEVER exit non-zero (GP-095: crash耐性).
_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" || true

payload="$(cat 2>/dev/null || true)"
if [ -z "${payload//[[:space:]]/}" ]; then
    exit 0
fi

HOOK_PAYLOAD="$payload" PROJECT_ROOT="${_PROJECT_ROOT:-/mnt/c/tools/multi-agent-shogun}" python3 - <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path


def load_payload(raw: str) -> dict:
    try:
        data = json.loads(raw)
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def extract_tool_name(data: dict) -> str:
    value = data.get("tool_name") or data.get("toolName") or ""
    return value if isinstance(value, str) else ""


def extract_tool_input(data: dict) -> dict:
    value = data.get("tool_input") or data.get("toolInput") or {}
    return value if isinstance(value, dict) else {}


def candidate_paths(tool_input: dict):
    candidates = []
    for key in ("file_path", "filePath", "path"):
        value = tool_input.get(key)
        if isinstance(value, str) and value:
            candidates.append(value)

    for key in ("paths", "file_paths", "filePaths"):
        value = tool_input.get(key)
        if isinstance(value, list):
            for item in value:
                if isinstance(item, str) and item:
                    candidates.append(item)

    return candidates


def resolve_shell_file(raw_paths, root: Path):
    for raw in raw_paths:
        path = Path(raw)
        if not path.is_absolute():
            path = root / path
        try:
            resolved = path.resolve()
        except Exception:
            continue
        if resolved.suffix not in {".sh", ".bash"}:
            continue
        if root not in resolved.parents and resolved != root:
            continue
        return resolved
    return None


def emit_context(text: str):
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": text,
        }
    }
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


root = Path(os.environ["PROJECT_ROOT"]).resolve()
sys.path.insert(0, str(root / ".claude" / "hooks"))
from hook_violation_logger import append_violation_log

data = load_payload(os.environ.get("HOOK_PAYLOAD", ""))
tool_name = extract_tool_name(data)
if tool_name not in {"Write", "Edit"}:
    raise SystemExit(0)

tool_input = extract_tool_input(data)
target_path = resolve_shell_file(candidate_paths(tool_input), root)
if target_path is None:
    raise SystemExit(0)

relative_target = str(target_path.relative_to(root))
proc = subprocess.run(
    ["shellcheck", relative_target],
    cwd=str(root),
    text=True,
    capture_output=True,
    check=False,
)
if proc.returncode == 0:
    raise SystemExit(0)

violations = "\n".join(part for part in (proc.stdout, proc.stderr) if part.strip()).strip()
if not violations:
    raise SystemExit(0)

append_violation_log(root, "shellcheck", relative_target, violations)
msg = (
    f"ERROR: ShellCheck violations in {relative_target}\n"
    f"WHY: Shell script lint violations must be resolved before proceeding.\n"
    f"FIX: 1) Read the violations below. 2) Fix each violation in {relative_target}. "
    f"3) ShellCheck will re-check automatically on save. "
    f"4) For CRLF errors (SC1017), run: sed -i 's/\\r$//' {relative_target}\n"
    f"\n{violations}"
)
emit_context(msg)
PY
_py_exit=$?
if [ "${_py_exit:-0}" -ne 0 ]; then
    echo "{\"timestamp\":\"$(date -uIs 2>/dev/null || date)\",\"hook\":\"post-write-shellcheck.sh\",\"crash_exit\":${_py_exit}}" >> "${_PROJECT_ROOT}/logs/hook_violations.jsonl" 2>/dev/null || true
fi
exit 0
