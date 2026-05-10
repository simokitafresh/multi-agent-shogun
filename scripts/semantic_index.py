#!/usr/bin/env python3
"""Semantic index search helper for semantic_search.sh.

Called by semantic_search.sh instead of an inline heredoc to enable
Python bytecode caching and JSON index caching.
"""

import json
import hashlib
import os
import re
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
            if left in {"id", "label", "aliases"}:
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
        cache_path.write_text(json.dumps(concepts, ensure_ascii=False), encoding="utf-8")
    except OSError:
        pass  # Cache write failure is non-fatal
    return concepts


def print_resources(concept: dict) -> None:
    print("resources:")
    if concept["resources"]:
        for resource_type, ref in concept["resources"]:
            print(f"- {resource_type}: {ref}")
    else:
        print("- none")


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
            terms = [concept["label"], *concept["aliases"]]
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

        for idx, (concept, matched_terms) in enumerate(matches, 1):
            if idx > 1:
                print("")
            print(f"## {concept['id']} — {concept['label']}")
            print(f"matched: {', '.join(matched_terms)}")
            print(f"aliases: {', '.join(concept['aliases'])}")
            print_resources(concept)

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

    else:
        print(f"ERROR: unknown semantic index mode: {mode}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
