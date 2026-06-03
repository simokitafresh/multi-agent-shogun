#!/usr/bin/env bash
# semantic-links: [[SQLite記憶DB]], [[想起制御state遷移]], [[三層記憶アーキテクチャ]]
# Archive old verified memory events without deleting them.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
db_path="$script_dir/data/multi_agent_shogun_memory.db"
backup_dir=""
older_than_days=90
limit=100
reason=""
dry_run=0

usage() {
    cat <<'EOF' >&2
Usage: memory_recall_control.sh [--db PATH] [--backup-dir DIR] [--older-than-days N]
                                [--limit N] [--reason TEXT] [--dry-run]

Transitions old verified events to state=archived. State-changing runs always
create a SQLite backup before UPDATE and log each transition.
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
        --older-than-days)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            older_than_days="$2"
            shift 2
            ;;
        --limit)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            limit="$2"
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

python3 - "$script_dir" "$db_path" "$backup_dir" "$older_than_days" "$limit" "$reason" "$dry_run" <<'PY'
from __future__ import annotations

import importlib.util
import re
import sqlite3
import sys
from pathlib import Path


SQLITE_BUSY_TIMEOUT_MS = 5000
INT_RE = re.compile(r"^[0-9]+$")


def load_state_module(repo_root: Path):
    module_path = repo_root / "scripts" / "memory_db_live_insert.py"
    spec = importlib.util.spec_from_file_location("memory_db_live_insert", module_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"memory_recall_control: cannot load {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_positive_int(value: str, name: str) -> int:
    if not INT_RE.match(value) or int(value) < 1:
        raise SystemExit(f"memory_recall_control: invalid {name}: {value}")
    return int(value)


def require_columns(conn: sqlite3.Connection, table: str, columns: set[str]) -> None:
    existing = {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}
    missing = sorted(columns - existing)
    if missing:
        raise SystemExit(
            f"memory_recall_control: missing columns in {table}: {', '.join(missing)}"
        )


def main() -> int:
    repo_root = Path(sys.argv[1])
    state_module = load_state_module(repo_root)
    db_path = Path(sys.argv[2])
    backup_dir = sys.argv[3]
    older_than_days = parse_positive_int(sys.argv[4], "--older-than-days")
    limit = parse_positive_int(sys.argv[5], "--limit")
    reason = sys.argv[6].strip() or f"verified event older than {older_than_days} days"
    dry_run = sys.argv[7] == "1"

    if not db_path.exists():
        print(f"memory_recall_control: database not found: {db_path}", file=sys.stderr)
        return 1

    cutoff_expr = f"-{older_than_days} days"
    with sqlite3.connect(db_path) as conn:
        conn.row_factory = sqlite3.Row
        conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
        require_columns(conn, "events", {"id", "summary", "state", "updated_at"})

        rows = conn.execute(
            """
            SELECT id, summary
            FROM events
            WHERE state = 'verified'
              AND date(COALESCE(NULLIF(updated_at, ''), ts, '1970-01-01')) <= date('now', ?)
            ORDER BY COALESCE(NULLIF(updated_at, ''), ts, '1970-01-01'), id
            LIMIT ?
            """,
            (cutoff_expr, limit),
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
                print(f"{row['id']}|{row['summary']}")
            return 0

        backup_path = state_module.create_sqlite_backup(
            str(db_path), backup_dir or None, "recall_control"
        )
        with conn:
            updated = state_module.update_event_state(
                conn,
                [row["id"] for row in rows],
                "archived",
                reason,
                "memory_recall_control",
            )
        print(f"backup={backup_path}")
        print(f"updated={updated}")
        for row in rows:
            print(f"{row['id']}|{row['summary']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
