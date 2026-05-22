#!/usr/bin/env bash
# semantic-links: [[SQLite記憶DB]], [[events_fts]], [[FTS5]]
# memory_db_query.sh — Run SQL against the local memory DB via Python sqlite3.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
db_path="${MEMORY_DB_QUERY_DB:-$script_dir/data/multi_agent_shogun_memory.db}"

usage() {
    cat <<'EOF' >&2
Usage: memory_db_query.sh [--db PATH] [--target AGENT] --search QUERY
       memory_db_query.sh [--db PATH] SQL

Runs SQL through Python sqlite3 and prints sqlite3 CLI-style list output:
pipe-separated fields, no headers, NULL as an empty field.
EOF
}

if [ "$#" -eq 0 ]; then
    usage
    exit 2
fi

search_query=""
target="${MEMORY_DB_QUERY_TARGET:-${AGENT_ID:-}}"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --db)
            if [ "$#" -lt 2 ]; then
                usage
                exit 2
            fi
            db_path="$2"
            shift 2
            ;;
        --target)
            if [ "$#" -lt 2 ]; then
                usage
                exit 2
            fi
            target="$2"
            shift 2
            ;;
        --search)
            if [ "$#" -lt 2 ]; then
                usage
                exit 2
            fi
            search_query="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            usage
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

if [ -z "$target" ] && [ -n "${TMUX_PANE:-}" ]; then
    target="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
fi

if [ -n "$search_query" ]; then
    search_args=(
        --db "$db_path"
        --search "$search_query"
        --limit "${MEMORY_DB_QUERY_LIMIT:-20}"
    )
    if [ -n "$target" ] && [ "$target" != "unknown" ]; then
        search_args+=(--target "$target")
    fi
    python3 "$script_dir/scripts/memory_db_import.py" \
        "${search_args[@]}"
    exit $?
fi

if [ "$#" -ne 1 ]; then
    usage
    exit 2
fi

sql="$1"

python3 - "$db_path" "$sql" <<'PY'
from __future__ import annotations

import sqlite3
import sys
from pathlib import Path


SQLITE_BUSY_TIMEOUT_MS = 5000
ALLOWED_INITIAL_KEYWORDS = {"SELECT", "WITH"}


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


def first_keyword(statement: str) -> str:
    text = statement.lstrip()
    while text:
        if text.startswith("--"):
            newline = text.find("\n")
            if newline == -1:
                return ""
            text = text[newline + 1 :].lstrip()
            continue
        if text.startswith("/*"):
            end = text.find("*/")
            if end == -1:
                return ""
            text = text[end + 2 :].lstrip()
            continue
        break
    keyword_chars: list[str] = []
    for char in text:
        if char.isalpha() or char == "_":
            keyword_chars.append(char)
            continue
        break
    return "".join(keyword_chars).upper()


def require_select_statement(statement: str) -> None:
    keyword = first_keyword(statement)
    if keyword not in ALLOWED_INITIAL_KEYWORDS:
        raise ValueError(
            f"only SELECT statements are allowed; blocked statement starts with {keyword or 'UNKNOWN'}"
        )


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
    try:
        for statement in statements:
            require_select_statement(statement)
    except ValueError as exc:
        print(f"memory_db_query: BLOCKED: {exc}", file=sys.stderr)
        return 2

    db_uri = f"{db_path.resolve().as_uri()}?mode=ro"
    with sqlite3.connect(db_uri, uri=True) as conn:
        conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
        try:
            for statement in statements:
                cursor = conn.execute(statement)
                if cursor.description is None:
                    continue
                for row in cursor:
                    print("|".join(format_value(value) for value in row))
        except sqlite3.DatabaseError as exc:
            print(f"memory_db_query: BLOCKED: only SELECT statements are allowed ({exc})", file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
