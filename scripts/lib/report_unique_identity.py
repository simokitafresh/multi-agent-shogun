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
    current = Path(path).resolve(strict=False)
    root_path = Path(root).resolve(strict=False)
    matches = []
    for directory in (root_path / "queue/reports", root_path / "queue/archive/reports"):
        if not directory.is_dir():
            continue
        for candidate in directory.glob("*.yaml"):
            if candidate.resolve(strict=False) == current:
                continue
            try:
                if str(load(str(candidate)).get("report_id") or "").strip() == report_id:
                    matches.append(canonical_path(str(candidate), root))
            except (OSError, ValueError, yaml.YAMLError):
                continue
    if matches:
        raise ValueError(f"report_id reused by another report: {matches[0]}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("new", "resolve", "verify"))
    parser.add_argument("--path", required=True)
    parser.add_argument("--root", default=os.getcwd())
    parser.add_argument("--task")
    args = parser.parse_args()

    if args.command == "new":
        print(f"rpt-{uuid.uuid4()}")
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
