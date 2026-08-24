#!/usr/bin/env python3
"""Resolve the immutable source checkout used by review prechecks.

The review report is produced in the shared checkout, while implementation
tasks with an isolated worktree publish their source commit from that
worktree.  Context-link checks must inspect that same source generation.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys

import yaml


GENERATION_RE = re.compile(r"^[0-9a-f]{64}$")


def emit(values: dict[str, str]) -> None:
    for key, value in values.items():
        print(f"{key}={shlex.quote(value)}")


def fail(reason: str) -> int:
    emit(
        {
            "SOURCE_CONTEXT_STATUS": "BLOCK",
            "SOURCE_CONTEXT_REASON": reason,
            "SOURCE_CONTEXT_ROOT": "",
            "SOURCE_CONTEXT_GENERATION": "",
            "SOURCE_CONTEXT_COMMIT": "",
        }
    )
    return 1


def load_mapping(path: pathlib.Path) -> dict:
    try:
        value = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception as exc:  # pragma: no cover - defensive boundary
        raise ValueError(f"YAML load failed: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"YAML mapping required: {path}")
    return value.get("task", value) if isinstance(value.get("task", value), dict) else {}


def git(repo: pathlib.Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(repo), *args], stderr=subprocess.DEVNULL, text=True
    ).strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", required=True)
    parser.add_argument("--task", required=True)
    parser.add_argument("--repo-root", required=True)
    args = parser.parse_args()
    report_path = pathlib.Path(args.report).resolve()
    task_path = pathlib.Path(args.task).resolve()
    repo_root = pathlib.Path(args.repo_root).resolve()

    try:
        report = load_mapping(report_path)
        task = load_mapping(task_path)
    except ValueError as exc:
        return fail(str(exc))

    context_files = []
    for item in report.get("files_modified") or []:
        path = item.get("path", "") if isinstance(item, dict) else str(item)
        if path.startswith("context/") and path.endswith(".md"):
            context_files.append(path)
    if not context_files:
        emit(
            {
                "SOURCE_CONTEXT_STATUS": "SKIP",
                "SOURCE_CONTEXT_REASON": "no_context_files",
                "SOURCE_CONTEXT_ROOT": str(repo_root),
                "SOURCE_CONTEXT_GENERATION": "shared",
                "SOURCE_CONTEXT_COMMIT": "",
            }
        )
        return 0

    required_raw = task.get("task_worktree_required")
    required = required_raw is True or str(required_raw).strip().lower() in {"1", "true", "yes", "on"}
    worktree_raw = str(task.get("task_worktree_workdir") or task.get("task_worktree_path") or "").strip()
    generation = str(task.get("task_worktree_generation") or "").strip().lower()
    if not required:
        # Legacy/recon reports have no isolated source generation.  Preserve
        # the historical shared-root behavior for those tasks.
        emit(
            {
                "SOURCE_CONTEXT_STATUS": "SHARED",
                "SOURCE_CONTEXT_REASON": "task_worktree_not_required",
                "SOURCE_CONTEXT_ROOT": str(repo_root),
                "SOURCE_CONTEXT_GENERATION": "shared",
                "SOURCE_CONTEXT_COMMIT": str(report.get("commit_hash") or ""),
            }
        )
        return 0

    if not worktree_raw:
        return fail("task_worktree_path_missing")
    if not GENERATION_RE.fullmatch(generation):
        return fail("task_worktree_generation_missing_or_invalid")
    worktree = pathlib.Path(worktree_raw).resolve()
    if not worktree.is_dir():
        return fail("task_worktree_missing")
    try:
        if pathlib.Path(git(worktree, "rev-parse", "--show-toplevel")).resolve() != worktree:
            return fail("task_worktree_root_mismatch")
    except (OSError, subprocess.CalledProcessError):
        return fail("task_worktree_not_git")

    marker_raw = str(task.get("task_worktree_marker") or "").strip()
    if not marker_raw:
        return fail("task_worktree_marker_missing")
    marker = pathlib.Path(marker_raw)
    try:
        marker_data = json.loads(marker.read_text(encoding="utf-8"))
    except Exception:
        return fail("task_worktree_marker_unreadable")
    if marker_data.get("generation") != generation:
        return fail("task_worktree_marker_generation_mismatch")
    task_id = str(task.get("task_id") or "").strip()
    if task_id and marker_data.get("task_id") != task_id:
        return fail("task_worktree_marker_task_id_mismatch")
    if pathlib.Path(str(marker_data.get("worktree") or "")).resolve() != worktree:
        return fail("task_worktree_marker_path_mismatch")
    if marker_data.get("state") not in {"active", "published"}:
        return fail("task_worktree_marker_not_active")

    commit = str(report.get("commit_hash") or "").strip()
    if not commit:
        return fail("report_commit_missing_for_task_worktree")
    try:
        resolved_commit = git(worktree, "rev-parse", f"{commit}^{{commit}}")
        head = git(worktree, "rev-parse", "HEAD")
    except (OSError, subprocess.CalledProcessError):
        return fail("report_commit_not_resolved_in_task_worktree")
    if resolved_commit != head:
        return fail("report_commit_task_worktree_head_mismatch")

    for path in context_files:
        if not (worktree / path).is_file():
            return fail(f"source_context_missing:{path}")
    emit(
        {
            "SOURCE_CONTEXT_STATUS": "SOURCE",
            "SOURCE_CONTEXT_REASON": "task_worktree_generation_verified",
            "SOURCE_CONTEXT_ROOT": str(worktree),
            "SOURCE_CONTEXT_GENERATION": generation,
            "SOURCE_CONTEXT_COMMIT": resolved_commit,
        }
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
