"""test_necessity: preserve lesson boost parity while forbidding a second SQLite snapshot copy."""

from concurrent.futures import ThreadPoolExecutor
import importlib.util
import sqlite3
from pathlib import Path
import time


MODULE_PATH = Path(__file__).parents[2] / "scripts/lib/deploy_task_lesson_memory_boost_fast.py"
SPEC = importlib.util.spec_from_file_location("memory_boost_fast", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


def seed(path: Path, extra: bool = False) -> None:
    with sqlite3.connect(path) as conn:
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS events(
                id TEXT PRIMARY KEY, event_id TEXT UNIQUE, event_type TEXT,
                summary TEXT, detail TEXT, concepts TEXT, cmd_id TEXT, ts TEXT
            );
            CREATE TABLE IF NOT EXISTS event_concepts(
                event_id TEXT, concept_name TEXT, relevance_score REAL
            );
            DELETE FROM event_concepts; DELETE FROM events;
            INSERT INTO events VALUES
              ('e1','e1','knowledge','alpha note','no lesson','','cmd_1','2026-01-01'),
              ('e2','e2','lesson','L020 applied','detail L021','','cmd_2','2026-01-03'),
              ('e3','e3','lesson','beta lesson','embedded L300','','cmd_3','2026-01-02');
            INSERT INTO event_concepts VALUES
              ('e1','alpha',1.0), ('e2','alpha',2.0), ('e3','beta',2.5);
        """)
        if extra:
            conn.execute(
                "INSERT INTO events VALUES (?,?,?,?,?,?,?,?)",
                ('e4', 'e4', 'lesson', 'gamma', 'L404', '', 'cmd_4', '2026-01-04'),
            )
            conn.execute("INSERT INTO event_concepts VALUES ('e4','gamma',4.0)")


def test_resolved_snapshot_direct_read_newer_and_parallel_readers(tmp_path: Path) -> None:
    source, cache = tmp_path / "memory.sqlite3", tmp_path / "ext4-cache"
    seed(source)
    cold_started = time.monotonic()
    cold = MODULE.read_boosts(source, cache)
    cold_seconds = time.monotonic() - cold_started
    warm_samples = []
    for _ in range(9):
        started = time.monotonic()
        assert MODULE.read_boosts(source, cache) == cold
        warm_samples.append(time.monotonic() - started)
    assert cold == [
        {"concept": "alpha", "score": 3.0, "lesson_boost": 2.0},
        {"concept": "beta", "score": 2.5, "lesson_boost": 2.5},
    ]
    assert cold_seconds < 60
    assert sorted(warm_samples)[4] < 1
    assert not cache.exists(), "Python must not create an independent snapshot generation"

    time.sleep(0.002)
    seed(source, extra=True)
    refreshed = MODULE.read_boosts(source, cache)
    assert refreshed[0] == {"concept": "gamma", "score": 4.0, "lesson_boost": 4.0}
    with ThreadPoolExecutor(max_workers=2) as pool:
        parallel = list(pool.map(lambda _: MODULE.read_boosts(source, cache), range(2)))
    assert parallel == [refreshed, refreshed]
    assert len({row["concept"] for row in refreshed}) == len(refreshed)


def reference_query(
    source: Path,
    query_text: object,
    seed_concepts: list[object] | None = None,
    lesson_boost: int = 20,
) -> tuple[dict[str, int], list[str], int]:
    """Literal reference for deploy_task.sh::_memory_db_concept_lesson_boosts."""
    import re

    query_fold = str(query_text or "").casefold()
    if not query_fold.strip():
        return {}, [], 0
    matched = []
    seeds = [str(c).strip() for c in (seed_concepts or []) if str(c).strip()]
    with sqlite3.connect(source) as conn:
        rows = conn.execute(
            "SELECT concept_name FROM event_concepts GROUP BY concept_name "
            "ORDER BY MAX(relevance_score) DESC, COUNT(*) DESC LIMIT 1000"
        ).fetchall()
        available = {str(c or "").strip() for (c,) in rows}
        for concept in seeds:
            if concept in available and concept not in matched:
                matched.append(concept)
        for (concept_name,) in rows:
            concept = str(concept_name or "").strip()
            if not concept:
                continue
            folded = concept.casefold()
            if folded in query_fold or query_fold in folded:
                matched.append(concept)
            if len(matched) >= 10:
                break
        if not matched:
            return {}, [], 0
        placeholders = ",".join("?" for _ in matched)
        events = conn.execute(
            f"SELECT e.summary,e.detail,e.concepts,e.cmd_id FROM event_concepts c "
            f"JOIN events e ON e.id=c.event_id WHERE c.concept_name IN ({placeholders}) "
            "ORDER BY COALESCE(e.ts,'') DESC LIMIT 300",
            matched,
        ).fetchall()
    boosts = {}
    lesson_re = re.compile(r"(?<![A-Za-z0-9_])L\d{2,4}(?![A-Za-z0-9_])")
    for row in events:
        for lesson_id in lesson_re.findall(" ".join(str(value or "") for value in row)):
            boosts[lesson_id] = max(boosts.get(lesson_id, 0), lesson_boost)
    return boosts, matched, len(events)


def test_query_lesson_boost_contract_parity(tmp_path: Path) -> None:
    source, cache = tmp_path / "memory.sqlite3", tmp_path / "ext4-cache"
    seed(source)
    cases = [
        ("ALPHA deployment", [], 20),
        ("unmatched task", ["beta", "missing", "beta"], 37),
        ("alpha", ["alpha"], 20),
        ("", ["alpha"], 20),
    ]
    for query, seeds, boost in cases:
        assert MODULE.query_lesson_boosts(source, cache, query, seeds, boost) == reference_query(
            source, query, seeds, boost
        )

    result = MODULE.query_lesson_boosts(source, cache, "ALPHA deployment")
    assert result == ({"L020": 20, "L021": 20}, ["alpha"], 2)
    assert MODULE.query_lesson_boosts(tmp_path / "missing.sqlite3", cache, "alpha") == ({}, [], 0)
