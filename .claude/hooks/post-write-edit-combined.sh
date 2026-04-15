#!/usr/bin/env bash
# Combined Write/Edit PostToolUse guard: shellcheck + report-guard + instruction-consistency
# cmd_1661: 3 hooks → 1 script. Eliminates 2 bash startup costs (~60ms each).
# GP-095: crash耐性 — PostToolUse hookは非ゼロ終了禁止

payload="$(cat 2>/dev/null || true)"
[[ -z "${payload//[[:space:]]/}" ]] && exit 0
[[ "$payload" != *'"Write"'* && "$payload" != *'"Edit"'* ]] && exit 0

emit_context() {
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$1"
}

# Extract file_path with jq (single call for all guards)
file_path="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .file_path // .filePath // .path // empty' 2>/dev/null)" || exit 0
[[ -z "$file_path" ]] && exit 0

# === Guard 1: report-guard (WARN + YAML parse check) ===
if [[ "$file_path" =~ queue/reports/[^/]*_report_[^/]*\.yaml$ ]]; then
    emit_context "WARNING: 報告YAMLへの直接Edit/Write検出。\\nWHY: 報告YAMLはreport_field_set.sh経由で更新せよ。flock排他制御+構造保全のため。\\nFIX: bash scripts/report_field_set.sh <report_path> <dot.notation.key> <value>"
    # GP-197: YAML構文検証。parse errorなら即通知(忍者が壊れたYAMLに気づける)
    if [[ -f "$file_path" ]]; then
        parse_err="$(python3 -c "
import yaml,sys
try:
    yaml.safe_load(open(sys.argv[1]))
except yaml.YAMLError as e:
    print(str(e).replace(chr(10),' ')[:200])
    sys.exit(1)
" "$file_path" 2>/dev/null)" || \
            emit_context "ERROR: 報告YAML構文エラー。gate BLOCKされる。修正せよ: ${parse_err//\"/\\\"}"
    fi
fi

# === Guard 2: shellcheck (only for .sh/.bash files) ===
basename="${file_path##*/}"
if [[ "$basename" == *.sh || "$basename" == *.bash ]]; then
    _PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" || true
    HOOK_PAYLOAD="$payload" PROJECT_ROOT="${_PROJECT_ROOT:-/mnt/c/tools/multi-agent-shogun}" python3 - <<'PY' || true
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


root = Path(os.environ["PROJECT_ROOT"]).resolve()
sys.path.insert(0, str(root / ".claude" / "hooks"))
from hook_violation_logger import append_violation_log

data = load_payload(os.environ.get("HOOK_PAYLOAD", ""))
tool_input = data.get("tool_input") or data.get("toolInput") or {}
if not isinstance(tool_input, dict): raise SystemExit(0)

raw_path = tool_input.get("file_path") or tool_input.get("filePath") or tool_input.get("path") or ""
if not raw_path: raise SystemExit(0)

path = Path(raw_path)
if not path.is_absolute(): path = root / path
try: resolved = path.resolve()
except Exception: raise SystemExit(0)
if resolved.suffix not in {".sh", ".bash"}: raise SystemExit(0)
if root not in resolved.parents and resolved != root: raise SystemExit(0)

relative_target = str(resolved.relative_to(root))
proc = subprocess.run(["shellcheck", relative_target], cwd=str(root), text=True, capture_output=True, check=False)
if proc.returncode == 0: raise SystemExit(0)

violations = "\n".join(part for part in (proc.stdout, proc.stderr) if part.strip()).strip()
if not violations: raise SystemExit(0)

append_violation_log(root, "shellcheck", relative_target, violations)
msg = (
    f"ERROR: ShellCheck violations in {relative_target}\n"
    f"WHY: Shell script lint violations must be resolved before proceeding.\n"
    f"FIX: 1) Read the violations below. 2) Fix each violation in {relative_target}. "
    f"3) ShellCheck will re-check automatically on save. "
    f"4) For CRLF errors (SC1017), run: sed -i 's/\\r$//' {relative_target}\n"
    f"\n{violations}"
)
payload_out = {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": msg}}
print(json.dumps(payload_out, ensure_ascii=False, separators=(",", ":")))
PY
fi

# === Guard 3: instruction-hook-consistency (only for instruction/hook files) ===
if [[ "$file_path" == *'CLAUDE.md'* || "$file_path" == *'instructions/'* || "$file_path" == *'.claude/hooks/'* ]]; then
    _PROJECT_ROOT="${_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)}" || true
    HOOK_PAYLOAD="$payload" PROJECT_ROOT="${_PROJECT_ROOT:-/mnt/c/tools/multi-agent-shogun}" python3 - <<'PY' || true
import json
import os
import re
import sys
from pathlib import Path


def load_payload(raw: str) -> dict:
    try:
        data = json.loads(raw)
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def is_instruction_file(file_path: str, root: Path) -> bool:
    p = Path(file_path)
    try: rel = p.resolve().relative_to(root.resolve())
    except ValueError: return False
    rel_str = str(rel)
    return rel_str == "CLAUDE.md" or rel_str.startswith("instructions/")


def is_hook_file(file_path: str, root: Path) -> bool:
    p = Path(file_path)
    try: rel = p.resolve().relative_to(root.resolve())
    except ValueError: return False
    rel_str = str(rel)
    return rel_str.startswith(".claude/hooks/") and rel_str.endswith(".sh")


def extract_deny_patterns(root: Path):
    denies = []
    hook_dir = root / ".claude" / "hooks"
    if not hook_dir.exists(): return denies
    for hook_file in hook_dir.glob("*.sh"):
        try: content = hook_file.read_text(encoding="utf-8")
        except Exception: continue
        if re.search(r"queue/tasks/.*deny", content, re.IGNORECASE):
            denies.append({"path_pattern": "queue/tasks/*.yaml", "blocked_tools": ["Edit", "Write"], "correct_method": "deploy_task.sh", "source": hook_file.name})
        if re.search(r"queue/reports/.*deny", content, re.IGNORECASE):
            denies.append({"path_pattern": "queue/reports/*.yaml", "blocked_tools": ["Edit", "Write"], "correct_method": "report_field_set.sh", "source": hook_file.name})
        if re.search(r"protected.*config|PROTECTED_PATTERNS", content):
            denies.append({"path_pattern": "config files", "blocked_tools": ["Edit", "Write"], "correct_method": "Fix the code", "source": hook_file.name})
    return denies


root = Path(os.environ["PROJECT_ROOT"])
data = load_payload(os.environ.get("HOOK_PAYLOAD", ""))
tool_input = data.get("tool_input") or data.get("toolInput") or {}
fp = ""
if isinstance(tool_input, dict):
    for key in ("file_path", "filePath", "path"):
        v = tool_input.get(key)
        if isinstance(v, str) and v: fp = v; break
if not fp: raise SystemExit(0)
if not is_instruction_file(fp, root) and not is_hook_file(fp, root): raise SystemExit(0)
denies = extract_deny_patterns(root)
if not denies: raise SystemExit(0)
conflicts = []
instruction_files = [root / "CLAUDE.md"]
instructions_dir = root / "instructions"
if instructions_dir.exists(): instruction_files.extend(instructions_dir.glob("*.md"))
for inst_file in instruction_files:
    if not inst_file.exists(): continue
    try: lines = inst_file.read_text(encoding="utf-8").splitlines()
    except Exception: continue
    for line_num, line in enumerate(lines, 1):
        for deny in denies:
            if "tasks" in deny["path_pattern"]:
                if re.search(r"\bEdit\b.*\btask", line, re.IGNORECASE) and "deploy_task" not in line and "hook" not in line.lower() and "saytask" not in line.lower():
                    conflicts.append(f"{inst_file.name}:{line_num}: 'Edit task' vs hook({deny['source']}) blocks Edit on {deny['path_pattern']}.")
            if "reports" in deny["path_pattern"]:
                if re.search(r"\b(Edit|Write)\b.*\breport", line, re.IGNORECASE) and "report_field_set" not in line and "hook" not in line.lower():
                    conflicts.append(f"{inst_file.name}:{line_num}: 'Edit/Write report' vs hook({deny['source']}) blocks on {deny['path_pattern']}.")
if not conflicts: raise SystemExit(0)
msg_lines = ["WARNING: 指示-hook整合性チェック検出。", ""]
for c in conflicts: msg_lines.append(f"  ⚠ {c}")
msg_lines.append("\nFIX: 指示を修正してhookと整合させよ。")
payload_out = {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "\n".join(msg_lines)}}
print(json.dumps(payload_out, ensure_ascii=False, separators=(",", ":")))
PY
fi

exit 0
