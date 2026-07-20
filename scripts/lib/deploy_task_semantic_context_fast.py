#!/usr/bin/env python3
"""Pure, batched semantic-context injection for deploy-task.

The shell implementation shells out to ``semantic_search.sh`` and then walks
the rendered output with several text filters.  This module keeps the same
first-layer matching and related-concept ordering, but parses the supplied
index once and returns the task bytes that would have been published.  It has
no filesystem or logging side effects; the caller owns publication.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Mapping

import yaml


AMBIGUOUS_SINGLE_TERM_QUERIES = {"記憶"}


@dataclass(frozen=True)
class Concept:
    concept_id: str
    label: str
    aliases: tuple[str, ...]
    skills: tuple[str, ...]
    related: tuple[tuple[str, str], ...]
    related_lessons: tuple[str, ...]
    resources: tuple[tuple[str, str], ...]


def _parse_related(value: str) -> tuple[tuple[str, str], ...]:
    result: list[tuple[str, str]] = []
    for raw in str(value or "").split(","):
        item = raw.strip().strip("`")
        if not item:
            continue
        relation = "related"
        match = re.match(r"^([A-Za-z0-9_-]+)\s*\((.*?)\)$", item)
        if match:
            item = match.group(1).strip()
            for attribute in match.group(2).split(";"):
                key, separator, attr_value = attribute.partition("=")
                if separator and key.strip() == "relation_type" and attr_value.strip():
                    relation = attr_value.strip()
        result.append((item, relation))
    return tuple(result)


def parse_semantic_index(index_bytes: bytes | str) -> tuple[Concept, ...]:
    """Parse index.md sections once, preserving source order."""
    text = index_bytes.decode("utf-8") if isinstance(index_bytes, bytes) else index_bytes
    concepts: list[Concept] = []
    for raw in re.split(r"(?m)^##\s+", text)[1:]:
        lines = raw.splitlines()
        if not lines:
            continue
        heading = lines[0].strip()
        concept_id, separator, heading_label = heading.partition(" — ")
        if not separator:
            heading_label = ""
        attributes: dict[str, str] = {}
        resources: list[tuple[str, str]] = []
        for line in lines[1:]:
            stripped = line.strip()
            if not (stripped.startswith("|") and stripped.endswith("|")):
                continue
            cells = stripped.split("|")
            if len(cells) < 4:
                continue
            left = cells[1].strip()
            right = "|".join(cells[2:-1]).strip()
            if left in {"属性", "------", "種別"} or right in {"値", "----------"}:
                continue
            if left in {
                "id",
                "label",
                "aliases",
                "skills",
                "related_concepts",
                "related_lessons",
            }:
                attributes[left] = right
            elif right:
                resources.append((left, right))
        concepts.append(
            Concept(
                concept_id=attributes.get("id") or concept_id.strip(),
                label=attributes.get("label") or heading_label,
                aliases=tuple(
                    item.strip()
                    for item in attributes.get("aliases", "").split(",")
                    if item.strip()
                ),
                skills=tuple(
                    item.strip()
                    for item in attributes.get("skills", "").split(",")
                    if item.strip()
                ),
                related=_parse_related(attributes.get("related_concepts", "")),
                related_lessons=tuple(
                    item.strip().strip("`")
                    for item in attributes.get("related_lessons", "").split(",")
                    if item.strip()
                ),
                resources=tuple(resources),
            )
        )
    return tuple(concepts)


def _all_words_in_term(query: str, term: str) -> bool:
    words = [word for word in query.split() if word]
    return len(words) >= 2 and all(word in term for word in words)


def _single_generic_word(query: str, term: str) -> bool:
    query_words = [word for word in query.split() if word]
    if len(query_words) < 2:
        return False
    term_words = [word for word in term.split() if word]
    if len(term_words) != 1 or len(term_words[0]) >= 12:
        return False
    return any(term_words[0] in word or word in term_words[0] for word in query_words)


def first_layer_matches(
    concepts: Iterable[Concept], query: str
) -> list[tuple[Concept, tuple[str, ...]]]:
    """Mirror semantic_index.py's alias-layer match and sort contract."""
    query_fold = query.casefold()
    if query_fold in AMBIGUOUS_SINGLE_TERM_QUERIES:
        return []
    japanese_query = any("\u3000" <= char <= "\u30ff" for char in query)
    min_ratio = 0.3 if japanese_query else 0.5
    matches: list[tuple[Concept, tuple[str, ...]]] = []
    for concept in concepts:
        terms = (concept.concept_id, concept.label, *concept.aliases)
        matched = tuple(
            term
            for term in terms
            if not _single_generic_word(query_fold, term.casefold())
            and (
                term.casefold() in query_fold
                or (
                    query_fold in term.casefold()
                    and len(query_fold) >= len(term.casefold()) * min_ratio
                )
                or _all_words_in_term(query_fold, term.casefold())
            )
        )
        if matched:
            matches.append((concept, matched))
    matches.sort(key=lambda item: (min(map(len, item[1])), item[0].concept_id))
    return matches


def _related_order(seed: Concept, by_id: Mapping[str, Concept]) -> list[Concept]:
    seed_related = [concept_id for concept_id, relation in seed.related if relation != "混同注意"]
    related_set = set(seed_related)
    backlink_counts = {
        concept_id: sum(
            1
            for concept in by_id.values()
            if concept_id in {rid for rid, relation in concept.related if relation != "混同注意"}
        )
        for concept_id in seed_related
    }
    ranked: list[tuple[float, int, str, Concept]] = []
    for position, concept_id in enumerate(seed_related, 1):
        related = by_id.get(concept_id)
        if related is None:
            continue
        related_ids = {rid for rid, relation in related.related if relation != "混同注意"}
        reciprocal = 1.0 if seed.concept_id in related_ids else 0.0
        shared = len(related_set.intersection(related_ids))
        backlinks = backlink_counts.get(concept_id, 0)
        strength = 1.0 + reciprocal + shared * 0.25 + __import__("math").log1p(backlinks)
        density = 1 + len(related.resources) + len(related.skills) + len(related.related_lessons)
        score = density * strength / position
        ranked.append((score, backlinks, related.concept_id, related))
    ranked.sort(key=lambda item: (-item[0], -item[1], item[2]))
    return [item[3] for item in ranked[:8]]


def _render_concept(concept: Concept) -> list[str]:
    lines = [f"## {concept.concept_id} — {concept.label}"]
    lines.append(f"matched: {concept.aliases[0] if concept.aliases else concept.concept_id}")
    lines.append(f"aliases: {', '.join(concept.aliases)}")
    lines.append("resources:")
    if concept.skills:
        lines.append(f"- skills: {', '.join(concept.skills)}")
    if concept.resources:
        lines.extend(f"- {kind}: {value}" for kind, value in concept.resources)
    elif not concept.skills:
        lines.append("- none")
    return lines


def _semantic_output(concepts: tuple[Concept, ...], query: str) -> tuple[list[str], list[str]]:
    matches = first_layer_matches(concepts, query)
    if not matches:
        return [], []
    ordered = [concept for concept, _terms in matches]
    if len(matches) == 1:
        ordered.extend(_related_order(matches[0][0], {item.concept_id: item for item in concepts}))

    rendered: list[str] = []
    for index, concept in enumerate(ordered):
        if index:
            rendered.append("")
        rendered.extend(_render_concept(concept))

    # The shell implementation extracts only file resources from each rendered
    # section and retains the first five concept sections.
    concept_lines: list[str] = []
    current_label = ""
    files: list[str] = []
    for line in rendered + [""]:
        if line.startswith("## "):
            current_label = line[3:]
            files = []
            continue
        if line.startswith("- file: "):
            files.append(line[len("- file: "):].replace("`", ""))
            continue
        if line == "" and current_label and files:
            # The fixed-SHA awk accumulator starts with one leading space and
            # the print expression adds another space after the colon.
            concept_lines.append(f"{current_label}:  {' '.join(files)}")
            current_label = ""
            files = []
            if len(concept_lines) == 5:
                break

    skills: list[str] = []
    for line in rendered:
        if line.startswith("- skills: "):
            value = line[len("- skills: "):]
            if value != "なし":
                skills.extend(item.strip() for item in value.split(",") if item.strip())
    return concept_lines, list(dict.fromkeys(skills))[:10]


def _task_purpose(task_bytes: bytes) -> str:
    loaded = yaml.safe_load(task_bytes.decode("utf-8")) or {}
    task = loaded.get("task", loaded) if isinstance(loaded, dict) else {}
    purpose = task.get("purpose", "") if isinstance(task, dict) else ""
    if isinstance(purpose, (list, dict)):
        return " ".join(str(item) for item in purpose)
    return str(purpose or "").strip()


def _without_old_sections(lines: list[str]) -> list[str]:
    result: list[str] = []
    skip = False
    for line in lines:
        if re.match(r"^  (?:semantic_concepts|recommended_skills):\s*$", line):
            skip = True
            continue
        if skip:
            if re.match(r"^  [A-Za-z_][A-Za-z0-9_]*:", line) or re.match(r"^[^ ]", line):
                skip = False
            else:
                continue
        result.append(line)
    return result


def _replace_task_section(task_bytes: bytes, concept_lines: list[str], skills: list[str]) -> bytes:
    text = task_bytes.decode("utf-8")
    lines = _without_old_sections(text.splitlines())
    block = ["  semantic_concepts:", *(f'  - "{line}"' for line in concept_lines)]
    if skills:
        block.extend(["  recommended_skills:", *(f'  - "{skill}"' for skill in skills)])
    try:
        description_index = next(index for index, line in enumerate(lines) if line.startswith("  description:"))
    except StopIteration:
        lines.extend(block)
    else:
        lines[description_index:description_index] = block
    return ("\n".join(lines) + "\n").encode("utf-8")


def _default_skill_allowed(skill: str, purpose: str) -> bool:
    """Apply the fixed-SHA role/TRIGGER filter when the repo is available."""
    skill_file = Path(__file__).resolve().parents[2] / "skills" / skill / "SKILL.md"
    if not skill_file.is_file():
        return True
    content = skill_file.read_text(encoding="utf-8", errors="replace")
    if re.search(r"軍師専用|家老専用|将軍専用", content):
        return False
    trigger = re.search(r"^\s*TRIGGER\s*:\s*(.*)$", content, re.MULTILINE)
    if not trigger:
        return False
    terms = [term.strip().split(" project:", 1)[0].strip() for term in re.split(r"[、,]", trigger.group(1))]
    return any(term and term in purpose for term in terms)


def inject_semantic_concepts(
    task_bytes: bytes,
    semantic_index_bytes: bytes,
    *,
    skill_allowed: Callable[[str], bool] | None = None,
) -> bytes:
    """Return the task section produced by the fixed SHA implementation.

    ``task_bytes`` and ``semantic_index_bytes`` are read-only inputs.  The
    optional predicate is the caller's role-specific skill filter; omitting it
    retains all index-recommended skills, which is the pure data contract.
    """
    purpose = _task_purpose(task_bytes)
    if not purpose:
        return task_bytes
    concepts = parse_semantic_index(semantic_index_bytes)
    concept_lines, skills = _semantic_output(concepts, purpose)
    if not concept_lines:
        return task_bytes
    allowed = skill_allowed or (lambda skill: _default_skill_allowed(skill, purpose))
    skills = [skill for skill in skills if allowed(skill)]
    return _replace_task_section(task_bytes, concept_lines, skills)


def transform_task(task_bytes: bytes, semantic_index_bytes: bytes) -> bytes:
    """Compatibility alias for callers that name the operation generically."""
    return inject_semantic_concepts(task_bytes, semantic_index_bytes)


def load_and_inject(task_path: str | Path, index_path: str | Path) -> bytes:
    """Convenience entry point for the S1 adapter and local probes."""
    task = Path(task_path).read_bytes()
    index = Path(index_path).read_bytes()
    return inject_semantic_concepts(task, index)
