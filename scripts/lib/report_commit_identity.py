#!/usr/bin/env python3
"""Shared commit-identity contract for report creation, format, and review."""

from __future__ import annotations

import pathlib
import re
import subprocess
from typing import Any


FULL_HASH_RE = re.compile(r"[0-9a-f]{40}")
NO_CODE_IDENTITY = "no-code-change"
NO_COMMIT_MARKERS = ("実行していない", "commit禁止", "commit不要", "no-commit", "no commit")


def _reported_path(item: Any) -> str:
    value = item.get("path", "") if isinstance(item, dict) else item
    return value.strip() if isinstance(value, str) else ""


def explicit_no_commit(report: dict[str, Any]) -> bool:
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
        if result_yes and any(marker.lower() in text for marker in NO_COMMIT_MARKERS):
            return True
    return False


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
    return explicit_no_commit(report) and operational_files_only(report, root)


def valid_commit_identity(value: Any, report: dict[str, Any], root: pathlib.Path) -> bool:
    identity = str(value or "").strip()
    return bool(FULL_HASH_RE.fullmatch(identity)) or (
        identity == NO_CODE_IDENTITY and permits_no_code_identity(report, root)
    )
