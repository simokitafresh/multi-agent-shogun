#!/usr/bin/env python3
"""Materialize an exact commit into an isolated git worktree."""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import argparse
from pathlib import Path


class MaterializeError(RuntimeError):
    pass


def worktree_registry_plan(source_repo: str | Path) -> dict:
    """Return the exact stale Git registry entries without mutating them."""
    source = Path(source_repo).resolve()
    output = _git(source, "worktree", "list", "--porcelain")
    entries: list[dict] = []
    current: dict = {}
    for line in [*output.splitlines(), ""]:
        if not line:
            if current:
                entries.append(current)
                current = {}
            continue
        key, _, value = line.partition(" ")
        current[key] = value or True
    stale = sorted(str(row["worktree"]) for row in entries if "prunable" in row)
    paths = [str(row["worktree"]) for row in entries]
    duplicates = len(paths) - len(set(paths))
    return {"status": "dry_run", "worktree_count": len(entries), "stale_count": len(stale),
            "duplicate_count": duplicates, "stale_paths": stale}


def reconcile_worktree_registry(source_repo: str | Path, approve_count: int | None = None) -> dict:
    """Prune only the plan just approved; large reconciles fail closed."""
    before = worktree_registry_plan(source_repo)
    count = before["stale_count"]
    if count > 10 and approve_count != count:
        raise MaterializeError(f"approval required for {count} stale registry entries")
    if approve_count is not None and approve_count != count:
        raise MaterializeError("approved count no longer matches current registry")
    if count:
        _git(Path(source_repo).resolve(), "worktree", "prune")
    after = worktree_registry_plan(source_repo)
    if after["stale_count"] != 0 or after["duplicate_count"] != 0:
        raise MaterializeError("registry reconcile verification failed")
    return {"status": "reconciled", "removed_count": count, "stale_paths": before["stale_paths"],
            "worktree_count": after["worktree_count"], "duplicate_count": after["duplicate_count"]}


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
    # `git clone` does not inherit repository-local author identity.  Campaign
    # workers commit inside the isolated checkout, so copy only the two
    # identity keys from the trusted source repository when present.
    for key in ("user.name", "user.email"):
        value = subprocess.run(
            ["git", "-C", str(source), "config", "--local", "--get", key],
            text=True,
            capture_output=True,
            check=False,
        )
        if value.returncode == 0 and value.stdout.rstrip("\n"):
            _git(target, "config", "--local", key, value.stdout.rstrip("\n"))
    head = _git(target, "rev-parse", "HEAD")
    dirty = _git(target, "status", "--porcelain")
    if head != fixed_sha or dirty:
        raise MaterializeError("source materialize verification failed")
    return {"status": "success", "fixed_sha": head, "dirty": 0}


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    plan = sub.add_parser("registry-plan")
    plan.add_argument("source_repo")
    reconcile = sub.add_parser("registry-reconcile")
    reconcile.add_argument("source_repo")
    reconcile.add_argument("--approve-count", type=int)
    args = parser.parse_args()
    try:
        result = (worktree_registry_plan(args.source_repo) if args.command == "registry-plan"
                  else reconcile_worktree_registry(args.source_repo, args.approve_count))
    except MaterializeError as exc:
        parser.error(str(exc))
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
