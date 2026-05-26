#!/usr/bin/env python3
"""Semantic index search helper for semantic_search.sh.

Called by semantic_search.sh instead of an inline heredoc to enable
Python bytecode caching and JSON index caching.
"""

import json
import hashlib
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
    printed = False
    for related_id in related_ids:
        related = by_id.get(related_id)
        if not related:
            continue
        if not printed:
            print("")
            print("related_concepts:")
            printed = True
        print(f"## {related['id']} — {related['label']}")
        print(f"aliases: {', '.join(related['aliases'])}")
        print_resources(related)
        print("")


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
            matched_terms = [
                term
                for term in terms
                if query_fold in term.casefold() or term.casefold() in query_fold
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

    else:
        print(f"ERROR: unknown semantic index mode: {mode}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
