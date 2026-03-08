#!/usr/bin/env python3
"""
YAML queue slimming utility.

Archives stale non-canonical queue artifacts while preserving the canonical
task/report files used by the current local roster. Adapted from the upstream
multi-agent-shogun implementation for local agent names.
"""

from __future__ import annotations

import sys
import time
from datetime import datetime
from pathlib import Path

import yaml

LOCAL_AGENTS = {
    "karo",
    "sasuke",
    "kirimaru",
    "hayate",
    "kagemaru",
    "hanzo",
    "saizo",
    "kotaro",
    "tobisaru",
}
LEGACY_AGENTS = {f"ashigaru{i}" for i in range(1, 9)} | {"gunshi"}
CANONICAL_TASKS = LOCAL_AGENTS | LEGACY_AGENTS
CANONICAL_REPORTS = {f"{agent}_report" for agent in CANONICAL_TASKS}
IDLE_STUB = {"task": {"status": "idle"}}


def load_yaml(path: Path) -> object:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return yaml.safe_load(handle) or {}
    except FileNotFoundError:
        return {}
    except yaml.YAMLError as exc:
        print(f"Error parsing {path}: {exc}", file=sys.stderr)
        return {}


def save_yaml(path: Path, data: object) -> bool:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8") as handle:
            yaml.dump(
                data,
                handle,
                allow_unicode=True,
                sort_keys=False,
                default_flow_style=False,
            )
        return True
    except Exception as exc:  # pragma: no cover - defensive logging
        print(f"Error writing {path}: {exc}", file=sys.stderr)
        return False


def timestamp() -> str:
    return datetime.now().strftime("%Y%m%d%H%M%S")


def queue_dir() -> Path:
    return Path(__file__).resolve().parent.parent / "queue"


def active_cmd_ids() -> set[str]:
    shogun_file = queue_dir() / "shogun_to_karo.yaml"
    data = load_yaml(shogun_file)
    if not isinstance(data, dict):
        return set()

    key = "commands" if "commands" in data else "queue"
    commands = data.get(key, [])
    if not isinstance(commands, list):
        return set()

    active: set[str] = set()
    for command in commands:
        if not isinstance(command, dict):
            continue
        cmd_id = command.get("id")
        if cmd_id and command.get("status") != "done":
            active.add(str(cmd_id))
    return active


def archive_path(base: Path, src: Path) -> Path:
    candidate = base / src.name
    if candidate.exists():
        candidate = base / f"{src.stem}_{timestamp()}{src.suffix}"
    candidate.parent.mkdir(parents=True, exist_ok=True)
    return candidate


def slim_tasks(dry_run: bool = False) -> bool:
    tasks_dir = queue_dir() / "tasks"
    archive_dir = queue_dir() / "archive" / "tasks"
    if not tasks_dir.exists():
        return True

    for path in sorted(tasks_dir.glob("*.yaml")):
        data = load_yaml(path)
        if not isinstance(data, dict):
            continue

        task = data.get("task", {})
        if not isinstance(task, dict):
            continue

        status = task.get("status")
        if not status:
            continue

        if path.stem in CANONICAL_TASKS:
            if status not in {"done", "completed", "cancelled"}:
                continue
            archived = archive_dir / f"{path.stem}_{timestamp()}.yaml"
            if dry_run:
                print(f"[DRY-RUN] would archive {path} -> {archived}")
                print(f"[DRY-RUN] would reset {path} -> {IDLE_STUB}")
                continue
            if not save_yaml(archived, data):
                return False
            if not save_yaml(path, IDLE_STUB):
                return False
            continue

        if status not in {"done", "cancelled"}:
            continue

        archived = archive_path(archive_dir, path)
        if dry_run:
            print(f"[DRY-RUN] would archive {path} -> {archived}")
            continue
        path.rename(archived)

    return True


def slim_reports(dry_run: bool = False) -> bool:
    reports_dir = queue_dir() / "reports"
    archive_dir = queue_dir() / "archive" / "reports"
    if not reports_dir.exists():
        return True

    active_ids = active_cmd_ids()
    now = time.time()
    for path in sorted(reports_dir.glob("*.yaml")):
        if path.stem in CANONICAL_REPORTS:
            continue

        data = load_yaml(path)
        if not isinstance(data, dict):
            continue

        parent_cmd = data.get("parent_cmd")
        is_stale = now - path.stat().st_mtime >= 86400
        is_active = parent_cmd in active_ids
        if not is_stale or is_active:
            continue

        archived = archive_path(archive_dir, path)
        if dry_run:
            print(f"[DRY-RUN] would archive {path} -> {archived}")
            continue
        path.rename(archived)

    return True


def slim_inbox(agent_id: str, dry_run: bool = False) -> bool:
    inbox_file = queue_dir() / "inbox" / f"{agent_id}.yaml"
    if not inbox_file.exists():
        return True

    data = load_yaml(inbox_file)
    if not isinstance(data, dict):
        return True

    messages = data.get("messages", [])
    if not isinstance(messages, list):
        print(f"Error: messages is not a list in {inbox_file}", file=sys.stderr)
        return False

    unread = [msg for msg in messages if not msg.get("read", False)]
    archived_messages = [msg for msg in messages if msg.get("read", False)]
    if not archived_messages:
        return True

    archive_file = queue_dir() / "archive" / f"inbox_{agent_id}_{timestamp()}.yaml"
    if dry_run:
        print(f"[DRY-RUN] would archive read messages from {inbox_file} -> {archive_file}")
        return True

    if not save_yaml(archive_file, {"messages": archived_messages}):
        return False
    data["messages"] = unread
    return save_yaml(inbox_file, data)


def slim_shogun_to_karo() -> bool:
    shogun_file = queue_dir() / "shogun_to_karo.yaml"
    if not shogun_file.exists():
        return True

    data = load_yaml(shogun_file)
    if not isinstance(data, dict):
        return True

    key = "commands" if "commands" in data else "queue"
    commands = data.get(key, [])
    if not isinstance(commands, list):
        print(f"Error: {shogun_file} has non-list {key}", file=sys.stderr)
        return False

    active = []
    archived = []
    for command in commands:
        if isinstance(command, dict) and command.get("status") in {"done", "cancelled"}:
            archived.append(command)
        else:
            active.append(command)

    if not archived:
        return True

    archive_file = queue_dir() / "archive" / f"shogun_to_karo_{timestamp()}.yaml"
    if not save_yaml(archive_file, {key: archived}):
        return False
    data[key] = active
    return save_yaml(shogun_file, data)


def slim_all_inboxes(dry_run: bool = False) -> bool:
    inbox_dir = queue_dir() / "inbox"
    if not inbox_dir.exists():
        return True
    for path in sorted(inbox_dir.glob("*.yaml")):
        if not slim_inbox(path.stem, dry_run=dry_run):
            return False
    return True


def migrate_legacy_report_archive(dry_run: bool = False) -> bool:
    legacy_dir = queue_dir() / "reports" / "archive"
    if not legacy_dir.exists():
        return True

    target_dir = queue_dir() / "archive" / "reports"
    legacy_files = sorted(legacy_dir.glob("*.yaml"))
    if dry_run:
        print(f"[DRY-RUN] would migrate {len(legacy_files)} legacy report archives")
        return True

    target_dir.mkdir(parents=True, exist_ok=True)
    for path in legacy_files:
        path.rename(target_dir / path.name)
    if not any(legacy_dir.iterdir()):
        legacy_dir.rmdir()
    return True


def parse_args() -> tuple[str, bool]:
    args = [arg for arg in sys.argv[1:] if arg != "--dry-run"]
    dry_run = "--dry-run" in sys.argv[1:]
    if len(args) != 1:
        print("Usage: slim_yaml.py <agent_id> [--dry-run]", file=sys.stderr)
        sys.exit(1)
    return args[0], dry_run


def main() -> int:
    agent_id, dry_run = parse_args()
    (queue_dir() / "archive").mkdir(parents=True, exist_ok=True)

    if agent_id == "karo":
        if not slim_shogun_to_karo():
            return 1
        if not migrate_legacy_report_archive(dry_run=dry_run):
            return 1
        if not slim_tasks(dry_run=dry_run):
            return 1
        if not slim_reports(dry_run=dry_run):
            return 1
        if not slim_all_inboxes(dry_run=dry_run):
            return 1

    if not slim_inbox(agent_id, dry_run=dry_run):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
