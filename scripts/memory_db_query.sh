#!/usr/bin/env bash
# semantic-links: [[SQLite記憶DB]], [[events_fts]], [[FTS5]]
# memory_db_query.sh — Run SQL against the local memory DB via Python sqlite3.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
db_path="${MEMORY_DB_QUERY_DB:-$script_dir/data/multi_agent_shogun_memory.db}"

usage() {
    cat <<'EOF' >&2
Usage: memory_db_query.sh [--db PATH] SQL

Runs SQL through Python sqlite3 and prints sqlite3 CLI-style list output:
pipe-separated fields, no headers, NULL as an empty field.
EOF
}

if [ "$#" -eq 0 ]; then
    usage
    exit 2
fi

if [ "${1:-}" = "--db" ]; then
    if [ "$#" -lt 3 ]; then
        usage
        exit 2
    fi
    db_path="$2"
    shift 2
fi

sql="$1"

python3 - "$db_path" "$sql" <<'PY'
from __future__ import annotations

import sqlite3
import sys
from pathlib import Path


SQLITE_BUSY_TIMEOUT_MS = 5000


def split_sql(sql: str) -> list[str]:
    statements: list[str] = []
    current: list[str] = []
    for line in sql.splitlines(True):
        current.append(line)
        candidate = "".join(current)
        if sqlite3.complete_statement(candidate):
            statement = candidate.strip()
            if statement:
                statements.append(statement)
            current = []
    remainder = "".join(current).strip()
    if remainder:
        statements.append(remainder)
    return statements


def format_value(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.hex()
    return str(value)


def main() -> int:
    db_path = Path(sys.argv[1])
    sql = sys.argv[2]
    if not db_path.exists():
        print(f"memory_db_query: database not found: {db_path}", file=sys.stderr)
        return 1

    statements = split_sql(sql)
    if not statements:
        return 0

    with sqlite3.connect(db_path) as conn:
        conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
        for statement in statements:
            cursor = conn.execute(statement)
            if cursor.description is None:
                continue
            for row in cursor:
                print("|".join(format_value(value) for value in row))
        conn.commit()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
