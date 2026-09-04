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
    if not isinstance(report, dict) or not _legacy_na_files(report) or not _tree_evidence_valid(report):
        return False
    report_type = _task_type(report)
    task_node = task.get("task", task) if isinstance(task, dict) else None
    task_type = _task_type(task_node)
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
