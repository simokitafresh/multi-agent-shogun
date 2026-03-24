#!/usr/bin/env bash
# post-edit-instruction-hook-consistency.sh — PostToolUse hook
# 指示ファイル(CLAUDE.md, instructions/*.md)またはhookファイル(.claude/hooks/*.sh)が
# 編集された時に、hookのdenyパターンと指示内のツール参照の整合性を検証する。
#
# 根拠: WHY chain 7層分析(2026-03-24)
#   hookと指示は「行動仕様」という同一スキーマを共有する密結合コンポーネント。
#   形式の違い(bash vs markdown)が機能的結合を隠し、独立進化→矛盾を生む。
#   この抗体は層間整合性を自動検証し、矛盾を書いた瞬間に検出する。
#
# Mode: WARN (初期)
# GP-095: crash耐性 — PostToolUse hookは非ゼロ終了禁止

payload="$(cat 2>/dev/null || true)"
if [ -z "${payload//[[:space:]]/}" ]; then
    exit 0
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

HOOK_PAYLOAD="$payload" PROJECT_ROOT="$PROJECT_ROOT" python3 - <<'PY'
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


def is_instruction_file(file_path: str, root: Path) -> bool:
    """指示ファイルかどうか判定"""
    p = Path(file_path)
    try:
        rel = p.resolve().relative_to(root.resolve())
    except ValueError:
        return False
    rel_str = str(rel)
    return (
        rel_str == "CLAUDE.md"
        or rel_str.startswith("instructions/")
    )


def is_hook_file(file_path: str, root: Path) -> bool:
    """hookファイルかどうか判定"""
    p = Path(file_path)
    try:
        rel = p.resolve().relative_to(root.resolve())
    except ValueError:
        return False
    rel_str = str(rel)
    return rel_str.startswith(".claude/hooks/") and rel_str.endswith(".sh")


def extract_deny_patterns(root: Path) -> list[dict]:
    """hookファイルからdenyパターンを抽出"""
    denies = []
    hook_dir = root / ".claude" / "hooks"
    if not hook_dir.exists():
        return denies

    for hook_file in hook_dir.glob("*.sh"):
        try:
            content = hook_file.read_text(encoding="utf-8")
        except Exception:
            continue

        # queue/tasks/*.yaml deny
        if re.search(r"queue/tasks/.*deny", content, re.IGNORECASE):
            denies.append({
                "path_pattern": "queue/tasks/*.yaml",
                "blocked_tools": ["Edit", "Write"],
                "correct_method": "deploy_task.sh",
                "source": hook_file.name,
            })

        # queue/reports/*.yaml deny
        if re.search(r"queue/reports/.*deny", content, re.IGNORECASE):
            denies.append({
                "path_pattern": "queue/reports/*.yaml",
                "blocked_tools": ["Edit", "Write"],
                "correct_method": "report_field_set.sh",
                "source": hook_file.name,
            })

        # config file protections
        if re.search(r"protected.*config|PROTECTED_PATTERNS", content):
            denies.append({
                "path_pattern": "config files (pyproject.toml, eslintrc, etc.)",
                "blocked_tools": ["Edit", "Write"],
                "correct_method": "Fix the code, not the config",
                "source": hook_file.name,
            })

    return denies


def check_instructions_for_conflicts(root: Path, denies: list[dict]) -> list[str]:
    """指示ファイル内でhook denyと矛盾する記述を検出"""
    conflicts = []
    instruction_files = [root / "CLAUDE.md"]
    instructions_dir = root / "instructions"
    if instructions_dir.exists():
        instruction_files.extend(instructions_dir.glob("*.md"))

    for inst_file in instruction_files:
        if not inst_file.exists():
            continue
        try:
            lines = inst_file.read_text(encoding="utf-8").splitlines()
        except Exception:
            continue

        for line_num, line in enumerate(lines, 1):
            for deny in denies:
                # task YAML conflict check
                if "tasks" in deny["path_pattern"]:
                    # "Edit" on queue task YAML (but not "deploy_task.sh" context)
                    # Exclude: saytask, other non-queue task systems
                    if (
                        re.search(r"\bEdit\b.*\btask", line, re.IGNORECASE)
                        and "deploy_task" not in line
                        and "hookでブロック" not in line
                        and "hook" not in line.lower()
                        and "saytask" not in line.lower()
                    ):
                        conflicts.append(
                            f"{inst_file.name}:{line_num}: "
                            f"'Edit task' referenced but hook({deny['source']}) blocks Edit on {deny['path_pattern']}. "
                            f"Use {deny['correct_method']} instead."
                        )

                # report YAML conflict check
                if "reports" in deny["path_pattern"]:
                    # "Edit/Write" on report (but not "report_field_set.sh" context)
                    if re.search(
                        r"\b(Edit|Write)\b.*\breport", line, re.IGNORECASE
                    ) and "report_field_set" not in line and "hookでブロック" not in line and "hook" not in line.lower():
                        conflicts.append(
                            f"{inst_file.name}:{line_num}: "
                            f"'Edit/Write report' referenced but hook({deny['source']}) blocks on {deny['path_pattern']}. "
                            f"Use {deny['correct_method']} instead."
                        )

    return conflicts


# --- main ---
data = load_payload(os.environ.get("HOOK_PAYLOAD", ""))
tool_name = extract_tool_name(data)

if tool_name not in ("Edit", "Write"):
    raise SystemExit(0)

file_path = extract_file_path(data)
if not file_path:
    raise SystemExit(0)

root = Path(os.environ["PROJECT_ROOT"])

# 指示ファイルかhookファイルが編集された時のみ発火
if not is_instruction_file(file_path, root) and not is_hook_file(file_path, root):
    raise SystemExit(0)

# denyパターン抽出 → 指示との矛盾チェック
denies = extract_deny_patterns(root)
if not denies:
    raise SystemExit(0)

conflicts = check_instructions_for_conflicts(root, denies)
if not conflicts:
    raise SystemExit(0)

# WARN出力
msg_lines = [
    "WARNING: 指示-hook整合性チェック検出。",
    "WHY: hookのdenyパターンと指示内のツール参照が矛盾している可能性。",
    "密結合コンポーネント(hook/指示)の独立進化による矛盾。",
    "",
]
for c in conflicts:
    msg_lines.append(f"  ⚠ {c}")
msg_lines.append("")
msg_lines.append("FIX: 指示を修正してhookと整合させよ。")

emit_context("\n".join(msg_lines))
PY
exit 0
