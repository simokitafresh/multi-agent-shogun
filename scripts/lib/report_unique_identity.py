#!/usr/bin/env python3
"""Canonical, immutable identity for report YAML files."""

from __future__ import annotations

import argparse
import hashlib
import os
import uuid
from pathlib import Path

import yaml


VERSION = 2


def canonical_path(path: str, root: str) -> str:
    resolved = Path(path)
    if not resolved.is_absolute():
        resolved = Path(root) / resolved
    resolved = resolved.resolve(strict=False)
    root_path = Path(root).resolve(strict=False)
    try:
        return resolved.relative_to(root_path).as_posix()
    except ValueError:
        return resolved.as_posix()


def fallback_id(path: str, root: str) -> str:
    rel = canonical_path(path, root)
    return "legacy-" + hashlib.sha256(("report-v1\0" + rel).encode()).hexdigest()


def load(path: str) -> dict:
    with open(path, encoding="utf-8") as stream:
        value = yaml.safe_load(stream) or {}
    if not isinstance(value, dict):
        raise ValueError("report YAML must be a mapping")
    return value


def resolve(path: str, root: str) -> tuple[str, int]:
    data = load(path)
    report_id = str(data.get("report_id") or "").strip()
    version = int(data.get("report_identity_version") or 1)
    if version >= VERSION and not report_id:
        raise ValueError("v2 report is missing report_id")
    return (report_id or fallback_id(path, root), version)


def reject_reuse(path: str, root: str, report_id: str) -> None:
    root_path = Path(root).resolve(strict=False)
    owner = canonical_path(path, root)
    # Archive movement is lifecycle state, not a new identity owner.
    if owner.startswith("queue/archive/reports/"):
        owner = "queue/reports/" + owner.rsplit("/", 1)[-1]
    registry = root_path / "queue/report-identity-registry"
    registry.mkdir(parents=True, exist_ok=True)
    claim = registry / (hashlib.sha256(report_id.encode()).hexdigest() + ".path")
    payload = (owner + "\n").encode()
    try:
        fd = os.open(claim, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        existing = claim.read_text(encoding="utf-8").strip()
        if existing != owner:
            raise ValueError(f"report_id reused by another report: {existing}")
        return
    try:
        os.write(fd, payload)
        os.fsync(fd)
    finally:
        os.close(fd)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("new", "fallback", "resolve", "verify"))
    parser.add_argument("--path", required=True)
    parser.add_argument("--root", default=os.getcwd())
    parser.add_argument("--task")
    args = parser.parse_args()

    if args.command == "new":
        print(f"rpt-{uuid.uuid4()}")
        return 0
    if args.command == "fallback":
        print(f"{fallback_id(args.path, args.root)}\t1\t{canonical_path(args.path, args.root)}")
        return 0

    report_id, version = resolve(args.path, args.root)
    if args.command == "verify" and args.task:
        task = load(args.task).get("task") or load(args.task)
        task_id = str(task.get("report_id") or "").strip()
        task_version = int(task.get("report_identity_version") or 1)
        if version >= VERSION or task_version >= VERSION:
            if version != VERSION or task_version != VERSION or not task_id or task_id != report_id:
                raise ValueError("v2 task/report identity missing or mismatched")
            reject_reuse(args.path, args.root, report_id)
    print(f"{report_id}\t{version}\t{canonical_path(args.path, args.root)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, yaml.YAMLError) as exc:
        print(f"BLOCK: {exc}", file=__import__("sys").stderr)
        raise SystemExit(2)
