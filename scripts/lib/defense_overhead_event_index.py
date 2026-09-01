#!/usr/bin/env python3
"""Exact event_id sidecar for the append-only defense overhead ledger."""

from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import sys
from pathlib import Path


SCHEMA_VERSION = "2"


def connect(path: Path, building: bool = False) -> sqlite3.Connection:
    connection = sqlite3.connect(path, timeout=5)
    if building:
        connection.execute("PRAGMA journal_mode=OFF")
        connection.execute("PRAGMA synchronous=OFF")
    else:
        connection.execute("PRAGMA journal_mode=DELETE")
        connection.execute("PRAGMA synchronous=FULL")
    return connection


def create_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        CREATE TABLE events(event_id TEXT PRIMARY KEY) WITHOUT ROWID;
        CREATE TABLE anomalies(
            ledger_device INTEGER NOT NULL,
            ledger_inode INTEGER NOT NULL,
            ledger_offset INTEGER NOT NULL,
            row_length INTEGER NOT NULL,
            sha256 TEXT NOT NULL,
            reason TEXT NOT NULL,
            PRIMARY KEY(ledger_device, ledger_inode, ledger_offset, row_length, sha256)
        ) WITHOUT ROWID;
        CREATE TABLE state(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
        """
    )


def read_state(connection: sqlite3.Connection) -> dict[str, str]:
    return dict(connection.execute("SELECT key, value FROM state"))


def write_state(
    connection: sqlite3.Connection, *, device: int, inode: int, offset: int
) -> None:
    values = {
        "schema_version": SCHEMA_VERSION,
        "ledger_device": str(device),
        "ledger_inode": str(inode),
        "ledger_offset": str(offset),
    }
    connection.executemany(
        "INSERT OR REPLACE INTO state(key, value) VALUES (?, ?)", values.items()
    )


def state_matches_ledger(state: dict[str, str], ledger: Path) -> bool:
    try:
        if state.get("schema_version") != SCHEMA_VERSION:
            return False
        offset = int(state["ledger_offset"])
        if not ledger.exists():
            return (
                int(state["ledger_device"]) == 0
                and int(state["ledger_inode"]) == 0
                and offset == 0
            )
        stat = ledger.stat()
        return (
            int(state["ledger_device"]) == stat.st_dev
            and int(state["ledger_inode"]) == stat.st_ino
            and 0 <= offset <= stat.st_size
        )
    except (KeyError, OSError, TypeError, ValueError, sqlite3.Error):
        return False


def parse_event_id(raw: bytes) -> tuple[str | None, str | None]:
    try:
        row = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        return None, f"invalid_json:{type(exc).__name__}"
    if not isinstance(row, dict):
        return None, "row_not_object"
    event_id = row.get("event_id")
    if not isinstance(event_id, str) or not event_id:
        return None, "missing_event_id"
    return event_id, None


def event_id_from_line(raw: bytes) -> str | None:
    """Return an indexable event id without making one bad row stop a scan."""
    event_id, _ = parse_event_id(raw)
    return event_id


def record_anomaly(
    connection: sqlite3.Connection,
    *,
    device: int,
    inode: int,
    offset: int,
    raw: bytes,
    reason: str,
) -> None:
    connection.execute(
        """
        INSERT OR IGNORE INTO anomalies(
            ledger_device, ledger_inode, ledger_offset, row_length, sha256, reason
        ) VALUES (?, ?, ?, ?, ?, ?)
        """,
        (device, inode, offset, len(raw), hashlib.sha256(raw).hexdigest(), reason),
    )


def iter_prefix_records(ledger: Path, snapshot_size: int):
    """Yield complete snapshot rows with byte offsets and anomaly classification."""
    with ledger.open("rb") as stream:
        remaining = snapshot_size
        carry = b""
        offset = 0
        while remaining:
            chunk = stream.read(min(8 * 1024 * 1024, remaining))
            if not chunk:
                raise ValueError("ledger shortened during sidecar build")
            remaining -= len(chunk)
            rows = (carry + chunk).split(b"\n")
            carry = rows.pop()
            for raw in rows:
                event_id, reason = parse_event_id(raw)
                yield offset, raw, event_id, reason
                offset += len(raw) + 1
        if carry:
            raise ValueError("ledger snapshot ended in a partial row")


def iter_prefix_rows(ledger: Path, snapshot_size: int):
    for _, _, event_id, _ in iter_prefix_records(ledger, snapshot_size):
        if event_id is not None:
            yield event_id


def prepare(ledger: Path, index: Path) -> int:
    if index.exists():
        try:
            connection = connect(index)
            valid = state_matches_ledger(read_state(connection), ledger)
            connection.close()
            if valid:
                return 0
        except sqlite3.Error:
            pass

    index.parent.mkdir(parents=True, exist_ok=True)
    temporary = index.with_name(f"{index.name}.tmp.{os.getpid()}")
    try:
        temporary.unlink(missing_ok=True)
        connection = connect(temporary, building=True)
        create_schema(connection)
        if ledger.exists():
            stat = ledger.stat()
            snapshot_size = stat.st_size
            batch: list[tuple[str]] = []
            for offset, raw, event_id, reason in iter_prefix_records(
                ledger, snapshot_size
            ):
                if event_id is None:
                    record_anomaly(
                        connection,
                        device=stat.st_dev,
                        inode=stat.st_ino,
                        offset=offset,
                        raw=raw,
                        reason=reason or "unindexable_row",
                    )
                else:
                    batch.append((event_id,))
                if len(batch) >= 4096:
                    connection.executemany(
                        "INSERT OR IGNORE INTO events(event_id) VALUES (?)", batch
                    )
                    batch.clear()
            if batch:
                connection.executemany(
                    "INSERT OR IGNORE INTO events(event_id) VALUES (?)", batch
                )
            write_state(
                connection,
                device=stat.st_dev,
                inode=stat.st_ino,
                offset=snapshot_size,
            )
        else:
            write_state(connection, device=0, inode=0, offset=0)
        connection.commit()
        if connection.execute("PRAGMA quick_check").fetchone() != ("ok",):
            raise sqlite3.DatabaseError("sidecar quick_check failed")
        connection.close()
        os.replace(temporary, index)
        return 0
    except (OSError, sqlite3.Error, ValueError) as exc:
        print(f"defense_overhead index prepare failed: {exc}", file=sys.stderr)
        try:
            connection.close()
        except (NameError, sqlite3.Error):
            pass
        temporary.unlink(missing_ok=True)
        return 3


def reconcile_tail(
    connection: sqlite3.Connection, ledger: Path, state: dict[str, str]
) -> tuple[int, int, int]:
    if ledger.exists():
        stat = ledger.stat()
        if int(state.get("ledger_device", -1)) == 0 and int(
            state.get("ledger_inode", -1)
        ) == 0:
            offset = 0
        elif not state_matches_ledger(state, ledger):
            raise ValueError("sidecar identity/offset does not match ledger")
        else:
            offset = int(state["ledger_offset"])
        with ledger.open("rb") as stream:
            if offset:
                stream.seek(offset - 1)
                if stream.read(1) != b"\n":
                    raise ValueError("sidecar offset is not at a row boundary")
            stream.seek(offset)
            rows = []
            for raw in stream:
                if not raw.endswith(b"\n"):
                    raise ValueError("ledger tail contains a partial row")
                row_offset = stream.tell() - len(raw)
                event_id, reason = parse_event_id(raw[:-1])
                if event_id is not None:
                    rows.append((event_id,))
                else:
                    record_anomaly(
                        connection,
                        device=stat.st_dev,
                        inode=stat.st_ino,
                        offset=row_offset,
                        raw=raw[:-1],
                        reason=reason or "unindexable_row",
                    )
            if rows:
                connection.executemany(
                    "INSERT OR IGNORE INTO events(event_id) VALUES (?)", rows
                )
            offset = stream.tell()
        return stat.st_dev, stat.st_ino, offset
    if not state_matches_ledger(state, ledger):
        raise ValueError("sidecar expects a missing ledger with non-empty state")
    return 0, 0, 0


def append(ledger: Path, index: Path, line: str, event_id: str) -> int:
    try:
        connection = connect(index)
        connection.execute("BEGIN IMMEDIATE")
        state = read_state(connection)
        device, inode, offset = reconcile_tail(connection, ledger, state)
        if connection.execute(
            "SELECT 1 FROM events WHERE event_id = ?", (event_id,)
        ).fetchone():
            write_state(connection, device=device, inode=inode, offset=offset)
            connection.commit()
            connection.close()
            return 4

        with ledger.open("ab") as stream:
            stream.write(line.encode("utf-8") + b"\n")
            stream.flush()
            offset = stream.tell()
        stat = ledger.stat()
        connection.execute("INSERT INTO events(event_id) VALUES (?)", (event_id,))
        write_state(
            connection, device=stat.st_dev, inode=stat.st_ino, offset=offset
        )
        connection.commit()
        connection.close()
        return 0
    except (OSError, sqlite3.Error, UnicodeError, ValueError) as exc:
        print(f"defense_overhead index append failed: {exc}", file=sys.stderr)
        try:
            connection.rollback()
            connection.close()
        except (NameError, sqlite3.Error):
            pass
        return 3


def main() -> int:
    if len(sys.argv) < 4:
        return 3
    command, ledger_raw, index_raw = sys.argv[1:4]
    ledger, index = Path(ledger_raw), Path(index_raw)
    if command == "prepare" and len(sys.argv) == 4:
        return prepare(ledger, index)
    if command == "append" and len(sys.argv) == 6:
        return append(ledger, index, sys.argv[4], sys.argv[5])
    return 3


if __name__ == "__main__":
    raise SystemExit(main())
