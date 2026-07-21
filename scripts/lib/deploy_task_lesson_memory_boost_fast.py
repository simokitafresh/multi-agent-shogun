#!/usr/bin/env python3
"""Fast, deterministic concept/lesson boost reads from an ext4 snapshot."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sqlite3


LESSON_ID_PATTERN = r"(?<![A-Za-z0-9_])L\d{2,4}(?![A-Za-z0-9_])"


def read_boosts(source: Path, cache_dir: Path) -> list[dict[str, object]]:
    """Read a path resolved by memory_db_cache.sh without making another copy."""
    del cache_dir
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
    with sqlite3.connect(f"file:{source}?mode=ro", uri=True) as conn:
        rows = conn.execute(sql).fetchall()
    return [
        {"concept": concept, "score": score, "lesson_boost": boost}
        for concept, score, boost in rows
    ]


def query_lesson_boosts(
    source: Path,
    cache_dir: Path,
    query_text: object,
    seed_concepts: list[object] | None = None,
    lesson_boost: int = 20,
) -> tuple[dict[str, int], list[str], int]:
    """Return the deploy_task memory lesson-boost contract from a fast snapshot."""
    import re

    query_fold = str(query_text or "").casefold()
    if not query_fold.strip():
        return {}, [], 0

    if not source.exists():
        return {}, [], 0
    del cache_dir
    matched_concepts: list[str] = []
    normalized_seeds = [str(c).strip() for c in (seed_concepts or []) if str(c).strip()]
    try:
        with sqlite3.connect(f"file:{source}?mode=ro", uri=True) as conn:
            rows = conn.execute(
                """
                SELECT concept_name
                FROM event_concepts
                GROUP BY concept_name
                ORDER BY MAX(relevance_score) DESC, COUNT(*) DESC
                LIMIT 1000
                """
            ).fetchall()
            available_concepts = {str(c or "").strip() for (c,) in rows}
            for concept in normalized_seeds:
                if concept in available_concepts and concept not in matched_concepts:
                    matched_concepts.append(concept)
            for (concept_name,) in rows:
                concept = str(concept_name or "").strip()
                if not concept:
                    continue
                concept_fold = concept.casefold()
                if concept_fold in query_fold or query_fold in concept_fold:
                    matched_concepts.append(concept)
                if len(matched_concepts) >= 10:
                    break

            if not matched_concepts:
                return {}, [], 0

            placeholders = ",".join("?" for _ in matched_concepts)
            event_rows = conn.execute(
                f"""
                SELECT e.summary, e.detail, e.concepts, e.cmd_id
                FROM event_concepts AS c
                JOIN events AS e ON e.id = c.event_id
                WHERE c.concept_name IN ({placeholders})
                ORDER BY COALESCE(e.ts, '') DESC
                LIMIT 300
                """,
                matched_concepts,
            ).fetchall()
    except sqlite3.Error:
        return {}, [], 0

    boosts: dict[str, int] = {}
    lesson_re = re.compile(LESSON_ID_PATTERN)
    for row in event_rows:
        event_text = " ".join(str(value or "") for value in row)
        for lesson_id in lesson_re.findall(event_text):
            boosts[lesson_id] = max(boosts.get(lesson_id, 0), int(lesson_boost))
    return boosts, matched_concepts, len(event_rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("database", type=Path)
    parser.add_argument("--cache-dir", type=Path, default=Path("/tmp/shogun-memory-boost"))
    args = parser.parse_args()
    print(json.dumps(read_boosts(args.database, args.cache_dir), ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
