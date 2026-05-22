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
CMD_RE = re.compile(r"\bcmd_[A-Za-z0-9_]+\b")


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
) -> list[tuple[str, str, str, str, str, str, str, str, str, str, str, str, None, str]]:
    event_rows: list[tuple[str, str, str, str, str, str, str, str, str, str, str, str, None, str]] = []
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
) -> list[tuple[str, str, str, str, str, str, str, str, str, str, str, str, None, str]]:
    event_rows: list[tuple[str, str, str, str, str, str, str, str, str, str, str, str, None, str]] = []
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


def default_bulletin_paths_for_archive(archive_dir: Path) -> tuple[Path, Path]:
    try:
        if archive_dir.resolve() == DEFAULT_ARCHIVE_DIR.resolve():
            return DEFAULT_BULLETIN_FILE, DEFAULT_BULLETIN_ARCHIVE_DIR
    except FileNotFoundError:
        pass
    base_dir = archive_dir.parent
    return base_dir / "queue" / "bulletin_board.yaml", base_dir / "queue" / "archive"


def search_events(db_path: Path, query: str, limit: int = 20) -> list[sqlite3.Row]:
    normalized_query = normalize_text(query)
    if not normalized_query:
        return []
    with sqlite3.connect(db_path) as conn:
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


def build_db(
    db_path: Path,
    rows: list[tuple[str, str, str, str, str, str, str]],
    semantic_index_path: Path = DEFAULT_SEMANTIC_INDEX_PATH,
    bulletin_entries: list[dict[str, Any]] | None = None,
) -> None:
    concepts = list(iter_semantic_concepts(semantic_index_path))
    event_rows = event_rows_from_conversations(rows, concepts)
    event_rows.extend(event_rows_from_bulletins(bulletin_entries or [], concepts))
    db_path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(db_path) as conn:
        conn.execute("PRAGMA journal_mode=DELETE")
        conn.execute("DROP TABLE IF EXISTS events")
        conn.execute("DROP TABLE IF EXISTS conversations")
        conn.execute(
            """
            CREATE TABLE conversations (
                ts TEXT,
                agent TEXT,
                direction TEXT,
                summary TEXT,
                detail TEXT,
                session_id TEXT
            )
            """
        )
        conn.executemany(
            """
            INSERT INTO conversations (
                ts, agent, direction, summary, detail, session_id
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            [(ts, agent, direction, summary, detail, session_id) for ts, agent, direction, summary, detail, session_id, _source_file in rows],
        )
        conn.execute("CREATE INDEX idx_conversations_ts ON conversations(ts)")
        conn.execute("CREATE INDEX idx_conversations_session_id ON conversations(session_id)")
        conn.execute(
            """
            CREATE TABLE events (
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
            INSERT INTO events (
                id, ts, event_type, agent, target, direction, summary, detail,
                session_id, cmd_id, concepts, source_file, parent_event_id, importance
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            event_rows,
        )
        conn.execute("DROP TABLE IF EXISTS events_fts")
        conn.execute(
            """
            CREATE VIRTUAL TABLE events_fts USING fts5(
                summary,
                detail,
                content='events',
                content_rowid='rowid'
            )
            """
        )
        conn.execute("INSERT INTO events_fts(events_fts) VALUES ('rebuild')")
        conn.execute("CREATE INDEX idx_events_ts ON events(ts)")
        conn.execute("CREATE INDEX idx_events_event_type ON events(event_type)")
        conn.execute("CREATE INDEX idx_events_agent ON events(agent)")
        conn.execute("CREATE INDEX idx_events_cmd_id ON events(cmd_id)")
        conn.execute("CREATE INDEX idx_events_parent_event_id ON events(parent_event_id)")
        conn.execute("CREATE INDEX idx_events_importance ON events(importance)")


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
    build_db(db_path, rows, semantic_index_path, bulletin_entries)
    print(
        "memory_db_import: "
        f"files={len(list(iter_jsonl_files(archive_dir)))} "
        f"rows={len(rows)} "
        f"bulletins={len(bulletin_entries)} "
        f"db={db_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
