#!/usr/bin/env bash
# semantic-links: [[SQLite記憶DB]], [[semantic_search]], [[検索ログ]]
# search_log_write.sh — Append semantic_search execution metrics to SQLite.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
db_path="${SEMANTIC_SEARCH_LOG_DB_PATH:-${SEMANTIC_MEMORY_DB_PATH:-$script_dir/data/multi_agent_shogun_memory.db}}"
ts=""
caller="${SEMANTIC_SEARCH_LOG_CALLER:-semantic_search}"
agent_id="${SEMANTIC_SEARCH_LOG_AGENT_ID:-${AGENT_ID:-}}"
exit_code=""
elapsed_ms=0

usage() {
    cat <<'EOF' >&2
Usage: search_log_write.sh [--db PATH] [--ts TS] [--elapsed-ms MS] [--caller NAME] [--agent-id AGENT] [--exit-code RC] <query> <hit_count> <no_match>

Writes one row to search_logs. caller is the invoking script/function name,
not the agent id; agent_id is recorded separately when available. ts is the
search execution timestamp.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --db)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            db_path="$2"
            shift 2
            ;;
        --ts|--executed-at)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            ts="$2"
            shift 2
            ;;
        --elapsed-ms)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            elapsed_ms="$2"
            shift 2
            ;;
        --caller)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            caller="$2"
            shift 2
            ;;
        --agent-id)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            agent_id="$2"
            shift 2
            ;;
        --exit-code)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            exit_code="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
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

[ "$#" -eq 3 ] || { usage; exit 2; }

query="$1"
hit_count="$2"
no_match="$3"

case "$hit_count" in
    ''|*[!0-9]*)
        echo "search_log_write: hit_count must be a non-negative integer" >&2
        exit 2
        ;;
esac

case "$elapsed_ms" in
    ''|*[!0-9]*)
        echo "search_log_write: elapsed_ms must be a non-negative integer" >&2
        exit 2
        ;;
esac

case "$no_match" in
    0|1) ;;
    true|TRUE|yes|YES) no_match=1 ;;
    false|FALSE|no|NO) no_match=0 ;;
    *)
        echo "search_log_write: no_match must be 0/1" >&2
        exit 2
        ;;
esac

if [ -z "$agent_id" ] && [ -n "${TMUX_PANE:-}" ]; then
    agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
fi

if [ -z "$ts" ]; then
    ts="$(date "+%Y-%m-%dT%H:%M:%S%z")"
fi

mkdir -p "$(dirname "$db_path")"

python3 - "$db_path" "$ts" "$caller" "$agent_id" "$query" "$hit_count" "$no_match" "$exit_code" "$elapsed_ms" <<'PY'
from __future__ import annotations

import sqlite3
import sys


SQLITE_BUSY_TIMEOUT_MS = 5000


def main() -> int:
    db_path, ts, caller, agent_id, query, hit_count, no_match, exit_code, elapsed_ms = sys.argv[1:10]
    exit_code_value = None if exit_code == "" else int(exit_code)

    with sqlite3.connect(db_path) as conn:
        conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS search_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts TEXT NOT NULL,
                caller TEXT NOT NULL,
                agent_id TEXT,
                query TEXT NOT NULL,
                hit_count INTEGER NOT NULL CHECK(hit_count >= 0),
                no_match INTEGER NOT NULL CHECK(no_match IN (0, 1)),
                elapsed_ms INTEGER NOT NULL CHECK(elapsed_ms >= 0),
                exit_code INTEGER,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
            """
        )
        columns = {
            row[1] for row in conn.execute("PRAGMA table_info(search_logs)")
        }
        if "elapsed_ms" not in columns:
            conn.execute(
                "ALTER TABLE search_logs ADD COLUMN elapsed_ms INTEGER NOT NULL DEFAULT 0 CHECK(elapsed_ms >= 0)"
            )
            columns.add("elapsed_ms")
        if "ts" not in columns:
            conn.execute("ALTER TABLE search_logs ADD COLUMN ts TEXT")
            if "executed_at" in columns:
                conn.execute(
                    "UPDATE search_logs SET ts = COALESCE(ts, executed_at, created_at)"
                )
            else:
                conn.execute("UPDATE search_logs SET ts = COALESCE(ts, created_at)")
            columns.add("ts")
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_search_logs_ts ON search_logs(ts)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_search_logs_query ON search_logs(query)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_search_logs_no_match ON search_logs(no_match, ts)"
        )
        insert_columns = [
            "ts",
            "caller",
            "agent_id",
            "query",
            "hit_count",
            "no_match",
            "elapsed_ms",
            "exit_code",
        ]
        values = [
            ts,
            caller,
            agent_id or None,
            query,
            int(hit_count),
            int(no_match),
            int(elapsed_ms),
            exit_code_value,
        ]
        if "executed_at" in columns:
            insert_columns.insert(1, "executed_at")
            values.insert(1, ts)
        placeholders = ", ".join("?" for _ in insert_columns)
        conn.execute(
            f"""
            INSERT INTO search_logs ({", ".join(insert_columns)})
            VALUES ({placeholders})
            """,
            values,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
