#!/usr/bin/env python3
# semantic-links: [[gate迂回防止]], [[忍者報告品質プロトコル]]
import datetime as dt
import json
import math
import os
import pathlib
import re
import shlex
import statistics
import subprocess
import sys

import yaml

_PROJECT_ROOT = pathlib.Path(
    os.environ.get("PROJECT_ROOT") or pathlib.Path(__file__).resolve().parents[2]
).resolve()
sys.path.insert(0, str(_PROJECT_ROOT / "scripts" / "lib"))
from report_commit_identity import permits_no_code_identity, valid_commit_identity
from ac_contract import canonical_assigned_ids
from cross_repo_commit_contract import (
    validate_cross_repo_commit_ownership,
    validate_cross_repo_commits,
)


# Reconnaissance reports describe observations; they do not produce a code
# commit.  Keep this vocabulary in one place so every report contract uses the
# same boundary (publication, review, and this terminal gate all use it).
RECON_TASK_TYPES = frozenset(("recon", "scout", "recon2"))


def _task_type(report=None, task=None):
    """Resolve the effective task type from report/task contract data."""
    # The live task is authoritative when available; report metadata is the
    # fallback for standalone/archived report validation.
    for node in (task, report):
        if not isinstance(node, dict):
            continue
        contract = node.get("commit_contract")
        if isinstance(contract, str):
            try:
                contract = json.loads(contract)
            except (TypeError, ValueError):
                contract = None
        candidates = [
            contract.get("task_type") if isinstance(contract, dict) else None,
            node.get("task_type"),
            node.get("type"),
            node.get("scope_mode"),
        ]
        for candidate in candidates:
            value = str(candidate or "").strip().lower()
            if value:
                return value
    return ""


def _is_recon_report(report, task=None):
    return _task_type(report, task) in RECON_TASK_TYPES


def _nonempty_finding_fields(value):
    """Return the three required observation fields from a finding mapping."""
    if not isinstance(value, dict):
        return None

    def first(keys):
        for key in keys:
            item = value.get(key)
            if item not in (None, "", [], {}):
                if isinstance(item, str) and not item.strip():
                    continue
                return item
        return None

    return (
        first(("observation_target", "observed_target", "observation", "target", "subject", "観測対象")),
        first(("result", "outcome", "conclusion", "finding", "結果")),
        first(("evidence_path", "evidence", "path", "source", "根拠パス")),
    )


def _recon_finding_contract_issues(report):
    """Require structured observation, result, and evidence for recon reports."""
    value = report.get("finding")
    if value is None:
        value = report.get("findings")
    if value in (None, "", [], {}):
        return ["finding is required (observation_target, result, evidence_path)"]

    entries = value if isinstance(value, list) else [value]
    if not entries:
        return ["finding is required (observation_target, result, evidence_path)"]
    issues = []
    for index, entry in enumerate(entries):
        fields = _nonempty_finding_fields(entry)
        if fields is None:
            issues.append(f"finding[{index}] must be a mapping")
            continue
        missing = [
            name for name, item in zip(
                ("observation_target", "result", "evidence_path"), fields
            ) if item is None
        ]
        if missing:
            issues.append(
                f"finding[{index}] missing non-empty field(s): {', '.join(missing)}"
            )
    return issues


def _has_explicit_commit_scope(task):
    contract = task.get("commit_contract") if isinstance(task, dict) else None
    return any(task.get(key) for key in ("owned_paths", "planned_paths", "files_to_modify", "files_modified")) or (
        isinstance(contract, dict) and bool(contract.get("planned_paths"))
    )


def commit_owned_paths(task):
    """Return write/commit scope; target_path is legacy-only, never inspection scope."""
    if not isinstance(task, dict):
        return []

    values = []
    contract = task.get("commit_contract")
    if isinstance(contract, dict):
        values.append(contract.get("planned_paths"))
    values.extend(
        task.get(key)
        for key in ("owned_paths", "planned_paths", "files_to_modify", "files_modified")
    )

    paths = []

    def append(value):
        if isinstance(value, dict):
            value = value.get("path") or value.get("file") or value.get("name")
        if isinstance(value, (list, tuple)):
            for item in value:
                append(item)
            return
        text = str(value or "").strip()
        if text and text not in {"none", "null", "FILL_THIS"} and text not in paths:
            paths.append(text)

    for value in values:
        append(value)
    # Existing pre-migration tasks had no typed scope. Preserve their contract.
    # inspection_path is a read-only reference and does not define commit scope,
    # so target_path must still serve as fallback when no explicit paths exist.
    if not paths:
        append(task.get("target_path"))
    return paths


def _report_modified_paths(report):
    paths = []
    value = report.get("files_modified") if isinstance(report, dict) else None
    if not isinstance(value, list):
        return paths
    for item in value:
        if isinstance(item, dict):
            item = item.get("path")
        text = str(item or "").strip().rstrip("/")
        if text and text not in paths:
            paths.append(text)
    return paths


def _literal_path_within(path, scope, repo_root=None):
    """Match repository paths literally; brackets in dynamic routes are not globs.

    When repo_root is explicit, normalize relative paths beneath that root so
    report paths and absolute planned scopes share one canonical namespace.
    """
    candidate = str(path or "").strip().rstrip("/")
    boundary = str(scope or "").strip().rstrip("/")
    if not candidate or not boundary:
        return False
    root = str(repo_root or "").strip().rstrip("/")
    if root:
        root_path = pathlib.PurePosixPath(root)

        def canonical(value):
            value_path = pathlib.PurePosixPath(value)
            if ".." in value_path.parts:
                return None
            return value_path if value_path.is_absolute() else root_path / value_path

        candidate_path = canonical(candidate)
        boundary_path = canonical(boundary)
        if candidate_path is None or boundary_path is None:
            return False
        return candidate_path == boundary_path or boundary_path in candidate_path.parents
    if candidate == boundary or candidate.startswith(boundary + "/"):
        return True
    # Reverse containment: absolute scope ends with relative candidate
    if boundary.endswith("/" + candidate):
        return True
    # Reverse: absolute candidate ends with relative scope
    if candidate.endswith("/" + boundary):
        return True
    return False


def _subject_identifies_cmd(subject, cmd_id):
    """True if subject names cmd_id as a whole identifier, not a prefix substring.

    cmd_karo_impl_b46_commit_ownership_all_history_20260726 (B46): naive
    `cmd_id in subject` lets a shorter id (e.g. cmd_417) falsely match a
    longer sibling (cmd_4171) that merely starts with the same characters.
    cmd_id/task_id characters are limited to [A-Za-z0-9_], so \\b correctly
    rejects a digit-to-digit continuation (no boundary between '7' and '1' in
    'cmd_4171') while still matching a real, fully-bounded occurrence.
    """
    cmd_id = str(cmd_id or "").strip()
    if not cmd_id:
        return False
    return re.search(rf"\b{re.escape(cmd_id)}\b", str(subject or "")) is not None


def _canonical_commit_repo(repo_root):
    """Validate an explicit commit repository as an exact git toplevel."""
    text = str(repo_root or "").strip()
    if not text:
        return None, "explicit commit repository is empty"
    candidate = pathlib.Path(text).expanduser()
    if not candidate.is_absolute():
        return None, "explicit commit repository must be an absolute path"
    repo = candidate.resolve()
    try:
        probe = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--show-toplevel"],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return None, "explicit commit repository is unreadable or not a git repository"
    canonical = pathlib.Path(probe.stdout.strip()).resolve()
    if canonical != repo:
        return None, "explicit commit repository root mismatch"
    return canonical, None


def _resolve_commit_repo(report, task, root, contract=None):
    explicit_repo = contract.get("repo_root") if isinstance(contract, dict) else None
    if str(explicit_repo or "").strip():
        return _canonical_commit_repo(explicit_repo)

    project_id = str(report.get("project") or task.get("project") or "").strip()
    if not project_id or project_id == "infra":
        return pathlib.Path(root), None
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", project_id):
        return None, f"unknown or invalid project: {project_id!r}"

    project_file = pathlib.Path(root) / "projects" / f"{project_id}.yaml"
    try:
        project_data = yaml.safe_load(project_file.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        return None, f"unknown project: {project_id}"
    project = project_data.get("project")
    project_path = project.get("path") if isinstance(project, dict) else project_data.get("path")
    if not isinstance(project_path, str) or not project_path.strip():
        return None, f"project repository path is missing: {project_id}"

    repo = pathlib.Path(project_path).expanduser().resolve()
    try:
        probe = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--show-toplevel"],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return None, f"project repository is unreadable: {project_id}"
    canonical = pathlib.Path(probe.stdout.strip()).resolve()
    if canonical != repo:
        return None, f"project repository root mismatch: {project_id}"
    return canonical, None


def _resolved_commit_contract(report, task):
    """Resolve task/report contract without weakening identity or contradictions."""
    task_contract = task.get("commit_contract") if isinstance(task, dict) else None
    report_contract = report.get("commit_contract") if isinstance(report, dict) else None

    # Some deployed task YAMLs contain the structurally valid contract as a
    # JSON scalar (the field helper's legacy output) instead of a YAML mapping.
    # Decode only JSON objects so the gate preserves the same typed contract
    # instead of treating it as absent and demanding report-only snapshots.
    if isinstance(task_contract, str):
        try:
            decoded_contract = json.loads(task_contract)
        except (TypeError, ValueError):
            decoded_contract = None
        if isinstance(decoded_contract, dict):
            task_contract = decoded_contract

    if isinstance(task_contract, dict):
        if (
            isinstance(report_contract, dict)
            and report_contract.get("required") in (True, False)
            and task_contract.get("required") in (True, False)
            and report_contract.get("required") is not task_contract.get("required")
        ):
            return None, "task/report commit_contract required mismatch"
        if isinstance(report_contract, dict):
            task_repo = str(task_contract.get("repo_root") or "").strip()
            report_repo = str(report_contract.get("repo_root") or "").strip()
            if task_repo and report_repo:
                task_repo_path = pathlib.Path(task_repo).expanduser()
                report_repo_path = pathlib.Path(report_repo).expanduser()
                if not task_repo_path.is_absolute() or not report_repo_path.is_absolute():
                    return None, "task/report commit_contract repo_root mismatch"
                # WSL2 /mnt/c is case-insensitive (NTFS) but pathlib.resolve()
                # preserves case, causing DM-signal vs DM-Signal mismatches.
                # os.path.samefile compares by inode, handling case correctly.
                try:
                    if not os.path.samefile(task_repo_path, report_repo_path):
                        return None, "task/report commit_contract repo_root mismatch"
                except OSError:
                    if task_repo_path.resolve() != report_repo_path.resolve():
                        return None, "task/report commit_contract repo_root mismatch"
        return task_contract, None

    if not isinstance(report_contract, dict):
        return None, None
    snapshot = report.get("task_contract_snapshot")
    if not isinstance(snapshot, dict):
        return None, "report commit_contract task_contract_snapshot is missing"
    identity_fields = (
        ("task_id", "task_id"),
        ("parent_cmd", "parent_cmd"),
        ("ac_version_read", "ac_fingerprint"),
    )
    for report_key, snapshot_key in identity_fields:
        report_value = str(report.get(report_key) or "").strip()
        snapshot_value = str(snapshot.get(snapshot_key) or "").strip()
        if not report_value or not snapshot_value or report_value != snapshot_value:
            return None, f"report commit_contract snapshot identity mismatch: {report_key}"
    if report_contract.get("required") is False:
        task_type = str(report_contract.get("task_type") or report.get("task_type") or "").strip()
        if task_type not in RECON_TASK_TYPES:
            return None, "report commit_contract required=false is limited to no-code recon/scout"
    return report_contract, None


def _resolve_declared_cross_repo_identity(report, identity):
    """Return a declared report-only repository for a missing primary identity.

    A report can be produced in this repository while its task's project
    repository is elsewhere.  The task/report repo_root remains authoritative
    for normal commits; this narrow lane only accepts an identity explicitly
    declared in cross_repo_commits, whose changed paths are all report files.
    """
    identity = str(identity or "").strip()
    if not identity:
        return None
    validation_errors, owned = validate_cross_repo_commit_ownership(report)
    if validation_errors or not owned:
        return None
    for entry in report.get("cross_repo_commits") or []:
        if not isinstance(entry, dict) or str(entry.get("commit_hash") or "").strip() != identity:
            continue
        paths = entry.get("paths")
        if not isinstance(paths, list) or not paths:
            return None
        normalized = {
            str(path or "").replace("\\", "/").strip().lstrip("./")
            for path in paths
        }
        if not normalized or not all(path.startswith("queue/reports/") for path in normalized):
            return None
        declared_files = {
            str(item.get("path") or "").replace("\\", "/").strip().lstrip("./")
            for item in report.get("files_modified") or []
            if isinstance(item, dict)
        }
        if not declared_files or not declared_files.issubset(normalized):
            return None
        repo, repo_error = _canonical_commit_repo(entry.get("repo"))
        if repo_error:
            return None
        try:
            changed = {
                path
                for path in subprocess.run(
                    [
                        "git", "-C", str(repo), "diff-tree", "--no-commit-id", "-m", "--first-parent",
                        "--name-only", "-r", "--root", identity,
                    ],
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=5,
                ).stdout.splitlines()
                if path
            }
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
            return None
        if changed != normalized:
            return None
        return repo
    return None


def _verified_revert_identity(commit_repo, identity, contract):
    """Allow only an explicitly contracted, standard Git revert identity."""
    if not isinstance(contract, dict):
        return False
    reverted = str(contract.get("reverts_commit") or "").strip()
    if not re.fullmatch(r"[0-9a-f]{40}", reverted):
        return False
    try:
        subprocess.run(
            ["git", "-C", str(commit_repo), "cat-file", "-e", f"{reverted}^{{commit}}"],
            check=True, capture_output=True, text=True, timeout=5,
        )
        body = subprocess.run(
            ["git", "-C", str(commit_repo), "show", "-s", "--format=%b", identity],
            check=True, capture_output=True, text=True, timeout=5,
        ).stdout
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return False
    return re.search(
        rf"(?m)^This reverts commit {re.escape(reverted)}\.$", body
    ) is not None


def commit_contract_errors(report, task, root):
    if _is_recon_report(report, task):
        return []
    contract, contract_error = _resolved_commit_contract(report, task)
    if contract_error:
        return [contract_error]
    if isinstance(contract, dict) and contract.get("required") is False:
        return []
    identity = str(report.get("commit_hash") or "").strip()
    # cmd_karo_hotfix_no_code_identity_20260727: report_commit_identity.py が no-code報告の
    # 正本判定(permits_no_code_identity: tree_unchanged+before==after の40hex, explicit_no_commit,
    # operational_files_only の積)を持つのに、この関数は一度も呼んでいなかった(grep 0件を才蔵が実測)。
    # 結果 recon/scout以外のno-code報告は 40hex commit_hash を作れず構造的にFAILし、
    # review_approval.sh:132 の no-code経路と要求が相反していた(疾風/才蔵の2件でGATE deadlock)。
    # commit_hash は空文字とsentinel('no-code-change'等)の両方が実際に使われているため、
    # 40hexでないこと自体を条件にせず、no-code identityの3条件成立で許可する。
    if not re.fullmatch(r"[0-9a-f]{40}", identity) and permits_no_code_identity(report, root):
        return []
    if not re.fullmatch(r"[0-9a-f]{40}", identity):
        return ["required commit_hash is missing or invalid"]
    evidence = report.get("commit_identity_evidence")
    evidence_required = task.get("commit_identity_contract_required") is True
    if not isinstance(evidence, dict):
        evidence = {}
        if evidence_required:
            return ["commit_identity_evidence is required by opt-in contract"]
    expected_run_id = str(task.get("task_id") or report.get("task_id") or "").strip()
    errors = []
    if evidence:
        if str(evidence.get("source") or "") not in {"stdout", "terminal_ledger", "terminal_receipt"}:
            errors.append("commit identity source must be stdout/terminal_ledger/terminal_receipt")
        if str(evidence.get("run_id") or "") != expected_run_id:
            errors.append(f"commit identity run_id mismatch: expected {expected_run_id!r}")
        if str(evidence.get("commit_hash") or "") != identity:
            errors.append("commit identity evidence hash differs from report commit_hash")
    commit_repo, repo_error = _resolve_commit_repo(report, task, root, contract)
    if repo_error:
        return errors + [repo_error]
    try:
        subject = subprocess.run(["git", "-C", str(commit_repo), "show", "-s", "--format=%s", identity], check=True, capture_output=True, text=True, timeout=5).stdout.strip()
        changed = set(subprocess.run(["git", "-C", str(commit_repo), "diff-tree", "--no-commit-id", "--name-only", "-r", "-m", "--first-parent", identity], check=True, capture_output=True, text=True, timeout=5).stdout.splitlines())
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        fallback_repo = _resolve_declared_cross_repo_identity(report, identity)
        if fallback_repo is None:
            return errors + ["commit_hash does not resolve to a readable commit"]
        commit_repo = fallback_repo
        try:
            subject = subprocess.run(["git", "-C", str(commit_repo), "show", "-s", "--format=%s", identity], check=True, capture_output=True, text=True, timeout=5).stdout.strip()
            changed = set(subprocess.run(["git", "-C", str(commit_repo), "diff-tree", "--no-commit-id", "--name-only", "-r", "-m", "--first-parent", identity], check=True, capture_output=True, text=True, timeout=5).stdout.splitlines())
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
            return errors + ["commit_hash does not resolve to a readable commit"]
    subject_identifies_task = _subject_identifies_cmd(
        subject, expected_run_id
    ) or _subject_identifies_cmd(subject, report.get("parent_cmd"))
    if not subject_identifies_task and not _verified_revert_identity(
        commit_repo, identity, contract
    ):
        errors.append("commit subject does not identify task_id/parent_cmd")
    legacy_target_scope = not _has_explicit_commit_scope(task) and not task.get("inspection_path")
    allowed_targets = commit_owned_paths(task)
    if not allowed_targets:
        errors.append("commit owned/planned scope is missing")
    modified_targets = _report_modified_paths(report)
    cross_repo_errors, cross_repo_owned = validate_cross_repo_commit_ownership(report)
    if cross_repo_errors:
        cross_repo_owned = set()
    scope_violations = set()
    for modified in modified_targets:
        if allowed_targets and modified not in cross_repo_owned and not any(
            _literal_path_within(modified, allowed, commit_repo)
            for allowed in allowed_targets
        ):
            scope_violations.add(modified)
            # cmd_karo_hotfix_commit_contract_false_listing: if the path
            # doesn't exist on disk, hint that it may be a typo/stale path
            # in the report's files_modified — helps the ninja fix faster.
            full_path = commit_repo / modified
            hint = ""
            if not full_path.exists():
                hint = " (file does not exist — possible path typo in files_modified)"
            errors.append(f"files_modified path is outside planned scope: {modified}{hint}")
    # planned_paths is the permission ceiling, not a promise that every allowed
    # path changes. Commit provenance applies only to the report's actual subset.
    #
    # cmd_karo_impl_b46_commit_ownership_all_history_20260726 (B46): checking
    # only the single most-recent commit that touched a shared path let a
    # later, unrelated cmd's commit hide this task's own ownership commit
    # (実データ: gate_three_layer_health.sh — `git log -1` from 244b6eb6c
    # returned 疾風's cache_gap_telemetry commit; 影丸's own b45 commit
    # (aba450d32) was 3rd back). Walking the *entire* path history is
    # correct per 将軍裁定 but not viable at gate speed: `git log --format=%s
    # -- <path>` over the full history of a heavily-touched file
    # (scripts/deploy_task.sh, 569 commits) measured 15.6-27.8s (n=3) against
    # this gate's existing logs/defense_overhead.jsonl
    # (source=gate_report_format) baseline of median 530ms / p90 2820ms
    # (n=1378) — an unacceptable regression. A *pathspec-filtered* `git log
    # -nN -- path` is not a viable fix either: under this host's real
    # concurrent load (load average 8.5, many agents sharing the 9P-backed
    # worktree) it timed out (>8s) even at n=3, because git's pathspec
    # history-simplification computes a tree-diff per commit while walking
    # backward — expensive under I/O contention regardless of N.
    #
    # Fix: split the walk into two cheap primitives instead of one expensive
    # pathspec walk. (1) `git log --format=%H%x1f%s -nN <identity>` fetches
    # the last N commit hashes+subjects with NO pathspec (pure commit-graph
    # walk, no per-commit diff) — measured ~220ms even under the same load.
    # (2) filter that list to just the commits whose subject already
    # identifies *this* cmd (cheap, in-memory) — normally 1-3 of the N. (3)
    # only for those few self-owned commits, call `git diff-tree
    # --no-commit-id --name-only -r <hash>` (a single-commit diff, not a
    # history walk) to see which targets it actually touched. Total cost is
    # one cheap graph walk + a handful of single-commit diffs, independent of
    # how many total commits the repository or the target path has —
    # measured ~1-2.5s combined for both of B45's real targets under the
    # same heavy-load conditions where the pathspec approach timed out.
    #
    # ★見逃す事例: もし同一pathを、当該cmdのcommitより後に
    # OWNERSHIP_HISTORY_LOOKBACK 件以上の*別cmd*のcommitが割り込んだ場合、
    # 当該cmdのcommitはウィンドウ外へ押し出され再びBLOCKする(全件走査でしか
    # 救えない、本質的にはA8的な沈黙の窓が縮小しただけで消えてはいない)。
    # 2026-08-26: merge commit(親2+)は diff-tree に -m --first-parent が無いと変更ファイル0件になり
    # 所有パス検査が構造的にFAILする(履歴分岐統合 kotaro merge で実証: 0 files vs 15 files)。
    # -m --first-parent は非merge commitでは無影響。
    OWNERSHIP_HISTORY_LOOKBACK = 10
    targets = modified_targets or allowed_targets
    pending_targets = [
        t
        for t in (str(raw or "").strip().rstrip("/") for raw in targets)
        if t
        and not any(_literal_path_within(path, t) for path in changed)
        and not any(_literal_path_within(path, t) for path in cross_repo_owned)
    ]
    if pending_targets:
        try:
            log_out = subprocess.run(
                [
                    "git", "-C", str(commit_repo), "log",
                    f"-n{OWNERSHIP_HISTORY_LOOKBACK}", "--format=%H\x1f%s", identity,
                ],
                check=True, capture_output=True, text=True, timeout=5,
            ).stdout
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
            log_out = ""
        own_commits = []
        for line in log_out.splitlines():
            commit_hash, sep, subj = line.partition("\x1f")
            if not sep:
                continue
            if _subject_identifies_cmd(subj, expected_run_id) or _subject_identifies_cmd(
                subj, report.get("parent_cmd")
            ):
                own_commits.append(commit_hash)
        owned_targets = set()
        for commit_hash in own_commits:
            if len(owned_targets) == len(pending_targets):
                break
            try:
                commit_files = subprocess.run(
                    ["git", "-C", str(commit_repo), "diff-tree", "--no-commit-id", "--name-only", "-r", "-m", "--first-parent", commit_hash],
                    check=True, capture_output=True, text=True, timeout=5,
                ).stdout.splitlines()
            except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
                continue
            for t in pending_targets:
                if t not in owned_targets and any(_literal_path_within(p, t) for p in commit_files):
                    owned_targets.add(t)
        for t in pending_targets:
            if t not in owned_targets:
                scope_label = "target_path" if legacy_target_scope else "owned/planned path"
                errors.append(f"commit/task history does not contain {scope_label}: {t}")
    return errors


# gate_report_format.sh の contamination check(_CC_CHECK)と同一のread-only/
# commit禁止マーカー。忍者が"commit:"項目にread-only遵守を記述した場合、
# commit完了の申告として扱わない(両ゲートで判定基準を一致させる)。
_READONLY_COMMIT_MARKERS = (
    "read-only",
    "readonly",
    "読み取り専用",
    "commit禁止",
    "コミット禁止",
    "stage/commitを実行していない",
    "stage/commitを実行していないか",
    "stage・commit",
    "stage・commit・revert",
    "stage・commit・revert・削除",
)


def _iter_task_acceptance_criteria(task_data):
    ac = task_data.get("acceptance_criteria", [])
    if isinstance(ac, dict):
        for ac_id, ac_value in ac.items():
            yield str(ac_id), ac_value
    elif isinstance(ac, list):
        for index, ac_value in enumerate(ac, 1):
            if isinstance(ac_value, dict):
                yield str(ac_value.get("id") or f"AC{index}"), ac_value
            else:
                yield f"AC{index}", ac_value


def _count_task_ac_sections(task_data, assigned_acs):
    count = 0
    for ac_id, _ac_value in _iter_task_acceptance_criteria(task_data):
        if assigned_acs and ac_id not in assigned_acs:
            continue
        count += 1
    return count


def _count_task_binary_checks(task_data, assigned_acs):
    task_bc_count = 0
    tbc = task_data.get("binary_checks", {})
    if isinstance(tbc, dict):
        for key, value in tbc.items():
            if assigned_acs and key != "commit" and key not in assigned_acs:
                continue
            if isinstance(value, list):
                task_bc_count += len(value)

    if task_bc_count:
        return task_bc_count

    for ac_id, ac_value in _iter_task_acceptance_criteria(task_data):
        if assigned_acs and ac_id not in assigned_acs:
            continue
        if isinstance(ac_value, dict):
            checks = ac_value.get("binary_checks") or ac_value.get("checks")
            if isinstance(checks, list):
                task_bc_count += len(checks)

    return task_bc_count


_ZERO_TOLERANCE_RE = re.compile(
    r"zero[-_ ]?tolerance|(?:許容)?誤差(?:は|を|[:：= ]*)?ゼロ|誤差\s*0(?:件)?",
    re.I,
)
_STRUCTURED_CONFLICT_COUNT_KEYS = {
    "mismatch_count", "missing_count", "extra_count",
    "calculation_error_count", "calculation_failure_count", "uncomputable_count",
}


def _positive_structured_conflict_counts(value, path=""):
    """Find positive exact-key counters; intentionally ignore free-form prose."""
    found = []
    if isinstance(value, dict):
        for raw_key, child in value.items():
            key = str(raw_key).strip().lower()
            child_path = f"{path}.{raw_key}" if path else str(raw_key)
            if key in _STRUCTURED_CONFLICT_COUNT_KEYS and not isinstance(child, bool):
                try:
                    count = float(child)
                except (TypeError, ValueError):
                    count = 0.0
                if math.isfinite(count) and count > 0:
                    found.append((child_path, child))
            found.extend(_positive_structured_conflict_counts(child, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            found.extend(_positive_structured_conflict_counts(child, f"{path}[{index}]"))
    return found


def _zero_tolerance_conflict_errors(report, task, assigned_acs=None):
    zero_tolerance_acs = set()
    for ac_id, ac_value in _iter_task_acceptance_criteria(task):
        if assigned_acs and ac_id not in assigned_acs:
            continue
        if isinstance(ac_value, dict):
            ac_text = " ".join(str(ac_value.get(k, "") or "") for k in ("description", "check", "title"))
        else:
            ac_text = str(ac_value or "")
        if _ZERO_TOLERANCE_RE.search(ac_text):
            zero_tolerance_acs.add(ac_id)
    checks = report.get("binary_checks") if isinstance(report, dict) else None
    affirmed = set()
    if isinstance(checks, dict):
        for ac_id in zero_tolerance_acs:
            items = checks.get(ac_id)
            if isinstance(items, list) and any(
                isinstance(item, dict) and str(item.get("result", "")).strip().lower() == "yes"
                for item in items
            ):
                affirmed.add(ac_id)
    conflicts = _positive_structured_conflict_counts(report) if affirmed else []
    if not conflicts:
        return []
    evidence = ", ".join(f"{path}={value}" for path, value in conflicts)
    return [
        "zero-tolerance contradiction: structured conflict count is positive "
        f"({evidence}) while binary_checks {sorted(affirmed)} contain result=yes"
    ]


CAUSAL_SCOPE_RE = re.compile(
    r"hook|gate|daemon|semantic|search|memory[ _-]?db|記憶DB|deploy_task|配備フロー|report[_ -]?format|cmd_save|inbox_watcher|ninja_monitor",
    re.IGNORECASE,
)


def _flatten_for_scope(value):
    if value is None:
        return ""
    if isinstance(value, (str, int, float, bool)):
        return str(value)
    if isinstance(value, dict):
        return " ".join(f"{k} {_flatten_for_scope(v)}" for k, v in value.items())
    if isinstance(value, list):
        return " ".join(_flatten_for_scope(v) for v in value)
    return str(value)


def _report_mentions_residual_sweep(value):
    text = _flatten_for_scope(value)
    if not text:
        return False
    expansion_terms = ("横展開", "修正前パターン", "残存確認", "残存0件", "grep残存", "同一パターン残存")
    return any(term in text for term in expansion_terms)


def _report_claims_completed_residual_sweep(value):
    """Return true only for an affirmative claim that a sweep was performed."""
    text = _flatten_for_scope(value)
    if not text:
        return False
    expansion_terms = ("横展開", "修正前パターン", "残存確認", "同一パターン残存")
    completed_terms = ("実施", "完了", "対応済", "修正済", "展開済", "反映済", "確認した", "確認済")
    excluded_terms = (
        "read-only", "readonly", "読み取り専用", "調査のみ", "確認のみ",
        "提案", "提言", "推奨", "予定", "将来", "今後", "未実施", "実施していない",
        "実施せず", "横展開なし", "横展開不要", "横展開しない",
    )
    for sentence in re.split(r"[。.!！?？\n]", text):
        if not any(term in sentence for term in expansion_terms):
            continue
        if any(term in sentence.lower() for term in excluded_terms):
            continue
        if any(term in sentence for term in completed_terms):
            return True
    return False


def _report_has_existing_implementation_file(files_modified):
    """Return true when files_modified names an existing non-doc, non-test code file."""
    code_suffixes = {
        ".c", ".cc", ".cpp", ".cs", ".go", ".java", ".js", ".jsx", ".kt", ".php",
        ".py", ".rb", ".rs", ".sh", ".swift", ".ts", ".tsx",
    }
    if not isinstance(files_modified, list):
        return False
    for item in files_modified:
        raw_path = item.get("path") if isinstance(item, dict) else item
        if not isinstance(raw_path, str) or not raw_path.strip():
            continue
        relative = pathlib.PurePosixPath(raw_path.strip().replace("\\", "/"))
        lowered_parts = {part.lower() for part in relative.parts}
        if lowered_parts.intersection({"docs", "doc", "tests", "test"}):
            continue
        candidate = (_PROJECT_ROOT / pathlib.Path(*relative.parts)).resolve()
        try:
            candidate.relative_to(_PROJECT_ROOT)
        except ValueError:
            continue
        if candidate.is_file() and candidate.suffix.lower() in code_suffixes:
            return True
    return False


def _report_has_residual_sweep_evidence(value):
    text = _flatten_for_scope(value)
    if not text:
        return False
    has_search = bool(re.search(r"\b(rg|grep)\b|grep|検索", text, re.IGNORECASE))
    has_zero = bool(re.search(r"残存\s*0\s*件|0\s*件|0\s*hits?|該当\s*0\s*件|no matches?", text, re.IGNORECASE))
    return has_search and has_zero


def _task_needs_causal_verification(task_data):
    if not isinstance(task_data, dict) or not task_data:
        return False
    fields = [
        "purpose",
        "title",
        "command",
        "target_path",
        "scope",
        "context",
        "semantic_concepts",
        "task_type",
        "type",
        "scope_mode",
    ]
    haystack = " ".join(_flatten_for_scope(task_data.get(field)) for field in fields)
    return bool(CAUSAL_SCOPE_RE.search(haystack))


def _causal_verification_filled(value):
    placeholders = {"", "none", "null", "n/a", "na", "fill_this", "fILL_THIS".lower()}
    if isinstance(value, str):
        return value.strip().lower() not in placeholders
    if isinstance(value, dict):
        for key in ("cause_checked", "design_intent_checked", "evidence", "origin"):
            item = value.get(key)
            if isinstance(item, str) and item.strip().lower() not in placeholders:
                return True
        return False
    return bool(value)


_REQUIRED_VARIATION_CHECKS = (
    "normal_pass",
    "quoted_or_heredoc",
    "linked_worktree",
    "parallel_or_respawn",
    "abnormal_exit",
)


def _variation_contract_issues(task_data, report_data):
    """Return missing/invalid cells for an active required variation contract."""
    if not isinstance(task_data, dict) or not isinstance(report_data, dict):
        return [], []
    required_raw = task_data.get("variation_checks_required", False)
    required = required_raw is True or str(required_raw).strip().lower() in {"1", "true", "yes", "on"}
    if not required:
        return [], []

    checks = report_data.get("variation_checks")
    missing = []
    invalid = []
    for name in _REQUIRED_VARIATION_CHECKS:
        item = checks.get(name) if isinstance(checks, dict) else None
        if not isinstance(item, dict):
            missing.append(name)
            continue
        raw_result = item.get("result", "")
        if isinstance(raw_result, bool):
            normalized = "yes" if raw_result else "no"
        else:
            normalized = str(raw_result or "").strip().strip("\"'").lower()
        if not normalized:
            missing.append(name)
        elif normalized not in {"yes", "no"}:
            invalid.append(name)
    return missing, invalid


def _speed_ab_contract_issues(task_data, report_data):
    """Validate the evidence required by the same-run interleaved callback."""
    campaign = task_data.get("speed_campaign") if isinstance(task_data, dict) else None
    if not isinstance(campaign, dict) or campaign.get("baseline_policy") != "same_run_interleaved_ab":
        return []
    ab = report_data.get("speed_ab") if isinstance(report_data, dict) else None
    if not isinstance(ab, dict):
        return ["speed_ab is missing"]

    issues = []
    required = ("last_good_commit", "candidate_commit", "command")
    for key in required:
        if not str(ab.get(key) or "").strip():
            issues.append(f"speed_ab.{key} is missing")
    if ab.get("last_good_commit") == ab.get("candidate_commit"):
        issues.append("speed_ab commits must be distinct")
    if ab.get("order") != "alternating":
        issues.append("speed_ab.order must be alternating")
    try:
        if int(ab.get("warmup_each")) < 1:
            raise ValueError
    except (TypeError, ValueError, OverflowError):
        issues.append("speed_ab.warmup_each must be >=1")

    samples = []
    for key in ("last_good_samples_ms", "candidate_samples_ms"):
        raw = ab.get(key)
        if not isinstance(raw, list) or len(raw) < 10:
            issues.append(f"speed_ab.{key} requires >=10 samples")
            samples.append([])
            continue
        try:
            numeric = [float(value) for value in raw]
        except (TypeError, ValueError, OverflowError):
            numeric = []
        if not numeric or not all(math.isfinite(value) and value >= 0 for value in numeric):
            issues.append(f"speed_ab.{key} must contain finite nonnegative numbers")
        samples.append(numeric)
    base, candidate = samples
    if base and candidate:
        if len(base) != len(candidate):
            issues.append("speed_ab sample counts must match")
        expected_sequence = ["L" if index % 2 == 0 else "C" for index in range(len(base) * 2)]
        if ab.get("sequence") != expected_sequence:
            issues.append("speed_ab.sequence must be exact L/C alternation")

        def p95(values):
            ordered = sorted(values)
            return ordered[max(0, math.ceil(0.95 * len(ordered)) - 1)]

        computed = {
            "last_good_p50": statistics.median(base),
            "last_good_p95": p95(base),
            "candidate_p50": statistics.median(candidate),
            "candidate_p95": p95(candidate),
        }
        for key, expected in computed.items():
            try:
                actual = float(ab.get(key))
            except (TypeError, ValueError, OverflowError):
                issues.append(f"speed_ab.{key} is missing or nonnumeric")
                continue
            if not math.isfinite(actual) or not math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-6):
                issues.append(f"speed_ab.{key} does not match samples")
        expected_adopted = (
            computed["candidate_p50"] <= computed["last_good_p50"]
            and computed["candidate_p95"] <= computed["last_good_p95"]
            and (
                computed["candidate_p50"] < computed["last_good_p50"]
                or computed["candidate_p95"] < computed["last_good_p95"]
            )
        )
        if ab.get("adopted") is not expected_adopted:
            issues.append("speed_ab.adopted does not match the measured adoption contract")
    return issues


def _rfs_cmd(report_path, key, value):
    return "bash scripts/report_field_set.sh {} {} {}".format(
        shlex.quote(report_path),
        shlex.quote(key),
        shlex.quote(str(value)),
    )


def _rfs_stdin_cmd(report_path, key, yaml_text):
    return "cat <<'YAML' | bash scripts/report_field_set.sh {} {} -\n{}\nYAML".format(
        shlex.quote(report_path),
        shlex.quote(key),
        yaml_text.rstrip(),
    )


def _binary_checks_full_cmd(report_path):
    return _rfs_stdin_cmd(
        report_path,
        "binary_checks",
        'AC1:\n  - check: "確認内容を具体的に"\n    result: yes',
    )


def _investigation_contract_issues(report):
    """Validate the deployment-frozen outcome-neutral investigation contract.

    Absence is valid for legacy/non-investigation reports.  When the typed
    contract is present, zero findings and external boundaries are first-class
    successful outcomes; only incomplete method/evidence is rejected.
    """
    snapshot = report.get("task_contract_snapshot")
    contract = snapshot.get("investigation_contract") if isinstance(snapshot, dict) else None
    if not isinstance(contract, dict) or contract.get("required") is not True:
        return []

    issues = []
    if contract.get("outcome_neutral") is not True or contract.get("discovery_required") is not False:
        issues.append("task contract is not outcome-neutral")

    result = report.get("investigation_outcome")
    if not isinstance(result, dict):
        return issues + ["investigation_outcome mapping is missing"]

    allowed = contract.get("allowed_outcomes") or []
    outcome = str(result.get("outcome") or "").strip()
    if outcome not in allowed:
        issues.append("outcome must be one of: " + ", ".join(map(str, allowed)))
    if result.get("method_completed") is not True:
        issues.append("method_completed must be true")

    evidence = result.get("primary_evidence")
    minimum = contract.get("minimum_primary_evidence", 1)
    try:
        minimum = max(1, int(minimum))
    except (TypeError, ValueError):
        minimum = 1
    valid_evidence = [
        item for item in evidence or []
        if isinstance(item, dict)
        and str(item.get("source") or "").strip()
        and str(item.get("observation") or "").strip()
    ] if isinstance(evidence, list) else []
    if len(valid_evidence) < minimum:
        issues.append(f"primary_evidence requires at least {minimum} source+observation item(s)")

    unknowns = result.get("remaining_unknowns")
    if not isinstance(unknowns, list):
        issues.append("remaining_unknowns must be a list")
    elif outcome == "unknown_after_exhaustion" and not any(str(item).strip() for item in unknowns):
        issues.append("unknown_after_exhaustion requires a non-empty remaining_unknowns list")
    return issues


def ci_fix_clean_repro_evidence_errors(evidence):
    """Validate the typed ci_fix terminal checkpoint evidence once.

    The deploy path owns only the checkpoint schema.  This function is the
    shared validator used by the report terminal gate; keeping the rules here
    prevents deployment-time AC generation and report-time validation from
    drifting apart.
    """
    errors = []

    def add(message):
        errors.append("ci_fix clean repro evidence " + message)

    if not isinstance(evidence, dict):
        add("evidence mapping missing")
        return errors

    if str(evidence.get("outcome") or "").strip().lower() == "not_reproducible":
        nr = evidence.get("not_reproducible")
        if not isinstance(nr, dict):
            add("not_reproducible block missing")
            return errors
        receipts = nr.get("independent_receipts")
        if not isinstance(receipts, list) or len(receipts) < 3:
            add("not_reproducible needs >=3 independent verification receipts")
            return errors
        environments = set()
        for idx, receipt in enumerate(receipts):
            if not isinstance(receipt, dict):
                add(f"not_reproducible receipt[{idx}] must be a mapping")
                continue
            for key in ("path", "environment", "status", "started_at"):
                if not str(receipt.get(key) or "").strip():
                    add(f"not_reproducible receipt[{idx}].{key} missing")
            if str(receipt.get("status") or "").upper() != "PASS":
                add(f"not_reproducible receipt[{idx}] must be PASS (the failure did not reproduce)")
            environments.add(str(receipt.get("environment") or "").strip())
        if len(environments - {""}) < 3:
            add(f"not_reproducible needs 3 distinct environments, got {len(environments - {''})}")
        ci = nr.get("ci_green")
        if not isinstance(ci, dict):
            add("not_reproducible ci_green missing")
        else:
            for key in ("run_id", "status", "observed_at", "commit"):
                if not str(ci.get(key) or "").strip():
                    add("not_reproducible ci_green." + key + " missing")
            if str(ci.get("status") or "").upper() != "GREEN":
                add("not_reproducible ci_green.status must be GREEN")
            if not re.fullmatch(r"[0-9a-f]{40}", str(ci.get("commit") or "")):
                add("not_reproducible ci_green.commit must be a full sha")
        diagnostics = nr.get("diagnostics")
        if not isinstance(diagnostics, dict):
            add("not_reproducible diagnostics missing")
        else:
            if not str(diagnostics.get("path") or "").strip():
                add("not_reproducible diagnostics.path missing")
            emits = diagnostics.get("emits")
            if not isinstance(emits, list):
                add("not_reproducible diagnostics.emits missing")
            else:
                absent = [key for key in ("rc", "stderr", "reason_code") if key not in {str(x).strip() for x in emits}]
                if absent:
                    add("not_reproducible diagnostics must emit " + ",".join(absent))
        return errors

    if not str(evidence.get("e2_harness_command") or "").strip():
        add("harness command missing")
    pre = evidence.get("pre_fix_receipt")
    post = evidence.get("post_fix_receipt")
    if not isinstance(pre, dict) or not isinstance(post, dict):
        add("receipt mapping missing")
        return errors
    required = ("path", "status", "source_commit", "fixed_target", "started_at", "failures", "skips")
    for name, receipt in (("pre", pre), ("post", post)):
        for key in required:
            if receipt.get(key) in (None, ""):
                add(f"{name}.{key} missing")
    try:
        pre_failures, pre_skips = int(pre.get("failures")), int(pre.get("skips"))
        post_failures, post_skips = int(post.get("failures")), int(post.get("skips"))
    except (TypeError, ValueError):
        add("receipt failures/skips must be integers")
        return errors
    if str(pre.get("status") or "").upper() != "FAIL" or pre_failures < 1 or pre_skips != 0:
        add("pre receipt must be FAIL failures>=1 SKIP0")
    if str(post.get("status") or "").upper() != "PASS" or post_failures != 0 or post_skips != 0:
        add("post receipt must be PASS FAIL0 SKIP0")
    if pre.get("path") == post.get("path"):
        add("pre/post receipt paths must differ")
    if pre.get("source_commit") != post.get("source_commit") or not re.fullmatch(r"[0-9a-f]{40}", str(pre.get("source_commit") or "")):
        add("source_commit mismatch or invalid")
    if pre.get("fixed_target") != post.get("fixed_target") or not str(pre.get("fixed_target") or "").strip():
        add("fixed_target mismatch")

    def stamp(value, label):
        try:
            return dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        except (TypeError, ValueError):
            add(label + " timestamp invalid")
            return None

    push = stamp(evidence.get("push_started_at"), "push_started_at")
    for name, receipt in (("pre", pre), ("post", post)):
        started = stamp(receipt.get("started_at"), name + ".started_at")
        if started is not None and push is not None:
            if started.tzinfo is None or push.tzinfo is None:
                add("timestamps require timezone")
            elif started >= push:
                add(name + " harness must start before push")
    return errors


def _ci_fix_final_checkpoint_issues(task, report):
    """Return terminal errors for the task's typed final checkpoint."""
    if str(report.get("status") or "").strip().lower() not in {"completed", "done"}:
        return []
    checkpoint = task.get("final_checkpoint") if isinstance(task, dict) else None
    if not isinstance(checkpoint, dict):
        return []
    if checkpoint.get("required") is not True:
        return []
    if str(checkpoint.get("type") or "").strip() != "ci_fix_clean_repro":
        return ["final_checkpoint: unsupported type"]
    field = str(checkpoint.get("evidence_field") or "ci_fix_clean_repro_evidence").strip()
    return ci_fix_clean_repro_evidence_errors(report.get(field))


def main(report_data=None) -> int:
    if len(sys.argv) < 2:
        print("FAIL: report path required")
        return 1

    report_path = sys.argv[1]
    errors = []
    hints = []
    assigned_acs = set()

    if report_data is None:
        try:
            with open(report_path, encoding="utf-8") as f:
                data = yaml.safe_load(f)
        except Exception as e:
            print(f"FAIL: YAML parse error: {e}")
            return 1
    else:
        data = report_data

    if not data or not isinstance(data, dict):
        print("FAIL: report is empty or not a dict")
        return 1

    required = [
        "worker_id",
        "parent_cmd",
        "ac_version_read",
        "binary_checks",
        "files_modified",
        "lesson_candidate",
        "lessons_useful",
    ]
    missing_hints = {
        "worker_id": "FIX (worker_id): テンプレートに生成済み。上書きで消すな。report_field_set.sh経由で記入:\n  bash scripts/report_field_set.sh <report> worker_id <your_name>",
        "parent_cmd": "FIX (parent_cmd): テンプレートに生成済み。上書きで消すな。report_field_set.sh経由で記入:\n  bash scripts/report_field_set.sh <report> parent_cmd cmd_XXXX",
        "binary_checks": 'FIX (binary_checks): report_field_set.shで記入せよ:\n  ' + _binary_checks_full_cmd(report_path),
        "files_modified": "FIX (files_modified): 変更したファイルパスを記入せよ:\n  files_modified:\n    - path/to/file.py",
        "lesson_candidate": 'FIX (lesson_candidate): report_field_set.shで記入せよ:\n  lesson_candidate:\n    found: false\n    no_lesson_reason: "理由を具体的に書け"',
        "lessons_useful": "FIX (lessons_useful): テンプレートに注入済みの教訓にuseful/reasonを記入せよ。空リストで上書きするな",
        "ac_version_read": "FIX (ac_version_read): task YAMLのac_versionハッシュ値をコピーせよ",
    }
    for field in required:
        if field not in data:
            errors.append(f"{field}: MISSING")
            if field in missing_hints:
                hints.append(missing_hints[field])

    for field_name, field_hint in [
        ("worker_id", missing_hints.get("worker_id", "")),
        ("parent_cmd", missing_hints.get("parent_cmd", "")),
    ]:
        if field_name in data and not str(data.get(field_name) or "").strip():
            errors.append(f"{field_name}: MISSING (empty value)")
            if field_hint:
                hints.append(field_hint)

    fm = data.get("files_modified")
    def files_modified_has_fill_this(items) -> bool:
        if isinstance(items, str):
            return items.strip() == "FILL_THIS"
        if isinstance(items, list):
            for item in items:
                if isinstance(item, str) and item.strip() == "FILL_THIS":
                    return True
                if isinstance(item, dict) and str(item.get("path", "")).strip() == "FILL_THIS":
                    return True
        return False

    if fm is None and "files_modified" in data:
        errors.append("files_modified: null (must be string or list of file paths)")
        hints.append("FIX (files_modified): nullではなく変更ファイルパスを記入せよ:\n  files_modified:\n    - path/to/file.py")
    elif isinstance(fm, dict):
        errors.append("files_modified: is dict (must be string or list of file paths)")
        hints.append("FIX (files_modified): 文字列またはリスト形式で記入せよ:\n  files_modified: path/to/file.py\n  または\n  files_modified:\n    - path/to/file1.py\n    - path/to/file2.py")
    elif isinstance(fm, bool):
        errors.append(f"files_modified: is bool ({fm}), must be string or list of file paths")
    elif files_modified_has_fill_this(fm):
        errors.append("files_modified: FILL_THIS placeholder remaining (must fill actual file paths)")
        hints.append("FIX COMMAND (files_modified): " + _rfs_cmd(report_path, "files_modified", "scripts/gates/gate_report_format_main.py"))
    elif isinstance(fm, list) and len(fm) == 0 and data.get("status") == "completed":
        hints.append('GP-127 WARN: files_modified: [] (空リスト) — 変更ファイルを記入せよ。偵察のみの場合は文字列で "偵察のみ" と記入')

    # GP-286: files_modified path format validation (commit_missing WA根因: 説明文混入防止)
    if isinstance(fm, list) and len(fm) > 0 and data.get("status") == "completed":
        _fm_non_path_count = 0
        for item in fm:
            _p = str(item.get("path", "") if isinstance(item, dict) else item).strip()
            if _p and "/" not in _p and not _p.startswith("偵察"):
                _fm_non_path_count += 1
        if _fm_non_path_count > 0:
            errors.append(f"files_modified: {_fm_non_path_count}件がパス形式でない(/ を含まない)。説明文ではなくファイルパスを記入せよ")
            hints.append("FIX (files_modified): 各エントリは scripts/foo.sh や config/settings.yaml のようなファイルパスであること")

    # GP-288: files_modified empty path detection (cmd_3558 AC2: 空文字列path → WARN)
    if isinstance(fm, list) and data.get("status") == "completed":
        _fm_empty_path_count = sum(
            1 for item in fm
            if isinstance(item, dict) and str(item.get("path", "") or "").strip() == ""
        )
        if _fm_empty_path_count > 0:
            hints.append(
                f"GP-288 WARN: files_modified: {_fm_empty_path_count}件のpathが空文字列。"
                "ファイルパス (scripts/foo.sh 等) を記入せよ"
            )

    # GP-287: commit_hash full hash validation (commit_missing WA根因: 短縮hash→gate素通り防止)
    _ch = data.get("commit_hash")
    if _ch is not None:
        _ch_str = str(_ch).strip()
        if _ch_str and _ch_str.lower() not in ("", "none", "null"):
            if not valid_commit_identity(_ch_str, data, _PROJECT_ROOT):
                errors.append(f"commit_hash: '{_ch_str}' は40文字フルhashでない。git rev-parse HEADで取得したフルhashを記入せよ")
                hints.append("FIX COMMAND (commit_hash): " + _rfs_cmd(report_path, "commit_hash", "$(git rev-parse HEAD)"))

    # GP-285: files_modified entries with parentheses/comments (cmd_3381 incident)
    if isinstance(fm, list):
        _paren_re = re.compile(r'\(.*\)')
        for item in fm:
            _p = str(item.get("path", "") if isinstance(item, dict) else item)
            if _paren_re.search(_p):
                hints.append(f'GP-285 WARN: files_modified entry contains parentheses: "{_p}" — パスのみ記入せよ(コメント・注記混入禁止)')
                break

    parent_cmd_value = str(data.get("parent_cmd") or "")
    if parent_cmd_value and isinstance(fm, list) and len(fm) > 0:
        fm_paths = []
        for item in fm:
            if isinstance(item, dict):
                fm_paths.append(str(item.get("path", "")))
            elif isinstance(item, str):
                fm_paths.append(item)
        cmd_artifact_paths = [
            path for path in fm_paths
            if re.search(r"(?:^|[_-])cmd_[0-9A-Za-z_]+", os.path.basename(path))
        ]
        if cmd_artifact_paths and not any(
            parent_cmd_value in os.path.basename(path) for path in cmd_artifact_paths
        ):
            # 修行cmd/CI修正/karo_direct配備はcmd_idがファイル名に含まれない構造的偽陽性
            if not (parent_cmd_value.startswith("cmd_training_") or parent_cmd_value.startswith("cmd_karo_")):
                hints.append(f"GP-202 WARN: files_modified内に{parent_cmd_value}を含むファイルが0件。別cmdの成果物を上書きしていないか確認せよ")

    lc = data.get("lesson_candidate")
    if lc is None and "lesson_candidate" in data:
        errors.append("lesson_candidate: null (must be dict with found/title/detail)")
    elif lc is not None:
        if isinstance(lc, str):
            errors.append("lesson_candidate: is string (must be dict with found/title/detail)")
            hints.append('FIX (lesson_candidate): dict形式で再記入せよ:\n  ' + _rfs_stdin_cmd(report_path, "lesson_candidate", 'found: false\nno_lesson_reason: "既知パターンのため新規教訓なし"'))
        elif isinstance(lc, dict):
            if "found" not in lc:
                errors.append('lesson_candidate: missing "found" field')
            if not lc.get("found") and not lc.get("no_lesson_reason"):
                errors.append("lesson_candidate: found=false but no no_lesson_reason")
                hints.append('FIX (lesson_candidate): found: falseの場合はno_lesson_reasonが必須:\n  lesson_candidate:\n    found: false\n    no_lesson_reason: "既知のL084と同じパターンで新規教訓なし"')
            if not lc.get("found") and lc.get("no_lesson_reason"):
                reason = str(lc.get("no_lesson_reason", "")).strip()
                if len(reason) <= 3:
                    errors.append(f"lesson_candidate: no_lesson_reason too short ({len(reason)} chars, need >3)")
                    hints.append('FIX (lesson_candidate): no_lesson_reasonに具体的な理由を記入せよ。例: "既知のL084と同じパターン"')
                placeholder_values = ["なし", "特になし", "N/A", "n/a", "none", "None", "no", "No", "FILL_THIS"]
                if reason in placeholder_values:
                    errors.append(f'lesson_candidate: no_lesson_reason="{reason}" is placeholder (write a real reason)')
                    hints.append("FIX COMMAND (lesson_candidate): " + _rfs_cmd(report_path, "lesson_candidate.no_lesson_reason", "既知パターンのため新規教訓なし"))
            if lc.get("found") and not lc.get("title"):
                errors.append("lesson_candidate: found=true but no title")
            if lc.get("found") and not lc.get("detail") and not lc.get("summary"):
                errors.append("lesson_candidate: found=true but no detail or summary")
        else:
            errors.append(f"lesson_candidate: unexpected type {type(lc).__name__}")

    worker_id = data.get("worker_id", "")
    task_yaml_path = os.path.join(os.path.dirname(os.path.dirname(report_path)), "tasks", f"{worker_id}.yaml")
    task_data = {}
    try:
        if worker_id and os.path.exists(task_yaml_path):
            with open(task_yaml_path, encoding="utf-8") as task_file:
                raw = yaml.safe_load(task_file)
            task_data = (raw or {}).get("task", raw or {})
    except Exception:
        pass

    # The current task is the contract source only when it still belongs to
    # this report.  Ninja task files are reused, so applying a later task's
    # variation requirement to an older report would be a false BLOCK.
    task_matches_report = str(task_data.get("parent_cmd") or "").strip() == parent_cmd_value
    if not (task_matches_report and _is_recon_report(data, task_data)):
        for _investigation_error in _investigation_contract_issues(data):
            errors.append("investigation_contract: " + _investigation_error)
        if any(error.startswith("investigation_contract:") for error in errors):
            hints.append(
                "FIX (investigation_outcome): 発見件数ではなく探索完遂を報告せよ。"
                "outcome/method_completed/primary_evidence/remaining_unknownsを構造記入する"
            )
    if task_matches_report:
        if _is_recon_report(data, task_data):
            for _finding_error in _recon_finding_contract_issues(data):
                errors.append("finding: " + _finding_error)
            if any(error.startswith("finding:") for error in errors):
                hints.append(
                    "FIX (finding): 偵察結果をmappingで記録せよ。"
                    "観測対象・結果・根拠パスを全て空でない値にする"
                )
        else:
            for _commit_contract_error in commit_contract_errors(data, task_data, _PROJECT_ROOT):
                errors.append("commit_contract: " + _commit_contract_error)
            for _cross_repo_error in validate_cross_repo_commits(data):
                errors.append("cross_repo_commits: " + _cross_repo_error)
        variation_missing, variation_invalid = _variation_contract_issues(task_data, data)
        if variation_missing:
            errors.append(
                "variation_checks: required cells unfilled: " + ", ".join(variation_missing)
            )
        if variation_invalid:
            errors.append(
                "variation_checks: result must be yes/no: " + ", ".join(variation_invalid)
            )
        if variation_missing or variation_invalid:
            hints.append(
                "FIX (variation_checks): variation_checks_required=true。"
                "normal_pass/quoted_or_heredoc/linked_worktree/parallel_or_respawn/abnormal_exit "
                "の全resultをyes/noで記入せよ"
            )
    # final_checkpoint is deliberately outside acceptance_criteria and
    # therefore outside binary_checks. Validate its evidence exactly once,
    # and only at the terminal report boundary. The frozen deploy-generation
    # snapshot is authoritative for terminal checkpoint validation. Falling
    # back to the live task would allow a
    # reused ninja task YAML to silently remove a required checkpoint.
    _checkpoint_contract = task_data
    _snapshot = data.get("task_contract_snapshot")
    if isinstance(_snapshot, dict) and "final_checkpoint" in _snapshot:
        _checkpoint_contract = _snapshot
    _final_checkpoint_errors = _ci_fix_final_checkpoint_issues(_checkpoint_contract, data)
    for _checkpoint_error in _final_checkpoint_errors:
        errors.append("final_checkpoint: " + _checkpoint_error)

    # Multi-round speed callbacks consume a stricter measurement schema than
    # the generic operational_simulation contract.  A prose PASS row cannot
    # advance the campaign: require the exact numeric fields before a terminal
    # PASS report can reach the callback (R1/R2 both omitted them previously).
    speed_result = data.get("speed_result")
    if isinstance(speed_result, dict):
        speed_quality = str(speed_result.get("quality") or "").strip().lower()
        if speed_quality not in {"pass", "fail", "skip"}:
            errors.append(
                "speed_result.quality: must be pass/fail/skip for speed callback"
            )
        if speed_quality == "pass" and str(data.get("status") or "").strip().lower() in {"completed", "done"}:
            test_results = data.get("test_results")
            if isinstance(test_results, list):
                measurement_rows = test_results
            elif isinstance(test_results, dict):
                measurement_rows = (
                    [test_results]
                    if "wall_sec" in test_results
                    else [row for row in test_results.values() if isinstance(row, dict)]
                )
            else:
                measurement_rows = []
            valid_speed_measurement = False
            for measurement in measurement_rows:
                try:
                    status = str(measurement.get("status") or "").strip().lower()
                    wall_sec = float(measurement.get("wall_sec"))
                    failures = int(measurement.get("failures"))
                    skips = int(measurement.get("skips"))
                except (AttributeError, TypeError, ValueError, OverflowError):
                    continue
                if (
                    status == "pass"
                    and math.isfinite(wall_sec)
                    and wall_sec >= 0
                    and failures == 0
                    and skips == 0
                ):
                    valid_speed_measurement = True
                    break
            if not valid_speed_measurement:
                errors.append(
                    "speed callback schema: terminal quality=pass requires "
                    "test_results(status=pass, wall_sec=finite>=0, failures=0, skips=0)"
                )
                hints.append(
                    "FIX (speed callback schema): operational_simulation SSOTへ "
                    "status=pass, wall_sec=<seconds>, failures=0, skips=0 を "
                    "report_field_set.sh経由で記録せよ"
                )
            if task_matches_report:
                speed_ab_issues = _speed_ab_contract_issues(task_data, data)
                if speed_ab_issues:
                    errors.append("speed callback AB schema: " + "; ".join(speed_ab_issues))
                    hints.append(
                        "FIX (speed callback AB schema): speed_abへcommit/command/order/warmup/"
                        "sequence/各10samples/p50/p95/adoptedを構造化記録せよ"
                    )

    def metric_filled(metric) -> bool:
        if metric is None:
            return False
        if isinstance(metric, str):
            return bool(metric.strip())
        if isinstance(metric, dict):
            return any(str(v).strip() for v in metric.values() if v is not None)
        if isinstance(metric, list):
            return len(metric) > 0
        return True

    task_title = str(task_data.get("title") or "")
    task_type = str(task_data.get("task_type") or task_data.get("type") or task_data.get("scope_mode") or "").lower().strip()
    needs_before_after = (
        parent_cmd_value.startswith("cmd_karo_gp")
        or task_type in ("gp", "improvement")
        or task_title.startswith("GP")
        or task_title.startswith("強化")
        or task_title.startswith("改善")
        or "GP/" in task_title
    )
    if needs_before_after:
        if not metric_filled(data.get("before_metrics")):
            hints.append("GP-199 WARN: before_metrics未記入 — GP/改善cmdは実装前の計測値を記録せよ")
        if not metric_filled(data.get("after_metrics")):
            hints.append("GP-199 WARN: after_metrics未記入 — GP/改善cmdは実装後の計測値を記録せよ")
        regression = data.get("regression")
        if isinstance(regression, bool):
            regression_norm = "yes" if regression else "no"
        else:
            regression_norm = str(regression or "").strip().lower()
        if regression_norm not in ("yes", "no"):
            hints.append("GP-199 WARN: regression未記入 — GP/改善cmdは退化有無を yes/no で記録せよ")

    assigned_acs = canonical_assigned_ids(task_data)

    lu = data.get("lessons_useful")
    if lu is None and "lessons_useful" in data:
        errors.append("lessons_useful: null (must be list of dicts, not null)")
        hints.append('FIX (lessons_useful): nullではなくリスト形式で記入せよ。テンプレート注入済み教訓を上書きするな:\n  lessons_useful:\n    - id: L074\n      useful: true\n      reason: "具体的な理由"')
    elif lu is not None:
        if isinstance(lu, str):
            errors.append("lessons_useful: is string (must be list of dicts)")
        elif isinstance(lu, list):
            if len(lu) == 0:
                rel = task_data.get("related_lessons", [])
                has_related = bool(rel and isinstance(rel, list) and len(rel) > 0)
                if has_related:
                    errors.append("lessons_useful: empty list (テンプレートには教訓が注入済み。空リストで上書きするな)")
                    hints.append("FIX (lessons_useful): report_field_set.sh経由でuseful/reasonを各教訓に記入せよ")
            for i, item in enumerate(lu):
                if isinstance(item, dict):
                    if str(item.get("useful", "")).strip() == "FILL_THIS" or str(item.get("reason", "")).strip() == "FILL_THIS":
                        errors.append(f"lessons_useful[{i}]: value is FILL_THIS placeholder (must fill actual values)")
                    if "id" not in item:
                        errors.append(f'lessons_useful[{i}]: missing "id" field (must have lesson ID like L074)')
                        hints.append(f'FIX (lessons_useful[{i}]): id フィールド必須。テンプレート注入済みの教訓IDを確認せよ:\n  - id: L074\n    useful: true\n    reason: "理由"')
                    elif isinstance(item["id"], str) and not re.match(r'^L[SKG]?-?A?\d+(\(\d+\))?$', item["id"]):
                        # 実在する教訓ID体系(L074/LS086/LK-A10/LG017/LS-A04(46)/LS110)を全て許容する。
                        # 旧 ^L\d+$ はLS/LK/LG系・ハイフン・括弧付きを弾く厳格すぎるregexだった
                        # (殿裁定2026-07-23 gate品質バグ即時修正)。
                        errors.append(f'lessons_useful[{i}]: id="{item["id"]}" is invalid (must be a lesson ID like L074/LS086/LK-A10/LG017)')
                        hints.append(f'FIX (lessons_useful[{i}]): idは教訓ID形式(L+数字, LS/LK/LG系, ハイフン・括弧可)。テンプレート注入済みの教訓IDを確認せよ')
                    if "useful" not in item:
                        errors.append(f'lessons_useful[{i}]: missing "useful" field')
                        hints.append(f"FIX (lessons_useful[{i}]): useful: true or false を記入せよ")
                    elif not isinstance(item["useful"], bool):
                        errors.append(f"lessons_useful[{i}]: useful={item['useful']} is {type(item['useful']).__name__} (must be true or false)")
                        hints.append(f"FIX (lessons_useful[{i}]): useful: true または useful: false を指定せよ（文字列やnullは不可）")
                    if "reason" not in item:
                        errors.append(f'lessons_useful[{i}]: missing "reason" field')
                        hints.append(f"FIX (lessons_useful[{i}]): reason フィールド必須。教訓が有用/無用な理由を具体的に記入せよ")
                    elif isinstance(item.get("reason"), str) and not item["reason"].strip():
                        errors.append(f"lessons_useful[{i}]: reason is empty (教訓が有用/無用な理由を具体的に書け)")
                        hints.append(f'FIX (lessons_useful[{i}]): reason: "L246のreturn 1罠と一致し、set -e呼出元確認の指針として有用" / "今回の変更では未使用。対象箇所と無関係" など具体的に記述')
                else:
                    errors.append(f"lessons_useful[{i}]: is {type(item).__name__} (must be dict)")
        elif isinstance(lu, dict):
            errors.append('lessons_useful: is dict (must be list). Use "- id: L001" not "0: {id: L001}". Numbered keys are not YAML lists')
            hints.append("FIX (lessons_useful): numbered dict を YAML list へ変換して再記入せよ。report_field_set.sh でテンプレート注入済みの list 形式を維持すること")
        else:
            errors.append(f"lessons_useful: unexpected type {type(lu).__name__} (must be list of dicts)")

    mr = data.get("memory_references")
    if mr is not None:
        if isinstance(mr, list):
            for i, item in enumerate(mr):
                if not isinstance(item, dict):
                    errors.append(f"memory_references[{i}]: is {type(item).__name__} (must be dict)")
                    continue
                for key in ("id", "source", "query", "used", "useful", "reason"):
                    if key not in item:
                        errors.append(f'memory_references[{i}]: missing "{key}" field')
                for key in ("id", "source", "query"):
                    value = str(item.get(key, "") or "").strip()
                    if not value:
                        errors.append(f"memory_references[{i}].{key}: empty")
                    elif value == "FILL_THIS":
                        errors.append(f"memory_references[{i}].{key}: FILL_THIS placeholder remaining")
                for key in ("used", "useful"):
                    if key in item and not isinstance(item.get(key), bool):
                        errors.append(f"memory_references[{i}].{key}: is {type(item.get(key)).__name__} (must be true or false)")
                reason = str(item.get("reason", "") or "").strip()
                if reason == "FILL_THIS":
                    errors.append(f"memory_references[{i}].reason: FILL_THIS placeholder remaining")
                if item.get("used") is True and not reason:
                    errors.append(f"memory_references[{i}].reason: empty (参照した理由を具体的に書け)")
        else:
            errors.append(f"memory_references: is {type(mr).__name__} (must be list of dicts)")

    bc = data.get("binary_checks")
    if bc is None and "binary_checks" in data:
        errors.append("binary_checks: null (must be dict with AC entries)")
        hints.append('FIX (binary_checks): nullではなくdict形式で記入せよ:\n  binary_checks:\n    AC1:\n      - check: "確認内容"\n        result: "yes"')
    elif isinstance(bc, str):
        errors.append("binary_checks: is string (must be dict with AC entries)")
        hints.append('FIX (binary_checks): dict形式で再記入せよ:\n  ' + _binary_checks_full_cmd(report_path))
    elif isinstance(bc, dict) and not bc:
        errors.append("binary_checks: empty dict (must have at least one AC entry)")
        hints.append('FIX (binary_checks): AC完了ごとに二値チェックを記入せよ:\n  ' + _binary_checks_full_cmd(report_path))
    elif isinstance(bc, dict):
        verdict_words = {"PASS", "FAIL", "OK", "NG", "yes", "no", "YES", "NO", "true", "false", "True", "False", "pass", "fail", "ok", "ng"}
        for ac_key, ac_val in bc.items():
            if not isinstance(ac_val, list):
                errors.append(f"binary_checks.{ac_key}: is {type(ac_val).__name__} (must be list of check items)")
                hints.append(f'FIX (binary_checks.{ac_key}): list形式で記入せよ:\n  ' + _rfs_stdin_cmd(report_path, f"binary_checks.{ac_key}", '- check: "確認内容を具体的に"\n  result: yes'))
            else:
                for j, check_item in enumerate(ac_val):
                    if isinstance(check_item, list):
                        errors.append(f"binary_checks.{ac_key}[{j}]: nested list detected (- - check: pattern). autofix対象")
                        hints.append(f'FIX (binary_checks.{ac_key}[{j}]): "- - check:" を "- check:" に修正せよ(余分な"-"を削除)')
                        continue
                    if not isinstance(check_item, dict):
                        continue
                    if "check" not in check_item:
                        errors.append(f'binary_checks.{ac_key}[{j}]: missing "check" field')
                    if "result" not in check_item:
                        errors.append(f'binary_checks.{ac_key}[{j}]: missing "result" field')
                    ck = check_item.get("check", "")
                    rs = check_item.get("result", "")
                    if isinstance(ck, str) and ck.strip() in verdict_words:
                        errors.append(f'binary_checks.{ac_key}[{j}].check: "{ck}" は確認項目ではない。PASS/FAILではなく「何を確認したか」を書け')
                        hints.append(f'FIX (binary_checks.{ac_key}[{j}]): check に確認内容を書け。result に yes/no を書け。\n  例: {{check: "_pane_offset変数が除去されたか", result: "yes"}}')
                    elif isinstance(ck, str) and 0 < len(ck.strip()) < 5:
                        errors.append(f'binary_checks.{ac_key}[{j}].check: "{ck}" が短すぎる(確認内容を具体的に書け)')
                    elif isinstance(ck, str) and ("<<REPLACE" in ck or "FILL:" in ck):
                        errors.append(f"binary_checks.{ac_key}[{j}].check: プレースホルダ残存。具体的な確認内容に書き換えよ")
                    if isinstance(rs, str) and not rs.strip():
                        errors.append(f'binary_checks.{ac_key}[{j}].result: 空文字。"yes" または "no" を記入せよ')
                        hints.append(f'FIX (binary_checks.{ac_key}[{j}].result): 確認結果を "yes" or "no" で記入せよ\n  ★引用符なし: result: yes（result: \'yes\' はNG。YAMLでは引用符付き文字列になる）')
                        hints.append("FIX COMMAND (binary_checks result): " + _rfs_cmd(report_path, f"binary_checks.{ac_key}.{j}.result", "yes"))
                    elif isinstance(rs, str) and rs.strip().lower() not in ("yes", "no"):
                        errors.append(f'binary_checks.{ac_key}[{j}].result: "{rs[:40]}" は不正。"yes" または "no" のみ')
                        hints.append(f'FIX (binary_checks.{ac_key}[{j}].result): "yes" or "no" のみ。自由記述は acceptance_criteria.detail に書け\n  ★引用符なし: result: yes（result: \'yes\' はNG。YAMLでは引用符付き文字列になる）')
                        hints.append("FIX COMMAND (binary_checks result): " + _rfs_cmd(report_path, f"binary_checks.{ac_key}.{j}.result", "yes"))
    elif isinstance(bc, list) and not bc:
        errors.append("binary_checks: empty list (must have at least one entry)")

    # Fail closed when a zero-tolerance AC is affirmed despite an explicitly
    # structured positive mismatch/calculation-failure counter.  Exact mapping
    # keys only: free-form report prose is deliberately outside this detector.
    errors.extend(_zero_tolerance_conflict_errors(data, task_data, assigned_acs))

    if isinstance(bc, dict) and bc:
        rpt_bc_count = 0
        for key, value in bc.items():
            if assigned_acs and key != "commit" and key not in assigned_acs:
                continue
            if isinstance(value, list):
                rpt_bc_count += len(value)
        task_bc_count = _count_task_binary_checks(task_data, assigned_acs)
        if task_bc_count > 0:
            if rpt_bc_count < task_bc_count * 0.5:
                errors.append(f"binary_checks: item count {rpt_bc_count}/{task_bc_count} (<50% of task template)")
                hints.append(f"FIX (binary_checks): task YAMLに{task_bc_count}件の確認項目がある。全項目にresultを記入せよ")
            elif rpt_bc_count < task_bc_count:
                hints.append(f"GP-131 WARN: binary_checks item count {rpt_bc_count}/{task_bc_count} (task templateより少ない)")
        else:
            ac_count = _count_task_ac_sections(task_data, assigned_acs)
            if ac_count > 0:
                rpt_ac_keys = [k for k in bc.keys() if k.upper().startswith("AC")]
                # Fallback: description配下にAC1/AC2等のcheckが格納されている場合もカウント
                if not rpt_ac_keys and "description" in bc and isinstance(bc["description"], list):
                    ac_in_desc = set()
                    for item in bc["description"]:
                        if isinstance(item, dict):
                            chk = item.get("check", "")
                            m = re.match(r"(AC\d+)", str(chk))
                            if m:
                                ac_in_desc.add(m.group(1))
                    rpt_ac_keys = list(ac_in_desc)
                if assigned_acs:
                    rpt_ac_keys = [k for k in rpt_ac_keys if k in assigned_acs]
                if len(rpt_ac_keys) == 0:
                    errors.append(f"binary_checks: AC self-verification missing (0/{ac_count} ACs). 全ACの二値チェックを記入せよ")
                    hints.append(f"FIX (binary_checks): task YAMLに{ac_count}件のACがある。AC1, AC2, ... のセクションを追加し各result=yes/noを記入\n  " + _binary_checks_full_cmd(report_path))
                elif len(rpt_ac_keys) < ac_count:
                    hints.append(f"GP-131b WARN: binary_checks has {len(rpt_ac_keys)} AC sections but task has {ac_count} ACs")

    if "purpose_validation" not in data:
        errors.append("purpose_validation: MISSING")
        hints.append('FIX (purpose_validation): cmdの目的との適合を記入せよ:\n  purpose_validation:\n    cmd_purpose: "cmdの目的"\n    fit: true\n    purpose_gap: ""')
    elif data.get("purpose_validation") is None:
        errors.append("purpose_validation: null (must be dict with fit/reason)")

    status_val = data.get("status", "")
    if isinstance(status_val, str) and status_val.strip().lower() == "pending":
        errors.append('status: "pending" はテンプレート初期値。完了後に "completed" に更新せよ')
        hints.append("FIX (status): bash scripts/report_field_set.sh <report> status completed")

    if isinstance(status_val, str) and status_val.strip().lower() in ("completed", "revision_requested"):
        timestamp_val = data.get("timestamp")
        timestamp_text = str(timestamp_val).strip() if timestamp_val is not None else ""
        try:
            dt.datetime.fromisoformat(timestamp_text.replace("Z", "+00:00"))
        except (TypeError, ValueError):
            errors.append("timestamp: completed/revision_requested report requires a parseable ISO timestamp")
            hints.append("FIX (timestamp): bash scripts/report_field_set.sh <report> timestamp \"$(date -Iseconds)\"")

    result = data.get("result", {})
    if isinstance(result, dict):
        summary = result.get("summary")
        if not summary:
            errors.append("result.summary: MISSING or empty")
            hints.append("FIX COMMAND (result.summary): " + _rfs_cmd(report_path, "result.summary", "実施内容と検証結果を1行で要約"))
        elif isinstance(summary, str) and summary.strip() == "FILL_THIS":
            errors.append("result.summary: FILL_THIS placeholder remaining (must fill actual summary)")
            hints.append("FIX COMMAND (result.summary): " + _rfs_cmd(report_path, "result.summary", "実施内容と検証結果を1行で要約"))
    else:
        errors.append("result: not a dict")

    verdict = data.get("verdict")
    _VALID_VERDICTS = ("PASS", "FAIL", "PASS_NO_IMPROVEMENT")
    if not isinstance(verdict, str) or verdict not in _VALID_VERDICTS:
        errors.append(f'verdict: "{verdict}" is not valid (must be "PASS", "FAIL", or "PASS_NO_IMPROVEMENT")')
        hints.append("verdictはPASS/FAIL/PASS_NO_IMPROVEMENTの三値のみ。binary_checks全yes→PASS、1つでもno→FAIL、revert多数→PASS_NO_IMPROVEMENT")
        hints.append("FIX COMMAND (verdict): " + _rfs_cmd(report_path, "verdict", "PASS"))

    # ── LG055: executable reports require operational_simulation ──
    # 全report templateへLevel5注入し、docs/data-onlyだけを免除する。
    _fm = data.get("files_modified") or []
    _paths = [str(f.get("path") or "") for f in _fm if isinstance(f, dict)] if isinstance(_fm, list) else []
    _docs_data_prefixes = ("docs/", "context/", "logs/", "queue/", "projects/")
    _no_code_recon = _is_recon_report(data, task_data) and not _paths
    _docs_data_only = _no_code_recon or (bool(_paths) and all(path.startswith(_docs_data_prefixes) for path in _paths))
    if not _docs_data_only:
        _opsim = data.get("operational_simulation")
        _opsim_required = ("command", "expected", "actual", "result")
        _opsim_missing = (
            list(_opsim_required)
            if not isinstance(_opsim, dict)
            else [key for key in _opsim_required if not str(_opsim.get(key) or "").strip()]
        )
        if _opsim_missing:
            errors.append(
                "operational_simulation: MISSING "
                f"({','.join(_opsim_missing)}; integration cmd requires "
                "command/expected/actual/result — LG055)"
            )
        elif str(_opsim.get("result") or "").strip() not in ("PASS", "FAIL"):
            errors.append("operational_simulation.result: must be PASS or FAIL")
            hints.append("FIX (operational_simulation.result): " + _rfs_cmd(report_path, "operational_simulation.result", "PASS"))
            hints.append(
                "FIX (operational_simulation): "
                + _rfs_cmd(
                    report_path,
                    "operational_simulation.command",
                    "bats tests/unit/test_xxx.bats",
                )
            )

    # LG051 Level4: gate/hook/dispatcher の変更は、専用テストが通るだけでは
    # dead code の耐久化を防げない。レビューへ進む前に、定義・test/fixtureを
    # 除外した実運用 caller 数の一次計測を報告へ強制する。
    _fm_paths = []
    for _entry in _fm if isinstance(_fm, list) else [_fm]:
        _path = _entry.get("path", "") if isinstance(_entry, dict) else str(_entry)
        if _path:
            _fm_paths.append(_path)
    # cmd_karo_impl_lg051_scope_basename_20260725 (B16):
    # 旧判定 r"(?:^|/)(?:hooks?|gates?|dispatchers?)(?:/|[^/]*$)" はbasenameの
    # 「先頭」一致しか拾えず、cmd_complete_gate.sh のように語が中間・末尾にある
    # 実運用gateを取りこぼしていた(実測: 真対象124件中12件=9.7%が対象外)。
    # 是正: (1)hooks/gates/dispatchers ディレクトリ節、または
    #       (2)basename内で区切り([_.-]/境界)に挟まれたトークン一致。
    # トークン境界必須にしているため delegate/mitigate/aggregate/propagate/navigate
    # のような「gate」を部分文字列として含むだけの語は拾わない(偽陽性を増やさない)。
    # test/fixtureは対象外: 本検査が求めるのは「定義・test/fixtureを除外した実運用
    # caller数」であり、test自身はgate/hook/dispatcherの実運用コードではない。
    # (トークン境界化でtests/test_gate_report_format.batsのようなtestまで巻き込み
    #  T-GP286-2がCI REDになった。母集団定義に元からtestは含まれていない)
    # 判定は「置き場所」で行う。basenameのtest_接頭辞で除外すると
    # scripts/hooks/test_hooks.sh / test_result_guard.sh のような
    # 名前がtest_で始まる本番hookまで対象外にしてしまう(実測FN=2)。
    _test_path_re = re.compile(
        r"(?:^|/)tests?/|\.bats$|(?:^|/)fixtures?/"
        # cmd_karo_hotfix_lg051_skill_fp: skills/gate-sync/SKILL.md のように
        # スキル名に gate/hook を含むだけのドキュメントを偽陽性対象から除外。
        # SKILL.md はコードではなく説明文書であり caller 数は無意味。
        r"|(?:^|/)skills/[^/]+/SKILL\.md$"
        # cmd_4248偽陽性根治: docs/research/cmd_4248_shogun_gate_triage_*.md のように
        # 成果物・ドキュメント・報告のファイル名にgate/hookを含むだけで発火する偽陽性を排除。
        # LG051の対象はコード変更(scripts/hooks/gates/)であり、ドキュメントは対象外。
        r"|(?:^|/)(?:docs|context|queue|logs|memory|archive|projects|instructions)/",
        re.I,
    )
    _caller_scope = any(
        not _test_path_re.search(_path)
        and re.search(
            r"(?:^|/)(?:hooks?|gates?|dispatchers?)/"
            r"|(?:^|/|[_.-])(?:hooks?|gates?|dispatchers?|dispatch)(?:[_.-]|$)",
            _path,
            re.I,
        )
        for _path in _fm_paths
    )
    if _caller_scope:
        _cv = data.get("causal_verification") or {}
        _caller_evidence_parts = []
        if isinstance(_cv, dict):
            _caller_evidence_parts.extend(
                str(_cv.get(_key, "") or "")
                for _key in ("cause_checked", "design_intent_checked", "evidence")
            )
        # result.detailsも探索対象に含める(コード純減: 全出力転記のevidence限定を緩和)
        _result = data.get("result") or {}
        if isinstance(_result, dict):
            _caller_evidence_parts.append(str(_result.get("details", "") or ""))
        _caller_evidence = " ".join(_caller_evidence_parts)
        if not re.search(
            r"(?:non[-_ ]?test|非test|実運用)\s*caller(?:\s*(?:数|count)|s|_count)?\s*[:=]\s*\d+",
            _caller_evidence,
            re.I,
        ):
            errors.append(
                "LG051: gate/hook/dispatcher変更には非test caller数の一次証跡が必須"
            )
            hints.append(
                "FIX (LG051): causal_verification.evidenceへ、定義行とtest/fixtureを除外した"
                "rgコマンドと `non-test caller count: N` を記録せよ。N=0なら強化せず削除または正本経路へ統合せよ"
            )

    # revision_requested is an editing/unlock state, not a terminal report
    # state.  A successful terminal verdict must only be accepted after the
    # explicit revision round-trip has returned the report to completed.
    status_norm = status_val.strip().lower() if isinstance(status_val, str) else ""
    if verdict in ("PASS", "PASS_NO_IMPROVEMENT") and status_norm != "completed":
        errors.append(
            f'status: "{status_val}" cannot carry terminal verdict {verdict} '
            '(set status to completed after revisions)'
        )
        hints.append("FIX (status): bash scripts/report_field_set.sh <report> status completed")

    if isinstance(verdict, str) and verdict in _VALID_VERDICTS and isinstance(bc, dict) and bc:
        bc_has_no = False
        bc_has_empty = False
        bc_results_found = False
        for ac_key, ac_val in bc.items():
            if assigned_acs and ac_key != "commit" and ac_key not in assigned_acs:
                continue
            if isinstance(ac_val, list):
                for item in ac_val:
                    if isinstance(item, dict):
                        result_value = item.get("result")
                        if result_value is None or (isinstance(result_value, str) and not result_value.strip()):
                            bc_has_empty = True
                        if "result" in item:
                            bc_results_found = True
                            result_norm = str(item["result"]).strip().lower()
                            if result_norm in ("no", "false", "fail", "ng"):
                                waive = item.get("waive_reason", "")
                                if not (isinstance(waive, str) and waive.strip()):
                                    bc_has_no = True
        if verdict == "PASS" and bc_has_empty:
            errors.append('verdict: PASS but binary_checks contain empty result(s) (全result記入後にverdictを設定せよ)')
            hints.append('FIX (verdict-BC矛盾): verdict=PASSの前にbinary_checksの全result欄を"yes"/"no"で埋めよ')
        if bc_results_found:
            if verdict == "PASS" and bc_has_no:
                errors.append('verdict: PASS but binary_checks contain "no" results (verdict must be FAIL when any check fails)')
                hints.append('FIX (verdict): binary_checksにno/fail/ngがある場合はverdict: FAILにせよ')
            elif verdict == "FAIL" and not bc_has_no:
                hints.append('GP-128 WARN: verdict=FAIL but all binary_checks are "yes" — 外部制約によるFAILか確認せよ')

    # ─── binary_checks 客観裏付けチェック(a)(b)(c)(d) [cmd_2124, cmd_karo_hotfix_report_commit_contract_202607131320] ───
    # (a)(b)(c)はWARNのみ（段階的導入）。(d)はcommit_hash欠落をBLOCK（review_approval後段BLOCKの前段検出）
    if isinstance(bc, dict) and bc:
        _pc_for_check = str(data.get("parent_cmd", "") or "").strip()

        # (a) files_modifiedが空なのにbinary_checks全yes → WARN
        try:
            _fm = data.get("files_modified")
            _fm_empty = (
                _fm is None
                or (isinstance(_fm, list) and len(_fm) == 0)
                or (isinstance(_fm, str) and _fm.strip() in ("", "null", "[]"))
            )
            if _fm_empty:
                _bc_all_yes = True
                _bc_has_entries = False
                for _ac_items_a in bc.values():
                    if isinstance(_ac_items_a, list):
                        for _item_a in _ac_items_a:
                            if isinstance(_item_a, dict) and "result" in _item_a:
                                _bc_has_entries = True
                                if str(_item_a.get("result", "")).strip().lower() != "yes":
                                    _bc_all_yes = False
                if _bc_has_entries and _bc_all_yes:
                    hints.append(
                        "GP-201a WARN: files_modifiedが空なのにbinary_checks全yes — "
                        "変更ファイルを確認せよ。未コミット or files_modified未記入の可能性"
                    )
        except Exception:
            pass

        # (b) commit+pushのACがyesなのにgit logにcmd_idを含むcommitがない → WARN
        try:
            _commit_ac_yes = False
            for _ac_items_b in bc.values():
                if isinstance(_ac_items_b, list):
                    for _item_b in _ac_items_b:
                        if isinstance(_item_b, dict):
                            _chk_b = str(_item_b.get("check", "")).lower()
                            _rs_b = str(_item_b.get("result", "")).strip().lower()
                            if _rs_b == "yes" and any(kw in _chk_b for kw in ("commit", "push")):
                                _commit_ac_yes = True
            _commit_hash_present = bool(str(data.get("commit_hash", "") or "").strip())
            if _commit_ac_yes and _pc_for_check and not _commit_hash_present:
                _git_cwd = os.path.dirname(os.path.abspath(report_path))
                _log_res = subprocess.run(
                    ["git", "log", "--oneline", "-5"],
                    capture_output=True, text=True, timeout=5, cwd=_git_cwd,
                )
                if _log_res.returncode == 0 and _pc_for_check not in _log_res.stdout:
                    hints.append(
                        f"GP-201b WARN: commit+push ACがyesだが直近5コミットに{_pc_for_check}が見つからない — "
                        "pushが完了しているか確認せよ"
                    )
        except Exception:
            pass

        # (d) commit完了を申告(binary_checks.commit=yes)した報告のcommit_hash欠落を
        # review_approval到達前にBLOCK。scripts/lib/review_approval.sh
        # review_report_fingerprint()のno-code(scout/recon)契約は「commit未申告」
        # (not commit_claimed)が前提なので、commit_claimed=yesの時点でその契約上も
        # 常にfail-closed — ここでは前段の(b)と異なりparent_cmdの直近git log一致を
        # 問わない(karo_direct hotfixのようにparent cmd sourceが無いfixtureでも
        # 欠落を検出するため)。commit未申告(偵察等)の報告は対象外のまま真陰性を維持。
        # 実運用でPASS→review_approval.shの後段BLOCKが繰り返し発生した(段階的導入卒業)。
        try:
            _commit_claimed_d = False
            _commit_items_d = bc.get("commit", [])
            if isinstance(_commit_items_d, list):
                for _item_d in _commit_items_d:
                    if isinstance(_item_d, dict):
                        _chk_d = str(_item_d.get("check", "") or "")
                        if any(_marker in _chk_d for _marker in _READONLY_COMMIT_MARKERS):
                            continue
                        _rs_d = _item_d.get("result")
                        if _rs_d is True or str(_rs_d).strip().lower() == "yes":
                            _commit_claimed_d = True
                            break

            if _commit_claimed_d and data.get("status") == "completed":
                _commit_identity_d = ""
                for _ch_key_d in ("commit_hash", "commit", "git_commit"):
                    _ch_val_d = data.get(_ch_key_d)
                    if isinstance(_ch_val_d, str) and _ch_val_d.strip():
                        _commit_identity_d = _ch_val_d.strip()
                        break
                if not _commit_identity_d:
                    _result_field_d = data.get("result")
                    if isinstance(_result_field_d, dict):
                        _rch_d = _result_field_d.get("commit_hash")
                        if isinstance(_rch_d, str) and _rch_d.strip():
                            _commit_identity_d = _rch_d.strip()
                _has_valid_identity_d = valid_commit_identity(_commit_identity_d, data, _PROJECT_ROOT)

                if not _has_valid_identity_d:
                    errors.append(
                        "commit_hash: 欠落または40文字フルhashでない(binary_checks.commitがyes) — "
                        "review_approvalの後段BLOCK(review_report_fingerprint契約)をここで前段検出。"
                        "git rev-parse HEADの40文字フルhashを記入せよ"
                    )
                    hints.append(
                        "FIX COMMAND (commit_hash): "
                        + _rfs_cmd(report_path, "commit_hash", "$(git rev-parse HEAD)")
                    )
        except Exception:
            pass

        # (c) テスト全PASSのACがyesなのにtest_resultsが空 → WARN
        try:
            _test_ac_yes = False
            for _ac_items_c in bc.values():
                if isinstance(_ac_items_c, list):
                    for _item_c in _ac_items_c:
                        if isinstance(_item_c, dict):
                            _chk_c = str(_item_c.get("check", "")).lower()
                            _rs_c = str(_item_c.get("result", "")).strip().lower()
                            if _rs_c == "yes" and any(kw in _chk_c for kw in ("test", "テスト", "bats", "pass")):
                                _test_ac_yes = True
            if _test_ac_yes:
                _tr = data.get("test_results")
                _tr_empty = (
                    _tr is None
                    or (isinstance(_tr, dict) and not _tr)
                    or (isinstance(_tr, str) and _tr.strip() in ("", "null", "{}"))
                )
                if _tr_empty:
                    hints.append(
                        "GP-201c WARN: テスト全PASS ACがyesだがtest_resultsが空 — "
                        "テスト実行結果をtest_resultsに記録せよ"
                    )
        except Exception:
            pass

    origin_candidates = [
        str(data.get("origin", "") or "").strip(),
    ]
    if isinstance(lc, dict):
        origin_candidates.append(str(lc.get("origin", "") or "").strip())
    if not any(
        origin and origin.lower() not in ("none", "null", "n/a", "na", "fILL_THIS".lower())
        for origin in origin_candidates
    ):
        hints.append(
            "WARN: origin欄が空/未記入 — 因果ネットワーク接続のため "
            'bash scripts/report_field_set.sh <report> origin "[[cmd_xxx]] -> [[原因]] -> [[結果]]" '
            "で記入せよ"
        )

    if _task_needs_causal_verification(task_data) and not _causal_verification_filled(data.get("causal_verification")):
        hints.append(
            "WARN: causal_verification欄が空/未記入 — hook/gate/daemon/semantic/search/memory DB/配備フロー変更では "
            "git log/blame・関連教訓・設計書・semantic/causal確認結果を記録せよ"
        )

    residual_sweep_sources = {
        "result": data.get("result"),
        "binary_checks": data.get("binary_checks"),
        "lesson_candidate": data.get("lesson_candidate"),
        "lessons_useful": data.get("lessons_useful"),
        "causal_verification": data.get("causal_verification"),
        "purpose_validation": data.get("purpose_validation"),
    }
    residual_sweep_applies = (
        _report_has_existing_implementation_file(data.get("files_modified"))
        and _report_claims_completed_residual_sweep(residual_sweep_sources)
    )
    if residual_sweep_applies and not _report_has_residual_sweep_evidence(
        residual_sweep_sources
    ):
        errors.append("LK-A14: 横展開/修正前パターンを扱う報告にはgrep/rg残存0件の一次証跡が必須")
        hints.append(
            "FIX (LK-A14): result.details または causal_verification.evidence に "
            "rg/grepの対象範囲・検索語・残存0件を記録せよ"
        )

    ai = data.get("assumption_invalidation")
    if ai is None and "assumption_invalidation" in data:
        errors.append("assumption_invalidation: null (must be dict with found/affected_cmds/detail)")
    elif ai is not None:
        if not isinstance(ai, dict):
            errors.append(f"assumption_invalidation: is {type(ai).__name__} (must be dict)")
        else:
            for ai_field in ["found", "affected_cmds", "detail"]:
                if ai_field not in ai:
                    errors.append(f'assumption_invalidation: missing "{ai_field}" field')
            ai_found = ai.get("found")
            ai_cmds = ai.get("affected_cmds")
            if ai_found is True and isinstance(ai_cmds, list) and len(ai_cmds) == 0:
                errors.append("assumption_invalidation: found=true but affected_cmds is empty (影響cmdを列挙せよ)")
                hints.append("FIX (assumption_invalidation): found:trueの場合、affected_cmdsに影響を受けるcmd_IDを列挙せよ")
    elif "assumption_invalidation" not in data:
        errors.append("assumption_invalidation: MISSING")
        hints.append('FIX (assumption_invalidation): テンプレートに生成済み。上書きで消すな:\n  assumption_invalidation:\n    found: false\n    affected_cmds: []\n    detail: ""')

    kc = data.get("knowledge_candidate")
    if kc is not None:
        if not isinstance(kc, dict):
            errors.append(f"knowledge_candidate: is {type(kc).__name__} (must be dict)")
        else:
            if kc.get("found") is True:
                kc_items = kc.get("items", [])
                if not isinstance(kc_items, list) or len(kc_items) == 0:
                    errors.append("knowledge_candidate: found=true but items is empty")
                    hints.append('FIX (knowledge_candidate): found:true時はitemsに事実データを列挙せよ:\n  knowledge_candidate:\n    found: true\n    items:\n      - fact: "発見した事実"\n        source: "確認元"')
                elif isinstance(kc_items, list):
                    for i, item in enumerate(kc_items):
                        if isinstance(item, dict) and not str(item.get("fact", "")).strip():
                            errors.append(f"knowledge_candidate.items[{i}].fact: empty")

    sgc = data.get("self_gate_check")
    if sgc is not None:
        if not isinstance(sgc, dict):
            errors.append(f"self_gate_check: is {type(sgc).__name__} (must be dict)")
            hints.append('FIX (self_gate_check): dict形式で記入せよ:\n  self_gate_check:\n    lesson_ref: PASS\n    lesson_candidate: PASS\n    status_valid: PASS\n    purpose_fit: PASS\n  各項目はPASS/FAILの二値')
        else:
            required_sgc_keys = ("lesson_ref", "lesson_candidate", "status_valid", "purpose_fit")
            valid_sgc_values = {"PASS", "FAIL"}
            required_sgc_key_text = ", ".join(required_sgc_keys)
            for required_sgc_key in required_sgc_keys:
                if required_sgc_key not in sgc:
                    errors.append(
                        f'self_gate_check: missing required key "{required_sgc_key}" '
                        f"(required: {required_sgc_key_text})"
                    )
                    hints.append(
                        "FIX (self_gate_check): 必須4キーを全て記入せよ:\n"
                        "  self_gate_check:\n"
                        "    lesson_ref: PASS\n"
                        "    lesson_candidate: PASS\n"
                        "    status_valid: PASS\n"
                        "    purpose_fit: PASS"
                    )
            for sgc_key, sgc_val in sgc.items():
                sgc_str = str(sgc_val).strip() if sgc_val is not None else ""
                if sgc_str == "":
                    errors.append(f"self_gate_check.{sgc_key}: empty (must be PASS or FAIL)")
                    hints.append(f"FIX: self_gate_check.{sgc_key} に PASS or FAIL を記入せよ")
                elif sgc_str not in valid_sgc_values:
                    errors.append(f'self_gate_check.{sgc_key}: "{sgc_str}" is not valid (must be "PASS" or "FAIL")')
                    hints.append(f'FIX: Change self_gate_check.{sgc_key} from "{sgc_str}" to "PASS" or "FAIL"')

    filename = os.path.basename(report_path)
    fname_match = re.search(r"_report_(.+?)\.ya?ml", filename)
    parent_cmd = data.get("parent_cmd", "")
    if fname_match and parent_cmd:
        fname_cmd = fname_match.group(1)
        if not fname_cmd.startswith(str(parent_cmd) + "_") and fname_cmd != str(parent_cmd):
            errors.append(f"stale_report: filename has {fname_cmd} but parent_cmd={parent_cmd} (cmd_id mismatch)")

    report_text = json.dumps(data, ensure_ascii=False, default=str)
    other_cmds = set(re.findall(r"cmd_(?:[a-zA-Z_]*\d)[a-zA-Z0-9_]*", report_text)) - {str(parent_cmd)}
    if other_cmds and parent_cmd:
        stale_cmds = [cmd for cmd in other_cmds if not cmd.startswith(str(parent_cmd))]
        if stale_cmds:
            hints.append(f"GP-062 WARN: 報告内に別cmdの参照あり: {sorted(stale_cmds)} — staleコンテンツの可能性を確認せよ")

    if result and isinstance(result, dict):
        details_text = str(result.get("details", "")) + " " + str(result.get("summary", ""))
        for indicator in ["PE経由", "PE fallback", "PEフォールバック", "PE経由でフル実行", "use_pe_mode"]:
            if indicator in details_text:
                hints.append(f'PI-012 WARN: 報告にPE使用の痕跡あり("{indicator}")。GS探索でPE使用は禁止(cmd_1349)。batch pathの修正が必要')
                break

    seen_bases = set()
    deduped = []
    for hint in hints:
        base = re.sub(r"\[\d+\]", "[*]", hint)
        if base not in seen_bases:
            seen_bases.add(base)
            deduped.append(re.sub(r"\[\d+\]", "[N]", hint))
    hints = deduped

    if errors:
        print("FAIL: " + "; ".join(errors))
        for hint in hints:
            print(hint)
        return 1

    # --- PASS_NO_IMPROVEMENT detection (cmd_2072) ---
    # binary_checksでrevert含むACが全ACの50%以上の場合に発動
    _no_improvement = False
    if isinstance(bc, dict) and bc:
        _ac_keys = [k for k in bc.keys() if k.upper().startswith("AC")]
        if _ac_keys:
            _revert_acs = []
            for _ac_key in _ac_keys:
                _ac_items = bc.get(_ac_key, [])
                if isinstance(_ac_items, list):
                    for _item in _ac_items:
                        if isinstance(_item, dict):
                            if "revert" in str(_item.get("check", "")).lower():
                                _revert_acs.append(_ac_key)
                                break
            if len(_revert_acs) >= len(_ac_keys) * 0.5:
                _no_improvement = True

    if _no_improvement:
        print("PASS_NO_IMPROVEMENT")
        print(
            f"WARN: revertが検出されたAC={len(_revert_acs)}/{len(_ac_keys)}件(50%以上)。"
            "改善未達成。家老に改善未達成を通知せよ。"
        )
    else:
        print("PASS")
    for hint in hints:
        print(hint)
    return 0


# ─── FIX hint lookup API (used by skill_auto_improve.sh) ─────────────────────
# Maps FAIL reason substrings → specific FIX hint text from this gate.
# skill_auto_improve.sh imports lookup_fix_hints() to replace generic
# keyword-matching templates with concrete, actionable prevention steps.

_HINT_DB: "list[tuple[re.Pattern, str]]" = []


def _h(pattern: str, hint: str) -> None:
    _HINT_DB.append((re.compile(pattern), hint))


# binary_checks
_h(r'binary_checks\..+\.result: 空文字',
   'FIX (binary_checks.result): result欄に yes または no を記入。'
   '引用符なしで書け（result: yes が正式。result: \'yes\' はNG）。'
   '  bash scripts/report_field_set.sh <report> binary_checks.AC1 -'
   ' <<<\'[{check: "確認内容", result: yes}]\'')
_h(r'binary_checks\..+\.result: ".+" は不正',
   'FIX (binary_checks.result): "yes" または "no" のみ。自由記述は acceptance_criteria.detail に書け。'
   '引用符なし: result: yes（result: \'yes\' はNG）')
_h(r'binary_checks\..+\.check: ".+" は確認項目ではない',
   'FIX (binary_checks.check): check に「何を確認したか」を書け。result に yes/no を書け。'
   '  例: {check: "変数が除去されたか", result: yes}')
_h(r'binary_checks: null',
   'FIX (binary_checks): null ではなく dict 形式で記入:\n'
   '  binary_checks:\n    AC1:\n      - check: "確認内容"\n        result: yes')
_h(r'binary_checks: is string',
   'FIX (binary_checks): dict 形式で再記入:\n'
   '  binary_checks:\n    AC1:\n      - check: "確認内容"\n        result: yes')
_h(r'binary_checks: empty dict',
   'FIX (binary_checks): AC完了ごとに二値チェックを記入:\n'
   '  binary_checks:\n    AC1:\n      - check: "確認内容を具体的に"\n        result: yes')
_h(r'binary_checks\..+: is \w+ \(must be list',
   'FIX (binary_checks.AC*): list 形式で記入:\n'
   '  binary_checks:\n    AC1:\n      - check: "確認内容"\n        result: yes')
_h(r'binary_checks\..+: nested list detected',
   'FIX (binary_checks): "- - check:" を "- check:" に修正（余分な"-"を削除）')
_h(r'binary_checks: AC self-verification missing',
   'FIX (binary_checks): task YAML の acceptance_criteria を確認し AC1/AC2... セクションを追加。'
   '  echo \'[{check: "AC完了確認", result: yes}]\' | bash scripts/report_field_set.sh <report> binary_checks.AC1 -')
_h(r'binary_checks: item count \d+/\d+ \(<50%',
   'FIX (binary_checks): task YAML の全 binary_checks 項目に result を記入せよ。'
   'テンプレートより少ない確認項目は認められない')

# verdict
_h(r'verdict: ".*" is not valid',
   'FIX (verdict): bash scripts/report_field_set.sh <report> verdict PASS\n'
   '  verdict は PASS/FAIL/PASS_NO_IMPROVEMENT の三値。binary_checks 全 yes → PASS、1 つでも no → FAIL')
_h(r'verdict: PASS but binary_checks contain "no" results',
   'FIX (verdict): bash scripts/report_field_set.sh <report> verdict FAIL\n'
   '  binary_checks に no/fail/ng がある場合は verdict: FAIL にせよ')
_h(r'verdict: PASS but binary_checks contain empty result',
   'FIX (verdict-BC矛盾): binary_checks の全 result 欄を yes/no で埋めてから verdict を設定せよ')

# lessons_useful
_h(r'lessons_useful: null',
   'FIX (lessons_useful): null で上書きするな。テンプレートの list 形式を維持し useful/reason を記入せよ')
_h(r'lessons_useful: is dict',
   'FIX (lessons_useful): numbered dict を YAML list に変換して再記入。'
   'report_field_set.sh でテンプレート注入済みの list 形式を維持すること')
_h(r'lessons_useful: empty list',
   'FIX (lessons_useful): report_field_set.sh 経由で useful/reason を各教訓に記入せよ。'
   '空リスト [] で上書きするな')
_h(r'lessons_useful\[.+\]: missing "id" field',
   'FIX (lessons_useful.id): id フィールド必須。テンプレート注入済みの教訓 ID を確認:\n'
   '  - id: L074\n    useful: true\n    reason: "理由"')
_h(r'lessons_useful\[.+\]: id=".+" is invalid',
   'FIX (lessons_useful.id): id は L+数字形式のみ（例: L074）。テンプレート注入済みの教訓 ID を確認')
_h(r'lessons_useful\[.+\]: missing "useful" field',
   'FIX (lessons_useful.useful): useful: true または useful: false を記入せよ')
_h(r'lessons_useful\[.+\]: useful=.+ is .+ \(must be true or false\)',
   'FIX (lessons_useful.useful): useful: true または useful: false を指定（文字列や null は不可）')
_h(r'lessons_useful\[.+\]: missing "reason" field',
   'FIX (lessons_useful.reason): reason フィールド必須。教訓が有用/無用な理由を具体的に記入')
_h(r'lessons_useful\[.+\]: reason is empty',
   'FIX (lessons_useful.reason): reason: "L246 の return 1 罠と一致し有用" / '
   '"今回の変更では未使用。対象箇所と無関係" など具体的に記述')

# result / files_modified
_h(r'result\.summary: MISSING or empty',
   'FIX (result.summary): bash scripts/report_field_set.sh <report> result.summary "実施内容の要約"')
_h(r'result\.summary: FILL_THIS placeholder',
   'FIX (result.summary): FILL_THIS を実際の要約に書き換え:\n'
   '  bash scripts/report_field_set.sh <report> result.summary "実施内容の要約"')
_h(r'files_modified: MISSING',
   'FIX (files_modified): bash scripts/report_field_set.sh <report> files_modified <path>\n'
   '  偵察のみなら: bash scripts/report_field_set.sh <report> files_modified "偵察のみ"')
_h(r'files_modified: null',
   'FIX (files_modified): null ではなく変更ファイルパスを記入:\n'
   '  files_modified:\n    - path/to/file.py')
_h(r'files_modified: is dict',
   'FIX (files_modified): dict ではなく string/list 形式:\n'
   '  files_modified:\n    - path/to/file1.py\n    - path/to/file2.py')
_h(r'files_modified: FILL_THIS',
   'FIX (files_modified): FILL_THIS を実際のパスに書き換えよ')

# lesson_candidate
_h(r'lesson_candidate: found=false but no no_lesson_reason',
   'FIX (lesson_candidate): bash scripts/report_field_set.sh <report> lesson_candidate.found false\n'
   '  bash scripts/report_field_set.sh <report> lesson_candidate.no_lesson_reason "既知パターン L084 と同じ"')
_h(r'lesson_candidate: no_lesson_reason too short',
   'FIX (lesson_candidate): no_lesson_reason に具体的な理由（4 文字以上）を記入:\n'
   '  例: "既知の L084 と同じパターン"')
_h(r'lesson_candidate: no_lesson_reason=".+" is placeholder',
   'FIX (lesson_candidate): プレースホルダ禁止。なぜ教訓がないのか具体的に書け')
_h(r'lesson_candidate: found=true but no title',
   'FIX (lesson_candidate): bash scripts/report_field_set.sh <report> lesson_candidate.title "教訓タイトル"')

# status / purpose / ac_version / worker / parent_cmd
_h(r'status: "pending"',
   'FIX (status): bash scripts/report_field_set.sh <report> status completed')
_h(r'purpose_validation: MISSING',
   'FIX (purpose_validation): bash scripts/report_field_set.sh <report> purpose_validation.fit true\n'
   '  bash scripts/report_field_set.sh <report> purpose_validation.cmd_purpose "cmd の目的"')
_h(r'purpose_validation: null',
   'FIX (purpose_validation): null ではなく dict 形式:\n'
   '  purpose_validation:\n    cmd_purpose: "cmd の目的"\n    fit: true\n    purpose_gap: ""')
_h(r'ac_version_read: MISSING',
   'FIX (ac_version_read): task YAML の ac_version ハッシュをコピー:\n'
   '  bash scripts/report_field_set.sh <report> ac_version_read '
   '$(grep "^  ac_version:" queue/tasks/<ninja>.yaml | awk \'{print $2}\')')
_h(r'worker_id: MISSING',
   'FIX (worker_id): bash scripts/report_field_set.sh <report> worker_id <your_ninja_name>')
_h(r'parent_cmd: MISSING',
   'FIX (parent_cmd): bash scripts/report_field_set.sh <report> parent_cmd <cmd_id>')

# cross_repo_commits
_h(r'cross_repo_commits: (?:cross_repo_commits\[\d+\] commit does not change path|files_modified path lacks cross-repo ownership)',
   'FIX (cross_repo_commits): pathsを手書きで補正せず、'
   'scripts.lib.cross_repo_commit_contract.auto_generate_cross_repo_entries(repo, [commit_hash]) '
   'でcommit実体からentriesを再生成し、report_field_set.sh経由でcross_repo_commitsへ設定せよ。'
   'repoは絶対Git repository path、commit_hashは40-hexを渡すこと')
_h(r'cross_repo_commits: cross_repo_commits\[\d+\]\.(?:repo is not an absolute Git repository|commit_hash is not a resolvable 40-hex commit)',
   'FIX (cross_repo_commits): repo/commit_hashを推測で直さず、実在repoの絶対pathと'
   'git rev-parse <commit>の40-hexを確認してから '
   'scripts.lib.cross_repo_commit_contract.auto_generate_cross_repo_entries(repo, [commit_hash]) '
   'でentriesを再生成せよ')

# assumption_invalidation / self_gate_check / knowledge_candidate
_h(r'assumption_invalidation: is \w+',
   'FIX (assumption_invalidation): dict 形式で記入:\n'
   '  assumption_invalidation:\n    found: false\n    affected_cmds: []\n    detail: ""')
_h(r'assumption_invalidation: MISSING',
   'FIX (assumption_invalidation): テンプレートに生成済み。上書きで消すな:\n'
   '  bash scripts/report_field_set.sh <report> assumption_invalidation.found false')
_h(r'assumption_invalidation: null',
   'FIX (assumption_invalidation): null ではなく dict 形式:\n'
   '  assumption_invalidation:\n    found: false\n    affected_cmds: []\n    detail: ""')
_h(r'assumption_invalidation: found=true but affected_cmds is empty',
   'FIX (assumption_invalidation): found: true の場合 affected_cmds に影響 cmd を列挙せよ')
_h(r'self_gate_check:',
   'FIX (self_gate_check): 必須 4 キー（lesson_ref/lesson_candidate/status_valid/purpose_fit）を'
   '全て PASS/FAIL で記入')
_h(r'knowledge_candidate: found=true but items is empty',
   'FIX (knowledge_candidate): found: true 時は items に事実データを列挙:\n'
   '  knowledge_candidate:\n    found: true\n    items:\n      - fact: "発見した事実"\n        source: "確認元"')


def lookup_fix_hints(reason: str) -> "list[str]":
    """Return specific FIX hints for a FAIL reason string from gate_report_format.

    Used by skill_auto_improve.sh to replace generic keyword-matching templates
    with concrete, actionable prevention steps from the gate FIX hint DB.

    Args:
        reason: The semicolon-joined FAIL reason string from gate output.

    Returns:
        List of matching FIX hint strings (may be empty if no pattern matches).
    """
    results = []
    for pat, hint in _HINT_DB:
        if pat.search(reason):
            results.append(hint)
    return results


if __name__ == "__main__":
    raise SystemExit(main())
