"""test_necessity: preserve deterministic warm/cold lesson boosts without GROUP BY on the 9p source."""

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
            CREATE TABLE IF NOT EXISTS events(event_id TEXT PRIMARY KEY, event_type TEXT);
            CREATE TABLE IF NOT EXISTS event_concepts(
                event_id TEXT, concept_name TEXT, relevance_score REAL
            );
            DELETE FROM event_concepts; DELETE FROM events;
            INSERT INTO events VALUES ('e1','knowledge'), ('e2','lesson'), ('e3','lesson');
            INSERT INTO event_concepts VALUES
              ('e1','alpha',1.0), ('e2','alpha',2.0), ('e3','beta',2.5);
        """)
        if extra:
            conn.execute("INSERT INTO events VALUES ('e4','lesson')")
            conn.execute("INSERT INTO event_concepts VALUES ('e4','gamma',4.0)")


def test_warm_cold_newer_and_parallel_readers(tmp_path: Path) -> None:
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

    time.sleep(0.002)
    seed(source, extra=True)
    refreshed = MODULE.read_boosts(source, cache)
    assert refreshed[0] == {"concept": "gamma", "score": 4.0, "lesson_boost": 4.0}
    with ThreadPoolExecutor(max_workers=2) as pool:
        parallel = list(pool.map(lambda _: MODULE.read_boosts(source, cache), range(2)))
    assert parallel == [refreshed, refreshed]
    assert len({row["concept"] for row in refreshed}) == len(refreshed)
