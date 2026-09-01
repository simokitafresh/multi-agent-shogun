#!/usr/bin/env bash
# semantic-links: [[SQLite記憶DB]], [[events_fts]], [[FTS5]]
# memory_db_query.sh — Run SQL against the local memory DB via Python sqlite3.

set -euo pipefail

usage() {
    printf '%s\n' \
        'Usage: memory_db_query.sh [--db PATH] [--target AGENT] --search QUERY' \
        '       memory_db_query.sh [--db PATH] SQL' \
        '' \
        'Runs SQL through Python sqlite3 and prints sqlite3 CLI-style list output:' \
        'pipe-separated fields, no headers, NULL as an empty field.' >&2
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

# 2026-09-01: 位置引数が SQL(SELECT/WITH)でなければ --search と同義に扱う。
# MEMORY.md/復帰点は『記憶DB「session_save_…」を検索して読め』と書くため、
# 将軍が `memory_db_query.sh "session_save_…"` と打って "only SELECT statements" で
# 2 回 BLOCK→sqlite3 不在→schema 誤読と 3 段の試行錯誤になった(殿指摘 12:54)。
if [ -z "$search_query" ] && [ "$#" -gt 0 ]; then
    case "$1" in
        [Ss][Ee][Ll][Ee][Cc][Tt]*|[Ww][Ii][Tt][Hh]*|[Pp][Rr][Aa][Gg][Mm][Aa]*|[Ee][Xx][Pp][Ll][Aa][Ii][Nn]*) ;;
        *) search_query="$*"; set -- ;;
    esac
fi

if [ -z "$target" ] && [ -n "${TMUX_PANE:-}" ]; then
    target="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
fi

source_db_path="$db_path"
cache_db_path="$(memory_db_cache_path "$script_dir" "$source_db_path" 2>/dev/null || true)"
db_path="$(prepare_memory_db_for_read "$script_dir" "$db_path" "$default_db_path")"

if [ -n "$search_query" ]; then
    # A stale cache means the canonical DB has newer writes.  Searching the
    # entire 9P-backed canonical DB makes long CJK LIKE queries exceed the
    # preflight's 5s budget.  Search the complete ext4 snapshot, then only the
    # canonical rows appended after that snapshot's max rowid.  This preserves
    # read-after-write for live inserts without turning every recent write into
    # a 622MB 9P full scan while the asynchronous cache refresh is in flight.
    delta_source_path=""
    delta_after_rowid=""
    # cmd_karo_impl_b45_memory_cache_rowid_watermark_20260726: mtimeの3条件
    # (本体/-wal/-shm)は、cache生成がmkstemp→copy→os.replaceで公開されるため
    # cacheのmtimeが「コピー完了時刻」でしかなく、かつ本体.dbはWALモードで
    # checkpointまでmtimeが動かないため、書込み直後は全条件が偽になり
    # delta経路が抑止されていた(検索が古いcacheだけを見て0件を返す窓)。
    # 時刻を比較しても揃わない以上、内容の水位(rowid)で直接比較する。
    if [ -s "$cache_db_path" ]; then
        cache_max_rowid="$(python3 - "$cache_db_path" <<'PY' 2>/dev/null || true
import sqlite3, sys
with sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True) as conn:
    row = conn.execute("SELECT COALESCE(MAX(rowid), 0) FROM events").fetchone()
print(int(row[0]) if row else 0)
PY
)"
        if [[ "$cache_max_rowid" =~ ^[0-9]+$ ]]; then
            # source側は9P越しのため、高負荷時のstall防止にtimeoutで防御する。
            # timeout/失敗時はcacheのみへフォールバックする(9p高負荷時の既存
            # 防御を維持。AC3)。
            source_max_rowid="$(timeout 2 python3 - "$source_db_path" <<'PY' 2>/dev/null || true
import sqlite3, sys
with sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True) as conn:
    row = conn.execute("SELECT COALESCE(MAX(rowid), 0) FROM events").fetchone()
print(int(row[0]) if row else 0)
PY
)"
            if [[ "$source_max_rowid" =~ ^[0-9]+$ ]] && [ "$source_max_rowid" -gt "$cache_max_rowid" ]; then
                delta_after_rowid="$cache_max_rowid"
                delta_source_path="$source_db_path"
                db_path="$cache_db_path"
            fi
        fi
    fi
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
    # Cache and delta must use one comparable ordering contract when merged.
    # LIKE orders both partitions by importance then timestamp; the delta's
    # rowid predicate makes the canonical read an indexed range scan instead
    # of an unbounded FTS traversal over the 622MB primary DB.
    if [ -n "$delta_source_path" ]; then
        search_args+=(--force-like)
    fi
    search_stdout="$(mktemp "${TMPDIR:-/tmp}/memory_db_query.search.XXXXXX")"
    search_stderr="$(mktemp "${TMPDIR:-/tmp}/memory_db_query.search_err.XXXXXX")"
    search_rc=0
    python3 "$script_dir/scripts/memory_db_import.py" \
        "${search_args[@]}" >"$search_stdout" 2>"$search_stderr" || search_rc=$?
    if [ "$search_rc" -eq 0 ] && [ -n "$delta_source_path" ]; then
        delta_args=(
            --db "$delta_source_path"
            --search "$search_query"
            --limit "${MEMORY_DB_QUERY_LIMIT:-20}"
            --min-rowid-exclusive "$delta_after_rowid"
            --force-like
        )
        if [ -n "$target" ] && [ "$target" != "unknown" ]; then
            delta_args+=(--target "$target")
        fi
        python3 "$script_dir/scripts/memory_db_import.py" "${delta_args[@]}" \
            >>"$search_stdout" 2>>"$search_stderr" || search_rc=$?
        if [ "$search_rc" -eq 0 ]; then
            python3 - "$search_stdout" "${MEMORY_DB_QUERY_LIMIT:-20}" <<'PY'
import sys

path, limit_text = sys.argv[1:]
priority = {"critical": 4, "high": 3, "normal": 2, "low": 1}
rows = []
seen = set()
with open(path, encoding="utf-8") as handle:
    for order, line in enumerate(handle):
        parts = line.rstrip("\n").split("\t", 5)
        if len(parts) < 6 or parts[0] in seen:
            continue
        seen.add(parts[0])
        rows.append((priority.get(parts[4], 0), parts[1], -order, line))
rows.sort(reverse=True)
with open(path, "w", encoding="utf-8") as handle:
    for _, _, _, line in rows[: int(limit_text)]:
        handle.write(line)
PY
        fi
    fi
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

query_rc=0
python3 - "$db_path" "$source_db_path" "$script_dir" "$sql" <<'PY' || query_rc=$?
from __future__ import annotations

import os
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
        # Never repair a cache synchronously from a SQL caller.  The canonical
        # DB lives on 9P and quick_check()/backup() can enter uninterruptible I/O,
        # keeping review hooks alive indefinitely.  Exit with an internal
        # recovery request; the shell delegates the copy to the existing
        # detached, single-flight cache refresher and returns fail-closed.
        print(f"memory_db_query: BLOCKED: cache recovery scheduled ({exc})", file=sys.stderr)
        return 75
    for line in output:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

if [ "$query_rc" -eq 75 ]; then
    if [ -n "$cache_db_path" ]; then
        force_refresh_memory_db_cache_async "$script_dir" "$source_db_path" "$cache_db_path"
    fi
    exit 2
fi
exit "$query_rc"
