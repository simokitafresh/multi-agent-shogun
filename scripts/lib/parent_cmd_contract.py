#!/usr/bin/env python3
"""Fail-closed parent SSOT/purpose/AC coverage validation for numbered cmds."""
from __future__ import annotations

import argparse, glob, os, re, sys
from pathlib import Path
import yaml


def load(path: Path):
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception:
        return {}


def command_from(data, cmd_id):
    commands = data.get("commands", data)
    if isinstance(commands, dict):
        item = commands.get(cmd_id)
        return item if isinstance(item, dict) else None
    if isinstance(commands, list):
        return next((x for x in commands if isinstance(x, dict) and str(x.get("id")) == cmd_id), None)
    return None


def find_parent(root: Path, cmd_id: str):
    paths = [root / "queue/shogun_to_karo.yaml"]
    paths += [Path(p) for p in sorted(glob.glob(str(root / f"queue/archive/cmds/{cmd_id}_*.yaml")), reverse=True)]
    for path in paths:
        if path.is_file():
            item = command_from(load(path), cmd_id)
            if item is not None:
                return item, path
    return None, None


def ac_ids(value):
    result = []
    for i, item in enumerate(value or [], 1):
        if isinstance(item, dict):
            result.append(str(item.get("id") or f"AC{i}"))
        else:
            result.append(f"AC{i}")
    return result


def validate(root: Path, cmd_id: str):
    if not re.fullmatch(r"cmd_\d+", cmd_id):
        return True, "direct/non-numbered cmd exempt"
    parent, source = find_parent(root, cmd_id)
    if parent is None:
        return False, "parent_ssot_missing"
    purpose = str(parent.get("purpose") or parent.get("title") or "").strip()
    expected = set(ac_ids(parent.get("acceptance_criteria")))
    if not purpose or not expected:
        return False, "parent_contract_incomplete"
    tasks = []
    for path in sorted((root / "queue/tasks").glob("*.yaml")):
        task = load(path).get("task") or {}
        if str(task.get("parent_cmd") or "").strip() == cmd_id:
            tasks.append((path, task))
    if not tasks:
        return False, "parent_tasks_missing"
    if not any(str(t.get("purpose") or "").strip() == purpose for _, t in tasks):
        return False, "parent_purpose_unmatched"
    covered = set()
    for path in list((root / "queue/reports").glob("*.yaml")) + list((root / "queue/archive/reports").glob("*.yaml")):
        report = load(path)
        if str(report.get("parent_cmd") or "").strip() != cmd_id:
            continue
        checks = report.get("binary_checks") or {}
        if isinstance(checks, dict):
            for key, entries in checks.items():
                if key in expected and isinstance(entries, list) and entries and all(
                    isinstance(x, dict) and (x.get("result") is True or str(x.get("result", "")).lower() == "yes") for x in entries
                ):
                    covered.add(key)
    missing = sorted(expected - covered)
    if missing:
        return False, "parent_ac_uncovered:" + ",".join(missing)
    return True, f"parent_contract_ok source={source} ac={len(expected)}"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("cmd_id")
    p.add_argument("--root", default=os.environ.get("PROJECT_ROOT", Path(__file__).resolve().parents[2]))
    args = p.parse_args()
    ok, detail = validate(Path(args.root), args.cmd_id)
    print(("OK: " if ok else "BLOCK: ") + detail)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
