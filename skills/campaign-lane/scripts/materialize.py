#!/usr/bin/env python3
"""Materialize an exact commit into an isolated git worktree."""
from __future__ import annotations

import hashlib
import os
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


def materialize(
    source_repo: str | Path,
    destination: str | Path,
    fixed_sha: str,
    scratch_root: str | Path | None = None,
    retry_failed: bool = False,
) -> dict:
    source = Path(source_repo).resolve()
    logical_target = Path(destination).absolute()
    if not re.fullmatch(r"[0-9a-f]{40}", fixed_sha):
        raise MaterializeError("fixed SHA must be full lowercase SHA")
    if retry_failed and logical_target.is_symlink():
        # Keep the abandoned scratch checkout as evidence; only replace the
        # project-local logical pointer.  A unique generation prevents a retry
        # from colliding with the failed shard's ext4 destination.
        logical_target.unlink()
    elif retry_failed and logical_target.is_dir():
        # Pre-ext4 failed shards are full clones at the logical path.  Preserve
        # them with an O(1), same-filesystem rename instead of recursively
        # deleting/copying them, then reuse the canonical logical path.
        quarantine = logical_target.with_name(f"{logical_target.name}.failed-{os.getpid()}")
        if quarantine.exists():
            raise MaterializeError("retry quarantine already exists")
        logical_target.rename(quarantine)
    if logical_target.exists() and any(logical_target.iterdir()):
        raise MaterializeError("destination must be empty")
    logical_target.mkdir(parents=True, exist_ok=True)
    target = logical_target
    if scratch_root is not None:
        scratch = Path(scratch_root).resolve()
        scratch.mkdir(parents=True, exist_ok=True)
        identity = hashlib.sha256(str(logical_target).encode()).hexdigest()[:20]
        generation = f"-{os.getpid()}" if retry_failed else ""
        target = scratch / f"{identity}-{fixed_sha[:12]}{generation}"
        if target.exists() and any(target.iterdir()):
            raise MaterializeError("scratch destination must be empty")
        target.mkdir(parents=True, exist_ok=True)
        logical_target.rmdir()
        logical_target.symlink_to(target, target_is_directory=True)
    clone_args = ["git", "clone", "--no-checkout"]
    if scratch_root is None:
        clone_args.append("--local")
    else:
        # Referencing the durable source object store avoids both cross-device
        # hardlinks and a full object copy. New shard commits remain isolated.
        clone_args.append("--shared")
    result = subprocess.run([*clone_args, str(source), str(target)], text=True, capture_output=True, check=False)
    if result.returncode:
        raise MaterializeError(result.stderr.strip() or "clone failed")
    _git(target, "checkout", "--detach", fixed_sha)
    head = _git(target, "rev-parse", "HEAD")
    dirty = _git(target, "status", "--porcelain")
    if head != fixed_sha or dirty:
        raise MaterializeError("source materialize verification failed")
    return {"status": "success", "fixed_sha": head, "dirty": 0}
