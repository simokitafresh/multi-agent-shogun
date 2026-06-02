#!/usr/bin/env python3
"""Non-blocking wrapper for memory_db_live_insert.py.

Operational YAML writes must not wait behind SQLite/NTFS lock convoys. This
wrapper tries one global non-blocking lock; if another live insert is active,
it persists the requested insert as a JSON queue item and exits successfully.
The next wrapper that gets the lock drains a bounded number of queued items.
"""

from __future__ import annotations

import fcntl
import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
LIVE_INSERT = REPO_ROOT / "scripts" / "memory_db_live_insert.py"
QUEUE_DIR = Path(os.environ.get("SHOGUN_MEMORY_DB_LIVE_QUEUE_DIR", REPO_ROOT / "queue" / "memory_db_live_insert_queue"))
LOCK_PATH = Path(os.environ.get("SHOGUN_MEMORY_DB_LIVE_ASYNC_LOCK", "/tmp/shogun_memory_db_live_insert_async.lock"))
TIMEOUT_SECONDS = float(os.environ.get("SHOGUN_MEMORY_DB_LIVE_INSERT_TIMEOUT", "3"))
DRAIN_LIMIT = int(os.environ.get("SHOGUN_MEMORY_DB_LIVE_DRAIN_LIMIT", "10"))


def enqueue(args: list[str]) -> None:
    QUEUE_DIR.mkdir(parents=True, exist_ok=True)
    now = time.strftime("%Y%m%dT%H%M%S", time.gmtime())
    path = QUEUE_DIR / f"{now}_{uuid.uuid4().hex}.json"
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps({"args": args}, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, path)


def run_insert(args: list[str]) -> bool:
    try:
        subprocess.run(
            [sys.executable, str(LIVE_INSERT), *args],
            cwd=str(REPO_ROOT),
            timeout=TIMEOUT_SECONDS,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except subprocess.TimeoutExpired:
        return False


def queued_items() -> list[Path]:
    if not QUEUE_DIR.is_dir():
        return []
    return sorted(QUEUE_DIR.glob("*.json"))[: max(DRAIN_LIMIT, 0)]


def drain_queue() -> None:
    for path in queued_items():
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            args = payload.get("args")
            if not isinstance(args, list) or not all(isinstance(item, str) for item in args):
                path.unlink(missing_ok=True)
                continue
            if run_insert(args):
                path.unlink(missing_ok=True)
        except Exception:
            # Corrupt queue items must not block future live inserts forever.
            try:
                path.rename(path.with_suffix(".bad"))
            except OSError:
                pass


def main(argv: list[str]) -> int:
    if not LIVE_INSERT.is_file():
        return 0

    LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOCK_PATH.open("w", encoding="utf-8") as lock_handle:
        try:
            fcntl.flock(lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            enqueue(argv)
            return 0

        drain_queue()
        if argv:
            if not run_insert(argv):
                enqueue(argv)
        return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
