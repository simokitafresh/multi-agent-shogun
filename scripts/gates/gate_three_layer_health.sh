#!/usr/bin/env bash
# gate_three_layer_health.sh — Three-layer memory cache capacity and tmp hygiene gate.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
db_path="${SHOGUN_MEMORY_DB:-$repo_root/data/multi_agent_shogun_memory.db}"
warn_bytes="${SHOGUN_THREE_LAYER_CACHE_WARN_BYTES:-10737418240}"
cleanup_script="$repo_root/scripts/cleanup_three_layer_tmp.sh"
overall="PASS"

cache_path="$(
    python3 - "$db_path" "$repo_root" <<'PY' 2>/dev/null || true
import sys

db_path = sys.argv[1]
repo_root = sys.argv[2]
sys.path.insert(0, f"{repo_root}/scripts")
import memory_db_live_insert as live_insert

print(live_insert.memory_db_cache_path(db_path))
PY
)"
cache_dir="${SHOGUN_MEMORY_DB_CACHE_DIR:-/tmp/shogun_memory_db_cache}"
[ -n "$cache_path" ] && cache_dir="$(dirname "$cache_path")"

echo "=== three-layer memory health ==="
echo "db_path=$db_path"
echo "cache_path=${cache_path:-unknown}"

query_db="${cache_path:-}"

echo "■ events.state分布"
if [ -f "$query_db" ]; then
    if ! python3 - "$query_db" <<'PY'; then
import sqlite3
import sys

db_path = sys.argv[1]

warn = False

def has_column(conn, table, column):
    return any(row[1] == column for row in conn.execute(f"PRAGMA table_info({table})"))

def has_table(conn, table):
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        (table,),
    ).fetchone() is not None

def scalar(conn, query, params=()):
    value = conn.execute(query, params).fetchone()[0]
    return int(value or 0)

conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
try:
    has_events = has_table(conn, "events")
    if not has_events:
        raise RuntimeError("events table not found")

    has_state = has_column(conn, "events", "state")
    has_raw_content = has_column(conn, "events", "raw_content")

    if has_state:
        state_rows = list(
            conn.execute(
                """
                SELECT COALESCE(NULLIF(TRIM(state), ''), 'raw') AS state_name, COUNT(*)
                FROM events
                GROUP BY state_name
                ORDER BY COUNT(*) DESC, state_name
                """
            )
        )
    else:
        state_rows = [("state_column_missing", 0)]
    for state_name, count in state_rows:
        print(f"  state分布 {state_name}: {count}")

    if has_raw_content:
        total, filled = conn.execute(
            """
            SELECT COUNT(*),
                   SUM(CASE WHEN raw_content IS NOT NULL AND TRIM(raw_content) != '' THEN 1 ELSE 0 END)
            FROM events
            """
        ).fetchone()
        filled = filled or 0
        rate = (filled * 100.0 / total) if total else 0.0
        print(f"  raw_content充填率: {filled}/{total} ({rate:.1f}%)")
    else:
        print("  raw_content充填率: raw_content column missing")

    if has_state:
        contradiction_candidates = conn.execute(
            "SELECT COUNT(*) FROM events WHERE state = 'contradiction_candidate'"
        ).fetchone()[0]
        promote_candidates = conn.execute(
            "SELECT COUNT(*) FROM events WHERE state = 'obsidian_candidate'"
        ).fetchone()[0]
    else:
        contradiction_candidates = 0
        promote_candidates = 0
    print(f"  contradiction候補件数: {contradiction_candidates}")
    print(f"  promote昇格候補件数: {promote_candidates}")

    print("■ 三層記憶 使用計測")
    if has_table(conn, "search_logs"):
        search_logs_7d = scalar(
            conn,
            """
            SELECT COUNT(*)
            FROM search_logs
            WHERE COALESCE(ts, created_at, '') >= datetime('now', '-7 days')
            """,
        )
        print(f"  search_logs検索件数(直近7日): {search_logs_7d}")
        if search_logs_7d == 0:
            print("WARN: search_logs検索件数が0。三層記憶検索が使われていない可能性あり。")
            warn = True
    else:
        print("WARN: search_logs table missing")
        warn = True

    if has_state:
        state_transition_count = scalar(
            conn,
            """
            SELECT COUNT(*)
            FROM events
            WHERE COALESCE(NULLIF(TRIM(state), ''), 'raw') != 'raw'
            """,
        )
        candidate_count = scalar(
            conn,
            """
            SELECT COUNT(*)
            FROM events
            WHERE COALESCE(state, '') LIKE '%candidate'
            """,
        )
    else:
        state_transition_count = 0
        candidate_count = 0
    print(f"  state遷移件数(state!=raw): {state_transition_count}")
    if state_transition_count == 0:
        print("WARN: state遷移件数が0。想起制御/候補化が使われていない可能性あり。")
        warn = True

    if has_raw_content:
        raw_content_saved = scalar(
            conn,
            """
            SELECT COUNT(*)
            FROM events
            WHERE raw_content IS NOT NULL AND TRIM(raw_content) != ''
            """,
        )
    else:
        raw_content_saved = 0
    print(f"  raw_content原文保存件数: {raw_content_saved}")
    if raw_content_saved == 0:
        print("WARN: raw_content原文保存件数が0。原文保存経路が使われていない可能性あり。")
        warn = True

    print(f"  candidate候補生成件数: {candidate_count}")
    if candidate_count == 0 and state_transition_count == 0:
        print("WARN: candidate候補生成件数が0かつstate遷移件数が0。矛盾/重複/Obsidian候補生成が使われていない可能性あり。")
        warn = True

    if warn:
        sys.exit(2)
finally:
    conn.close()
PY
        overall="WARN"
    fi
else
    echo "WARN: 三層記憶DBが存在しない: $query_db"
    overall="WARN"
fi

echo "■ cache容量チェック"
if [ -d "$cache_dir" ]; then
    cache_bytes="$(du -sb "$cache_dir" 2>/dev/null | awk '{print $1+0}')"
else
    cache_bytes=0
fi
echo "cache_dir=$cache_dir bytes=$cache_bytes warn_bytes=$warn_bytes"
if [ "$cache_bytes" -gt "$warn_bytes" ]; then
    echo "WARN: cache容量が閾値を超過。cleanup dry-runで対象を確認せよ。"
    overall="WARN"
else
    echo "OK: cache容量は閾値内"
fi

echo "■ tmp残骸cleanup dry-run"
if [ -x "$cleanup_script" ]; then
    bash "$cleanup_script" --dry-run --cache-dir "$cache_dir"
else
    echo "WARN: cleanup script not executable: $cleanup_script"
    overall="WARN"
fi

echo "STATUS: $overall"
[ "$overall" = "PASS" ] && exit 0
exit 2
