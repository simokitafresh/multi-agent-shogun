#!/usr/bin/env python3
# semantic-links: [[SQLite記憶DB]], [[eventsテーブル]], [[掲示板通信基盤]], [[セマンティック辞書構想]]
"""Append live bulletin/insight events to the local memory DB."""

from __future__ import annotations

import argparse
import re
import sqlite3
import os
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DB_PATH = REPO_ROOT / "data" / "multi_agent_shogun_memory.db"
CMD_RE = re.compile(r"\bcmd_[A-Za-z0-9_]+\b")
SUMMARY_LIMIT = 240


def normalize_text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).replace("\r\n", "\n").replace("\r", "\n").strip()


def summarize(text: str) -> str:
    first_line = next((line.strip() for line in text.splitlines() if line.strip()), "")
    if not first_line:
        return ""
    return first_line[:SUMMARY_LIMIT]


def infer_cmd_id(summary: str, detail: str) -> str:
    match = CMD_RE.search(f"{summary}\n{detail}")
    return match.group(0) if match else ""


def require_live_tables(conn: sqlite3.Connection) -> bool:
    tables = {
        row[0]
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type IN ('table', 'virtual table')"
        )
    }
    return {"events", "events_fts"}.issubset(tables)


def append_event(db_path: Path, row: tuple[Any, ...]) -> None:
    if not db_path.exists():
        return
    with sqlite3.connect(db_path) as conn:
        if not require_live_tables(conn):
            return
        cursor = conn.execute(
            """
            INSERT OR IGNORE INTO events (
                id, ts, event_type, agent, target, direction, summary, detail,
                session_id, cmd_id, concepts, source_file, parent_event_id, importance
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            row,
        )
        if cursor.rowcount == 1:
            rowid = conn.execute("SELECT rowid FROM events WHERE id = ?", (row[0],)).fetchone()[0]
            conn.execute(
                "INSERT INTO events_fts(rowid, summary, detail) VALUES (?, ?, ?)",
                (rowid, row[6], row[7]),
            )


def append_bulletin(args: argparse.Namespace) -> None:
    content = normalize_text(args.content)
    action_type = normalize_text(args.action_type) or "info"
    status = normalize_text(args.status) or "open"
    requires_confirmation = normalize_text(args.requires_confirmation)
    actioned_by = normalize_text(args.actioned_by)
    summary = summarize(content) or "bulletin"
    detail = "\n".join(
        line
        for line in [
            content,
            f"action_type: {action_type}" if action_type else "",
            f"status: {status}" if status else "",
            f"actioned_by: {actioned_by}" if actioned_by else "",
            f"requires_confirmation: {requires_confirmation}",
        ]
        if line
    )
    importance = "high" if action_type == "action_required" and status != "closed" else "normal"
    append_event(
        args.db_path,
        (
            f"bulletin:{normalize_text(args.entry_id)}",
            normalize_text(args.ts),
            "bulletin",
            normalize_text(args.agent),
            actioned_by,
            action_type,
            summary,
            detail,
            "",
            infer_cmd_id(summary, detail),
            "[]",
            normalize_text(args.source_file),
            None,
            importance,
        ),
    )


def append_insight(args: argparse.Namespace) -> None:
    insight = normalize_text(args.insight)
    status = normalize_text(args.status) or "pending"
    priority = normalize_text(args.priority) or "medium"
    source = normalize_text(args.source) or "manual"
    resolved_at = normalize_text(args.resolved_at)
    summary = summarize(insight) or "insight"
    detail = "\n".join(
        line
        for line in [
            insight,
            f"status: {status}" if status else "",
            f"priority: {priority}" if priority else "",
            f"source: {source}" if source else "",
            f"resolved_at: {resolved_at}" if resolved_at else "",
        ]
        if line
    )
    importance = "high" if priority == "high" or status == "pending" else "normal"
    append_event(
        args.db_path,
        (
            f"insight:{normalize_text(args.entry_id)}",
            normalize_text(args.ts),
            "insight",
            source,
            "",
            status,
            summary,
            detail,
            "",
            infer_cmd_id(summary, detail),
            "[]",
            normalize_text(args.source_file),
            None,
            importance,
        ),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--db-path",
        type=Path,
        default=Path(os.environ.get("SHOGUN_MEMORY_DB", DEFAULT_DB_PATH)),
    )
    subparsers = parser.add_subparsers(dest="event_type", required=True)

    bulletin = subparsers.add_parser("bulletin")
    bulletin.add_argument("--entry-id", required=True)
    bulletin.add_argument("--ts", required=True)
    bulletin.add_argument("--agent", required=True)
    bulletin.add_argument("--content", required=True)
    bulletin.add_argument("--requires-confirmation", default="")
    bulletin.add_argument("--action-type", default="info")
    bulletin.add_argument("--actioned-by", default="")
    bulletin.add_argument("--status", default="open")
    bulletin.add_argument("--source-file", required=True)

    insight = subparsers.add_parser("insight")
    insight.add_argument("--entry-id", required=True)
    insight.add_argument("--ts", required=True)
    insight.add_argument("--insight", required=True)
    insight.add_argument("--priority", default="medium")
    insight.add_argument("--source", default="manual")
    insight.add_argument("--status", default="pending")
    insight.add_argument("--resolved-at", default="")
    insight.add_argument("--source-file", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.event_type == "bulletin":
        append_bulletin(args)
    elif args.event_type == "insight":
        append_insight(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
