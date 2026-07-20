#!/usr/bin/env python3
"""Fast, side-effect-free related-lessons selector and YAML section rewriter.

The deployment shell can load all inputs once and call ``inject_many`` for a
wave.  PyYAML is deliberately used only at the input boundary; task bytes are
updated textually so comments, ordering, and scalar styles remain unchanged.
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Iterable

import yaml

_CJK = r"\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff"
_BOUNDARY = re.compile(rf"(?<=[A-Za-z0-9_])(?=[{_CJK}])|(?<=[{_CJK}])(?=[A-Za-z0-9_])")
_SPLIT = re.compile(rf"[^A-Za-z0-9_{_CJK}]+")


def _terms(value: object) -> set[str]:
    words = _SPLIT.split(str(value or ""))
    expanded = (part for word in words for part in _BOUNDARY.split(word) if part)
    return {word.casefold() for word in expanded if len(word) > 3 or (len(word) >= 2 and word.isascii() and word.isupper())}


def parse_lessons(blobs: Iterable[bytes]) -> list[dict]:
    """Parse each lesson source exactly once and apply the legacy last-ID-wins rule."""
    by_id: dict[str, dict] = {}
    anonymous: list[dict] = []
    for blob in blobs:
        loaded = yaml.safe_load(blob) or {}
        for lesson in loaded.get("lessons", []):
            item = dict(lesson)
            lesson_id = str(item.get("id") or "")
            if lesson_id:
                by_id[lesson_id] = item
            else:
                anonymous.append(item)
    return [*by_id.values(), *anonymous]


def parse_semantic_index(blob: bytes | None) -> dict[str, set[str]]:
    """Return concept labels/aliases mapped to lesson IDs, parsing the index once."""
    result: dict[str, set[str]] = {}
    if not blob:
        return result
    for section in re.split(rb"(?m)^##\s+", blob)[1:]:
        text = section.decode("utf-8", "replace")
        lines = text.splitlines()
        if not lines:
            continue
        attrs = {}
        for line in lines[1:]:
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if len(cells) >= 2:
                attrs[cells[0]] = "|".join(cells[1:]).strip()
        keys = {value.casefold() for name in ("label", "aliases") for value in attrs.get(name, "").split(",") if value.strip()}
        lesson_ids = set(re.findall(r"\bL\d{2,4}\b", attrs.get("related_lessons", "")))
        for key in keys:
            result.setdefault(key, set()).update(lesson_ids)
    return result


def _detail(lesson: dict) -> str:
    rule = lesson.get("if_then")
    if isinstance(rule, dict):
        cond = str(rule.get("if") or "").strip()
        action = str(rule.get("then") or "").strip()
        reason = str(rule.get("because") or "").strip()
        parts = []
        if cond:
            parts.append(f"IF: {cond}")
        if action:
            parts.append(f"THEN: {action}")
        value = " → ".join(parts)
        if reason:
            value += (" " if value else "") + f"(BECAUSE: {reason})"
        if value:
            return value
    return str(lesson.get("detail") or lesson.get("content") or lesson.get("summary") or "")


def select(task: dict, lessons: list[dict], semantic: dict[str, set[str]], limit: int = 10) -> list[dict]:
    fields = ("title", "description", "purpose", "command", "target_path", "context_files", "acceptance_criteria")
    task_text = " ".join(str(task.get(field) or "") for field in fields)
    task_terms = _terms(task_text)
    folded = task_text.casefold()
    semantic_ids = {lid for phrase, ids in semantic.items() if phrase and phrase in folded for lid in ids}
    scored = []
    for pos, lesson in enumerate(lessons):
        lid = str(lesson.get("id") or "")
        if not lid or lesson.get("deprecated") or str(lesson.get("status") or "").casefold() == "deprecated":
            continue
        haystack = " ".join(str(lesson.get(k) or "") for k in ("title", "summary", "detail", "content", "tags", "when", "if_then", "target_files"))
        folded_lesson = haystack.casefold()
        score = sum(folded_lesson.count(term) for term in task_terms) + (20 if lid in semantic_ids else 0)
        target = str(task.get("target_path") or "")
        if target and any(str(pattern) in target for pattern in (lesson.get("target_files") or [])):
            score += 50
        minimum = 2 if target else 8
        if score >= minimum:
            scored.append((-score, pos, lesson))
    scored.sort(key=lambda row: (row[0], row[1]))
    return [{"id": l["id"], "summary": str(l.get("summary") or l.get("title") or ""), "detail": _detail(l)} for _, _, l in scored[:limit]]


def replace_section(task_bytes: bytes, related: list[dict]) -> bytes:
    """Replace only task.related_lessons, preserving every unrelated byte."""
    text = task_bytes.decode("utf-8")
    block = yaml.safe_dump({"related_lessons": related}, allow_unicode=True, sort_keys=False).rstrip().splitlines()
    replacement = "\n".join("  " + line for line in block)
    pattern = re.compile(r"(?ms)^  related_lessons:(?:.*?)(?=^  [A-Za-z_][A-Za-z0-9_]*:|\Z)")
    if pattern.search(text):
        text = pattern.sub(replacement + "\n", text, count=1)
    else:
        text = text.rstrip() + "\n" + replacement + "\n"
    return text.encode("utf-8")


def inject_many(tasks: Iterable[bytes], lesson_blobs: Iterable[bytes], semantic_blob: bytes | None = None) -> list[bytes]:
    lessons = parse_lessons(lesson_blobs)
    semantic = parse_semantic_index(semantic_blob)
    output = []
    for raw in tasks:
        document = yaml.safe_load(raw) or {}
        task = document.get("task") or {}
        output.append(replace_section(raw, select(task, lessons, semantic)))
    return output


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--task", action="append", required=True)
    parser.add_argument("--lessons", action="append", required=True)
    parser.add_argument("--semantic-index")
    args = parser.parse_args()
    task_paths = [Path(p) for p in args.task]
    results = inject_many(
        [p.read_bytes() for p in task_paths],
        [Path(p).read_bytes() for p in args.lessons],
        Path(args.semantic_index).read_bytes() if args.semantic_index else None,
    )
    for path, result in zip(task_paths, results):
        path.write_bytes(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
