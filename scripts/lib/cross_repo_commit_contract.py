"""Validate an explicit multi-repository commit identity without path mixing."""

from __future__ import annotations

import pathlib
import re
import subprocess
from collections.abc import Mapping
from typing import Any


def _git(repo: pathlib.Path, *args: str) -> bool:
    return (
        subprocess.run(
            ["git", "-C", str(repo), *args],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
        == 0
    )


def validate_cross_repo_commits(report: Mapping[str, Any]) -> list[str]:
    raw = report.get("cross_repo_commits")
    if raw in (None, []):
        return []
    if not isinstance(raw, list):
        return ["cross_repo_commits must be a list"]

    errors: list[str] = []
    owned: set[str] = set()
    primary = str(report.get("commit_hash") or "").strip()
    commits: set[str] = set()

    for index, entry in enumerate(raw):
        label = f"cross_repo_commits[{index}]"
        if not isinstance(entry, Mapping):
            errors.append(f"{label} must be a mapping")
            continue
        repo = pathlib.Path(str(entry.get("repo") or "")).expanduser()
        commit = str(entry.get("commit_hash") or "").strip()
        paths = entry.get("paths")
        if not repo.is_absolute() or not _git(repo, "rev-parse", "--git-dir"):
            errors.append(f"{label}.repo is not an absolute Git repository")
            continue
        if not re.fullmatch(r"[0-9a-f]{40}", commit) or not _git(
            repo, "cat-file", "-e", f"{commit}^{{commit}}"
        ):
            errors.append(f"{label}.commit_hash is not a resolvable 40-hex commit")
            continue
        commits.add(commit)
        if not isinstance(paths, list) or not paths:
            errors.append(f"{label}.paths must be a non-empty list")
            continue
        for raw_path in paths:
            path = str(raw_path or "").replace("\\", "/").strip().lstrip("./")
            if not path or path.startswith("/") or ".." in pathlib.PurePosixPath(path).parts:
                errors.append(f"{label}.paths contains unsafe path: {raw_path!r}")
                continue
            if path in owned:
                errors.append(f"cross_repo path appears in multiple entries: {path}")
                continue
            owned.add(path)
            if not _git(repo, "cat-file", "-e", f"{commit}:{path}"):
                errors.append(f"{label} commit does not contain path: {path}")

    if primary and primary not in commits:
        errors.append("primary commit_hash is absent from cross_repo_commits")
    for item in report.get("files_modified") or []:
        if isinstance(item, Mapping):
            path = str(item.get("path") or "").replace("\\", "/").strip().lstrip("./")
            if path and path not in owned:
                errors.append(f"files_modified path lacks cross-repo ownership: {path}")
    return errors
