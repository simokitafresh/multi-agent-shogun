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

memory_db_cache_path() {
    local source_path="$1"
    python3 - "$source_path" "$script_dir" <<'PY'
import sys

db_path = sys.argv[1]
repo_root = sys.argv[2]
sys.path.insert(0, f"{repo_root}/scripts")
import memory_db_live_insert as live_insert

print(live_insert.memory_db_cache_path(db_path))
PY
}

create_memory_db_cache() {
    local source_path="$1"
    python3 - "$source_path" "$script_dir" <<'PY'
import sys

db_path = sys.argv[1]
repo_root = sys.argv[2]
sys.path.insert(0, f"{repo_root}/scripts")
import memory_db_live_insert as live_insert

live_insert.create_memory_db_ext4_cache(db_path)
PY
}

refresh_memory_db_cache_async() {
    local source_path="$1"
    local cache_path="$2"
    local timeout_sec="${SHOGUN_MEMORY_DB_CACHE_REFRESH_TIMEOUT:-60}"
    export script_dir
    export -f create_memory_db_cache
    (
        flock -n 8 2>/dev/null || exit 0
        if command -v timeout >/dev/null 2>&1; then
            timeout -k 1 "$timeout_sec" bash -c 'create_memory_db_cache "$1"' _ "$source_path" >/dev/null 2>&1 || true
        else
            create_memory_db_cache "$source_path" >/dev/null 2>&1 || true
        fi
    ) 8>"${cache_path}.refresh.lock" >/dev/null 2>&1 </dev/null &
}

notify_cache_timeout() {
    local timeout_sec="$1"
    if [ -x "$script_dir/scripts/ntfy.sh" ]; then
        bash "$script_dir/scripts/ntfy.sh" "【memory_db_query】ext4 cache初期生成が${timeout_sec}sを超過。正本DBへfallback。" >/dev/null 2>&1 || true
    fi
}

prepare_memory_db_for_read() {
    local source_path="$1"
    if [ "${SHOGUN_MEMORY_DB_QUERY_DISABLE_CACHE:-0}" = "1" ] || [ "${SHOGUN_DISABLE_MEMORY_DB_CACHE:-0}" = "1" ]; then
        printf '%s\n' "$source_path"
        return 0
    fi
    if [ ! -f "$source_path" ]; then
        printf '%s\n' "$source_path"
        return 0
    fi
    if [ "$source_path" != "$default_db_path" ] && [ "${SHOGUN_MEMORY_DB_QUERY_CACHE_NONDEFAULT:-0}" != "1" ]; then
        printf '%s\n' "$source_path"
        return 0
    fi

    local cache_path timeout_sec rc
    cache_path="$(memory_db_cache_path "$source_path" 2>/dev/null || true)"
    if [ -z "$cache_path" ]; then
        printf '%s\n' "$source_path"
        return 0
    fi
    if [ -s "$cache_path" ]; then
        if [ "$source_path" -nt "$cache_path" ] \
            || { [ -f "${source_path}-wal" ] && [ "${source_path}-wal" -nt "$cache_path" ]; } \
            || { [ -f "${source_path}-shm" ] && [ "${source_path}-shm" -nt "$cache_path" ]; }; then
            refresh_memory_db_cache_async "$source_path" "$cache_path"
        fi
        printf '%s\n' "$cache_path"
        return 0
    fi

    timeout_sec="${SHOGUN_MEMORY_DB_CACHE_INIT_TIMEOUT:-30}"
    rc=0
    if command -v timeout >/dev/null 2>&1; then
        export script_dir
        export -f create_memory_db_cache
        timeout -k 1 "$timeout_sec" bash -c 'create_memory_db_cache "$1"' _ "$source_path" 2>/dev/null || rc=$?
    else
        create_memory_db_cache "$source_path" 2>/dev/null || rc=$?
    fi
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
        notify_cache_timeout "$timeout_sec"
    fi
    if [ "$rc" -eq 0 ] && [ -s "$cache_path" ]; then
        printf '%s\n' "$cache_path"
    else
        printf '%s\n' "$source_path"
    fi
}

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
db_path="$(prepare_memory_db_for_read "$db_path")"

if [ -n "$search_query" ]; then
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

    cache_is_corrupt=1
    if [ "$db_path" != "$source_db_path" ]; then
        python3 - "$db_path" <<'PY' >/dev/null 2>&1 && cache_is_corrupt=0 || cache_is_corrupt=$?
import sqlite3
import sys

try:
    with sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True) as conn:
        result = conn.execute("PRAGMA quick_check").fetchone()
    raise SystemExit(1 if result and result[0] == "ok" else 0)
except sqlite3.DatabaseError as exc:
    message = str(exc).lower()
    raise SystemExit(0 if "malformed" in message or "not a database" in message else 1)
PY
    fi
    if [ "$cache_is_corrupt" -eq 0 ]; then
        # Reuse SQL mode's atomic recovery, then retry this search exactly once.
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
            require_healthy_database(temp_path)
            os.replace(temp_path, cache_path)
            for suffix in ("-wal", "-shm", "-journal"):
                Path(f"{cache_path}{suffix}").unlink(missing_ok=True)
        finally:
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
