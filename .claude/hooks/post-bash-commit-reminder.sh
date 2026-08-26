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
import pathlib
import re
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
    commit_contract = task.get("commit_contract") if isinstance(task.get("commit_contract"), dict) else {}
    owned_paths = task.get("owned_paths")
    planned_paths = task.get("planned_paths") or commit_contract.get("planned_paths")
    target_path = task.get("target_path")
    report_path_value = task.get("report_path", "")
except Exception:
    raise SystemExit(0)

if not project:
    raise SystemExit(0)

# commit_contract.repo_root is the task-owned repository SSOT.  Registry
# lookup remains the fallback for older tasks.
contract_repo_root = str(commit_contract.get("repo_root") or "").strip()
if contract_repo_root:
    project_path = os.path.realpath(contract_repo_root)
else:
    project_path = ""

# projects.yamlからproject path取得
projects_path = os.path.join(script_dir, "config", "projects.yaml")
if not project_path and not os.path.exists(projects_path):
    raise SystemExit(0)

try:
    if project_path:
        raise StopIteration
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
except StopIteration:
    pass
except Exception:
    raise SystemExit(0)

if not project_path or not os.path.isdir(project_path):
    raise SystemExit(0)

scope_root = pathlib.Path(project_path).resolve()

def git(*args):
    return subprocess.run(
        ["git", "-C", str(scope_root), *args], capture_output=True,
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

def report_owned_paths(value):
    if not isinstance(value, list):
        return []
    result = []
    for item in value:
        path = item.get("path") if isinstance(item, dict) else item
        if isinstance(path, str) and path.strip() and not os.path.isabs(path):
            result.append(path.strip())
    return list(dict.fromkeys(result))


def normalized_rel_path(value):
    """Normalize git-style relative paths without weakening component boundaries."""
    return os.path.normpath(str(value).strip()).replace(os.sep, "/")


def path_in_planned_scope(planned_path, candidate_path):
    """Return true for an exact path or a child of a planned directory only."""
    planned = normalized_rel_path(planned_path)
    candidate = normalized_rel_path(candidate_path)
    if planned == candidate:
        return True
    planned_fs_path = os.path.join(str(scope_root), planned)
    return os.path.isdir(planned_fs_path) and candidate.startswith(planned + "/")


def paths_in_planned_scope(planned_paths, candidates):
    return {
        candidate for candidate in candidates
        if any(path_in_planned_scope(planned, candidate) for planned in planned_paths)
    }

def changed_tokens(diff_text):
    tokens = set()
    for line in diff_text.splitlines():
        if not line or line.startswith(("+++", "---", "@@")) or line[0] not in "+-":
            continue
        token = "".join(line[1:].split())
        if token:
            tokens.add(token)
    return tokens


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

source_scope_error = ""
if isinstance(report, dict):
    required_raw = task.get("task_worktree_required")
    required = required_raw is True or str(required_raw).strip().lower() in {
        "1", "true", "yes", "on"
    }
    if required:
        try:
            sys.path.insert(0, os.path.join(script_dir, "scripts", "lib"))
            from review_source_context import resolve_source_root
            scope_root = resolve_source_root(task, report, pathlib.Path(project_path))
        except Exception as exc:
            source_scope_error = f"source_scope_invalid:{exc}"

if not scope_paths:
    issues = ["task_scope_missing_or_invalid"]
elif not isinstance(report, dict):
    issues = ["report_missing_or_invalid"]
elif source_scope_error:
    issues = [source_scope_error]
else:
    reported_paths = report_owned_paths(report.get("files_modified"))
    planned = set(scope_paths)
    reported = set(reported_paths)
    reported_in_scope = paths_in_planned_scope(planned, reported)
    asymmetric = sorted(reported - reported_in_scope)
    scope_paths = sorted(reported_in_scope)
    if asymmetric:
        filtered.extend(asymmetric)
        issues.append("planned_report_scope_asymmetric")
    status = (git("status", "--porcelain", "--untracked-files=all", "--", *scope_paths)
              if scope_paths else subprocess.CompletedProcess([], 0, "", ""))
    if status.returncode != 0:
        issues = ["scope_status_failed"]
    else:
        filtered = sorted({
            line[3:].strip() for line in status.stdout.splitlines()
            if len(line) >= 4 and line[3:].strip()
        })
        # cmd_karo_hotfix_no_code_commit_reminder_20260728: 独自の40hex限定判定は
        # gate_report_format.sh(report_commit_identity.py)が正式に許可している
        # commit_hash="no-code-change"(queue/logs配下のみ・no_code_change_evidence
        # tree_unchanged済・explicit_no_commit済のno-code報告)を認識できず、正規
        # no-code報告全件にCOMMIT MISSING誤警告を出していた。正本の
        # valid_commit_identity()を再利用して単一の契約に統一する。
        # 孤立hookコピー(scripts/lib同梱なし。test_scope_resolvers_contract.bats等)は
        # importできないため、旧40hex限定判定へ安全にfallbackする(Guard1と同じ方針)。
        sys.path.insert(0, os.path.join(script_dir, "scripts", "lib"))
        try:
            from report_commit_identity import NO_CODE_IDENTITY, valid_commit_identity
        except ImportError:
            NO_CODE_IDENTITY = "no-code-change"

            def valid_commit_identity(value, _report, _root):
                v = str(value or "").strip()
                return len(v) == 40 and all(c in "0123456789abcdefABCDEF" for c in v)

        commit_hash = str(report.get("commit_hash") or "").strip()
        owned_commits = []
        if not valid_commit_identity(commit_hash, report, pathlib.Path(project_path)):
            issues.append("report_commit_hash_missing_or_invalid")
        elif commit_hash == NO_CODE_IDENTITY:
            pass  # no-code identity contract済み(tree_unchanged+explicit_no_commit+operational_files_only)。commitが存在しないため以降のblob突合は対象外
        else:
            commit = git("rev-parse", "--verify", f"{commit_hash}^{{commit}}")
            if commit.returncode != 0:
                issues.append("report_commit_not_found")
            else:
                def scalar_texts(value):
                    if isinstance(value, dict):
                        for child in value.values():
                            yield from scalar_texts(child)
                    elif isinstance(value, list):
                        for child in value:
                            yield from scalar_texts(child)
                    elif value is not None:
                        yield str(value)

                owned_commits = [commit_hash]
                identity_text = "\n".join(scalar_texts(report))
                parent_cmd = str(report.get("parent_cmd") or task.get("parent_cmd") or "")
                task_id = str(report.get("task_id") or task.get("task_id") or "")
                for candidate in re.findall(r"(?<![0-9a-f])[0-9a-f]{7,40}(?![0-9a-f])", identity_text):
                    resolved = git("rev-parse", "--verify", f"{candidate}^{{commit}}")
                    sha = resolved.stdout.strip()
                    if resolved.returncode != 0 or sha in owned_commits:
                        continue
                    subject = git("show", "-s", "--format=%s", sha).stdout.strip()
                    if subject and ((parent_cmd and parent_cmd in subject) or (task_id and task_id in subject)):
                        owned_commits.append(sha)

                commit_paths = set()
                for owned_commit in owned_commits:
                    commit_paths.update(git("diff-tree", "--root", "--no-commit-id", "--name-only", "-r", owned_commit).stdout.splitlines())
                effective_reported = reported
                if not reported:
                    # Legacy/independent reports may omit files_modified.  A
                    # valid task-owned commit still proves ownership, bounded
                    # by planned_paths; planned paths absent from both remain
                    # intentionally out of scope.
                    effective_reported = paths_in_planned_scope(planned, commit_paths)
                    scope_paths = sorted(effective_reported)
                    fallback_status = git("status", "--porcelain", "--untracked-files=all", "--", *scope_paths)
                    if fallback_status.returncode != 0:
                        issues.append("scope_status_failed")
                    else:
                        filtered.extend(
                            line[3:].strip() for line in fallback_status.stdout.splitlines()
                            if len(line) >= 4 and line[3:].strip()
                        )
                planned_asymmetric = []
                for planned_path in planned:
                    reported_match = any(
                        path_in_planned_scope(planned_path, path)
                        for path in effective_reported
                    )
                    committed_match = any(
                        path_in_planned_scope(planned_path, path)
                        for path in commit_paths
                    )
                    if reported_match != committed_match:
                        planned_asymmetric.append(planned_path)
                planned_asymmetric = sorted(set(planned_asymmetric))
                if planned_asymmetric:
                    filtered.extend(planned_asymmetric)
                    issues.append("planned_report_scope_asymmetric")
                mismatched = []
                for path in scope_paths:
                    head_blob = git("rev-parse", f"HEAD:{path}")
                    report_blob = git("rev-parse", f"{commit_hash}:{path}")
                    if head_blob.returncode != 0 or report_blob.returncode != 0:
                        mismatched.append(path)
                        continue
                    if head_blob.stdout.strip() == report_blob.stdout.strip():
                        continue
                    owned_diff_text = "\n".join(git("diff", "--unified=0", f"{owned_commit}^", owned_commit, "--", path).stdout for owned_commit in owned_commits)
                    later_diff = git("diff", "--unified=0", commit_hash, "HEAD", "--", path)
                    dirty_diff = git("diff", "--unified=0", "--", path)
                    owned_tokens = changed_tokens(owned_diff_text)
                    foreign_tokens = changed_tokens(later_diff.stdout + "\n" + dirty_diff.stdout)
                    if not owned_tokens or owned_tokens & foreign_tokens:
                        mismatched.append(path)
                if mismatched:
                    filtered.extend(mismatched)
                    filtered = sorted(set(filtered))
                    issues.append("head_report_blob_mismatch")

        if filtered and "planned_report_scope_asymmetric" not in issues:
            unresolved = []
            for path in filtered:
                if not commit_hash or commit_hash == NO_CODE_IDENTITY:
                    unresolved.append(path)
                    continue
                owned_text = "\n".join(git("diff", "--unified=0", f"{owned_commit}^", owned_commit, "--", path).stdout for owned_commit in owned_commits)
                dirty = git("diff", "--unified=0", "--", path)
                if not changed_tokens(owned_text) or changed_tokens(owned_text) & changed_tokens(dirty.stdout):
                    unresolved.append(path)
            filtered = unresolved
            if unresolved:
                issues.append("owned_paths_uncommitted")

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
