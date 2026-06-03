#!/usr/bin/env bash
# semantic-links: [[SQLite記憶DB]], [[Obsidian昇格候補]], [[三層記憶アーキテクチャ]]
# Extract high-value memory events and mark them as Obsidian promotion candidates.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
db_path="$script_dir/data/multi_agent_shogun_memory.db"
backup_dir=""
limit=50
min_concept_frequency=3
min_links=2
importance="high"
dry_run=0

usage() {
    cat <<'EOF' >&2
Usage: obsidian_promote_candidate.sh [--db PATH] [--backup-dir DIR] [--limit N]
                                     [--min-concept-frequency N] [--min-links N]
                                     [--importance VALUE] [--dry-run]

Marks high-value events as state=obsidian_candidate.
State-changing runs always create a SQLite backup before UPDATE.
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
        --limit)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            limit="$2"
            shift 2
            ;;
        --min-concept-frequency)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            min_concept_frequency="$2"
            shift 2
            ;;
        --min-links)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            min_links="$2"
            shift 2
            ;;
        --importance)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            importance="$2"
            shift 2
            ;;
        --dry-run)
            dry_run=1
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

python3 - "$script_dir" "$db_path" "$backup_dir" "$limit" "$min_concept_frequency" "$min_links" "$importance" "$dry_run" <<'PY'
from __future__ import annotations

import importlib.util
import re
import sqlite3
import sys
from pathlib import Path


SQLITE_BUSY_TIMEOUT_MS = 5000
INT_RE = re.compile(r"^[0-9]+$")
NORMAL_STATES = ("raw", "verified")


def load_state_module(repo_root: Path):
    module_path = repo_root / "scripts" / "memory_db_live_insert.py"
    spec = importlib.util.spec_from_file_location("memory_db_live_insert", module_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"obsidian_promote_candidate: cannot load {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_positive_int(value: str, name: str) -> int:
    if not INT_RE.match(value) or int(value) < 1:
        raise SystemExit(f"obsidian_promote_candidate: invalid {name}: {value}")
    return int(value)


def require_columns(conn: sqlite3.Connection, table: str, columns: set[str]) -> None:
    existing = {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}
    missing = sorted(columns - existing)
    if missing:
        raise SystemExit(
            f"obsidian_promote_candidate: missing columns in {table}: {', '.join(missing)}"
        )


def main() -> int:
    repo_root = Path(sys.argv[1])
    state_module = load_state_module(repo_root)
    db_path = Path(sys.argv[2])
    backup_dir = sys.argv[3]
    limit = parse_positive_int(sys.argv[4], "--limit")
    min_concept_frequency = parse_positive_int(sys.argv[5], "--min-concept-frequency")
    min_links = parse_positive_int(sys.argv[6], "--min-links")
    importance = sys.argv[7]
    dry_run = sys.argv[8] == "1"

    if not db_path.exists():
        print(f"obsidian_promote_candidate: database not found: {db_path}", file=sys.stderr)
        return 1

    with sqlite3.connect(db_path) as conn:
        conn.row_factory = sqlite3.Row
        conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
        require_columns(
            conn,
            "events",
            {"id", "summary", "event_type", "importance", "state", "updated_at"},
        )
        require_columns(conn, "event_concepts", {"event_id", "concept_name"})
        require_columns(conn, "event_links", {"source_event_id", "target_concept"})

        rows = conn.execute(
            """
            WITH concept_frequency AS (
                SELECT concept_name, COUNT(*) AS frequency
                FROM event_concepts
                GROUP BY concept_name
            ),
            event_signal AS (
                SELECT
                    e.id,
                    e.summary,
                    e.event_type,
                    e.importance,
                    COUNT(DISTINCT el.target_concept) AS link_count,
                    MAX(cf.frequency) AS max_concept_frequency,
                    COUNT(DISTINCT ec.concept_name) AS concept_count
                FROM events AS e
                JOIN event_concepts AS ec ON ec.event_id = e.id
                JOIN concept_frequency AS cf ON cf.concept_name = ec.concept_name
                JOIN event_links AS el ON el.source_event_id = e.id
                WHERE e.importance = ?
                  AND COALESCE(e.state, 'raw') IN (?, ?)
                GROUP BY e.id
                HAVING link_count >= ?
                   AND max_concept_frequency >= ?
                ORDER BY max_concept_frequency DESC, link_count DESC, e.id
                LIMIT ?
            )
            SELECT * FROM event_signal
            """,
            (importance, *NORMAL_STATES, min_links, min_concept_frequency, limit),
        ).fetchall()

        if not rows:
            print("candidates=0")
            if dry_run:
                print("dry_run=true")
            return 0

        if dry_run:
            print(f"candidates={len(rows)}")
            print("dry_run=true")
            for row in rows:
                print(
                    f"{row['id']}|{row['importance']}|links={row['link_count']}|"
                    f"concept_frequency={row['max_concept_frequency']}|{row['summary']}"
                )
            return 0

        backup_path = state_module.create_sqlite_backup(
            str(db_path), backup_dir or None, "obsidian_candidate"
        )
        with conn:
            updated = state_module.update_event_state(
                conn,
                [row["id"] for row in rows],
                "obsidian_candidate",
                "high-value event selected for Obsidian promotion review",
                "obsidian_promote_candidate",
            )
        print(f"backup={backup_path}")
        print(f"updated={updated}")
        for row in rows:
            print(
                f"{row['id']}|{row['importance']}|links={row['link_count']}|"
                f"concept_frequency={row['max_concept_frequency']}|{row['summary']}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
