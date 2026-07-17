#!/usr/bin/env python3
"""Materialize an exact commit into an isolated git worktree."""
from __future__ import annotations

import re
import subprocess
from pathlib import Path


class MaterializeError(RuntimeError):
    pass


def _git(repo: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True, check=False)
    if result.returncode:
        raise MaterializeError(result.stderr.strip() or "git command failed")
    return result.stdout.strip()


def materialize(source_repo: str | Path, destination: str | Path, fixed_sha: str) -> dict:
    source, target = Path(source_repo).resolve(), Path(destination).resolve()
    if not re.fullmatch(r"[0-9a-f]{40}", fixed_sha):
        raise MaterializeError("fixed SHA must be full lowercase SHA")
    if target.exists() and any(target.iterdir()):
        raise MaterializeError("destination must be empty")
    target.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(["git", "clone", "--no-checkout", "--local", str(source), str(target)], text=True, capture_output=True, check=False)
    if result.returncode:
        raise MaterializeError(result.stderr.strip() or "clone failed")
    _git(target, "checkout", "--detach", fixed_sha)
    head = _git(target, "rev-parse", "HEAD")
    dirty = _git(target, "status", "--porcelain")
    if head != fixed_sha or dirty:
        raise MaterializeError("source materialize verification failed")
    return {"status": "success", "fixed_sha": head, "dirty": 0}

