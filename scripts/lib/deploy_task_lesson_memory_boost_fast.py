#!/usr/bin/env python3
"""Fast, deterministic concept/lesson boost reads from an ext4 snapshot."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import tempfile


def _identity(source: Path) -> str:
    stat = source.stat()
    return f"{stat.st_dev}:{stat.st_ino}:{stat.st_size}:{stat.st_mtime_ns}:{stat.st_ctime_ns}"


def _snapshot_path(source: Path, cache_dir: Path) -> Path:
    key = hashlib.sha256(str(source.resolve()).encode()).hexdigest()[:20]
    return cache_dir / f"lesson-memory-{key}.sqlite3"


def prepare_snapshot(source: Path, cache_dir: Path) -> Path:
    """Publish one complete snapshot per source generation, safe for parallel readers."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    snapshot = _snapshot_path(source, cache_dir)
    marker = snapshot.with_suffix(".identity")
    lock_path = snapshot.with_suffix(".lock")
    wanted = _identity(source)
    with lock_path.open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        current = marker.read_text().strip() if marker.exists() else ""
        if not snapshot.exists() or current != wanted:
            fd, temporary_name = tempfile.mkstemp(prefix=f".{snapshot.name}.", dir=cache_dir)
            os.close(fd)
            temporary = Path(temporary_name)
            try:
                with sqlite3.connect(f"file:{source}?mode=ro", uri=True) as src:
                    with sqlite3.connect(temporary) as dst:
                        src.backup(dst)
                os.replace(temporary, snapshot)
                marker_tmp = marker.with_suffix(f".identity.{os.getpid()}.tmp")
                marker_tmp.write_text(wanted + "\n")
                os.replace(marker_tmp, marker)
            finally:
                temporary.unlink(missing_ok=True)
    return snapshot


def read_boosts(source: Path, cache_dir: Path) -> list[dict[str, object]]:
    snapshot = prepare_snapshot(source, cache_dir)
    sql = """
        SELECT ec.concept_name,
               ROUND(SUM(ec.relevance_score), 8) AS concept_score,
               ROUND(SUM(CASE WHEN e.event_type = 'lesson'
                              THEN ec.relevance_score ELSE 0 END), 8) AS lesson_boost
          FROM event_concepts ec
          JOIN events e ON e.event_id = ec.event_id
         GROUP BY ec.concept_name
         ORDER BY concept_score DESC, ec.concept_name ASC
    """
    with sqlite3.connect(f"file:{snapshot}?mode=ro", uri=True) as conn:
        rows = conn.execute(sql).fetchall()
    return [
        {"concept": concept, "score": score, "lesson_boost": boost}
        for concept, score, boost in rows
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("database", type=Path)
    parser.add_argument("--cache-dir", type=Path, default=Path("/tmp/shogun-memory-boost"))
    args = parser.parse_args()
    print(json.dumps(read_boosts(args.database, args.cache_dir), ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
