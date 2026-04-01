#!/usr/bin/env bash
# Combined Bash PostToolUse guard: test_result_guard + commit-reminder
# cmd_1661: 2 hooks → 1 script. Eliminates 1 bash startup cost (~60ms).
set -eu

payload="$(cat 2>/dev/null || true)"
[[ -z "${payload//[[:space:]]/}" ]] && exit 0
[[ "$payload" != *'"Bash"'* ]] && exit 0

# === Guard 1: test_result_guard ===
if [[ "$payload" == *'pytest'* || "$payload" == *'bats'* || "$payload" == *'jest'* || \
      "$payload" == *'npm test'* || "$payload" == *'pnpm test'* || "$payload" == *'yarn test'* || \
      "$payload" == *'bun test'* || "$payload" == *'py.test'* ]]; then
    # Delegate to existing python3 logic for complex test output parsing
    HOOK_PAYLOAD="$payload" python3 - <<'PYTEST'
import json
import os
import re
import shlex
import sys


def load_payload(raw: str):
    try:
        data = json.loads(raw)
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def split_segments(command: str):
    return [segment.strip() for segment in re.split(r"(?:&&|\|\||;|\|)", command) if segment.strip()]


def is_test_command(command: str) -> bool:
    if not isinstance(command, str) or not command.strip():
        return False
    for segment in split_segments(command):
        try:
            tokens = shlex.split(segment, posix=True)
        except ValueError:
            continue
        if not tokens:
            continue
        cmd0 = os.path.basename(tokens[0])
        if cmd0 in {"pytest", "py.test", "bats", "jest"}:
            return True
        if cmd0 in {"python", "python3"} and len(tokens) >= 3 and tokens[1] == "-m" and tokens[2] == "pytest":
            return True
        if cmd0 == "npx" and len(tokens) >= 2 and tokens[1] == "jest":
            return True
        if cmd0 in {"npm", "pnpm", "yarn", "bun"} and len(tokens) >= 2 and tokens[1] == "test":
            return True
    return False


def collect_text(value):
    parts = []
    def walk(node):
        if isinstance(node, str):
            if node.strip(): parts.append(node)
            return
        if isinstance(node, list):
            for item in node: walk(item)
            return
        if isinstance(node, dict):
            for item in node.values(): walk(item)
    walk(value)
    return "\n".join(parts)


def extract_output_text(data: dict) -> str:
    candidates = []
    for key in ("tool_result", "toolUseResult", "tool_output", "toolOutput",
                "tool_response", "result", "output", "stdout", "stderr"):
        if key in data:
            candidates.append(collect_text(data.get(key)))
    text = "\n".join(part for part in candidates if part.strip())
    if text.strip():
        return text
    transcript_path = data.get("transcript_path") or data.get("transcriptPath") or ""
    if not isinstance(transcript_path, str) or not transcript_path:
        return ""
    try:
        with open(transcript_path, "r", encoding="utf-8") as fh:
            tail = fh.readlines()[-200:]
    except Exception:
        return ""
    return "".join(tail)


def _filter_tap_lines(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines()
        if not re.match(r"\s*(?:ok|not ok)\b", line)
        and not re.match(r"\s*[✓✗]", line)
    )


def parse_skip_count(text: str) -> int:
    non_tap_text = _filter_tap_lines(text)
    matches = []
    for pat in (r"(\d+)\s+(?:tests?\s+)?skipped\b", r"(\d+)\s+(?:tests?\s+)?skips?\b",
                r"skipped:\s*(\d+)\b", r"skips?:\s*(\d+)\b"):
        for m in re.finditer(pat, non_tap_text, flags=re.IGNORECASE | re.MULTILINE):
            try: matches.append(int(m.group(1)))
            except Exception: pass
    bats_skips = len(re.findall(r"(?im)^\s*(?:ok|not ok)\s+\d+\b.*#\s*skip\b", text))
    if bats_skips: matches.append(bats_skips)
    if matches: return max(matches)
    if re.search(r"(?m)(?:^\s*SKIP(?:PED)?\b|\bSKIP(?:PED)?\s*$)", non_tap_text): return 1
    return 0


def parse_fail_count(text: str) -> int:
    matches = []
    for pat in (r"(\d+)\s+(?:tests?\s+)?failed\b", r"(\d+)\s+(?:test suites?\s+)?failed\b",
                r"(\d+)\s+failures?\b", r"failed:\s*(\d+)\b", r"failures?:\s*(\d+)\b"):
        for m in re.finditer(pat, text, flags=re.IGNORECASE | re.MULTILINE):
            try: matches.append(int(m.group(1)))
            except Exception: pass
    bats_fails = len(re.findall(r"(?im)^\s*not ok\b(?!.*#\s*skip\b)", text))
    if bats_fails: matches.append(bats_fails)
    if matches: return max(matches)
    if re.search(r"(?im)^\s*FAIL(?:ED)?\b", text) or re.search(r"\bFAILED\b", text): return 1
    return 0


data = load_payload(os.environ.get("HOOK_PAYLOAD", ""))
tool_name = data.get("tool_name") or data.get("toolName") or ""
if tool_name != "Bash": raise SystemExit(0)
tool_input = data.get("tool_input") or data.get("toolInput") or {}
command = ""
if isinstance(tool_input, dict):
    raw_command = tool_input.get("command") or tool_input.get("cmd") or ""
    if isinstance(raw_command, str): command = raw_command
if not is_test_command(command): raise SystemExit(0)
output_text = extract_output_text(data)
if not output_text.strip(): raise SystemExit(0)
skip_count = parse_skip_count(output_text)
fail_count = parse_fail_count(output_text)
messages = []
if skip_count > 0:
    messages.append(f"ERROR: {skip_count} test(s) SKIPPED.\nWHY: SKIP=FAIL rule (CLAUDE.md). Skipped tests are treated as failures.\nFIX: 1) Check why tests are skipped. 2) Fix the skip condition or the test. 3) Re-run to confirm 0 skips.")
if fail_count > 0:
    messages.append(f"ERROR: {fail_count} test(s) FAILED.\nWHY: All tests must pass before proceeding.\nFIX: 1) Read the failure output above. 2) Fix the failing code or test. 3) Re-run to confirm all pass.")
if messages:
    payload_out = {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "\n".join(messages)}}
    print(json.dumps(payload_out, ensure_ascii=False, separators=(",", ":")))
PYTEST
fi

# === Guard 2: commit-reminder ===
if [[ "$payload" == *'inbox_write'* && "$payload" == *'report_received'* ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    HOOK_PAYLOAD="$payload" SCRIPT_DIR="$SCRIPT_DIR" python3 - <<'PYCOMMIT'
import json
import os
import subprocess
import sys
import yaml


def load_payload(raw: str) -> dict:
    try:
        data = json.loads(raw)
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


data = load_payload(os.environ.get("HOOK_PAYLOAD", ""))
tool_name = data.get("tool_name") or data.get("toolName") or ""
if tool_name != "Bash": raise SystemExit(0)
tool_input = data.get("tool_input") or data.get("toolInput") or {}
command = tool_input.get("command", "") if isinstance(tool_input, dict) else ""
if "inbox_write" not in command or "report_received" not in command: raise SystemExit(0)
script_dir = os.environ.get("SCRIPT_DIR", "")
ninja_name = ""
parts = command.split()
for i, p in enumerate(parts):
    if p == "report_received" and i + 1 < len(parts):
        ninja_name = parts[i + 1].strip("'\"")
        break
if not ninja_name: raise SystemExit(0)
task_path = os.path.join(script_dir, "queue", "tasks", f"{ninja_name}.yaml")
if not os.path.exists(task_path): raise SystemExit(0)
try:
    with open(task_path) as f:
        task_data = yaml.safe_load(f)
    task = task_data.get("task", task_data) if isinstance(task_data, dict) else {}
    project = task.get("project", "")
except Exception:
    raise SystemExit(0)
if not project: raise SystemExit(0)
projects_path = os.path.join(script_dir, "config", "projects.yaml")
if not os.path.exists(projects_path): raise SystemExit(0)
try:
    with open(projects_path) as f:
        projects = yaml.safe_load(f)
    project_conf = None
    for p in projects.get("projects", []):
        if isinstance(p, dict) and p.get("id") == project:
            project_conf = p
            break
    if not project_conf: raise SystemExit(0)
    project_path = project_conf.get("path", "")
except Exception:
    raise SystemExit(0)
if not project_path or not os.path.isdir(project_path): raise SystemExit(0)
try:
    unstaged = subprocess.run(["git", "diff", "--name-only"], capture_output=True, text=True, cwd=project_path, timeout=5)
    staged = subprocess.run(["git", "diff", "--cached", "--name-only"], capture_output=True, text=True, cwd=project_path, timeout=5)
except Exception:
    raise SystemExit(0)
uncommitted = set()
if unstaged.returncode == 0 and unstaged.stdout.strip(): uncommitted.update(unstaged.stdout.strip().splitlines())
if staged.returncode == 0 and staged.stdout.strip(): uncommitted.update(staged.stdout.strip().splitlines())
filtered = [f for f in uncommitted if not any(f.startswith(p) for p in ("logs/", "queue/", "node_modules/", ".next/", "__pycache__/")) and not f.endswith((".log", ".pyc"))]
if not filtered: raise SystemExit(0)
msg = f"\n⚠ COMMIT MISSING 警告 ⚠\nプロジェクト {project} ({project_path}) にuncommitted変更あり:\n"
for f in sorted(filtered)[:10]: msg += f"  - {f}\n"
if len(filtered) > 10: msg += f"  ... +{len(filtered) - 10} files\n"
msg += f"\n報告を提出する前にcommitせよ:\n  cd {project_path} && git add -A && git commit -m 'feat: <cmd_id> <summary>'\n\ncommit漏れはcmd_complete_gateでBLOCKされ家老の手動対応(WA)が発生する。"
payload_out = {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": msg}}
print(json.dumps(payload_out, ensure_ascii=False, separators=(",", ":")))
PYCOMMIT
fi

exit 0
