#!/usr/bin/env bash
# PostToolUse hook: inject context when Bash test commands report SKIP/FAIL.
set -eu

payload="$(cat 2>/dev/null || true)"
if [ -z "${payload//[[:space:]]/}" ]; then
    exit 0
fi

HOOK_PAYLOAD="$payload" python3 - <<'PY'
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
            if node.strip():
                parts.append(node)
            return
        if isinstance(node, list):
            for item in node:
                walk(item)
            return
        if isinstance(node, dict):
            for item in node.values():
                walk(item)

    walk(value)
    return "\n".join(parts)


def extract_output_text(data: dict) -> str:
    candidates = []
    for key in (
        "tool_result",
        "toolUseResult",
        "tool_output",
        "toolOutput",
        "tool_response",
        "result",
        "output",
        "stdout",
        "stderr",
    ):
        if key in data:
            candidates.append(collect_text(data.get(key)))

    # last_assistant_message is NOT tool output — exclude from SKIP/FAIL detection
    # to prevent false positives when conversation text contains "SKIP"/"FAIL".

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


def numeric_matches(text: str, patterns):
    values = []
    for pattern in patterns:
        for match in re.finditer(pattern, text, flags=re.IGNORECASE | re.MULTILINE):
            try:
                values.append(int(match.group(1)))
            except Exception:
                continue
    return values


def _filter_tap_lines(text: str) -> str:
    """Remove bats TAP output lines (ok N .../not ok N ...) and pretty-format
    lines (✓/✗) to prevent false positives in generic skip/fail regex patterns."""
    return "\n".join(
        line for line in text.splitlines()
        if not re.match(r"\s*(?:ok|not ok)\b", line)
        and not re.match(r"\s*[✓✗]", line)
    )


def parse_skip_count(text: str) -> int:
    non_tap_text = _filter_tap_lines(text)

    matches = numeric_matches(
        non_tap_text,
        (
            r"(\d+)\s+(?:tests?\s+)?skipped\b",
            r"(\d+)\s+(?:tests?\s+)?skips?\b",
            r"skipped:\s*(\d+)\b",
            r"skips?:\s*(\d+)\b",
        ),
    )

    bats_skips = len(re.findall(r"(?im)^\s*(?:ok|not ok)\s+\d+\b.*#\s*skip\b", text))
    if bats_skips:
        matches.append(bats_skips)

    if matches:
        return max(matches)

    if re.search(r"(?m)(?:^\s*SKIP(?:PED)?\b|\bSKIP(?:PED)?\s*$)", non_tap_text):
        return 1

    return 0


def parse_fail_count(text: str) -> int:
    matches = numeric_matches(
        text,
        (
            r"(\d+)\s+(?:tests?\s+)?failed\b",
            r"(\d+)\s+(?:test suites?\s+)?failed\b",
            r"(\d+)\s+failures?\b",
            r"failed:\s*(\d+)\b",
            r"failures?:\s*(\d+)\b",
        ),
    )

    bats_fails = len(re.findall(r"(?im)^\s*not ok\b(?!.*#\s*skip\b)", text))
    if bats_fails:
        matches.append(bats_fails)

    if matches:
        return max(matches)

    if re.search(r"(?im)^\s*FAIL(?:ED)?\b", text) or re.search(r"\bFAILED\b", text):
        return 1

    return 0


def emit_context(messages):
    if not messages:
        return
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": "\n".join(messages),
        }
    }
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


data = load_payload(os.environ.get("HOOK_PAYLOAD", ""))
tool_name = data.get("tool_name") or data.get("toolName") or ""
if tool_name != "Bash":
    raise SystemExit(0)

tool_input = data.get("tool_input") or data.get("toolInput") or {}
command = ""
if isinstance(tool_input, dict):
    raw_command = tool_input.get("command") or tool_input.get("cmd") or ""
    if isinstance(raw_command, str):
        command = raw_command

if not is_test_command(command):
    raise SystemExit(0)

output_text = extract_output_text(data)
if not output_text.strip():
    raise SystemExit(0)

skip_count = parse_skip_count(output_text)
fail_count = parse_fail_count(output_text)

messages = []
if skip_count > 0:
    messages.append(
        f"ERROR: {skip_count} test(s) SKIPPED.\n"
        f"WHY: SKIP=FAIL rule (CLAUDE.md). Skipped tests are treated as failures.\n"
        f"FIX: 1) Check why tests are skipped (missing dependencies? wrong conditions?). "
        f"2) Fix the skip condition or the test. 3) Re-run the test command to confirm 0 skips."
    )
if fail_count > 0:
    messages.append(
        f"ERROR: {fail_count} test(s) FAILED.\n"
        f"WHY: All tests must pass before proceeding.\n"
        f"FIX: 1) Read the failure output above. 2) Fix the failing code or test. "
        f"3) Re-run the test command to confirm all pass."
    )

emit_context(messages)
PY
