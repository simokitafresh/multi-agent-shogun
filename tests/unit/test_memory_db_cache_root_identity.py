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
import time


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


def _prepare_appendable_source(tmp_path, monkeypatch, name):
    """Create the production event shape plus append-only child projections."""
    ledger_dir = tmp_path / name / "logs"
    ledger_dir.mkdir(parents=True)
    ledger = ledger_dir / "defense_overhead.jsonl"
    monkeypatch.setenv("DEFENSE_OVERHEAD_LEDGER", str(ledger))
    monkeypatch.setenv("SHOGUN_MEMORY_DB_CACHE_PATH", str(tmp_path / name / "cache.sqlite"))
    db_path = tmp_path / name / "source.sqlite"
    with sqlite3.connect(db_path) as conn:
        conn.execute(
            """
            CREATE TABLE events(
                id TEXT PRIMARY KEY, ts TEXT, event_type TEXT, agent TEXT,
                target TEXT, direction TEXT, summary TEXT, detail TEXT,
                session_id TEXT, cmd_id TEXT, concepts TEXT, source_file TEXT,
                parent_event_id INTEGER, importance TEXT, confidence TEXT,
                freshness TEXT, source_type TEXT, state TEXT, occurred_at TEXT,
                recorded_at TEXT, updated_at TEXT, raw_content TEXT, skill TEXT
            )
            """
        )
        conn.execute(
            "CREATE TABLE event_concepts(event_id TEXT, concept_name TEXT, relevance_score REAL)"
        )
        conn.execute(
            "CREATE TABLE event_links(source_event_id TEXT, target_concept TEXT, link_type TEXT)"
        )
        for index in range(1, 4):
            conn.execute(
                "INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (
                    f"event-{index}", "2026-08-04T19:00:00", "bulletin", "saizo",
                    "", "info", f"summary-{index}", f"detail-{index}", "", "", "[]", "",
                    None, "normal", "medium", "current", "fact", "raw", None,
                    "2026-08-04T19:00:00", "2026-08-04T19:00:00", f"raw-{index}", "",
                ),
            )
        conn.executemany(
            "INSERT INTO event_concepts VALUES (?,?,?)",
            [(f"event-{index}", f"concept-{index}", 1.0) for index in range(1, 4)],
        )
        conn.executemany(
            "INSERT INTO event_links VALUES (?,?,?)",
            [(f"event-{index}", f"link-{index}", "obsidian") for index in range(1, 4)],
        )
        conn.execute(
            """
            CREATE VIRTUAL TABLE events_fts USING fts5(
                summary, detail, content='events', content_rowid='rowid', tokenize='trigram'
            )
            """
        )
        conn.execute(
            "INSERT INTO events_fts(rowid, summary, detail) SELECT rowid, summary, detail FROM events"
        )
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


def test_append_only_refresh_uses_atomic_incremental_snapshot(tmp_path, monkeypatch):
    """test_necessity: a proven append-only source change must update the
    published cache without re-reading the canonical full database, while the
    returned cache remains complete for events and child projections."""
    module = load_module(SOURCE, "memory_db_live_insert_incremental_append")
    db_path, ledger = _prepare_appendable_source(tmp_path, monkeypatch, "incremental")
    monkeypatch.setenv("SHOGUN_MEMORY_DB_INCREMENTAL_MIN_BYTES", "0")
    monkeypatch.setenv("SHOGUN_MEMORY_DB_INCREMENTAL_PREFIX_VERIFY_MAX_BYTES", "0")
    published = Path(module.create_memory_db_ext4_cache(str(db_path)))

    with sqlite3.connect(db_path) as conn:
        conn.execute(
            "INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                "event-4", "2026-08-04T19:01:00", "bulletin", "saizo", "", "info",
                "summary-4", "detail-4", "", "", "[]", "", None, "normal", "medium",
                "current", "fact", "raw", None, "2026-08-04T19:01:00",
                "2026-08-04T19:01:00", "raw-4", "",
            ),
        )
        conn.execute("INSERT INTO event_concepts VALUES (?,?,?)", ("event-4", "concept-4", 1.0))
        conn.execute("INSERT INTO event_links VALUES (?,?,?)", ("event-4", "link-4", "obsidian"))

    def full_copy_forbidden(*args, **kwargs):
        raise AssertionError("append-only refresh unexpectedly used full source copy")

    module.create_sqlite_backup = full_copy_forbidden
    module._hot_copy_snapshot = full_copy_forbidden
    module.require_cache_backup_healthy = full_copy_forbidden
    published = Path(module.create_memory_db_ext4_cache(str(db_path)))

    with sqlite3.connect(published) as conn:
        assert conn.execute("SELECT COUNT(*) FROM events").fetchone() == (4,)
        assert conn.execute("SELECT COUNT(*) FROM event_concepts").fetchone() == (4,)
        assert conn.execute("SELECT COUNT(*) FROM event_links").fetchone() == (4,)
        assert conn.execute("SELECT detail FROM events WHERE id='event-4'").fetchone() == ("detail-4",)
    incremental_rows = _ledger_rows(ledger, "refresh_incremental_event")
    assert len(incremental_rows) == 1
    assert ":event-event-4:" in incremental_rows[0]["event_id"]


def test_continuous_cache_sync_calls_are_debounced(tmp_path, monkeypatch):
    """test_necessity: a burst of live inserts must not start one cache
    refresh per insert; a later call after the debounce window remains able to
    refresh, so coalescing cannot strand the final suffix forever."""
    module = load_module(SOURCE, "memory_db_live_insert_debounce")
    db_path, _ = _prepare_source(tmp_path, monkeypatch, "debounce", 2)
    monkeypatch.setenv("SHOGUN_MEMORY_DB_CACHE_DEBOUNCE_SEC", "0.05")
    calls = []
    original = module.create_memory_db_ext4_cache

    def counted(path):
        calls.append(path)
        return original(path)

    module.create_memory_db_ext4_cache = counted
    module.sync_memory_db_ext4_cache(str(db_path))
    module.sync_memory_db_ext4_cache(str(db_path))
    assert len(calls) == 1
    time.sleep(0.06)
    module.sync_memory_db_ext4_cache(str(db_path))
    assert len(calls) == 2


def test_routine_backup_retention_is_two_generations(tmp_path):
    """test_necessity: automatic rotation must retain exactly the two newest
    routine generations; older backups remain available for the separate
    aggregate archive plan rather than being silently treated as recovery
    generations."""
    module = load_module(SOURCE, "memory_db_live_insert_retention")
    assert module.ROUTINE_BACKUP_KEEP_RECENT == 2
    assert module.ROUTINE_BACKUP_KEEP_DAILY_DAYS == 0


def test_prefix_mutation_forces_full_snapshot_fallback(tmp_path, monkeypatch):
    """test_necessity: an old-row mutation must never be treated as an
    append-only delta; uncertain provenance falls back to the existing full
    snapshot and integrity path."""
    module = load_module(SOURCE, "memory_db_live_insert_incremental_fallback")
    db_path, ledger = _prepare_appendable_source(tmp_path, monkeypatch, "fallback")
    module.create_memory_db_ext4_cache(str(db_path))

    with sqlite3.connect(db_path) as conn:
        conn.execute("UPDATE events SET updated_at = ? WHERE id = ?", ("2026-08-04T19:02:00", "event-1"))
        conn.execute(
            "INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                "event-4", "2026-08-04T19:03:00", "bulletin", "saizo", "", "info",
                "summary-4", "detail-4", "", "", "[]", "", None, "normal", "medium",
                "current", "fact", "raw", None, "2026-08-04T19:03:00",
                "2026-08-04T19:03:00", "raw-4", "",
            ),
        )

    original_backup = module.create_sqlite_backup
    calls = []

    def counted_full_copy(*args, **kwargs):
        calls.append(True)
        return original_backup(*args, **kwargs)

    module.create_sqlite_backup = counted_full_copy
    published = Path(module.create_memory_db_ext4_cache(str(db_path)))

    assert len(calls) == 1
    with sqlite3.connect(published) as conn:
        assert conn.execute("SELECT COUNT(*) FROM events").fetchone() == (4,)
    fallback_rows = _ledger_rows(ledger, "refresh_fallback")
    assert len(fallback_rows) == 1
    assert ":event-event-4:" in fallback_rows[0]["event_id"]
    assert "reason-DatabaseError_source_prefix_content_changed" in fallback_rows[0]["event_id"]
