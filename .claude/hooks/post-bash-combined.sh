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
    _post_bash_self="${BASH_SOURCE[0]}"
    [[ "$_post_bash_self" != /* ]] && _post_bash_self="$PWD/$_post_bash_self"
    SCRIPT_DIR="${_post_bash_self%/.claude/hooks/post-bash-combined.sh}"
    unset _post_bash_self

    command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
    if [[ -n "$command" && "$command" == *'inbox_write'* && "$command" == *'report_received'* ]]; then
        ninja_name=""
        if [[ "$command" =~ report_received[[:space:]]+([a-z_]+) ]]; then
            ninja_name="${BASH_REMATCH[1]}"
        fi

        if [[ -n "$ninja_name" ]]; then
            task_path="$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml"
            if [[ -f "$task_path" ]]; then
                project="$(awk '
                    /^task:[[:space:]]*$/ { in_task=1; next }
                    in_task && /^[^[:space:]]/ { exit }
                    in_task && /^[[:space:]]+project:[[:space:]]*/ {
                        sub(/^[[:space:]]+project:[[:space:]]*/, "")
                        gsub(/^["'\''"]|["'\''"]$/, "")
                        print
                        exit
                    }
                ' "$task_path" 2>/dev/null || true)"

                if [[ -n "$project" ]]; then
                    projects_path="$SCRIPT_DIR/config/projects.yaml"
                    project_path="$(awk -v target="$project" '
                        /^projects:[[:space:]]*$/ { in_projects=1; next }
                        in_projects && /^[^[:space:]]/ { exit }
                        in_projects && /^[[:space:]]+-[[:space:]]id:[[:space:]]*/ {
                            current=$0
                            sub(/^[[:space:]]+-[[:space:]]id:[[:space:]]*/, "", current)
                            gsub(/^["'\''"]|["'\''"]$/, "", current)
                            next
                        }
                        in_projects && current == target && /^[[:space:]]+path:[[:space:]]*/ {
                            sub(/^[[:space:]]+path:[[:space:]]*/, "")
                            gsub(/^["'\''"]|["'\''"]$/, "")
                            print
                            exit
                        }
                    ' "$projects_path" 2>/dev/null || true)"

                    if [[ -n "$project_path" && -d "$project_path" ]]; then
                        status_output="$(git -C "$project_path" status --porcelain --untracked-files=no 2>/dev/null || true)"
                        filtered_files="$(printf '%s\n' "$status_output" | awk '
                            length($0) >= 4 {
                                path=substr($0,4)
                                if (path ~ /^logs\// || path ~ /^queue\// || path ~ /^node_modules\// || path ~ /^\.next\// || path ~ /^__pycache__\//) next
                                if (path ~ /\.(log|pyc)$/) next
                                print path
                            }
                        ' | sort -u)"

                        if [[ -n "$filtered_files" ]]; then
                            msg=$'\n'"⚠ COMMIT MISSING 警告 ⚠"$'\n'"プロジェクト ${project} (${project_path}) にuncommitted変更あり:"$'\n'
                            count=0
                            while IFS= read -r f; do
                                [[ -n "$f" ]] || continue
                                count=$((count + 1))
                                if (( count <= 10 )); then
                                    msg+="  - ${f}"$'\n'
                                fi
                            done <<< "$filtered_files"
                            if (( count > 10 )); then
                                msg+="  ... +$((count - 10)) files"$'\n'
                            fi
                            msg+=$'\n'"報告を提出する前にcommitせよ:"$'\n'"  cd ${project_path} && git add -A && git commit -m 'feat: <cmd_id> <summary>'"$'\n'$'\n'"commit漏れはcmd_complete_gateでBLOCKされ家老の手動対応(WA)が発生する。"
                            printf '%s' "$msg" | jq -Rs '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:.}}'
                        fi
                    fi
                fi
            fi
        fi
    fi
fi

exit 0
