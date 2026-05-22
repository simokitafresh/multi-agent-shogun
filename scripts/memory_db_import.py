#!/usr/bin/env python3
# semantic-links: [[SQLite記憶DB]], [[セマンティック辞書構想]]
"""Build the local SQLite memory DB from lord conversation JSONL archives."""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path
from typing import Any, Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ARCHIVE_DIR = REPO_ROOT / "logs" / "lord_conversation_archive"
DEFAULT_DB_PATH = REPO_ROOT / "data" / "multi_agent_shogun_memory.db"


def normalize_text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).replace("\r\n", "\n").replace("\r", "\n").strip()


def iter_jsonl_files(archive_dir: Path) -> Iterable[Path]:
    if not archive_dir.exists():
        return []
    return sorted(path for path in archive_dir.glob("*.jsonl") if path.is_file())


def row_from_line(path: Path, raw: str) -> tuple[str, str, str, str, str, str]:
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
    )


def load_rows(archive_dir: Path) -> list[tuple[str, str, str, str, str, str]]:
    rows: list[tuple[str, str, str, str, str, str]] = []
    for path in iter_jsonl_files(archive_dir):
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            for raw in handle:
                if not raw.strip():
                    continue
                rows.append(row_from_line(path, raw))
    return rows


def build_db(db_path: Path, rows: list[tuple[str, str, str, str, str, str]]) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(db_path) as conn:
        conn.execute("PRAGMA journal_mode=DELETE")
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
            rows,
        )
        conn.execute("CREATE INDEX idx_conversations_ts ON conversations(ts)")
        conn.execute("CREATE INDEX idx_conversations_session_id ON conversations(session_id)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build data/multi_agent_shogun_memory.db from lord conversation archives."
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
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    archive_dir = Path(args.archive_dir)
    db_path = Path(args.db)
    rows = load_rows(archive_dir)
    build_db(db_path, rows)
    print(f"memory_db_import: files={len(list(iter_jsonl_files(archive_dir)))} rows={len(rows)} db={db_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
