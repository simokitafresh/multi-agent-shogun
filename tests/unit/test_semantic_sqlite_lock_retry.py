import importlib.util
import sqlite3
import threading
import time
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("semantic_index_lock_test", ROOT / "scripts/semantic_index.py")
semantic_index = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(semantic_index)


def make_db(tmp_path: Path) -> Path:
    tmp_path.mkdir(parents=True, exist_ok=True)
    db = tmp_path / "memory.db"
    with sqlite3.connect(db) as conn:
        conn.execute("CREATE TABLE sample(value INTEGER)")
        conn.execute("INSERT INTO sample VALUES (1)")
    return db


def hold_exclusive(db: Path):
    conn = sqlite3.connect(db, timeout=0, check_same_thread=False)
    conn.execute("BEGIN EXCLUSIVE")
    conn.execute("UPDATE sample SET value = value")
    return conn


def test_short_exclusive_lock_recovers_twenty_of_twenty(tmp_path, monkeypatch):
    monkeypatch.setattr(semantic_index, "SQLITE_READ_BUSY_TIMEOUT_MS", 5)
    monkeypatch.setattr(semantic_index, "SQLITE_READ_RETRY_DEADLINE_MS", 500)
    successes = 0
    lock_errors = 0
    for _ in range(20):
        db = make_db(tmp_path / str(successes))
        locker = hold_exclusive(db)
        release = threading.Thread(target=lambda: (time.sleep(0.2), locker.rollback(), locker.close()))
        release.start()
        try:
            with semantic_index.memory_db_read_connection(db) as conn:
                assert conn.execute("SELECT value FROM sample").fetchone()[0] == 1
            successes += 1
        except sqlite3.OperationalError as exc:
            lock_errors += "locked" in str(exc).lower()
            raise
        finally:
            release.join(timeout=1)
            assert not release.is_alive()
    assert (successes, lock_errors) == (20, 0)


def test_permanent_lock_has_bounded_diagnostic(tmp_path, monkeypatch):
    db = make_db(tmp_path)
    locker = hold_exclusive(db)
    monkeypatch.setattr(semantic_index, "SQLITE_READ_BUSY_TIMEOUT_MS", 5)
    monkeypatch.setattr(semantic_index, "SQLITE_READ_RETRY_DEADLINE_MS", 80)
    started = time.monotonic()
    try:
        with semantic_index.memory_db_read_connection(db) as conn:
            with pytest.raises(RuntimeError, match="lock deadline exceeded after 80ms"):
                conn.execute("SELECT value FROM sample").fetchone()
    finally:
        locker.rollback()
        locker.close()
    assert 0.08 <= time.monotonic() - started < 0.35


def test_uncontended_read_succeeds(tmp_path):
    db = make_db(tmp_path)
    with semantic_index.memory_db_read_connection(db) as conn:
        assert conn.execute("SELECT value FROM sample").fetchone()[0] == 1


def test_non_lock_operational_error_keeps_original_meaning(tmp_path):
    db = make_db(tmp_path)
    with semantic_index.memory_db_read_connection(db) as conn:
        started = time.monotonic()
        with pytest.raises(sqlite3.OperationalError, match="no such table") as caught:
            conn.execute("SELECT * FROM missing_table")
    assert "lock deadline" not in str(caught.value)
    assert time.monotonic() - started < 0.05
