#!/usr/bin/env bash
# semantic-links: [[SQLite記憶DB]], [[Obsidian昇格候補]], [[L7 Obsidian戻り経路]]
# Finalize reviewed Obsidian promotion candidates into note drafts and SQLite state.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
db_path="$script_dir/data/multi_agent_shogun_memory.db"
backup_dir=""
notes_dir="$script_dir/docs/obsidian-promoted"
limit=10
event_id=""
reason=""
dry_run=0
force=0

usage() {
    cat <<'EOF' >&2
Usage: obsidian_promote_finalize.sh [--db PATH] [--backup-dir DIR] [--notes-dir DIR]
                                    [--limit N] [--event-id ID] [--reason TEXT]
                                    [--dry-run] [--force]

Creates Obsidian note drafts from events in state=obsidian_candidate, records the
event_id -> note path relationship in event_links, and transitions finalized
events to state=obsidian_promoted. State-changing runs always create a SQLite
backup before UPDATE.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --db)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            db_path="$2"
            shift 2
            ;;
        --backup-dir)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            backup_dir="$2"
            shift 2
            ;;
        --notes-dir)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            notes_dir="$2"
            shift 2
            ;;
        --limit)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            limit="$2"
            shift 2
            ;;
        --event-id)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            event_id="$2"
            shift 2
            ;;
        --reason)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            reason="$2"
            shift 2
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        --force)
            force=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

python3 - "$script_dir" "$db_path" "$backup_dir" "$notes_dir" "$limit" "$event_id" "$reason" "$dry_run" "$force" <<'PY'
from __future__ import annotations

import importlib.util
import re
import sqlite3
import sys
from pathlib import Path


SQLITE_BUSY_TIMEOUT_MS = 5000
INT_RE = re.compile(r"^[0-9]+$")
PROMOTED_LINK_TYPE = "obsidian_promoted_note"


def load_state_module(repo_root: Path):
    module_path = repo_root / "scripts" / "memory_db_live_insert.py"
    spec = importlib.util.spec_from_file_location("memory_db_live_insert", module_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"obsidian_promote_finalize: cannot load {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_positive_int(value: str, name: str) -> int:
    if not INT_RE.match(value) or int(value) < 1:
        raise SystemExit(f"obsidian_promote_finalize: invalid {name}: {value}")
    return int(value)


def require_columns(conn: sqlite3.Connection, table: str, columns: set[str]) -> None:
    existing = {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}
    missing = sorted(columns - existing)
    if missing:
        raise SystemExit(
            f"obsidian_promote_finalize: missing columns in {table}: {', '.join(missing)}"
        )


def ensure_event_links(conn: sqlite3.Connection) -> None:
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
    conn.execute("CREATE INDEX IF NOT EXISTS idx_event_links_source_event_id ON event_links(source_event_id)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_event_links_target_concept ON event_links(target_concept)")


def slugify(value: str, fallback: str) -> str:
    text = re.sub(r"\s+", "-", value.strip().lower())
    text = re.sub(r"[^a-z0-9._-]+", "-", text)
    text = re.sub(r"-{2,}", "-", text).strip("-._")
    return (text or fallback)[:80]


def yaml_scalar(value: object) -> str:
    text = "" if value is None else str(value)
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def note_body(row: sqlite3.Row, relative_note_path: str, generated_at: str) -> str:
    summary = row["summary"] or row["id"]
    detail = row["raw_content"] or row["detail"] or ""
    concepts = row["concepts"] or ""
    return "\n".join(
        [
            "---",
            f"event_id: {yaml_scalar(row['id'])}",
            f"source_state: {yaml_scalar(row['state'])}",
            f"cmd_id: {yaml_scalar(row['cmd_id'])}",
            f"event_type: {yaml_scalar(row['event_type'])}",
            f"agent: {yaml_scalar(row['agent'])}",
            f"source_file: {yaml_scalar(row['source_file'])}",
            f"generated_at: {yaml_scalar(generated_at)}",
            f"sqlite_link: {yaml_scalar(relative_note_path)}",
            "---",
            "",
            f"# {summary}",
            "",
            "## Source",
            "",
            f"- event_id: `{row['id']}`",
            f"- state: `{row['state']}`",
            f"- importance: `{row['importance'] or ''}`",
            f"- occurred_at: `{row['occurred_at'] or row['ts'] or ''}`",
            "",
            "## Concepts",
            "",
            concepts or "(none)",
            "",
            "## Detail",
            "",
            detail or summary,
            "",
        ]
    )


def relative_path(path: Path, repo_root: Path) -> str:
    try:
        return path.resolve().relative_to(repo_root.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def main() -> int:
    repo_root = Path(sys.argv[1])
    state_module = load_state_module(repo_root)
    db_path = Path(sys.argv[2])
    backup_dir = sys.argv[3]
    notes_dir = Path(sys.argv[4])
    limit = parse_positive_int(sys.argv[5], "--limit")
    event_id = sys.argv[6].strip()
    reason = sys.argv[7].strip() or "Obsidian note draft generated and linked"
    dry_run = sys.argv[8] == "1"
    force = sys.argv[9] == "1"

    if not db_path.exists():
        print(f"obsidian_promote_finalize: database not found: {db_path}", file=sys.stderr)
        return 1

    with sqlite3.connect(db_path) as conn:
        conn.row_factory = sqlite3.Row
        conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
        require_columns(
            conn,
            "events",
            {
                "id",
                "ts",
                "event_type",
                "agent",
                "summary",
                "detail",
                "cmd_id",
                "concepts",
                "source_file",
                "importance",
                "state",
                "occurred_at",
                "raw_content",
                "updated_at",
            },
        )
        ensure_event_links(conn)

        params: list[object] = ["obsidian_candidate"]
        where = "state = ?"
        if event_id:
            where += " AND id = ?"
            params.append(event_id)
        params.append(limit)
        rows = conn.execute(
            f"""
            SELECT id, ts, event_type, agent, summary, detail, cmd_id, concepts,
                   source_file, importance, state, occurred_at, raw_content, updated_at
            FROM events
            WHERE {where}
            ORDER BY COALESCE(NULLIF(updated_at, ''), ts, id), id
            LIMIT ?
            """,
            params,
        ).fetchall()

        if not rows:
            print("candidates=0")
            if dry_run:
                print("dry_run=true")
            return 0

        generated_at = state_module.now_timestamp()
        note_plan: list[tuple[sqlite3.Row, Path, str]] = []
        for row in rows:
            title_slug = slugify(row["summary"] or "", slugify(row["id"], "event"))
            id_slug = slugify(row["id"], "event")
            note_path = notes_dir / f"{title_slug}-{id_slug}.md"
            rel_note_path = relative_path(note_path, repo_root)
            note_plan.append((row, note_path, rel_note_path))

        if dry_run:
            print(f"candidates={len(note_plan)}")
            print("dry_run=true")
            for row, _note_path, rel_note_path in note_plan:
                print(f"{row['id']}|note={rel_note_path}|summary={row['summary'] or ''}")
            return 0

        existing = [path for _row, path, _rel in note_plan if path.exists() and not force]
        if existing:
            for path in existing:
                print(f"obsidian_promote_finalize: note already exists: {path}", file=sys.stderr)
            print("obsidian_promote_finalize: use --force to overwrite generated note drafts", file=sys.stderr)
            return 1

        backup_path = state_module.create_sqlite_backup(
            str(db_path), backup_dir or None, "obsidian_promote_finalize"
        )
        notes_dir.mkdir(parents=True, exist_ok=True)
        for row, note_path, rel_note_path in note_plan:
            note_path.write_text(note_body(row, rel_note_path, generated_at), encoding="utf-8")

        with conn:
            conn.executemany(
                """
                INSERT OR REPLACE INTO event_links (source_event_id, target_concept, link_type)
                VALUES (?, ?, ?)
                """,
                [
                    (row["id"], rel_note_path, PROMOTED_LINK_TYPE)
                    for row, _note_path, rel_note_path in note_plan
                ],
            )
            updated = state_module.update_event_state(
                conn,
                [row["id"] for row, _note_path, _rel_note_path in note_plan],
                "obsidian_promoted",
                reason,
                "obsidian_promote_finalize",
            )

        print(f"backup={backup_path}")
        print(f"updated={updated}")
        for row, _note_path, rel_note_path in note_plan:
            print(f"{row['id']}|note={rel_note_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
