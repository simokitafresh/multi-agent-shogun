#!/usr/bin/env python3
# semantic-links: [[SQLite記憶DB]], [[セマンティック辞書構想]]
"""Build the local SQLite memory DB from multi-agent event archives."""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
from pathlib import Path
from typing import Any, Iterable

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ARCHIVE_DIR = REPO_ROOT / "logs" / "lord_conversation_archive"
DEFAULT_DB_PATH = REPO_ROOT / "data" / "multi_agent_shogun_memory.db"
DEFAULT_SEMANTIC_INDEX_PATH = REPO_ROOT / "docs" / "semantic-index" / "index.md"
DEFAULT_BULLETIN_FILE = REPO_ROOT / "queue" / "bulletin_board.yaml"
DEFAULT_BULLETIN_ARCHIVE_DIR = REPO_ROOT / "queue" / "archive"
DEFAULT_INSIGHTS_FILE = REPO_ROOT / "queue" / "insights.yaml"
DEFAULT_SKILL_EXECUTION_LOG = REPO_ROOT / "logs" / "skill_execution_log.yaml"
DEFAULT_CMD_ARCHIVE_DIR = REPO_ROOT / "queue" / "archive" / "cmds"
DEFAULT_PENDING_DECISIONS_FILE = REPO_ROOT / "queue" / "pending_decisions.yaml"
CMD_RE = re.compile(r"\bcmd_[A-Za-z0-9_]+\b")
OBSIDIAN_LINK_RE = re.compile(r"\[\[([^\[\]]+)\]\]")
SQLITE_BUSY_TIMEOUT_MS = 5000
EventRow = tuple[str, str, str, str, str, str, str, str, str, str, str, str, None, str]


def normalize_text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).replace("\r\n", "\n").replace("\r", "\n").strip()


def iter_jsonl_files(archive_dir: Path) -> Iterable[Path]:
    if not archive_dir.exists():
        return []
    return sorted(path for path in archive_dir.glob("*.jsonl") if path.is_file())


def iter_bulletin_files(bulletin_file: Path, bulletin_archive_dir: Path) -> Iterable[Path]:
    paths: list[Path] = []
    if bulletin_file.is_file():
        paths.append(bulletin_file)
    if bulletin_archive_dir.is_dir():
        paths.extend(sorted(path for path in bulletin_archive_dir.glob("bulletin_*.yaml") if path.is_file()))
        archive_file = bulletin_archive_dir / "bulletin_board_archive.yaml"
        if archive_file.is_file():
            paths.append(archive_file)
        nested_archive_dir = bulletin_archive_dir / "bulletin_board"
        if nested_archive_dir.is_dir():
            paths.extend(sorted(path for path in nested_archive_dir.glob("*.yaml") if path.is_file()))
    seen: set[Path] = set()
    for path in paths:
        resolved = path.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        yield path


def row_from_line(path: Path, raw: str) -> tuple[str, str, str, str, str, str, str]:
    line = raw.rstrip("\n")
    try:
        parsed = json.loads(line)
    except json.JSONDecodeError:
        parsed = {
            "ts": "",
            "agent": "",
            "direction": "invalid",
            "summary": "JSONL parse error",
            "detail": line,
        }

    if not isinstance(parsed, dict):
        parsed = {
            "ts": "",
            "agent": "",
            "direction": "invalid",
            "summary": "Non-object JSONL entry",
            "detail": line,
        }

    return (
        normalize_text(parsed.get("ts")),
        normalize_text(parsed.get("agent")),
        normalize_text(parsed.get("direction")),
        normalize_text(parsed.get("summary")),
        normalize_text(parsed.get("detail")),
        normalize_text(parsed.get("session_id")) or path.stem,
        str(path),
    )


def load_rows(archive_dir: Path) -> list[tuple[str, str, str, str, str, str, str]]:
    rows: list[tuple[str, str, str, str, str, str, str]] = []
    for path in iter_jsonl_files(archive_dir):
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            for raw in handle:
                if not raw.strip():
                    continue
                rows.append(row_from_line(path, raw))
    return rows


def load_bulletin_entries(bulletin_file: Path, bulletin_archive_dir: Path) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for path in iter_bulletin_files(bulletin_file, bulletin_archive_dir):
        try:
            payload = yaml.safe_load(path.read_text(encoding="utf-8", errors="replace")) or {}
        except yaml.YAMLError:
            payload = {}
        if not isinstance(payload, dict):
            continue
        raw_entries = payload.get("entries", [])
        if not isinstance(raw_entries, list):
            continue
        for entry in raw_entries:
            if not isinstance(entry, dict):
                continue
            normalized = dict(entry)
            normalized["_source_file"] = str(path)
            entries.append(normalized)
    return entries


def load_insight_entries(insights_file: Path) -> list[dict[str, Any]]:
    try:
        payload = yaml.safe_load(insights_file.read_text(encoding="utf-8", errors="replace")) or {}
    except (FileNotFoundError, yaml.YAMLError):
        return []
    if not isinstance(payload, dict):
        return []
    raw_entries = payload.get("insights", [])
    if not isinstance(raw_entries, list):
        return []
    entries: list[dict[str, Any]] = []
    for entry in raw_entries:
        if not isinstance(entry, dict):
            continue
        normalized = dict(entry)
        normalized["_source_file"] = str(insights_file)
        entries.append(normalized)
    return entries


def load_skill_execution_entries(skill_execution_log: Path) -> list[dict[str, Any]]:
    try:
        payload = yaml.safe_load(skill_execution_log.read_text(encoding="utf-8", errors="replace")) or {}
    except (FileNotFoundError, yaml.YAMLError):
        return []
    if not isinstance(payload, dict):
        return []
    raw_entries = payload.get("executions", [])
    if not isinstance(raw_entries, list):
        return []
    entries: list[dict[str, Any]] = []
    for entry in raw_entries:
        if not isinstance(entry, dict):
            continue
        normalized = dict(entry)
        normalized["_source_file"] = str(skill_execution_log)
        entries.append(normalized)
    return entries


def iter_cmd_archive_files(cmd_archive_dir: Path) -> Iterable[Path]:
    if not cmd_archive_dir.is_dir():
        return []
    return sorted(path for path in cmd_archive_dir.glob("*.yaml") if path.is_file())


def load_cmd_archive_entries(cmd_archive_dir: Path) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for path in iter_cmd_archive_files(cmd_archive_dir):
        try:
            payload = yaml.safe_load(path.read_text(encoding="utf-8", errors="replace")) or {}
        except yaml.YAMLError:
            continue
        if not isinstance(payload, dict):
            continue
        commands = payload.get("commands", {})
        if isinstance(commands, dict):
            raw_entries = commands.values()
        elif isinstance(commands, list):
            raw_entries = commands
        else:
            raw_entries = []
        for entry in raw_entries:
            if not isinstance(entry, dict):
                continue
            normalized = dict(entry)
            normalized["_source_file"] = str(path)
            normalized["_source_stem"] = path.stem
            entries.append(normalized)
    return entries


def load_pending_decision_entries(pending_decisions_file: Path) -> list[dict[str, Any]]:
    try:
        payload = yaml.safe_load(pending_decisions_file.read_text(encoding="utf-8", errors="replace")) or {}
    except (FileNotFoundError, yaml.YAMLError):
        return []
    if not isinstance(payload, dict):
        return []
    raw_entries = payload.get("decisions", [])
    if not isinstance(raw_entries, list):
        return []
    entries: list[dict[str, Any]] = []
    for entry in raw_entries:
        if not isinstance(entry, dict):
            continue
        normalized = dict(entry)
        normalized["_source_file"] = str(pending_decisions_file)
        entries.append(normalized)
    return entries


def iter_semantic_concepts(index_path: Path) -> Iterable[dict[str, Any]]:
    if not index_path.exists():
        return []

    concepts: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for raw_line in index_path.read_text(encoding="utf-8", errors="replace").splitlines():
        heading = re.match(r"^##\s+([A-Za-z0-9_-]+)\s+—\s+(.+?)\s*$", raw_line)
        if heading:
            if current:
                concepts.append(current)
            current = {
                "id": heading.group(1).strip(),
                "label": heading.group(2).strip(),
                "aliases": [],
            }
            continue
        if current is None:
            continue
        alias_match = re.match(r"^\|\s*aliases\s*\|\s*(.*?)\s*\|$", raw_line)
        if alias_match:
            current["aliases"] = [
                alias.strip()
                for alias in alias_match.group(1).split(",")
                if alias.strip()
            ]
    if current:
        concepts.append(current)
    return concepts


def concept_terms(concept: dict[str, Any]) -> list[str]:
    terms = [concept["id"], concept["label"], *concept.get("aliases", [])]
    return [term for term in terms if len(term) >= 3]


def concepts_for_text(text: str, concepts: Iterable[dict[str, Any]]) -> str:
    haystack = text.casefold()
    matched: list[str] = []
    for concept in concepts:
        if any(term.casefold() in haystack for term in concept_terms(concept)):
            matched.append(concept["id"])
    return json.dumps(sorted(set(matched)), ensure_ascii=False)


def infer_cmd_id(summary: str, detail: str) -> str:
    match = CMD_RE.search(f"{summary}\n{detail}")
    return match.group(0) if match else ""


def infer_target(agent: str, direction: str) -> str:
    if direction == "inbound":
        return "shogun"
    if direction in {"response", "outbound"}:
        return "lord"
    return ""


def event_rows_from_conversations(
    rows: list[tuple[str, str, str, str, str, str, str]],
    concepts: list[dict[str, Any]],
) -> list[EventRow]:
    event_rows: list[EventRow] = []
    for idx, (ts, agent, direction, summary, detail, session_id, source_file) in enumerate(rows, start=1):
        event_rows.append(
            (
                f"conversation:{session_id}:{idx}",
                ts,
                "conversation",
                agent,
                infer_target(agent, direction),
                direction,
                summary,
                detail,
                session_id,
                infer_cmd_id(summary, detail),
                concepts_for_text(f"{summary}\n{detail}", concepts),
                source_file,
                None,
                "normal",
            )
        )
    return event_rows


def bulletin_summary(content: str, action_type: str, status: str) -> str:
    first_line = next((line.strip() for line in content.splitlines() if line.strip()), "")
    if first_line:
        return first_line[:240]
    parts = [part for part in [action_type, status] if part]
    return "bulletin " + " ".join(parts) if parts else "bulletin"


def bulletin_requires_confirmation(value: Any) -> str:
    if isinstance(value, list):
        return ",".join(normalize_text(item) for item in value if normalize_text(item))
    if isinstance(value, bool):
        return "true" if value else "false"
    return normalize_text(value)


def event_rows_from_bulletins(
    entries: list[dict[str, Any]],
    concepts: list[dict[str, Any]],
) -> list[EventRow]:
    event_rows: list[EventRow] = []
    seen_ids: set[str] = set()
    for idx, entry in enumerate(entries, start=1):
        raw_id = normalize_text(entry.get("id")) or f"generated:{idx}"
        event_id = f"bulletin:{raw_id}"
        if event_id in seen_ids:
            continue
        seen_ids.add(event_id)
        content = normalize_text(entry.get("content"))
        action_type = normalize_text(entry.get("action_type"))
        status = normalize_text(entry.get("status"))
        detail = "\n".join(
            line
            for line in [
                content,
                f"action_type: {action_type}" if action_type else "",
                f"status: {status}" if status else "",
                f"actioned_by: {normalize_text(entry.get('actioned_by'))}" if normalize_text(entry.get("actioned_by")) else "",
                f"requires_confirmation: {bulletin_requires_confirmation(entry.get('requires_confirmation'))}",
            ]
            if line
        )
        summary = bulletin_summary(content, action_type, status)
        event_rows.append(
            (
                event_id,
                normalize_text(entry.get("posted_at")),
                "bulletin",
                normalize_text(entry.get("posted_by")),
                normalize_text(entry.get("actioned_by")),
                action_type or "bulletin",
                summary,
                detail,
                "",
                infer_cmd_id(summary, detail),
                concepts_for_text(f"{summary}\n{detail}", concepts),
                normalize_text(entry.get("_source_file")),
                None,
                "high" if action_type == "action_required" and status != "closed" else "normal",
            )
        )
    return event_rows


def event_rows_from_insights(
    entries: list[dict[str, Any]],
    concepts: list[dict[str, Any]],
) -> list[EventRow]:
    event_rows: list[EventRow] = []
    seen_ids: set[str] = set()
    for idx, entry in enumerate(entries, start=1):
        raw_id = normalize_text(entry.get("id")) or f"generated:{idx}"
        event_id = f"insight:{raw_id}"
        if event_id in seen_ids:
            continue
        seen_ids.add(event_id)
        insight = normalize_text(entry.get("insight"))
        status = normalize_text(entry.get("status"))
        priority = normalize_text(entry.get("priority"))
        source = normalize_text(entry.get("source"))
        resolved_reason = normalize_text(entry.get("resolved_reason"))
        detail = "\n".join(
            line
            for line in [
                insight,
                f"status: {status}" if status else "",
                f"priority: {priority}" if priority else "",
                f"source: {source}" if source else "",
                f"resolved_reason: {resolved_reason}" if resolved_reason else "",
            ]
            if line
        )
        summary = insight[:240] if insight else "insight"
        importance = "high" if priority == "high" or status == "pending" else "normal"
        event_rows.append(
            (
                event_id,
                normalize_text(entry.get("ts")),
                "insight",
                source,
                "",
                status or "insight",
                summary,
                detail,
                "",
                infer_cmd_id(summary, detail),
                concepts_for_text(f"{summary}\n{detail}", concepts),
                normalize_text(entry.get("_source_file")),
                None,
                importance,
            )
        )
    return event_rows


def event_rows_from_skill_executions(
    entries: list[dict[str, Any]],
    concepts: list[dict[str, Any]],
) -> list[EventRow]:
    event_rows: list[EventRow] = []
    seen_ids: set[str] = set()
    for idx, entry in enumerate(entries, start=1):
        skill = normalize_text(entry.get("skill"))
        executor = normalize_text(entry.get("executor"))
        result = normalize_text(entry.get("result"))
        stumbling_points = normalize_text(entry.get("stumbling_points"))
        gate = normalize_text(entry.get("gate"))
        source = normalize_text(entry.get("source"))
        raw_id = ":".join(
            part
            for part in [normalize_text(entry.get("ts")), skill, executor, source, str(idx)]
            if part
        )
        event_id = f"skill_execution:{raw_id or idx}"
        if event_id in seen_ids:
            continue
        seen_ids.add(event_id)
        detail = "\n".join(
            line
            for line in [
                stumbling_points,
                f"skill: {skill}" if skill else "",
                f"result: {result}" if result else "",
                f"gate: {gate}" if gate else "",
                f"source: {source}" if source else "",
                f"skill_path: {normalize_text(entry.get('skill_path'))}" if normalize_text(entry.get("skill_path")) else "",
                f"used: {normalize_text(entry.get('used'))}" if normalize_text(entry.get("used")) else "",
            ]
            if line
        )
        summary = f"{skill} {result}".strip()
        if stumbling_points:
            summary = f"{summary}: {stumbling_points[:180]}" if summary else stumbling_points[:240]
        event_rows.append(
            (
                event_id,
                normalize_text(entry.get("ts")),
                "skill_execution",
                executor,
                skill,
                result or "skill_execution",
                summary or "skill_execution",
                detail,
                "",
                infer_cmd_id(source, stumbling_points),
                concepts_for_text(f"{summary}\n{detail}", concepts),
                normalize_text(entry.get("_source_file")),
                None,
                "high" if result == "FAIL" else "normal",
            )
        )
    return event_rows


def event_rows_from_cmd_archives(
    entries: list[dict[str, Any]],
    concepts: list[dict[str, Any]],
) -> list[EventRow]:
    event_rows: list[EventRow] = []
    seen_ids: set[str] = set()
    for idx, entry in enumerate(entries, start=1):
        cmd_id = normalize_text(entry.get("id")) or f"generated:{idx}"
        source_stem = normalize_text(entry.get("_source_stem"))
        event_id = f"cmd_archive:{cmd_id}:{source_stem or idx}"
        if event_id in seen_ids:
            continue
        seen_ids.add(event_id)
        purpose = normalize_text(entry.get("purpose"))
        title = normalize_text(entry.get("title"))
        status = normalize_text(entry.get("status"))
        acceptance_criteria = entry.get("acceptance_criteria", [])
        if isinstance(acceptance_criteria, list):
            ac_detail = "\n".join(f"- {normalize_text(item)}" for item in acceptance_criteria if normalize_text(item))
        else:
            ac_detail = normalize_text(acceptance_criteria)
        detail = "\n".join(
            line
            for line in [
                purpose,
                f"title: {title}" if title else "",
                f"project: {normalize_text(entry.get('project'))}" if normalize_text(entry.get("project")) else "",
                f"type: {normalize_text(entry.get('type'))}" if normalize_text(entry.get("type")) else "",
                f"status: {status}" if status else "",
                f"acceptance_criteria:\n{ac_detail}" if ac_detail else "",
            ]
            if line
        )
        summary = title or purpose[:240] or cmd_id
        event_rows.append(
            (
                event_id,
                normalize_text(entry.get("timestamp")),
                "cmd_archive",
                "shogun",
                normalize_text(entry.get("project")),
                status or "archived",
                summary,
                detail,
                "",
                cmd_id,
                concepts_for_text(f"{summary}\n{detail}", concepts),
                normalize_text(entry.get("_source_file")),
                None,
                "normal",
            )
        )
    return event_rows


def event_rows_from_pending_decisions(
    entries: list[dict[str, Any]],
    concepts: list[dict[str, Any]],
) -> list[EventRow]:
    event_rows: list[EventRow] = []
    seen_ids: set[str] = set()
    for idx, entry in enumerate(entries, start=1):
        raw_id = normalize_text(entry.get("id")) or f"generated:{idx}"
        event_id = f"pending_decision:{raw_id}"
        if event_id in seen_ids:
            continue
        seen_ids.add(event_id)
        summary = normalize_text(entry.get("summary")) or raw_id
        status = normalize_text(entry.get("status"))
        resolution = normalize_text(entry.get("resolution")) or normalize_text(entry.get("resolved_content"))
        detail = "\n".join(
            line
            for line in [
                summary,
                f"type: {normalize_text(entry.get('type'))}" if normalize_text(entry.get("type")) else "",
                f"status: {status}" if status else "",
                f"source_cmd: {normalize_text(entry.get('source_cmd'))}" if normalize_text(entry.get("source_cmd")) else "",
                f"resolution: {resolution}" if resolution else "",
                f"context_synced: {normalize_text(entry.get('context_synced'))}" if normalize_text(entry.get("context_synced")) else "",
            ]
            if line
        )
        event_rows.append(
            (
                event_id,
                normalize_text(entry.get("created_at")),
                "pending_decision",
                normalize_text(entry.get("created_by")),
                normalize_text(entry.get("source_cmd")),
                status or normalize_text(entry.get("type")) or "pending_decision",
                summary[:240],
                detail,
                "",
                infer_cmd_id(normalize_text(entry.get("source_cmd")), summary),
                concepts_for_text(f"{summary}\n{detail}", concepts),
                normalize_text(entry.get("_source_file")),
                None,
                "high" if status == "pending" else "normal",
            )
        )
    return event_rows


def event_link_rows(
    event_rows: list[EventRow],
) -> list[tuple[str, str, str]]:
    rows: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str, str]] = set()
    for event_row in event_rows:
        event_id = event_row[0]
        text = f"{event_row[6]}\n{event_row[7]}"
        for match in OBSIDIAN_LINK_RE.finditer(text):
            concept = match.group(1).strip()
            if not concept:
                continue
            key = (event_id, concept, "obsidian")
            if key in seen:
                continue
            seen.add(key)
            rows.append(key)
    return rows


def event_concept_rows(
    event_rows: list[EventRow],
) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for event_row in event_rows:
        event_id = event_row[0]
        concepts_raw = event_row[10]
        try:
            concept_names = json.loads(concepts_raw)
        except json.JSONDecodeError:
            concept_names = []
        if not isinstance(concept_names, list):
            continue
        for concept_name_raw in concept_names:
            concept_name = normalize_text(concept_name_raw)
            if not concept_name:
                continue
            key = (event_id, concept_name)
            if key in seen:
                continue
            seen.add(key)
            rows.append(key)
    return rows


def default_bulletin_paths_for_archive(archive_dir: Path) -> tuple[Path, Path]:
    try:
        if archive_dir.resolve() == DEFAULT_ARCHIVE_DIR.resolve():
            return DEFAULT_BULLETIN_FILE, DEFAULT_BULLETIN_ARCHIVE_DIR
    except FileNotFoundError:
        pass
    base_dir = archive_dir.parent
    return base_dir / "queue" / "bulletin_board.yaml", base_dir / "queue" / "archive"


def default_insights_path_for_archive(archive_dir: Path) -> Path:
    try:
        if archive_dir.resolve() == DEFAULT_ARCHIVE_DIR.resolve():
            return DEFAULT_INSIGHTS_FILE
    except FileNotFoundError:
        pass
    return archive_dir.parent / "queue" / "insights.yaml"


def default_skill_execution_log_for_archive(archive_dir: Path) -> Path:
    try:
        if archive_dir.resolve() == DEFAULT_ARCHIVE_DIR.resolve():
            return DEFAULT_SKILL_EXECUTION_LOG
    except FileNotFoundError:
        pass
    return archive_dir.parent / "logs" / "skill_execution_log.yaml"


def default_cmd_archive_dir_for_archive(archive_dir: Path) -> Path:
    try:
        if archive_dir.resolve() == DEFAULT_ARCHIVE_DIR.resolve():
            return DEFAULT_CMD_ARCHIVE_DIR
    except FileNotFoundError:
        pass
    return archive_dir.parent / "queue" / "archive" / "cmds"


def default_pending_decisions_path_for_archive(archive_dir: Path) -> Path:
    try:
        if archive_dir.resolve() == DEFAULT_ARCHIVE_DIR.resolve():
            return DEFAULT_PENDING_DECISIONS_FILE
    except FileNotFoundError:
        pass
    return archive_dir.parent / "queue" / "pending_decisions.yaml"


def search_events(db_path: Path, query: str, limit: int = 20) -> list[sqlite3.Row]:
    normalized_query = normalize_text(query)
    if not normalized_query:
        return []
    with sqlite3.connect(db_path) as conn:
        configure_connection(conn)
        conn.row_factory = sqlite3.Row
        return list(
            conn.execute(
                """
                SELECT
                    e.id,
                    e.ts,
                    e.event_type,
                    e.agent,
                    e.target,
                    e.summary,
                    e.detail,
                    e.cmd_id,
                    e.parent_event_id,
                    e.importance,
                    bm25(events_fts) AS rank
                FROM events_fts
                JOIN events AS e ON e.rowid = events_fts.rowid
                WHERE events_fts MATCH ?
                ORDER BY rank, e.ts
                LIMIT ?
                """,
                (normalized_query, limit),
            )
        )


def configure_connection(conn: sqlite3.Connection) -> None:
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")


def build_db(
    db_path: Path,
    rows: list[tuple[str, str, str, str, str, str, str]],
    semantic_index_path: Path = DEFAULT_SEMANTIC_INDEX_PATH,
    bulletin_entries: list[dict[str, Any]] | None = None,
    insight_entries: list[dict[str, Any]] | None = None,
    skill_execution_entries: list[dict[str, Any]] | None = None,
    cmd_archive_entries: list[dict[str, Any]] | None = None,
    pending_decision_entries: list[dict[str, Any]] | None = None,
) -> None:
    concepts = list(iter_semantic_concepts(semantic_index_path))
    event_rows = event_rows_from_conversations(rows, concepts)
    event_rows.extend(event_rows_from_bulletins(bulletin_entries or [], concepts))
    event_rows.extend(event_rows_from_insights(insight_entries or [], concepts))
    event_rows.extend(event_rows_from_skill_executions(skill_execution_entries or [], concepts))
    event_rows.extend(event_rows_from_cmd_archives(cmd_archive_entries or [], concepts))
    event_rows.extend(event_rows_from_pending_decisions(pending_decision_entries or [], concepts))
    db_path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(db_path) as conn:
        configure_connection(conn)
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS conversations (
                ts TEXT,
                agent TEXT,
                direction TEXT,
                summary TEXT,
                detail TEXT,
                session_id TEXT
            )
            """
        )
        conn.execute(
            """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_conversations_unique
            ON conversations(ts, agent, direction, summary, detail, session_id)
            """
        )
        conn.executemany(
            """
            INSERT OR REPLACE INTO conversations (
                ts, agent, direction, summary, detail, session_id
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            [(ts, agent, direction, summary, detail, session_id) for ts, agent, direction, summary, detail, session_id, _source_file in rows],
        )
        conn.execute("CREATE INDEX IF NOT EXISTS idx_conversations_ts ON conversations(ts)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_conversations_session_id ON conversations(session_id)")
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS events (
                id TEXT PRIMARY KEY,
                ts TEXT,
                event_type TEXT,
                agent TEXT,
                target TEXT,
                direction TEXT,
                summary TEXT,
                detail TEXT,
                session_id TEXT,
                cmd_id TEXT,
                concepts TEXT,
                source_file TEXT,
                parent_event_id INTEGER,
                importance TEXT
            )
            """
        )
        conn.executemany(
            """
            INSERT OR REPLACE INTO events (
                id, ts, event_type, agent, target, direction, summary, detail,
                session_id, cmd_id, concepts, source_file, parent_event_id, importance
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            event_rows,
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS event_concepts (
                event_id TEXT NOT NULL,
                concept_name TEXT NOT NULL,
                PRIMARY KEY (event_id, concept_name),
                FOREIGN KEY (event_id) REFERENCES events(id)
            )
            """
        )
        conn.executemany(
            """
            INSERT OR REPLACE INTO event_concepts (event_id, concept_name)
            VALUES (?, ?)
            """,
            event_concept_rows(event_rows),
        )
        conn.execute(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS events_fts USING fts5(
                summary,
                detail,
                content='events',
                content_rowid='rowid'
            )
            """
        )
        conn.execute("INSERT INTO events_fts(events_fts) VALUES ('rebuild')")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_events_event_type ON events(event_type)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_events_agent ON events(agent)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_events_cmd_id ON events(cmd_id)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_events_parent_event_id ON events(parent_event_id)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_events_importance ON events(importance)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_event_concepts_concept_name ON event_concepts(concept_name)")
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS event_links (
                source_event_id TEXT NOT NULL,
                target_concept TEXT NOT NULL,
                link_type TEXT NOT NULL DEFAULT 'obsidian',
                PRIMARY KEY (source_event_id, target_concept, link_type),
                FOREIGN KEY (source_event_id) REFERENCES events(id)
            )
            """
        )
        conn.executemany(
            """
            INSERT OR REPLACE INTO event_links (source_event_id, target_concept, link_type)
            VALUES (?, ?, ?)
            """,
            event_link_rows(event_rows),
        )
        conn.execute("CREATE INDEX IF NOT EXISTS idx_event_links_source_event_id ON event_links(source_event_id)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_event_links_target_concept ON event_links(target_concept)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build data/multi_agent_shogun_memory.db from multi-agent event archives."
    )
    parser.add_argument(
        "--archive-dir",
        default=str(DEFAULT_ARCHIVE_DIR),
        help="Directory containing archived *.jsonl conversation files.",
    )
    parser.add_argument(
        "--db",
        default=str(DEFAULT_DB_PATH),
        help="SQLite DB path to create or replace.",
    )
    parser.add_argument(
        "--semantic-index",
        default=str(DEFAULT_SEMANTIC_INDEX_PATH),
        help="Semantic index used to populate events.concepts by alias matching.",
    )
    parser.add_argument(
        "--bulletin-file",
        default="",
        help="bulletin_board.yaml path. Defaults to queue/bulletin_board.yaml for the production archive.",
    )
    parser.add_argument(
        "--bulletin-archive-dir",
        default="",
        help="Directory containing archived bulletin_*.yaml files.",
    )
    parser.add_argument(
        "--insights-file",
        default="",
        help="insights.yaml path. Defaults to queue/insights.yaml beside the archive root.",
    )
    parser.add_argument(
        "--skill-execution-log",
        default="",
        help="skill_execution_log.yaml path. Defaults to logs/skill_execution_log.yaml beside the archive root.",
    )
    parser.add_argument(
        "--cmd-archive-dir",
        default="",
        help="Directory containing completed cmd archive YAML files.",
    )
    parser.add_argument(
        "--pending-decisions-file",
        default="",
        help="pending_decisions.yaml path. Defaults to queue/pending_decisions.yaml beside the archive root.",
    )
    parser.add_argument(
        "--search",
        default="",
        help="Search events.summary/detail using the FTS5 index instead of rebuilding the DB.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=20,
        help="Maximum rows returned by --search.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    archive_dir = Path(args.archive_dir)
    db_path = Path(args.db)
    semantic_index_path = Path(args.semantic_index)
    default_bulletin_file, default_bulletin_archive_dir = default_bulletin_paths_for_archive(archive_dir)
    bulletin_file = Path(args.bulletin_file) if args.bulletin_file else default_bulletin_file
    bulletin_archive_dir = Path(args.bulletin_archive_dir) if args.bulletin_archive_dir else default_bulletin_archive_dir
    insights_file = Path(args.insights_file) if args.insights_file else default_insights_path_for_archive(archive_dir)
    skill_execution_log = Path(args.skill_execution_log) if args.skill_execution_log else default_skill_execution_log_for_archive(archive_dir)
    cmd_archive_dir = Path(args.cmd_archive_dir) if args.cmd_archive_dir else default_cmd_archive_dir_for_archive(archive_dir)
    pending_decisions_file = (
        Path(args.pending_decisions_file)
        if args.pending_decisions_file
        else default_pending_decisions_path_for_archive(archive_dir)
    )
    if args.search:
        for row in search_events(db_path, args.search, args.limit):
            print(
                "\t".join(
                    [
                        str(row["id"]),
                        str(row["ts"]),
                        str(row["agent"]),
                        str(row["cmd_id"]),
                        str(row["importance"]),
                        normalize_text(row["summary"]).replace("\t", " "),
                    ]
                )
            )
        return 0
    rows = load_rows(archive_dir)
    bulletin_entries = load_bulletin_entries(bulletin_file, bulletin_archive_dir)
    insight_entries = load_insight_entries(insights_file)
    skill_execution_entries = load_skill_execution_entries(skill_execution_log)
    cmd_archive_entries = load_cmd_archive_entries(cmd_archive_dir)
    pending_decision_entries = load_pending_decision_entries(pending_decisions_file)
    build_db(
        db_path,
        rows,
        semantic_index_path,
        bulletin_entries,
        insight_entries,
        skill_execution_entries,
        cmd_archive_entries,
        pending_decision_entries,
    )
    print(
        "memory_db_import: "
        f"files={len(list(iter_jsonl_files(archive_dir)))} "
        f"rows={len(rows)} "
        f"bulletins={len(bulletin_entries)} "
        f"insights={len(insight_entries)} "
        f"skill_executions={len(skill_execution_entries)} "
        f"cmd_archives={len(cmd_archive_entries)} "
        f"pending_decisions={len(pending_decision_entries)} "
        f"db={db_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
