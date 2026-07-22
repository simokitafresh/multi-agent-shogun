#!/usr/bin/env python3
"""Fast, side-effect-free related-lessons selector and YAML section rewriter.

The deployment shell can load all inputs once and call ``inject_many`` for a
wave.  PyYAML is deliberately used only at the input boundary; task bytes are
updated textually so comments, ordering, and scalar styles remain unchanged.
"""
from __future__ import annotations

import argparse
import csv
import datetime
import fnmatch
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Iterable, Mapping, MutableSequence

import yaml

_CJK = r"\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff"
_BOUNDARY = re.compile(rf"(?<=[A-Za-z0-9_])(?=[{_CJK}])|(?<=[{_CJK}])(?=[A-Za-z0-9_])")
_SPLIT = re.compile(rf"[^A-Za-z0-9_{_CJK}]+")


def _terms(value: object) -> set[str]:
    words = _SPLIT.split(str(value or ""))
    expanded = (part for word in words for part in _BOUNDARY.split(word) if part)
    return {word.casefold() for word in expanded if len(word) > 3 or (len(word) >= 2 and word.isascii() and word.isupper())}


def parse_lessons(
    blobs: Iterable[bytes],
    source_projects: Iterable[str] | None = None,
    source_paths: Iterable[str] | None = None,
    errors: MutableSequence[dict[str, str]] | None = None,
) -> list[dict]:
    """Parse healthy sources once; quarantine malformed sources with provenance."""
    result = []
    blobs = list(blobs)
    sources = list(source_projects or ("" for _ in blobs))
    paths = list(source_paths or ("" for _ in blobs))
    if len(sources) != len(blobs):
        raise ValueError("source_projects must have one entry per lesson blob")
    if len(paths) != len(blobs):
        raise ValueError("source_paths must have one entry per lesson blob")
    for blob, source_project, source_path in zip(blobs, sources, paths):
        try:
            loaded = yaml.safe_load(blob) or {}
            if not isinstance(loaded, dict) or not isinstance(loaded.get("lessons", []), list):
                raise yaml.YAMLError("top-level mapping with lessons list required")
        except yaml.YAMLError as exc:
            error = {
                "level": "ERROR",
                "type": "malformed_lesson_source",
                "source_project": str(source_project or ""),
                "source_path": str(source_path or ""),
                "error": str(exc).splitlines()[0],
            }
            if errors is None:
                raise
            errors.append(error)
            continue
        for lesson in loaded.get("lessons", []):
            item = dict(lesson)
            item["_source_project"] = str(source_project or "")
            result.append(item)
    return result


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
        keys = {value.strip().casefold() for name in ("label", "aliases") for value in attrs.get(name, "").split(",") if value.strip()}
        lesson_ids = set(re.findall(r"\bL\d{2,4}\b", attrs.get("related_lessons", "")))
        for key in keys:
            result.setdefault(key, set()).update(lesson_ids)
    return result


def parse_semantic_matches(
    blob: bytes | None,
    query_text: object,
    boost: int = 20,
) -> tuple[dict[str, int], list[str]]:
    """Return the legacy semantic lesson boost map and matched concept IDs."""
    if not blob:
        return {}, []
    query_fold = str(query_text or "").casefold()
    boosts: dict[str, int] = {}
    matched: list[str] = []
    text = blob.decode("utf-8", "replace")
    for section in re.split(r"(?m)^##\s+", text)[1:]:
        lines = section.splitlines()
        if not lines:
            continue
        heading = lines[0].strip()
        concept_id, heading_label = heading.split(" — ", 1) if " — " in heading else (heading, "")
        attrs = {"id": concept_id.strip(), "label": heading_label.strip()}
        for line in lines[1:]:
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if len(cells) >= 2 and cells[0] in {"id", "label", "aliases", "related_lessons"}:
                attrs[cells[0]] = "|".join(cells[1:]).strip()
        lesson_ids = [item.strip().strip("`") for item in attrs.get("related_lessons", "").split(",")
                      if item.strip() and item.strip() != "なし"]
        terms = [attrs.get("label", ""), *[item.strip().strip("`") for item in attrs.get("aliases", "").split(",")]]
        if not lesson_ids or not any(term and (term.casefold() in query_fold or query_fold in term.casefold()) for term in terms):
            continue
        matched.append(attrs.get("id") or concept_id.strip())
        for lesson_id in lesson_ids:
            boosts[lesson_id] = max(boosts.get(lesson_id, 0), int(boost))
        if len(matched) >= 5:
            break
    return boosts, matched


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


def _subdomains(task: dict) -> set[str]:
    aliases = {"frontend": "fe", "front": "fe", "ui": "fe", "backend": "be", "back": "be",
               "api": "be", "grid_search": "gs", "grid-search": "gs", "gridsearch": "gs",
               "infra": "infra", "platform": "infra"}
    value = task.get("target_path") or []
    paths = [value] if isinstance(value, str) else list(value)
    found = set()
    for raw in paths:
        path = str(raw).replace("\\", "/").casefold()
        name = Path(path).name
        if path.startswith("frontend/") or "/frontend/" in path:
            found.add("fe")
        if path.startswith("backend/") or "/backend/" in path or "/app/api/" in path:
            found.add("be")
        if "grid_search" in path or name.startswith(("run_077", "gs_")):
            found.add("gs")
        if path.startswith(("scripts/", "queue/", "context/", "instructions/", "projects/", "config/", "tests/")) and not found:
            found.add("infra")
    return {aliases.get(item, item) for item in found}


def _lesson_subdomains(value: object) -> set[str]:
    aliases = {"frontend": "fe", "front": "fe", "ui": "fe", "backend": "be", "back": "be",
               "api": "be", "grid_search": "gs", "grid-search": "gs", "gridsearch": "gs",
               "infra": "infra", "platform": "infra"}
    raw = re.split(r"[, ]+", value) if isinstance(value, str) else (value or [])
    return {aliases.get(str(item).casefold().strip(), str(item).casefold().strip()) for item in raw if str(item).strip()}


def _tech_terms(lesson: dict) -> set[str]:
    text = " ".join(str(lesson.get(k) or "") for k in ("title", "summary", "content"))
    terms = set(re.findall(r"[a-zA-Z_][a-zA-Z0-9_.]{2,}", text.casefold()))
    terms.update(term.casefold() for term in re.findall(r"L\d{2,3}", text))
    terms.update(term.casefold() for term in re.findall(r"\.[a-z]{1,4}", text.casefold()))
    return terms


def _dedup(scored: list[tuple[int, int, dict]]) -> list[tuple[int, int, dict]]:
    accepted = []
    accepted_terms: list[set[str]] = []
    for row in scored:
        terms = _tech_terms(row[2])
        if any(terms and other and len(terms & other) / len(terms | other) >= 0.25 for other in accepted_terms):
            continue
        accepted.append(row)
        accepted_terms.append(terms)
    return accepted


def select(
    task: dict,
    lessons: list[dict],
    semantic: dict[str, set[str]],
    limit: int = 3,
    *,
    platform_projects: Iterable[str] = (),
    semantic_boosts: Mapping[str, int] | None = None,
    memory_boosts: Mapping[str, int] | None = None,
    useful_rates: Mapping[str, float] | None = None,
    _metadata: dict[str, object] | None = None,
) -> list[dict]:
    fields = ("title", "description", "purpose", "command", "target_path", "context_files", "acceptance_criteria")
    task_text = " ".join(str(task.get(field) or "") for field in fields)
    task_terms = _terms(task_text)
    folded = task_text.casefold()
    semantic_ids = {lid for phrase, ids in semantic.items() if phrase and phrase in folded for lid in ids}
    boosts = {lid: 20 for lid in semantic_ids}
    for boost_map in (semantic_boosts or {}, memory_boosts or {}):
        for lid, boost in boost_map.items():
            boosts[str(lid)] = max(boosts.get(str(lid), 0), int(boost))
    project = str(task.get("project") or "")
    platforms = {str(value) for value in platform_projects}
    task_subdomains = _subdomains(task)
    recon_mode = str(task.get("task_type") or task.get("type") or task.get("scope_mode") or "").casefold() in {
        "recon", "scout", "research"
    }
    recon_ids = {"L219", "L211", "L213", "L104", "L129", "L128"}
    filtered = []
    for lesson in lessons:
        source = str(lesson.get("_source_project") or "")
        declared = str(lesson.get("project") or "")
        if source and source not in platforms and (source != project or (declared and declared != project)):
            continue
        if not source and declared and declared != project:
            continue
        filtered.append(lesson)
    by_id: dict[str, dict] = {}
    anonymous = []
    for lesson in filtered:
        lid = str(lesson.get("id") or "")
        if lid:
            by_id[lid] = lesson
        else:
            anonymous.append(lesson)
    lessons = [*by_id.values(), *anonymous]
    task_tags = task.get("tags") or []
    task_tags = [task_tags] if isinstance(task_tags, str) else task_tags
    task_tags = {str(tag).casefold().strip() for tag in task_tags if str(tag).strip()}
    universal = []
    candidates = []
    effectiveness_excluded = []
    target = str(task.get("target_path") or "")
    rates = {str(key): float(value) for key, value in (useful_rates or {}).items()}
    for lesson in lessons:
        lid = str(lesson.get("id") or "")
        status = str(lesson.get("status") or "confirmed").casefold()
        if (not lid or status != "confirmed" or lesson.get("deprecated") or lesson.get("retired")
                or str(lesson.get("superseded_by") or "").strip()):
            continue
        domains = _lesson_subdomains(lesson.get("subdomain"))
        if task_subdomains and domains and not domains & task_subdomains:
            continue
        if recon_mode and lid not in recon_ids:
            continue
        tags = lesson.get("tags") or []
        tags = [tags] if isinstance(tags, str) else tags
        tags = {str(tag).casefold().strip() for tag in tags if str(tag).strip()}
        patterns = lesson.get("target_files") or []
        patterns = [patterns] if isinstance(patterns, str) else patterns
        target_match = bool(target) and any(
            fnmatch.fnmatch(target, str(pattern)) or fnmatch.fnmatch(Path(target).name, Path(str(pattern)).name)
            for pattern in patterns
        )
        if "universal" in tags:
            if (patterns and target_match) or (not patterns and (not task_tags or bool(task_tags & (tags - {"universal"})))):
                if rates.get(lid, 1.0) < 0.40:
                    effectiveness_excluded.append(lesson)
                else:
                    universal.append(lesson)
            continue
        if lid in boosts or not tags or not task_tags or task_tags & tags:
            if rates.get(lid, 1.0) < 0.40:
                effectiveness_excluded.append(lesson)
            else:
                candidates.append(lesson)
    lessons = candidates
    scored = []
    for pos, lesson in enumerate(lessons):
        lid = str(lesson.get("id") or "")
        source = str(lesson.get("_source_project") or "")
        declared = str(lesson.get("project") or "")
        haystack = " ".join(str(lesson.get(k) or "") for k in ("title", "summary", "detail", "content", "tags", "when", "if_then", "target_files"))
        folded_lesson = haystack.casefold()
        title = str(lesson.get("title") or "").casefold()
        other = " ".join(str(lesson.get(k) or "") for k in ("summary", "content", "source", "when", "how")).casefold()
        keyword_score = sum(title.count(term) * 3 + other.count(term) for term in task_terms)
        score = keyword_score
        if not str(lesson.get("when") or "").strip() or str(lesson.get("when")).strip() == "未設定":
            score -= 10
        if boosts.get(lid) and keyword_score > 0:
            score += boosts[lid]
        patterns = lesson.get("target_files") or []
        patterns = [patterns] if isinstance(patterns, str) else patterns
        target_match = target and any(
            fnmatch.fnmatch(target, str(pattern))
            or fnmatch.fnmatch(Path(target).name, Path(str(pattern)).name)
            for pattern in patterns
        )
        if patterns and not target_match and lid not in boosts:
            continue
        if keyword_score > 0 and target_match:
            score += 50
        minimum = 2 if target else 8
        if score >= minimum:
            if source == project or (not source and declared == project):
                score += 2
            scored.append((-score, pos, lesson))
    scored.sort(key=lambda row: (row[0], row[1]))
    scored = _dedup(scored)
    scored.sort(key=lambda row: (row[0], -(row[2].get("helpful_count", 0) or 0)))
    universal.sort(key=lambda lesson: -(lesson.get("helpful_count", 0) or 0))
    chosen = universal[:1] + [row[2] for row in scored[: max(0, limit - min(1, len(universal)))]]
    related = []
    for lesson in chosen:
        entry = {"id": lesson["id"], "summary": str(lesson.get("summary") or lesson.get("title") or "")}
        detail = _detail(lesson)[:200]
        if detail:
            entry["detail"] = detail
        related.append(entry)
    if _metadata is not None:
        chosen_ids = {str(lesson.get("id") or "") for lesson in chosen}
        scored_lessons = [row[2] for row in scored]
        withheld = [*effectiveness_excluded]
        withheld.extend(lesson for lesson in [*universal, *scored_lessons]
                        if str(lesson.get("id") or "") not in chosen_ids and str(lesson.get("id") or "") in rates)
        unique_withheld = {}
        for lesson in withheld:
            unique_withheld[str(lesson.get("id") or "")] = {
                "id": str(lesson.get("id") or ""),
                "summary": str(lesson.get("summary") or lesson.get("title") or ""),
            }
        _metadata.update({
            "available": len(candidates) + len(universal),
            "withheld": list(unique_withheld.values()),
            "scores": {str(row[2].get("id") or ""): -row[0] for row in scored},
        })
    return related


def replace_section(task_bytes: bytes, related: list[dict]) -> bytes:
    """Replace only task.related_lessons, preserving every unrelated byte."""
    text = task_bytes.decode("utf-8")
    lines = ["  related_lessons:"]
    for lesson in related:
        lines.extend((
            f"  - id: {json.dumps(str(lesson['id']), ensure_ascii=False)}",
            f"    summary: {json.dumps(str(lesson['summary']), ensure_ascii=False)}",
        ))
        if lesson.get("detail"):
            lines.append(f"    detail: {json.dumps(str(lesson['detail']), ensure_ascii=False)}")
    if not related:
        lines[0] += " []"
    replacement = "\n".join(lines)
    pattern = re.compile(r"(?ms)^  related_lessons:(?:.*?)(?=^  [A-Za-z_][A-Za-z0-9_]*:|\Z)")
    if pattern.search(text):
        text = pattern.sub(replacement + "\n", text, count=1)
    else:
        text = text.rstrip() + "\n" + replacement + "\n"
    if related:
        document = yaml.safe_load(text) or {}
        task = document.get("task") or {}
        description = str(task.get("description") or "")
        if "【注入教訓】" not in description:
            prefix = ["【注入教訓】 必ず確認してから作業開始せよ"]
            prefix.extend(f"  - {item['id']}: {str(item['summary'])[:80]}" for item in related)
            prefix.extend(("─" * 40, ""))
            description = "\n".join(prefix) + "\n" + description
            desc_pattern = re.compile(r"(?ms)^  description:(?:.*?)(?=^  [A-Za-z_][A-Za-z0-9_]*:|\Z)")
            replacement = "  description: |-\n" + "\n".join(f"    {line}" for line in description.split("\n")) + "\n"
            if desc_pattern.search(text):
                text = desc_pattern.sub(replacement, text, count=1)
            else:
                text = text.rstrip() + "\n" + replacement
    return text.encode("utf-8")


def inject_many(
    tasks: Iterable[bytes],
    lesson_blobs: Iterable[bytes],
    semantic_blob: bytes | None = None,
    *,
    source_projects: Iterable[str] | None = None,
    source_paths: Iterable[str] | None = None,
    source_errors: MutableSequence[dict[str, str]] | None = None,
    platform_projects: Iterable[str] = (),
    semantic_boosts: Mapping[str, int] | None = None,
    memory_boosts: Mapping[str, int] | None = None,
    useful_rates: Mapping[str, float] | None = None,
) -> list[bytes]:
    lessons = parse_lessons(lesson_blobs, source_projects, source_paths, source_errors)
    semantic = parse_semantic_index(semantic_blob)
    output = []
    for raw in tasks:
        document = yaml.safe_load(raw) or {}
        task = document.get("task") or {}
        output.append(replace_section(raw, select(
            task, lessons, semantic, platform_projects=platform_projects,
            semantic_boosts=semantic_boosts, memory_boosts=memory_boosts, useful_rates=useful_rates,
        )))
    return output


_IMPACT_COLUMNS = (
    "timestamp", "cmd_id", "ninja", "lesson_id", "action", "result",
    "referenced", "project", "task_type", "bloom_level", "score", "traversal_depth",
)


def _task_text(task: dict, root: Path) -> str:
    command = str(task.get("command") or "")
    parent_cmd = str(task.get("parent_cmd") or "")
    if not command and parent_cmd:
        try:
            commands = yaml.safe_load((root / "queue/shogun_to_karo.yaml").read_bytes()) or {}
            command = str((commands.get("commands") or {}).get(parent_cmd, {}).get("command") or "")
        except (OSError, yaml.YAMLError):
            pass
    context_files = task.get("context_files") or []
    context_text = " ".join(str(item) for item in context_files) if isinstance(context_files, list) else str(context_files)
    acceptance = task.get("acceptance_criteria") or []
    if isinstance(acceptance, list):
        acceptance_text = " ".join(str(item.get("description") or "") if isinstance(item, dict) else str(item) for item in acceptance)
    else:
        acceptance_text = str(acceptance)
    return " ".join(str(task.get(key) or "") for key in ("title", "description", "purpose")) + \
        f" {command} {task.get('target_path') or ''} {context_text} {acceptance_text}"


def _useful_rates(path: Path) -> dict[str, float]:
    counts: dict[str, list[int]] = {}
    try:
        with path.open(encoding="utf-8", newline="") as stream:
            for row in csv.DictReader(stream, delimiter="\t"):
                lesson_id = str(row.get("lesson_id") or "").strip()
                if str(row.get("action") or "").strip().casefold() != "feedback" or not lesson_id:
                    continue
                result = str(row.get("result") or "").strip().upper()
                if result not in {"USEFUL", "NOT_USEFUL"}:
                    continue
                counts.setdefault(lesson_id, [0, 0])[1] += 1
                counts[lesson_id][0] += result == "USEFUL"
    except OSError:
        return {}
    return {lesson_id: useful / total for lesson_id, (useful, total) in counts.items() if total}


def _publish_bytes(path: Path, content: bytes) -> None:
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def _publish_side_effects(
    root: Path,
    task_path: Path,
    task: dict,
    project: str,
    available: int,
    withheld: Iterable[dict] = (),
    scores: Mapping[str, int] | None = None,
) -> None:
    related = [item for item in (task.get("related_lessons") or []) if isinstance(item, dict) and item.get("id")]
    postcondition = task_path.parent / ".postcond_lesson_inject"
    postcondition.write_text(
        f"available={available}\ninjected={len(related)}\n"
        f"task_id={task.get('task_id') or 'unknown'}\nproject={project}\n"
        f"injected_ids={' '.join(str(item['id']) for item in related)}\n",
        encoding="utf-8",
    )
    impact = root / "logs/lesson_impact.tsv"
    impact.parent.mkdir(parents=True, exist_ok=True)
    existing = set()
    if impact.exists():
        try:
            with impact.open(encoding="utf-8", newline="") as stream:
                for row in csv.DictReader(stream, delimiter="\t"):
                    existing.add((str(row.get("cmd_id") or ""), str(row.get("lesson_id") or "")))
        except OSError:
            pass
    write_header = not impact.exists() or impact.stat().st_size == 0
    cmd_id = str(task.get("task_id") or task.get("parent_cmd") or "unknown")
    with impact.open("a", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        if write_header:
            writer.writerow(_IMPACT_COLUMNS)
        for item in related:
            key = (cmd_id, str(item["id"]))
            if key in existing:
                continue
            writer.writerow((
                datetime.datetime.now().isoformat(timespec="seconds"), cmd_id, task_path.stem,
                item["id"], "injected", "pending", "pending", project,
                task.get("task_type") or task.get("type") or "unknown",
                task.get("bloom_level") or "unknown", 0, 0,
            ))
            existing.add(key)
        for item in withheld:
            lesson_id = str(item.get("id") or "")
            key = (cmd_id, lesson_id)
            if not lesson_id or key in existing:
                continue
            writer.writerow((
                datetime.datetime.now().isoformat(timespec="seconds"), cmd_id, task_path.stem,
                lesson_id, "withheld", "pending", "no", project,
                task.get("task_type") or task.get("type") or "unknown",
                task.get("bloom_level") or "unknown", (scores or {}).get(lesson_id, 0), 0,
            ))
            existing.add(key)


def inject_repository_task(
    task_path: Path,
    root: Path,
    *,
    memory_database: Path | None = None,
    memory_cache: Path | None = None,
) -> dict[str, object]:
    """Run the single S1 related+memory selection and publish legacy side effects."""
    raw = task_path.read_bytes()
    document = yaml.safe_load(raw) or {}
    task = document.get("task") or {}
    if str(task.get("parent_cmd") or "").startswith("cmd_training_L4_") and str(task.get("task_type") or "normal") == "normal":
        return {"injected": 0, "available": 0, "skipped": "training_L4"}
    project = str(task.get("project") or "").strip()
    if not project:
        try:
            config = yaml.safe_load((root / "config/projects.yaml").read_bytes()) or {}
            project = str(config.get("current_project") or "").strip()
        except (OSError, yaml.YAMLError):
            project = ""
    if not project:
        return {"injected": 0, "available": 0, "skipped": "no_project"}

    config = yaml.safe_load((root / "config/projects.yaml").read_bytes()) or {}
    platform_ids = [str(item.get("id") or "").strip() for item in config.get("projects", [])
                    if item.get("type") == "platform" and str(item.get("id") or "").strip()]
    source_ids = [project, *[item for item in platform_ids if item != project]]
    lesson_paths = []
    lesson_sources = []
    for source_id in source_ids:
        index = root / "projects" / source_id / "lessons.yaml"
        archive = root / "projects" / source_id / "lessons_archive.yaml"
        path = index if index.exists() else archive
        if path.exists():
            lesson_paths.append(path)
            lesson_sources.append(source_id)
    semantic_path = root / "docs/semantic-index/index.md"
    semantic_blob = semantic_path.read_bytes() if semantic_path.exists() else None
    query_text = _task_text(task, root)
    semantic_boosts, matched_concepts = parse_semantic_matches(semantic_blob, query_text)

    memory_boosts: dict[str, int] = {}
    memory_events = 0
    database = memory_database or Path(os.environ.get("MEMORY_DB_PATH", root / "data/multi_agent_shogun_memory.db"))
    if memory_database is None and database.exists():
        cache_helper = root / "scripts/lib/memory_db_cache.sh"
        if cache_helper.exists():
            command = 'source "$1"; prepare_memory_db_for_read "$2" "$3" "$3"'
            try:
                resolved = subprocess.run(
                    ["bash", "-c", command, "_", str(cache_helper), str(root), str(database)],
                    check=False, capture_output=True, text=True, timeout=5,
                ).stdout.strip()
                if resolved:
                    database = Path(resolved)
            except (OSError, subprocess.SubprocessError):
                pass
    cache = memory_cache or Path(os.environ.get("DEPLOY_LESSON_MEMORY_CACHE_DIR", "/tmp/shogun-memory-boost"))
    memory_helper = Path(__file__).with_name("deploy_task_lesson_memory_boost_fast.py")
    if memory_helper.exists() and database.exists():
        spec = importlib.util.spec_from_file_location("deploy_task_lesson_memory_boost_fast", memory_helper)
        if spec and spec.loader:
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            memory_boosts, _, memory_events = module.query_lesson_boosts(
                database, cache, query_text, matched_concepts,
                int(os.environ.get("MEMORY_DB_LESSON_BOOST", "20")),
            )
    lesson_blobs = [path.read_bytes() for path in lesson_paths]
    source_errors: list[dict[str, str]] = []
    lessons = parse_lessons(
        lesson_blobs, lesson_sources, [str(path) for path in lesson_paths], source_errors,
    )
    semantic = parse_semantic_index(semantic_blob)
    rates = _useful_rates(root / "logs/lesson_impact.tsv")
    metadata: dict[str, object] = {}
    related = select(
        task, lessons, semantic, platform_projects=platform_ids,
        semantic_boosts=semantic_boosts, memory_boosts=memory_boosts,
        useful_rates=rates, _metadata=metadata,
    )
    result = replace_section(raw, related)
    _publish_bytes(task_path, result)
    final_task = (yaml.safe_load(result) or {}).get("task") or {}
    available = int(metadata.get("available") or 0)
    _publish_side_effects(
        root, task_path, final_task, project, available,
        metadata.get("withheld") or (), metadata.get("scores") or {},
    )
    return {
        "injected": len(final_task.get("related_lessons") or []), "available": available,
        "project": project, "semantic_concepts": matched_concepts, "memory_events": memory_events,
        "source_errors": source_errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--task", action="append", required=True)
    parser.add_argument("--lessons", action="append")
    parser.add_argument("--semantic-index")
    parser.add_argument("--source-project", action="append")
    parser.add_argument("--platform-project", action="append", default=[])
    parser.add_argument("--semantic-boosts-json")
    parser.add_argument("--memory-boosts-json")
    parser.add_argument("--useful-rates-json")
    parser.add_argument("--repository-root", type=Path)
    args = parser.parse_args()
    task_paths = [Path(p) for p in args.task]
    if args.repository_root:
        for path in task_paths:
            print(json.dumps(inject_repository_task(path, args.repository_root), ensure_ascii=False, sort_keys=True))
        return 0
    if not args.lessons:
        parser.error("--lessons is required without --repository-root")
    def load_map(path: str | None) -> dict:
        return json.loads(Path(path).read_text()) if path else {}

    source_errors: list[dict[str, str]] = []
    results = inject_many(
        [p.read_bytes() for p in task_paths],
        [Path(p).read_bytes() for p in args.lessons],
        Path(args.semantic_index).read_bytes() if args.semantic_index else None,
        source_projects=args.source_project,
        source_paths=args.lessons,
        source_errors=source_errors,
        platform_projects=args.platform_project,
        semantic_boosts=load_map(args.semantic_boosts_json),
        memory_boosts=load_map(args.memory_boosts_json),
        useful_rates=load_map(args.useful_rates_json),
    )
    for error in source_errors:
        print(json.dumps(error, ensure_ascii=False, sort_keys=True), file=sys.stderr)
    for path, result in zip(task_paths, results):
        fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(result)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, path)
        except BaseException:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass
            raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
