"""Validate an explicit multi-repository commit identity without path mixing."""

from __future__ import annotations

import pathlib
import re
import subprocess
from collections.abc import Mapping
from typing import Any


_git_repo_cache: dict[str, bool] = {}


def _normalize_path(path: str) -> str:
    """Remove explicit ``./`` prefixes without stripping leading-dot names."""
    normalized = path.replace("\\", "/").strip()
    while normalized.startswith("./"):
        normalized = normalized[2:]
    return normalized


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


def _is_git_repo(repo: pathlib.Path) -> bool:
    """Cache git repo existence check to avoid repeated subprocess on WSL2 /mnt/c."""
    key = str(repo)
    if key not in _git_repo_cache:
        _git_repo_cache[key] = (repo / ".git").is_dir() or _git(repo, "rev-parse", "--git-dir")
    return _git_repo_cache[key]


def validate_cross_repo_commit_ownership(
    report: Mapping[str, Any],
) -> tuple[list[str], set[str]]:
    """Return validation errors and paths changed by their declared commit."""
    raw = report.get("cross_repo_commits")
    if raw in (None, []):
        return [], set()
    if not isinstance(raw, list):
        return ["cross_repo_commits must be a list"], set()

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
        if not repo.is_absolute() or not _is_git_repo(repo):
            errors.append(f"{label}.repo is not an absolute Git repository")
            continue
        if not re.fullmatch(r"[0-9a-f]{40}", commit):
            errors.append(f"{label}.commit_hash is not a resolvable 40-hex commit")
            continue
        # Combine cat-file check and diff-tree into one subprocess call.
        # diff-tree on a valid commit succeeds; on an invalid one it fails —
        # so a single diff-tree covers both existence and changed-file listing.
        try:
            changed = set(
                subprocess.run(
                    [
                        "git", "-C", str(repo), "diff-tree", "--no-commit-id",
                        "--name-only", "-r", "--root", commit,
                    ],
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=5,
                ).stdout.splitlines()
            )
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
            errors.append(f"{label}.commit_hash is not a resolvable 40-hex commit")
            continue
        commits.add(commit)
        if not isinstance(paths, list) or not paths:
            errors.append(f"{label}.paths must be a non-empty list")
            continue
        entry_declared: set[str] = set()
        for raw_path in paths:
            path = _normalize_path(str(raw_path or ""))
            if not path or path.startswith("/") or ".." in pathlib.PurePosixPath(path).parts:
                errors.append(f"{label}.paths contains unsafe path: {raw_path!r}")
                continue
            if path in entry_declared:
                errors.append(f"cross_repo path appears multiple times in {label}: {path}")
                continue
            entry_declared.add(path)
            if path not in changed:
                errors.append(f"{label} commit does not change path: {path}")
                continue
            owned.add(path)

    if primary and primary not in commits:
        errors.append("primary commit_hash is absent from cross_repo_commits")
    for item in report.get("files_modified") or []:
        if isinstance(item, Mapping):
            path = _normalize_path(str(item.get("path") or ""))
            if path and path not in owned:
                errors.append(f"files_modified path lacks cross-repo ownership: {path}")
    return errors, owned


def validate_cross_repo_commits(report: Mapping[str, Any]) -> list[str]:
    errors, _owned = validate_cross_repo_commit_ownership(report)
    if errors:
        # Collect repo+commit pairs from the report so the FIX hint is actionable.
        fix_parts: list[str] = []
        for entry in report.get("cross_repo_commits") or []:
            if not isinstance(entry, Mapping):
                continue
            repo = str(entry.get("repo") or "").strip()
            commit = str(entry.get("commit_hash") or "").strip()
            if repo and commit:
                fix_parts.append(
                    f'python3 -c "from scripts.lib.cross_repo_commit_contract import '
                    f"auto_generate_cross_repo_entries; import json; "
                    f"print(json.dumps(auto_generate_cross_repo_entries("
                    f"'{repo}', ['{commit}']), indent=2, ensure_ascii=False))\""
                )
        if fix_parts:
            errors.append(
                "FIX hint: cross_repo_commitsのpathsが実際のcommit内容と不一致。"
                "以下を実行して正しいentriesを取得し、報告YAMLのcross_repo_commitsを置換せよ: "
                + " ; ".join(fix_parts)
            )
    return errors


def auto_generate_cross_repo_entries(
    repo: str | pathlib.Path,
    commit_hashes: list[str],
) -> list[dict[str, Any]]:
    """Generate correct cross_repo_commits entries from actual commit data.

    Each commit is queried via git diff-tree for its changed paths, and one
    entry per commit is returned with the repo, hash, and changed paths.
    Commits that cannot be resolved are silently skipped.
    """
    repo = pathlib.Path(repo).resolve()
    entries: list[dict[str, Any]] = []
    for commit in commit_hashes:
        commit = commit.strip()
        if not re.fullmatch(r"[0-9a-f]{40}", commit):
            continue
        try:
            changed = [
                p for p in subprocess.run(
                    ["git", "-C", str(repo), "diff-tree", "--no-commit-id",
                     "--name-only", "-r", "--root", commit],
                    check=True, capture_output=True, text=True, timeout=5,
                ).stdout.splitlines() if p.strip()
            ]
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
            continue
        if changed:
            entries.append({
                "repo": str(repo),
                "commit_hash": commit,
                "paths": sorted(changed),
            })
    return entries
