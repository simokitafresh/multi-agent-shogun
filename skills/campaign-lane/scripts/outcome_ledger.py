#!/usr/bin/env python3
"""Append campaign outcomes with flock and atomic publication."""
from __future__ import annotations

import fcntl
import json
import os
import tempfile
from pathlib import Path

from .contracts import OUTCOME_SCHEMA, canonical_json


class OutcomeContractError(ValueError):
    pass


def validate_outcome(row: dict) -> None:
    missing = [key for key in OUTCOME_SCHEMA["required"] if row.get(key) in (None, "")]
    if missing:
        raise OutcomeContractError(f"missing outcome fields: {','.join(missing)}")
    if row["decision"] not in OUTCOME_SCHEMA["decision"]:
        raise OutcomeContractError("invalid decision")
    if not isinstance(row["round"], int) or isinstance(row["round"], bool) or row["round"] <= 0:
        raise OutcomeContractError("round must be positive integer")


def append_outcome(path: str | Path, row: dict) -> None:
    validate_outcome(row)
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    lock_path = destination.with_suffix(destination.suffix + ".lock")
    with lock_path.open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        rows = []
        if destination.exists():
            for number, line in enumerate(destination.read_text().splitlines(), 1):
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError as exc:
                    raise OutcomeContractError(f"invalid ledger line {number}") from exc
        key = tuple(row[item] for item in OUTCOME_SCHEMA["key"])
        if key in {tuple(item.get(field) for field in OUTCOME_SCHEMA["key"]) for item in rows}:
            raise OutcomeContractError("duplicate outcome key")
        rows.append(row)
        fd, temporary = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
        try:
            with os.fdopen(fd, "w") as handle:
                for item in rows:
                    handle.write(canonical_json(item) + "\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, destination)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

