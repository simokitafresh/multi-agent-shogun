#!/usr/bin/env bash
# post-bash-commit-reminder.sh — PostToolUse hook (Bash)
# inbox_write report_received 実行後にプロジェクトrepoのuncommitted変更を検出しWARN。
# GP-048: commit_missing事前防止。忍者が報告送信した瞬間にcommit漏れを警告。
# cmd_complete_gate.shのBLOCK(事後)を補完する事前検出層。

set -eu

if [ -n "${HOOK_PAYLOAD+x}" ]; then
    payload="$HOOK_PAYLOAD"
else
    payload="$(cat 2>/dev/null || true)"
fi
[[ -z "${payload//[[:space:]]/}" ]] && exit 0

# Fast-path: skip if not Bash or no inbox_write+report_received keywords
[[ "$payload" != *'"Bash"'* ]] && exit 0
[[ "$payload" != *'inbox_write'* ]] && exit 0
[[ "$payload" != *'report_received'* ]] && exit 0

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
    owned_paths = task.get("owned_paths")
    planned_paths = task.get("planned_paths")
    target_path = task.get("target_path")
    report_path_value = task.get("report_path", "")
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

def git(*args):
    return subprocess.run(
        ["git", "-C", project_path, *args], capture_output=True,
        text=True, timeout=5
    )


def valid_scope_paths(value):
    if not isinstance(value, list) or not value:
        return []
    if not all(
        isinstance(path, str) and path.strip() and not os.path.isabs(path)
        for path in value
    ):
        return []
    return list(dict.fromkeys(path.strip() for path in value))


def resolve_task_scope():
    for value in (owned_paths, planned_paths):
        resolved = valid_scope_paths(value)
        if resolved:
            return resolved
    if isinstance(target_path, str) and target_path.strip() and not os.path.isabs(target_path):
        return [target_path.strip()]
    return []


issues = []
filtered = []
scope_paths = resolve_task_scope()
report_path = report_path_value
if report_path and not os.path.isabs(report_path):
    report_path = os.path.join(script_dir, report_path)

report = None
if report_path and os.path.isfile(report_path):
    try:
        with open(report_path) as f:
            report = yaml.safe_load(f)
    except Exception:
        report = None

if not scope_paths:
    issues = ["task_scope_missing_or_invalid"]
elif not isinstance(report, dict):
    issues = ["report_missing_or_invalid"]
else:
    status = git("status", "--porcelain", "--untracked-files=all", "--", *scope_paths)
    if status.returncode != 0:
        issues = ["scope_status_failed"]
    else:
        filtered = sorted({
            line[3:].strip() for line in status.stdout.splitlines()
            if len(line) >= 4 and line[3:].strip()
        })
        if filtered:
            issues.append("owned_paths_uncommitted")

        commit_hash = str(report.get("commit_hash") or "").strip()
        if len(commit_hash) != 40 or any(c not in "0123456789abcdefABCDEF" for c in commit_hash):
            issues.append("report_commit_hash_missing_or_invalid")
        else:
            commit = git("rev-parse", "--verify", f"{commit_hash}^{{commit}}")
            if commit.returncode != 0:
                issues.append("report_commit_not_found")
            else:
                mismatched = []
                for path in scope_paths:
                    head_blob = git("rev-parse", f"HEAD:{path}")
                    report_blob = git("rev-parse", f"{commit_hash}:{path}")
                    if (head_blob.returncode != 0 or report_blob.returncode != 0
                            or head_blob.stdout.strip() != report_blob.stdout.strip()):
                        mismatched.append(path)
                if mismatched:
                    filtered.extend(mismatched)
                    filtered = sorted(set(filtered))
                    issues.append("head_report_blob_mismatch")

if not issues:
    raise SystemExit(0)

msg = (
    f"\n⚠ COMMIT MISSING 警告 ⚠\n"
    f"プロジェクト {project} ({project_path}) の任務scope整合性に問題あり:\n"
)
for f in sorted(filtered)[:10]:
    msg += f"  - {f}\n"
if len(filtered) > 10:
    msg += f"  ... +{len(filtered) - 10} files\n"
for issue in issues:
    msg += f"  reason: {issue}\n"
msg += (
    "\n報告を提出する前に、自分の任務scope内ファイルだけをcommitせよ:\n"
    f"  cd {project_path} && git add <scope内file...> && git commit -m 'feat: <cmd_id> <summary>'\n"
    "\nscope外/他忍者担当の変更はstageせず、家老へ報告せよ。commit漏れはcmd_complete_gateでBLOCKされ家老の手動対応(WA)が発生する。"
)

emit_context(msg)
PY
