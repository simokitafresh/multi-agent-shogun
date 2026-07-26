#!/usr/bin/env python3
"""Contract for canonical memory DB cache identity.

test_necessity: A symlinked fast-deploy import must never derive repository or
cache identity from the disposable deploy root.
"""

import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import threading


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "scripts" / "memory_db_live_insert.py"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_symlink_imports_share_canonical_root_and_cache_path(tmp_path, monkeypatch):
    cache_dir = tmp_path / "cache"
    monkeypatch.setenv("SHOGUN_MEMORY_DB_CACHE_DIR", str(cache_dir))
    monkeypatch.delenv("SHOGUN_MEMORY_DB_CACHE_PATH", raising=False)

    imported = []
    for index in (1, 2):
        deploy_scripts = tmp_path / f".deploy-report-fast-{index}" / "scripts"
        deploy_scripts.mkdir(parents=True)
        linked_module = deploy_scripts / SOURCE.name
        linked_module.symlink_to(SOURCE)
        imported.append(load_module(linked_module, f"memory_db_live_insert_deploy_{index}"))

    expected_root = str(ROOT)
    db_path = str(ROOT / "data" / "multi_agent_shogun_memory.db")
    roots = {module.REPO_ROOT for module in imported}
    cache_paths = {module.memory_db_cache_path(db_path) for module in imported}

    assert roots == {expected_root}
    assert len(cache_paths) == 1
    assert all(".deploy-report-fast" not in path for path in cache_paths)
    assert not cache_dir.exists() or list(cache_dir.iterdir()) == []


def test_normal_import_override_and_cache_read_write_contract(tmp_path, monkeypatch):
    module = load_module(SOURCE, "memory_db_live_insert_canonical")
    db_path = tmp_path / "primary.sqlite"
    with sqlite3.connect(db_path) as conn:
        conn.execute("CREATE TABLE marker(value TEXT)")
        conn.execute("INSERT INTO marker VALUES ('canonical')")

    override = tmp_path / "explicit" / "memory.sqlite"
    monkeypatch.setenv("SHOGUN_MEMORY_DB_CACHE_PATH", str(override))
    assert module.REPO_ROOT == str(ROOT)
    assert module.memory_db_cache_path(str(db_path)) == str(override)

    published = Path(module.create_memory_db_ext4_cache(str(db_path)))
    assert published == override
    with sqlite3.connect(published) as conn:
        assert conn.execute("SELECT value FROM marker").fetchone() == ("canonical",)


def _prepare_source(tmp_path, monkeypatch, name, rows):
    """Source DB plus an isolated ledger and cache path for one refresh."""
    ledger_dir = tmp_path / name / "logs"
    ledger_dir.mkdir(parents=True)
    ledger = ledger_dir / "defense_overhead.jsonl"
    monkeypatch.setenv("DEFENSE_OVERHEAD_LEDGER", str(ledger))
    monkeypatch.setenv("SHOGUN_MEMORY_DB_CACHE_PATH", str(tmp_path / name / "cache.sqlite"))
    db_path = tmp_path / name / "source.sqlite"
    with sqlite3.connect(db_path) as conn:
        conn.execute("CREATE TABLE events(id TEXT)")
        conn.executemany("INSERT INTO events VALUES (?)", [(str(i),) for i in range(rows)])
    return db_path, ledger


def _ledger_rows(ledger: Path, check_id: str):
    if not ledger.exists():
        return []
    rows = [json.loads(line) for line in ledger.read_text(encoding="utf-8").splitlines() if line]
    return [row for row in rows if row.get("check_id") == check_id]


def test_refresh_publishes_two_point_window_into_the_shared_ledger(tmp_path, monkeypatch):
    """test_necessity: one cache refresh must leave both endpoints of its own
    window in the existing defense ledger, so window length and the number of
    source writes that arrived during it are measured values rather than
    values derived from an assumed refresh interval."""
    module = load_module(SOURCE, "memory_db_live_insert_window_pair")
    db_path, ledger = _prepare_source(tmp_path, monkeypatch, "pair", 5)

    module.create_memory_db_ext4_cache(str(db_path))

    rows = _ledger_rows(ledger, "refresh_window")
    assert len(rows) == 2
    assert {row["source"] for row in rows} == {"three_layer_health"}
    begin = next(r for r in rows if ":begin:" in r["event_id"])
    end = next(r for r in rows if ":end:" in r["event_id"])
    group = begin["event_id"].split(":grp-")[1].split(":")[0]
    assert f":grp-{group}" in end["event_id"]
    assert ":rowid-5:" in begin["event_id"] + ":"
    assert ":arrived-0:" in end["event_id"]
    assert begin["wall_ms"] == 0 and end["wall_ms"] >= 0


def test_writes_arriving_during_the_window_are_counted_not_inferred(tmp_path, monkeypatch):
    """test_necessity: the end record must report the count of source rows
    that arrived after the snapshot began, so a gap needs no threshold to be
    interpreted."""
    module = load_module(SOURCE, "memory_db_live_insert_window_arrived")
    db_path, ledger = _prepare_source(tmp_path, monkeypatch, "arrived", 5)

    original_backup = module.create_sqlite_backup

    def backup_with_concurrent_writes(*args, **kwargs):
        result = original_backup(*args, **kwargs)
        with sqlite3.connect(db_path) as conn:
            conn.executemany("INSERT INTO events VALUES (?)", [(str(i),) for i in range(3)])
        return result

    module.create_sqlite_backup = backup_with_concurrent_writes
    module.create_memory_db_ext4_cache(str(db_path))

    end = next(r for r in _ledger_rows(ledger, "refresh_window") if ":end:" in r["event_id"])
    assert ":arrived-3:" in end["event_id"]
    assert ":beginrowid-5:" in end["event_id"] + ":"


def test_recording_failure_never_aborts_cache_publication(tmp_path, monkeypatch):
    """test_necessity: cache creation is a data path; a failure in its own
    instrumentation must not change its outcome."""
    module = load_module(SOURCE, "memory_db_live_insert_window_failopen")
    db_path, ledger = _prepare_source(tmp_path, monkeypatch, "failopen", 4)

    def explode(*args, **kwargs):
        raise RuntimeError("telemetry unavailable")

    module._memory_db_source_max_rowid = explode
    module._record_refresh_window_point = explode

    published = Path(module.create_memory_db_ext4_cache(str(db_path)))

    with sqlite3.connect(published) as conn:
        assert conn.execute("SELECT COUNT(*) FROM events").fetchone() == (4,)
    assert _ledger_rows(ledger, "refresh_window") == []


def test_instrumentation_does_not_change_the_published_cache(tmp_path, monkeypatch):
    """test_necessity: adding observation must leave the same input producing
    the same cache content and the same returned path."""
    module = load_module(SOURCE, "memory_db_live_insert_window_neutral")
    db_path, _ = _prepare_source(tmp_path, monkeypatch, "neutral", 6)

    instrumented = Path(module.create_memory_db_ext4_cache(str(db_path)))
    instrumented_rows = sqlite3.connect(instrumented).execute(
        "SELECT id FROM events ORDER BY id"
    ).fetchall()
    os.unlink(instrumented)

    module._record_refresh_window_point = lambda *args, **kwargs: None
    module._memory_db_source_max_rowid = lambda path: "na"
    silent = Path(module.create_memory_db_ext4_cache(str(db_path)))

    assert silent == instrumented
    assert sqlite3.connect(silent).execute(
        "SELECT id FROM events ORDER BY id"
    ).fetchall() == instrumented_rows


def test_parallel_refreshes_do_not_collapse_into_one_observation(tmp_path, monkeypatch):
    """test_necessity: concurrent refreshes must each leave their own pair of
    records; collapsing two observations into one row would hide a window."""
    module = load_module(SOURCE, "memory_db_live_insert_window_parallel")
    db_path, ledger = _prepare_source(tmp_path, monkeypatch, "parallel", 5)

    errors = []

    def refresh():
        try:
            module.create_memory_db_ext4_cache(str(db_path))
        except Exception as exc:  # pragma: no cover - surfaced via assertion
            errors.append(exc)

    threads = [threading.Thread(target=refresh) for _ in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    assert errors == []
    rows = _ledger_rows(ledger, "refresh_window")
    groups = {row["event_id"].split(":grp-")[1].split(":")[0] for row in rows}
    assert len(rows) == 4
    assert len(groups) == 2
