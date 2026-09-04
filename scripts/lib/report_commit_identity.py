#!/usr/bin/env python3
"""Shared commit-identity contract for report creation, format, and review."""

from __future__ import annotations

import json
import pathlib
import re
import subprocess
from typing import Any


FULL_HASH_RE = re.compile(r"[0-9a-f]{40}")
NO_CODE_IDENTITY = "no-code-change"
NO_COMMIT_MARKERS = ("実行していない", "commit禁止", "commit不要", "no-commit", "no commit")
RECON_TASK_TYPES = frozenset(("recon", "recon2", "scout"))
LEGACY_NA_MARKERS = frozenset(("n/a", "na"))


def _reported_path(item: Any) -> str:
    value = item.get("path", "") if isinstance(item, dict) else item
    return value.strip() if isinstance(value, str) else ""


def explicit_no_commit(report: dict[str, Any]) -> bool:
    contract = report.get("commit_contract")
    if isinstance(contract, dict) and contract.get("required") is False:
        return True
    checks = report.get("binary_checks") or {}
    items = checks.get("commit", []) if isinstance(checks, dict) else []
    if not isinstance(items, list):
        return False
    for item in items:
        if not isinstance(item, dict):
            continue
        text = str(item.get("check", "")).strip().lower()
        result = item.get("result")
        result_yes = result is True or str(result).strip().lower() == "yes"
        if result_yes and any(marker.lower() in text for marker in (*NO_COMMIT_MARKERS, "commit n/a")):
            return True
    return False


def _task_type(node: Any) -> str:
    if not isinstance(node, dict):
        return ""
    contract = node.get("commit_contract")
    if isinstance(contract, str):
        try:
            contract = json.loads(contract)
        except (TypeError, ValueError):
            contract = None
    if isinstance(contract, dict) and str(contract.get("task_type") or "").strip():
        return str(contract.get("task_type") or "").strip().lower()
    for key in ("task_type", "type", "scope_mode"):
        value = str(node.get(key) or "").strip().lower()
        if value:
            return value
    return ""


def _legacy_na_files(report: dict[str, Any]) -> bool:
    files = report.get("files_modified")
    if isinstance(files, str):
        values = [files]
    elif isinstance(files, list) and len(files) == 1:
        item = files[0]
        values = [item.get("path") if isinstance(item, dict) else item]
    else:
        return False
    return str(values[0] or "").strip().lower() in LEGACY_NA_MARKERS


def _tree_evidence_valid(report: dict[str, Any]) -> bool:
    evidence = report.get("no_code_change_evidence")
    if not isinstance(evidence, dict) or evidence.get("tree_unchanged") is not True:
        return False
    before = str(evidence.get("before_tree") or "").strip().lower()
    after = str(evidence.get("after_tree") or "").strip().lower()
    return bool(FULL_HASH_RE.fullmatch(before)) and before == after


def _legacy_recon_shape(report: dict[str, Any], task: dict[str, Any] | None = None) -> bool:
    if not isinstance(report, dict) or not _legacy_na_files(report):
        return False
    report_type = _task_type(report)
    task_node = _task_node(task)
    task_type = _task_type(task_node)
    if isinstance(task_node, dict):
        for key in ("task_id", "parent_cmd"):
            report_value = str(report.get(key) or "").strip()
            task_value = str(task_node.get(key) or "").strip()
            if report_value and task_value and report_value != task_value:
                return False
    if task_type:
        if task_type not in RECON_TASK_TYPES or report_type not in RECON_TASK_TYPES:
            return False
        if task_type != report_type:
            return False
    elif report_type not in RECON_TASK_TYPES:
        return False
    for node in (report, task_node):
        contract = node.get("commit_contract") if isinstance(node, dict) else None
        if isinstance(contract, str):
            try:
                contract = json.loads(contract)
            except (TypeError, ValueError):
                contract = None
        if isinstance(contract, dict) and contract.get("required") is True:
            return False
    return explicit_no_commit(report)


def permits_legacy_recon_identity(
    report: dict[str, Any], root: pathlib.Path, task: dict[str, Any] | None = None
) -> bool:
    """Allow the pre-typed N/A form only with equivalent no-code proof.

    Older recon reports used ``files_modified: N/A`` and an empty commit hash.
    The marker alone is not an exemption: the effective task must remain a
    recon task, both task/report contracts must reject a commit when present,
    the report must affirm no commit, and before/after tree evidence must be
    identical.  The caller still resolves the evidence tree in the owning
    repository before accepting the identity.
    """
    return _legacy_recon_shape(report, task) and _tree_evidence_valid(report)


def _task_node(task: dict[str, Any] | None) -> dict[str, Any] | None:
    if not isinstance(task, dict):
        return None
    node = task.get("task", task)
    return node if isinstance(node, dict) else None


def _legacy_task_paths(task_node: dict[str, Any]) -> list[str]:
    """Resolve the read-only source scope used for a legacy recon proof."""
    raw = task_node.get("task_worktree_source_paths")
    if isinstance(raw, str):
        try:
            decoded = json.loads(raw)
        except (TypeError, ValueError):
            decoded = None
        raw = decoded if decoded is not None else [raw]
    if isinstance(raw, list) and raw:
        values = raw
    else:
        raw = task_node.get("target_path")
        values = raw if isinstance(raw, list) else [raw]
    paths = []
    for value in values:
        text = str(value or "").strip()
        if len(text) >= 2 and text[0] == text[-1] and text[0] in "'\"":
            text = text[1:-1].strip()
        if text:
            paths.append(text)
    return paths


def legacy_recon_task_state(
    report: dict[str, Any], task: dict[str, Any] | None
) -> tuple[bool, str, str]:
    """Validate a legacy N/A report against the task's immutable source scope.

    The old report format has no typed tree evidence.  The task's fixed
    independence base and live linked worktree are the independent witness:
    the declared source scope must be unchanged in both the committed HEAD
    and the current worktree.  Operational queue changes outside that scope
    are intentionally irrelevant to a read-only recon.
    """
    task_node = _task_node(task)
    if not _legacy_recon_shape(report, task):
        return False, "identity mismatch", ""
    if task_node is None:
        return False, "task missing", ""

    base = str(task_node.get("independence_base_commit") or "").strip().lower()
    if not FULL_HASH_RE.fullmatch(base):
        return False, "fixed base missing or invalid", ""
    worktree_raw = str(task_node.get("task_worktree_path") or "").strip()
    if not worktree_raw:
        return False, "task worktree missing", ""
    worktree = pathlib.Path(worktree_raw).resolve()
    try:
        git_root = pathlib.Path(
            subprocess.run(
                ["git", "-C", str(worktree), "rev-parse", "--show-toplevel"],
                check=True,
                capture_output=True,
                text=True,
                timeout=5,
            ).stdout.strip()
        ).resolve()
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return False, "task worktree is not a git worktree", ""
    if not git_root.is_dir():
        return False, "task worktree is not a git worktree", ""

    def git(*args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", "-C", str(git_root), *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )

    if git("cat-file", "-e", base + "^{commit}").returncode != 0:
        return False, "fixed base is unresolvable", ""
    head_result = git("rev-parse", "--verify", "HEAD^{commit}")
    if head_result.returncode != 0:
        return False, "task worktree HEAD is unresolvable", ""
    head = head_result.stdout.strip().lower()

    raw_paths = _legacy_task_paths(task_node)
    if not raw_paths:
        return False, "task source scope missing", ""
    paths: list[str] = []
    for raw_path in raw_paths:
        path = pathlib.Path(raw_path)
        resolved = path.resolve() if path.is_absolute() else (git_root / path).resolve()
        try:
            relative = resolved.relative_to(git_root)
        except ValueError:
            return False, "task source scope escapes worktree", ""
        if not relative.parts:
            return False, "task source scope is worktree root", ""
        paths.append(relative.as_posix())

    path_args = ["--", *paths]
    if git("diff", "--quiet", base, head, *path_args).returncode != 0:
        return False, "source tree drift from fixed base", ""
    if git("diff", "--quiet", base, *path_args).returncode != 0:
        return False, "current worktree source drift", ""
    status = git("status", "--porcelain", "--untracked-files=all", *path_args)
    if status.returncode != 0:
        return False, "current worktree status unavailable", ""
    if status.stdout.strip():
        return False, "implementation or source drift present", ""

    base_tree = git("rev-parse", base + "^{tree}")
    if base_tree.returncode != 0:
        return False, "fixed base tree is unresolvable", ""
    return True, "", base_tree.stdout.strip().lower()


def _ignored_project_path(rel: pathlib.Path, root: pathlib.Path) -> bool:
    if not rel.parts or rel.parts[0] != "projects":
        return False
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "check-ignore", "--quiet", "--", str(rel)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


def operational_files_only(report: dict[str, Any], root: pathlib.Path) -> bool:
    files = report.get("files_modified")
    if not isinstance(files, list) or not files:
        return False
    root = root.resolve()
    for item in files:
        raw = _reported_path(item)
        if not raw:
            return False
        path = pathlib.Path(raw)
        resolved = path.resolve() if path.is_absolute() else (root / path).resolve()
        try:
            rel = resolved.relative_to(root)
        except ValueError:
            return False
        if not rel.parts or (
            rel.parts[0] not in ("queue", "logs")
            and not _ignored_project_path(rel, root)
        ):
            return False
    return True


def permits_no_code_identity(report: dict[str, Any], root: pathlib.Path) -> bool:
    evidence = report.get("no_code_change_evidence")
    evidence_valid = (
        isinstance(evidence, dict)
        and evidence.get("tree_unchanged") is True
        and bool(FULL_HASH_RE.fullmatch(str(evidence.get("before_tree") or "").strip()))
        and str(evidence.get("before_tree") or "").strip()
        == str(evidence.get("after_tree") or "").strip()
    )
    return evidence_valid and explicit_no_commit(report) and operational_files_only(report, root)


def valid_commit_identity(value: Any, report: dict[str, Any], root: pathlib.Path) -> bool:
    identity = str(value or "").strip()
    return bool(FULL_HASH_RE.fullmatch(identity)) or (
        identity == NO_CODE_IDENTITY and permits_no_code_identity(report, root)
    )
