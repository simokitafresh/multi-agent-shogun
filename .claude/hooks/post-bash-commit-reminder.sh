#!/usr/bin/env bash
# post-bash-commit-reminder.sh — PostToolUse hook (Bash)
# inbox_write report_received 実行後にプロジェクトrepoのuncommitted変更を検出しWARN。
# GP-048: commit_missing事前防止。忍者が報告送信した瞬間にcommit漏れを警告。
# cmd_complete_gate.shのBLOCK(事後)を補完する事前検出層。

set -eu

payload="$(cat 2>/dev/null || true)"
if [ -z "${payload//[[:space:]]/}" ]; then
    exit 0
fi

HOOK_PAYLOAD="$payload" SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" python3 - <<'PY'
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


def extract_command(data: dict) -> str:
    tool_input = data.get("tool_input") or data.get("toolInput") or {}
    if not isinstance(tool_input, dict):
        return ""
    return tool_input.get("command", "")


def emit_context(text: str):
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": text,
        }
    }
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


data = load_payload(os.environ.get("HOOK_PAYLOAD", ""))
tool_name = data.get("tool_name") or data.get("toolName") or ""
if tool_name != "Bash":
    raise SystemExit(0)

command = extract_command(data)
if not command:
    raise SystemExit(0)

# inbox_write + report_received のみ対象
if "inbox_write" not in command or "report_received" not in command:
    raise SystemExit(0)

# 忍者名を抽出（inbox_write <to> "<msg>" <type> <from>の<from>）
# パターン: report_received <ninja_name> の部分
script_dir = os.environ.get("SCRIPT_DIR", "")
ninja_name = ""
parts = command.split()
for i, p in enumerate(parts):
    if p == "report_received" and i + 1 < len(parts):
        ninja_name = parts[i + 1].strip("'\"")
        break

if not ninja_name:
    raise SystemExit(0)

# タスクYAMLからproject取得
task_path = os.path.join(script_dir, "queue", "tasks", f"{ninja_name}.yaml")
if not os.path.exists(task_path):
    raise SystemExit(0)

try:
    with open(task_path) as f:
        task_data = yaml.safe_load(f)
    task = task_data.get("task", task_data) if isinstance(task_data, dict) else {}
    project = task.get("project", "")
except Exception:
    raise SystemExit(0)

if not project:
    raise SystemExit(0)

# projects.yamlからproject path取得
projects_path = os.path.join(script_dir, "config", "projects.yaml")
if not os.path.exists(projects_path):
    raise SystemExit(0)

try:
    with open(projects_path) as f:
        projects = yaml.safe_load(f)
    project_conf = None
    for p in projects.get("projects", []):
        if isinstance(p, dict) and p.get("id") == project:
            project_conf = p
            break
    if not project_conf:
        raise SystemExit(0)
    project_path = project_conf.get("path", "")
except Exception:
    raise SystemExit(0)

if not project_path or not os.path.isdir(project_path):
    raise SystemExit(0)

# uncommitted変更チェック
try:
    unstaged = subprocess.run(
        ["git", "diff", "--name-only"],
        capture_output=True, text=True, cwd=project_path, timeout=5
    )
    staged = subprocess.run(
        ["git", "diff", "--cached", "--name-only"],
        capture_output=True, text=True, cwd=project_path, timeout=5
    )
except Exception:
    raise SystemExit(0)

uncommitted = set()
if unstaged.returncode == 0 and unstaged.stdout.strip():
    uncommitted.update(unstaged.stdout.strip().splitlines())
if staged.returncode == 0 and staged.stdout.strip():
    uncommitted.update(staged.stdout.strip().splitlines())

# 運用ファイル除外（logs, queue等はshogun repoのため通常該当しない）
filtered = [f for f in uncommitted if not any(
    f.startswith(p) for p in ("logs/", "queue/", "node_modules/", ".next/", "__pycache__/")
) and not f.endswith((".log", ".pyc"))]

if not filtered:
    raise SystemExit(0)

msg = (
    f"\n⚠ COMMIT MISSING 警告 ⚠\n"
    f"プロジェクト {project} ({project_path}) にuncommitted変更あり:\n"
)
for f in sorted(filtered)[:10]:
    msg += f"  - {f}\n"
if len(filtered) > 10:
    msg += f"  ... +{len(filtered) - 10} files\n"
msg += (
    "\n報告を提出する前にcommitせよ:\n"
    f"  cd {project_path} && git add -A && git commit -m 'feat: <cmd_id> <summary>'\n"
    "\ncommit漏れはcmd_complete_gateでBLOCKされ家老の手動対応(WA)が発生する。"
)

emit_context(msg)
PY
