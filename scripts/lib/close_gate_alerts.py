#!/usr/bin/env python3
"""Close gate alerts whose gate/check implementation was changed by a cmd."""

from __future__ import annotations

import argparse
import fcntl
import os
from pathlib import Path
import re
import tempfile

import yaml


def _normalize(path: str) -> str:
    normalized = path.strip().replace("\\", "/")
    while normalized.startswith("./"):
        normalized = normalized[2:]
    return normalized


def _matches(alert: dict, changed_files: list[str]) -> bool:
    gate = str(alert.get("gate") or "").strip().lower().replace("-", "_")
    detail = str(alert.get("alert_detail") or "").lower().replace("\\", "/")
    if not gate:
        return False

    for raw_path in changed_files:
        path = _normalize(raw_path).lower()
        if not path:
            continue
        basename = Path(path).name
        stem = Path(basename).stem.replace("-", "_")

        # Gate implementation names use either gate_<gate>.sh or <gate>.sh.
        if stem in {gate, f"gate_{gate}"}:
            return True

        # Some alerts identify the failing check by its concrete file.  Require
        # an exact path/basename mention; broad token overlap would close
        # unrelated historical alerts.
        if path in detail or (basename and basename in detail):
            return True
    return False


def close_alerts(alerts_path: Path, cmd_id: str, changed_files: list[str]) -> int:
    alerts_path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = alerts_path.with_suffix(alerts_path.suffix + ".lock")
    with lock_path.open("a+", encoding="utf-8") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        if not alerts_path.exists():
            return 0
        with alerts_path.open(encoding="utf-8") as handle:
            original = handle.read()
        document = yaml.safe_load(original) or {}
        alerts = document.get("alerts") if isinstance(document, dict) else None
        if not isinstance(alerts, list):
            return 0

        closed_ids: list[str] = []
        for alert in alerts:
            if not isinstance(alert, dict) or alert.get("improvement_done") is True:
                continue
            if _matches(alert, changed_files):
                alert_id = str(alert.get("alert_id") or "").strip()
                if alert_id:
                    closed_ids.append(alert_id)

        if not closed_ids:
            return 0

        updated = original
        for alert_id in closed_ids:
            block_pattern = re.compile(
                rf"(?ms)(^  - alert_id: {re.escape(alert_id)}\s*$)(.*?)(?=^  - alert_id: |\Z)"
            )
            match = block_pattern.search(updated)
            if not match:
                continue
            block = match.group(0)
            block = re.sub(
                r"(?m)^    investigation_cmd:.*$",
                f"    investigation_cmd: {cmd_id}",
                block,
                count=1,
            )
            block = re.sub(
                r"(?m)^    improvement_done:.*$",
                "    improvement_done: true",
                block,
                count=1,
            )
            updated = updated[: match.start()] + block + updated[match.end() :]

        fd, temp_name = tempfile.mkstemp(
            prefix=f".{alerts_path.name}.", dir=str(alerts_path.parent), text=True
        )
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(updated)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temp_name, alerts_path)
        finally:
            if os.path.exists(temp_name):
                os.unlink(temp_name)
        return len(closed_ids)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--alerts", required=True, type=Path)
    parser.add_argument("--cmd-id", required=True)
    parser.add_argument("files", nargs="*")
    args = parser.parse_args()
    print(close_alerts(args.alerts, args.cmd_id, args.files))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
