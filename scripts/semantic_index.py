#!/usr/bin/env python3
"""Semantic index search helper for semantic_search.sh.

Called by semantic_search.sh instead of an inline heredoc to enable
Python bytecode caching and JSON index caching.
"""

import json
import hashlib
import math
import os
import re
import sqlite3
import sys
from pathlib import Path


def parse_index(index_path: Path) -> list:
    """Parse index.md sections into concept dicts."""
    text = index_path.read_text(encoding="utf-8")
    sections = re.split(r"(?m)^##\s+", text)
    concepts = []

    for raw in sections[1:]:
        lines = raw.splitlines()
        if not lines:
            continue
        heading = lines[0].strip()
        if " — " in heading:
            concept_id, heading_label = heading.split(" — ", 1)
        else:
            concept_id, heading_label = heading, ""

        attrs: dict = {}
        resources: list = []
        for line in lines[1:]:
            stripped = line.strip()
            if not stripped.startswith("|") or not stripped.endswith("|"):
                continue
            parts = stripped.split("|")
            if len(parts) < 4:
                continue
            left = parts[1].strip()
            right = "|".join(parts[2:-1]).strip()
            if left in {"属性", "------", "種別"} or right in {"値", "----------"}:
                continue
            if left in {"id", "label", "aliases", "skills", "related_concepts", "related_lessons"}:
                attrs[left] = right
            elif right:
                resources.append((left, right))

        concepts.append(
            {
                "id": attrs.get("id") or concept_id.strip(),
                "label": attrs.get("label") or heading_label,
                "aliases": [
                    item.strip()
                    for item in attrs.get("aliases", "").split(",")
                    if item.strip()
                ],
                "skills": [
                    item.strip()
                    for item in attrs.get("skills", "").split(",")
                    if item.strip()
                ],
                "related_concepts": [
                    item.strip().strip("`")
                    for item in attrs.get("related_concepts", "").split(",")
                    if item.strip()
                ],
                "related_lessons": [
                    item.strip().strip("`")
                    for item in attrs.get("related_lessons", "").split(",")
                    if item.strip()
                ],
                "resources": resources,
            }
        )
    return concepts


def load_concepts(index_path: Path) -> list:
    """Load concepts from JSON cache if fresh, otherwise parse and rebuild cache."""
    cache_dir = os.environ.get("SEMANTIC_INDEX_CACHE_DIR")
    if cache_dir:
        cache_root = Path(cache_dir)
        cache_key = hashlib.sha256(str(index_path.resolve()).encode("utf-8")).hexdigest()
        cache_path = cache_root / f"{cache_key}.json"
    else:
        cache_root = None
        cache_path = Path(str(index_path) + ".cache.json")

    try:
        if (
            cache_path.exists()
            and cache_path.stat().st_mtime >= index_path.stat().st_mtime
        ):
            return json.loads(cache_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        pass

    concepts = parse_index(index_path)
    try:
        if cache_root is not None:
            cache_root.mkdir(parents=True, exist_ok=True)
        tmp_path = cache_path.with_name(f".{cache_path.name}.{os.getpid()}.tmp")
        tmp_path.write_text(json.dumps(concepts, ensure_ascii=False), encoding="utf-8")
        tmp_path.replace(cache_path)
    except OSError:
        pass  # Cache write failure is non-fatal
    return concepts


def print_resources(concept: dict) -> None:
    print("resources:")
    if concept.get("skills"):
        print(f"- skills: {', '.join(concept['skills'])}")
    if concept["resources"]:
        for resource_type, ref in concept["resources"]:
            print(f"- {resource_type}: {ref}")
    elif not concept.get("skills"):
        print("- none")


def print_related_concepts(concept: dict, concepts: list) -> None:
    related_ids = concept.get("related_concepts", [])
    if not related_ids:
        return

    by_id = {item["id"]: item for item in concepts}
    backlink_counts = precompute_related_concept_backlinks(concepts)
    ranked_related = rank_related_concepts(concept, by_id, backlink_counts)
    limit = int(os.environ.get("SEMANTIC_RELATED_CONCEPT_LIMIT", "8"))
    printed = False
    for related, score, density, strength, backlinks in ranked_related[: max(limit, 1)]:
        if not printed:
            print("")
            print("related_concepts:")
            printed = True
        print(f"## {related['id']} — {related['label']}")
        print(
            "path_b_score: "
            f"{score:.3f} (density={density}, connection_strength={strength:.3f}, backlinks={backlinks})"
        )
        print(f"aliases: {', '.join(related['aliases'])}")
        print_resources(related)
        print("")


def precompute_related_concept_backlinks(concepts: list[dict]) -> dict[str, int]:
    """Count incoming index.md related_concepts once for O(1) neighbor scoring."""
    counts: dict[str, int] = {}
    known_ids = {concept["id"] for concept in concepts}
    for concept in concepts:
        for related_id in concept.get("related_concepts", []):
            if related_id in known_ids:
                counts[related_id] = counts.get(related_id, 0) + 1
    return counts


def concept_density(concept: dict) -> int:
    return (
        1
        + len(concept.get("resources", []))
        + len(concept.get("skills", []))
        + len(concept.get("related_lessons", []))
    )


def rank_related_concepts(
    seed: dict,
    by_id: dict[str, dict],
    backlink_counts: dict[str, int],
) -> list[tuple[dict, float, int, float, int]]:
    seed_related = set(seed.get("related_concepts", []))
    ranked: list[tuple[dict, float, int, float, int]] = []
    for position, related_id in enumerate(seed.get("related_concepts", []), 1):
        related = by_id.get(related_id)
        if not related:
            continue
        reciprocal = 1.0 if seed["id"] in related.get("related_concepts", []) else 0.0
        shared_neighbors = len(seed_related.intersection(related.get("related_concepts", [])))
        backlinks = backlink_counts.get(related_id, 0)
        strength = 1.0 + reciprocal + (shared_neighbors * 0.25) + math.log1p(backlinks)
        density = concept_density(related)
        score = density * strength / position
        ranked.append((related, score, density, strength, backlinks))
    ranked.sort(key=lambda item: (-item[1], -item[4], item[0]["id"]))
    return ranked


def concept_ids_from_search_output(output_path: Path) -> list[str]:
    raw_output = output_path.read_text(encoding="utf-8", errors="replace")
    ids: list[str] = []
    seen: set[str] = set()
    for match in re.finditer(r"(?m)^##\s+([A-Za-z0-9_-]+)\s+—", raw_output):
        concept_id = match.group(1)
        if concept_id in seen:
            continue
        seen.add(concept_id)
        ids.append(concept_id)
    return ids


def placeholders(values: list[str]) -> str:
    return ", ".join("?" for _ in values)


def memory_db_concept_rows(
    db_path: Path,
    seed_concepts: list[str],
    expansion_limit: int,
    result_limit: int,
) -> tuple[list[str], list[sqlite3.Row]]:
    if not seed_concepts or not db_path.is_file():
        return [], []

    uri = f"file:{db_path}?mode=ro"
    with sqlite3.connect(uri, uri=True) as conn:
        conn.execute("PRAGMA busy_timeout=1000")
        conn.row_factory = sqlite3.Row
        seed_params = seed_concepts[:]
        seed_sql = placeholders(seed_params)
        expanded = [
            row["target_concept"]
            for row in conn.execute(
                f"""
                SELECT DISTINCT el2.target_concept
                FROM event_links AS el1
                JOIN event_links AS el2
                  ON el2.source_event_id = el1.source_event_id
                WHERE el1.target_concept IN ({seed_sql})
                  AND el2.target_concept NOT IN ({seed_sql})
                ORDER BY el2.target_concept
                LIMIT ?
                """,
                [*seed_params, *seed_params, expansion_limit],
            )
        ]

        concept_set: list[str] = []
        seen: set[str] = set()
        for concept_name in [*seed_concepts, *expanded]:
            if concept_name in seen:
                continue
            seen.add(concept_name)
            concept_set.append(concept_name)

        if not concept_set:
            return expanded, []

        concept_sql = placeholders(concept_set)
        rows = list(
            conn.execute(
                f"""
                WITH matched_event_ids AS (
                    SELECT source_event_id AS event_id
                    FROM event_links
                    WHERE target_concept IN ({concept_sql})
                )
                SELECT
                    e.id,
                    e.ts,
                    e.event_type,
                    e.agent,
                    e.cmd_id,
                    e.importance,
                    e.summary
                FROM matched_event_ids AS m
                JOIN events AS e
                  ON e.id = m.event_id
                ORDER BY
                    CASE e.importance WHEN 'high' THEN 0 ELSE 1 END,
                    e.ts DESC,
                    e.id
                LIMIT ?
                """,
                [*concept_set, result_limit],
            )
        )
        return expanded, rows


def fts5_query_for_text(text: str) -> str:
    terms: list[str] = []
    for token in re.findall(r"[\w\u3040-\u30ff\u3400-\u9fff]+", text, flags=re.UNICODE):
        token = token.strip()
        if token:
            terms.append(f'"{token.replace(chr(34), chr(34) + chr(34))}"')
    return " OR ".join(terms)


def memory_db_fts_concept_rank_rows(
    db_path: Path,
    query: str,
    result_limit: int,
    target: str = "",
) -> tuple[list[dict], int]:
    fts_query = fts5_query_for_text(query)
    if not fts_query or not db_path.is_file():
        return [], 0

    target = target.strip()
    target_clause = "AND (e.target = ? OR e.event_type = 'document')" if target else ""
    params: list[object] = [fts_query]
    if target:
        params.append(target)
    params.append(max(result_limit, 1))

    uri = f"file:{db_path}?mode=ro"
    with sqlite3.connect(uri, uri=True) as conn:
        conn.execute("PRAGMA busy_timeout=1000")
        conn.row_factory = sqlite3.Row
        total_events = int(conn.execute("SELECT COUNT(*) FROM events").fetchone()[0] or 0)
        rows = list(
            conn.execute(
                f"""
                SELECT
                    e.id,
                    e.ts,
                    e.event_type,
                    e.agent,
                    e.target,
                    e.cmd_id,
                    e.importance,
                    e.summary,
                    bm25(events_fts) AS rank
                FROM events_fts
                JOIN events AS e ON e.rowid = events_fts.rowid
                WHERE events_fts MATCH ?
                  {target_clause}
                ORDER BY rank, e.ts
                LIMIT ?
                """,
                params,
            )
        )
        if not rows:
            return [], total_events

        event_ids = [str(row["id"]) for row in rows]
        event_sql = placeholders(event_ids)
        concept_counts = {
            str(row["concept_name"]): int(row["doc_count"])
            for row in conn.execute(
                f"""
                SELECT concept_name, COUNT(DISTINCT event_id) AS doc_count
                FROM event_concepts
                GROUP BY concept_name
                """
            )
        }
        concept_rows = list(
            conn.execute(
                f"""
                SELECT event_id, concept_name
                FROM event_concepts
                WHERE event_id IN ({event_sql})
                ORDER BY event_id, concept_name
                """,
                event_ids,
            )
        )

    concepts_by_event: dict[str, list[str]] = {}
    for row in concept_rows:
        concepts_by_event.setdefault(str(row["event_id"]), []).append(str(row["concept_name"]))

    scores: dict[str, dict] = {}
    event_by_id = {str(row["id"]): row for row in rows}
    for position, row in enumerate(rows, 1):
        event_id = str(row["id"])
        concepts_for_event = concepts_by_event.get(event_id, [])
        if not concepts_for_event:
            continue
        rank_weight = 1.0 / position
        for concept_name in concepts_for_event:
            doc_count = concept_counts.get(concept_name, 0)
            idf = math.log((total_events + 1.0) / (doc_count + 1.0)) + 1.0
            item = scores.setdefault(
                concept_name,
                {
                    "concept": concept_name,
                    "score": 0.0,
                    "idf": idf,
                    "hits": 0,
                    "events": [],
                },
            )
            item["score"] += rank_weight * idf
            item["hits"] += 1
            if len(item["events"]) < 3:
                item["events"].append(event_by_id[event_id])

    ranked = sorted(
        scores.values(),
        key=lambda item: (-item["score"], -item["idf"], item["concept"]),
    )
    return ranked, total_events


def print_memory_db_fts_concept_search(
    query: str,
    concepts: list[dict],
    mode_arg: str,
) -> int:
    db_path = Path(os.environ.get("SEMANTIC_MEMORY_DB_PATH", "data/multi_agent_shogun_memory.db"))
    result_limit = int(os.environ.get("SEMANTIC_MEMORY_DB_LIMIT", "10"))
    target = mode_arg.strip()
    ranked, total_events = memory_db_fts_concept_rank_rows(
        db_path,
        query,
        result_limit=max(result_limit, 1),
        target=target,
    )
    if not ranked:
        return 1

    by_id = {item["id"]: item for item in concepts}
    top = ranked[0]
    print(f"MEMORY_DB_MATCH: {query}")
    print("")
    print("memory_db_concept_ranking:")
    print(f"  fts_limit: {max(result_limit, 1)}")
    print(f"  target: {target if target else 'none'}")
    print(f"  total_events: {total_events}")
    print(f"  top_concept: {top['concept']}")
    print("  concepts:")
    for item in ranked[: max(result_limit, 1)]:
        print(f"  - concept: {item['concept']}")
        print(f"    score: {item['score']:.6f}")
        print(f"    idf: {item['idf']:.6f}")
        print(f"    hits: {item['hits']}")
        print("    sample_events:")
        for event in item["events"]:
            print(f"    - id: {event['id']}")
            print(f"      ts: {event['ts']}")
            print(f"      agent: {event['agent']}")
            if event["cmd_id"]:
                print(f"      cmd_id: {event['cmd_id']}")
            summary = str(event["summary"]).replace("\n", " ")
            print(f"      summary: {summary}")

    print("")
    print(f"MATCH: {top['concept']}")
    print("reason: memory DB FTS5 bm25 hits joined to event_concepts and ranked with IDF.")
    concept = by_id.get(str(top["concept"]))
    if concept:
        print("")
        print(f"## {concept['id']} — {concept['label']}")
        print(f"aliases: {', '.join(concept['aliases'])}")
        print_resources(concept)
    return 0


def print_memory_db_concept_search(mode_arg: str) -> int:
    db_path = Path(os.environ.get("SEMANTIC_MEMORY_DB_PATH", "data/multi_agent_shogun_memory.db"))
    expansion_limit = int(os.environ.get("SEMANTIC_CONCEPT_EXPANSION_LIMIT", "20"))
    result_limit = int(os.environ.get("SEMANTIC_MEMORY_DB_LIMIT", "10"))
    seed_concepts = concept_ids_from_search_output(Path(mode_arg))
    return print_memory_db_concept_search_for_ids(db_path, seed_concepts, expansion_limit, result_limit)


def print_memory_db_concept_search_for_ids(
    db_path: Path,
    seed_concepts: list[str],
    expansion_limit: int,
    result_limit: int,
) -> int:
    expanded, rows = memory_db_concept_rows(
        db_path,
        seed_concepts,
        expansion_limit=max(expansion_limit, 0),
        result_limit=max(result_limit, 1),
    )
    if not rows:
        return 1

    print("")
    print("memory_db_concept_results:")
    print("  depth: 1")
    print(f"  expansion_limit: {max(expansion_limit, 0)}")
    print(f"  seed_concepts: {', '.join(seed_concepts) if seed_concepts else 'none'}")
    print(f"  expanded_concepts: {', '.join(expanded) if expanded else 'none'}")
    print("  rows:")
    for row in rows:
        print(f"  - id: {row['id']}")
        print(f"    ts: {row['ts']}")
        print(f"    event_type: {row['event_type']}")
        print(f"    agent: {row['agent']}")
        if row["cmd_id"]:
            print(f"    cmd_id: {row['cmd_id']}")
        print(f"    importance: {row['importance']}")
        summary = str(row["summary"]).replace("\n", " ")
        print(f"    summary: {summary}")
    return 0


def main() -> None:
    index_path = Path(sys.argv[1])
    query = sys.argv[2].strip()
    mode = sys.argv[3]
    mode_arg = sys.argv[4] if len(sys.argv) > 4 else ""

    if mode == "first-layer" and not query:
        print("ERROR: query is empty", file=sys.stderr)
        sys.exit(2)

    concepts = load_concepts(index_path)

    if mode == "first-layer":
        no_match_mode = mode_arg
        query_fold = query.casefold()
        matches = []
        for concept in concepts:
            terms = [concept["id"], concept["label"], *concept["aliases"]]
            min_ratio = 0.3 if any('\u3000' <= c <= '\u9fff' or '\u30a0' <= c <= '\u30ff' for c in query) else 0.5
            matched_terms = [
                term
                for term in terms
                if (
                    term.casefold() in query_fold
                    or (query_fold in term.casefold() and len(query_fold) >= len(term.casefold()) * min_ratio)
                )
            ]
            if matched_terms:
                matches.append((concept, matched_terms))

        if not matches:
            if no_match_mode != "silent":
                print(f"NO_MATCH: {query}")
            sys.exit(1)

        matches.sort(
            key=lambda item: (
                min(len(term) for term in item[1]),
                item[0]["id"],
            )
        )

        for idx, (concept, matched_terms) in enumerate(matches, 1):
            if idx > 1:
                print("")
            print(f"## {concept['id']} — {concept['label']}")
            print(f"matched: {', '.join(matched_terms)}")
            print(f"aliases: {', '.join(concept['aliases'])}")
            print_resources(concept)
            if len(matches) == 1:
                print_related_concepts(concept, concepts)
        if os.environ.get("SEMANTIC_DISABLE_MEMORY_DB", "0") != "1":
            db_path = Path(os.environ.get("SEMANTIC_MEMORY_DB_PATH", "data/multi_agent_shogun_memory.db"))
            expansion_limit = int(os.environ.get("SEMANTIC_CONCEPT_EXPANSION_LIMIT", "20"))
            result_limit = int(os.environ.get("SEMANTIC_MEMORY_DB_LIMIT", "10"))
            seed_concepts = [concept["id"] for concept, _matched_terms in matches]
            if len(matches) == 1:
                seed_concepts.extend(matches[0][0].get("related_concepts", []))
            print_memory_db_concept_search_for_ids(db_path, seed_concepts, expansion_limit, result_limit)

    elif mode == "render-llm-resources":
        llm_output_path = Path(mode_arg)
        raw_output = llm_output_path.read_text(encoding="utf-8", errors="replace")
        matched = [
            concept
            for concept in concepts
            if re.search(
                rf"(?<![A-Za-z0-9_.-]){re.escape(concept['id'])}(?![A-Za-z0-9_.-])",
                raw_output,
            )
        ]

        if not matched:
            print("resources: LLM output did not contain known concept ids")
            sys.exit(0)

        print("resolved resources:")
        for idx, concept in enumerate(matched[:3], 1):
            if idx > 1:
                print("")
            print(f"## {concept['id']} — {concept['label']}")
            print(f"aliases: {', '.join(concept['aliases'])}")
            print_resources(concept)

    elif mode == "memory-db-concept-search":
        sys.exit(print_memory_db_concept_search(mode_arg))

    elif mode == "memory-db-fts-concept-search":
        sys.exit(print_memory_db_fts_concept_search(query, concepts, mode_arg))

    else:
        print(f"ERROR: unknown semantic index mode: {mode}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
