#!/usr/bin/env bash
# semantic-links: [[SQLite記憶DB]], [[events_fts]], [[FTS5]]
# memory_db_query.sh — Run SQL against the local memory DB via Python sqlite3.

set -euo pipefail

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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_db_path="$script_dir/data/multi_agent_shogun_memory.db"
db_path="${MEMORY_DB_QUERY_DB:-$default_db_path}"

# shellcheck source=lib/memory_db_cache.sh
source "$script_dir/scripts/lib/memory_db_cache.sh"

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

source_db_path="$db_path"
db_path="$(prepare_memory_db_for_read "$script_dir" "$db_path" "$default_db_path")"

if [ -n "$search_query" ]; then
    # A cache whose SQLite header is absent cannot satisfy any search. Repair
    # it through SQL mode before launching the heavier FTS search process.
    # Concurrent callers converge in regenerate_cache_atomically(): the flock
    # holder rechecks cache health, so exactly one process performs the backup.
    if [ "$db_path" != "$source_db_path" ] \
        && [ "$(LC_ALL=C head -c 15 "$db_path" 2>/dev/null || true)" != "SQLite format 3" ]; then
        bash "$0" --db "$source_db_path" \
            "SELECT name FROM sqlite_master LIMIT 1" >/dev/null 2>&1 || true
    fi
    search_args=(
        --db "$db_path"
        --search "$search_query"
        --limit "${MEMORY_DB_QUERY_LIMIT:-20}"
    )
    if [ -n "$target" ] && [ "$target" != "unknown" ]; then
        search_args+=(--target "$target")
    fi
    search_stdout="$(mktemp "${TMPDIR:-/tmp}/memory_db_query.search.XXXXXX")"
    search_stderr="$(mktemp "${TMPDIR:-/tmp}/memory_db_query.search_err.XXXXXX")"
    search_rc=0
    python3 "$script_dir/scripts/memory_db_import.py" \
        "${search_args[@]}" >"$search_stdout" 2>"$search_stderr" || search_rc=$?
    if [ "$search_rc" -eq 0 ]; then
        cat "$search_stdout"
        cat "$search_stderr" >&2
        rm -f "$search_stdout" "$search_stderr"
        exit 0
    fi

    # A failed search against the cache can be a transient torn-read (the
    # cache self-heals as soon as any in-flight write finishes) or genuine
    # corruption. Re-checking cache health with a second, separate PRAGMA
    # quick_check before deciding whether to recover races the self-heal
    # case: by the time that second check runs, the cache can already be
    # healthy again, so the old gate concluded "nothing to recover" and
    # returned the stale original failure instead of just retrying.
    # Always attempt recovery-and-retry once instead of gating on a fresh
    # health probe. The recursive call below reuses SQL mode's own recovery
    # (regenerate_cache_atomically), which no-ops when the cache is already
    # healthy, so this is safe and cheap whichever case actually happened.
    if [ "$db_path" != "$source_db_path" ]; then
        if bash "$0" --db "$source_db_path" "SELECT name FROM sqlite_master LIMIT 1" >/dev/null 2>&1; then
            rm -f "$search_stdout" "$search_stderr"
            python3 "$script_dir/scripts/memory_db_import.py" "${search_args[@]}"
            exit $?
        fi
    fi
    cat "$search_stdout"
    cat "$search_stderr" >&2
    rm -f "$search_stdout" "$search_stderr"
    exit "$search_rc"
fi

if [ "$#" -ne 1 ]; then
    usage
    exit 2
fi

sql="$1"

python3 - "$db_path" "$source_db_path" "$script_dir" "$sql" <<'PY'
from __future__ import annotations

import fcntl
import os
import sqlite3
import sys
import tempfile
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


def execute_read(db_path: Path, statements: list[str]) -> list[str]:
    """Execute all statements without publishing partial output."""
    output: list[str] = []
    db_uri = f"{db_path.resolve().as_uri()}?mode=ro"
    with sqlite3.connect(db_uri, uri=True) as conn:
        conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
        for statement in statements:
            cursor = conn.execute(statement)
            if cursor.description is None:
                continue
            col_names = [d[0] for d in cursor.description]
            if (
                os.environ.get("MEMORY_DB_QUERY_WARN_AGENT_MIX", "0") == "1"
                and "agent" not in col_names
                and "events" in statement.lower()
            ):
                print(
                    "★ WARN: eventsテーブル検索にagentカラムなし。他エージェントの記録と混同する危険。"
                    "SELECT agent,... またはWHERE agent='自分'を追加せよ",
                    file=sys.stderr,
                )
            output.extend("|".join(format_value(value) for value in row) for row in cursor)
    return output


def is_corrupt_database_error(exc: sqlite3.DatabaseError) -> bool:
    message = str(exc).lower()
    return "database disk image is malformed" in message or "file is not a database" in message


def require_healthy_database(db_path: Path) -> None:
    db_uri = f"{db_path.resolve().as_uri()}?mode=ro"
    with sqlite3.connect(db_uri, uri=True) as conn:
        result = conn.execute("PRAGMA quick_check").fetchone()
    if result is None or result[0] != "ok":
        detail = result[0] if result else "no result"
        raise sqlite3.DatabaseError(f"database disk image is malformed ({detail})")


def require_cache_backup_healthy(db_path: Path) -> None:
    """Verify a freshly-built cache copy before it is published.

    PRAGMA quick_check validates ordinary b-tree structure but does not
    exercise FTS5's own index-vs-content consistency, so a page-level "ok"
    can still hide a search-time failure. Run FTS5's dedicated
    'integrity-check' command too when the table exists. Only call this
    against a private, not-yet-published temp copy — never the live
    primary DB — since the FTS check needs a writable connection.
    """
    require_healthy_database(db_path)
    with sqlite3.connect(db_path.resolve().as_uri() + "?mode=ro", uri=True) as conn:
        has_fts = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'events_fts'"
        ).fetchone() is not None
    if has_fts:
        with sqlite3.connect(db_path) as conn:
            conn.execute("INSERT INTO events_fts(events_fts) VALUES ('integrity-check')")


def regenerate_cache_atomically(source_path: Path, cache_path: Path) -> None:
    """Build a verified replacement beside cache_path, then publish atomically."""
    require_healthy_database(source_path)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = Path(f"{cache_path}.lock")
    with lock_path.open("a", encoding="utf-8") as lock_handle:
        fcntl.flock(lock_handle, fcntl.LOCK_EX)
        # Another process may have repaired the cache while this process waited.
        try:
            require_healthy_database(cache_path)
            return
        except (OSError, sqlite3.DatabaseError):
            pass

        recovery_log = os.environ.get("MEMORY_DB_QUERY_RECOVERY_LOG", "")
        if recovery_log:
            with open(recovery_log, "a", encoding="utf-8") as handle:
                handle.write(f"backup pid={os.getpid()}\n")

        fd, temp_name = tempfile.mkstemp(
            prefix=f".{cache_path.name}.", suffix=".tmp", dir=cache_path.parent
        )
        os.close(fd)
        temp_path = Path(temp_name)
        try:
            with sqlite3.connect(source_path) as source, sqlite3.connect(temp_path) as destination:
                source.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
                destination.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
                source.backup(destination)
            require_cache_backup_healthy(temp_path)
            os.replace(temp_path, cache_path)
            for suffix in ("-wal", "-shm", "-journal"):
                Path(f"{cache_path}{suffix}").unlink(missing_ok=True)
        finally:
            # os.replace() only renames temp_path itself; a WAL-mode backup
            # leaves -wal/-shm sidecars named after the temp path behind.
            for suffix in ("-wal", "-shm", "-journal"):
                Path(f"{temp_path}{suffix}").unlink(missing_ok=True)
            temp_path.unlink(missing_ok=True)


def main() -> int:
    db_path = Path(sys.argv[1])
    source_db_path = Path(sys.argv[2])
    sql = sys.argv[4]
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

    try:
        output = execute_read(db_path, statements)
    except sqlite3.DatabaseError as exc:
        is_cache = db_path.resolve() != source_db_path.resolve()
        if not (is_cache and is_corrupt_database_error(exc)):
            print(f"memory_db_query: BLOCKED: only SELECT statements are allowed ({exc})", file=sys.stderr)
            return 2
        try:
            regenerate_cache_atomically(source_db_path, db_path)
            # Exactly one retry. A second failure is returned fail-closed.
            output = execute_read(db_path, statements)
        except (OSError, sqlite3.DatabaseError) as retry_exc:
            print(f"memory_db_query: BLOCKED: cache recovery failed ({retry_exc})", file=sys.stderr)
            return 2
    for line in output:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
