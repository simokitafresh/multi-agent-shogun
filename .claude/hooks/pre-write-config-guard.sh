#!/usr/bin/env bash
set -eu

payload="$(cat 2>/dev/null || true)"
if [ -z "${payload//[[:space:]]/}" ]; then
    exit 0
fi

HOOK_PAYLOAD="$payload" PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" python3 - <<'PY'
import fnmatch
import json
import os
import sys
from pathlib import Path

PROTECTED_PATTERNS = [
    "pyproject.toml",
    ".eslintrc",
    ".eslintrc.*",
    "eslint.config*",
    "biome.json",
    ".prettierrc",
    ".prettierrc.*",
    "tsconfig.json",
    ".ruff.toml",
    "setup.cfg",
]


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


def resolve_paths(raw_paths, root: Path):
    resolved_paths = []
    for raw in raw_paths:
        path = Path(raw)
        if not path.is_absolute():
            path = root / path
        try:
            resolved = path.resolve()
        except Exception:
            continue
        resolved_paths.append(resolved)
    return resolved_paths


def matches_protected(path: Path, root: Path) -> bool:
    try:
        relative = path.relative_to(root)
    except ValueError:
        return False

    relative_posix = relative.as_posix()
    basename = path.name
    for pattern in PROTECTED_PATTERNS:
        if fnmatch.fnmatch(basename, pattern) or fnmatch.fnmatch(relative_posix, pattern):
            return True
    return False


def emit_deny(target: str):
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                f"ERROR: {target} is a protected config file.\n"
                f"WHY: Linter/formatter configs must not be modified to suppress violations.\n"
                f"FIX: Fix the code that triggered the violation, not the linter config."
            ),
        }
    }
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


root = Path(os.environ["PROJECT_ROOT"]).resolve()
data = load_payload(os.environ.get("HOOK_PAYLOAD", ""))
tool_name = extract_tool_name(data)
if tool_name not in {"Write", "Edit"}:
    raise SystemExit(0)

tool_input = extract_tool_input(data)
for resolved in resolve_paths(candidate_paths(tool_input), root):
    if matches_protected(resolved, root):
        try:
            target = str(resolved.relative_to(root))
        except ValueError:
            target = str(resolved)
        emit_deny(target)
        raise SystemExit(1)

raise SystemExit(0)
PY
