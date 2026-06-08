#!/usr/bin/env bats
# test_memory_db.bats — SQLite memory DB import tests

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/memory_db.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/archive" "$TEST_TMPDIR/data"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "memory_db_import creates conversations view and events table with required columns" {
    cat > "$TEST_TMPDIR/archive/2026-05-01.jsonl" <<'EOF'
{"ts":"2026-05-01T00:00:00+09:00","agent":"lord","direction":"inbound","summary":"sum1","detail":"detail1"}
{"ts":"2026-05-01T00:01:00+09:00","agent":"shogun","direction":"response","summary":"sum2","detail":"detail2","session_id":"explicit-session"}
EOF

    run bash "$PROJECT_ROOT/scripts/memory_db_init.sh" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"files=1 rows=2"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
conversation_cols = [row[1] for row in conn.execute("PRAGMA table_info(conversations)")]
event_cols = [row[1] for row in conn.execute("PRAGMA table_info(events)")]
conversation_type = conn.execute(
    "SELECT type FROM sqlite_master WHERE name='conversations'"
).fetchone()[0]
print(",".join(conversation_cols))
print(",".join(event_cols))
print(conversation_type)
print(conn.execute("SELECT COUNT(*) FROM conversations").fetchone()[0])
print(conn.execute("SELECT session_id FROM conversations ORDER BY ts LIMIT 1").fetchone()[0])
print(conn.execute("SELECT session_id FROM conversations ORDER BY ts DESC LIMIT 1").fetchone()[0])
print(conn.execute("SELECT COUNT(*) FROM events").fetchone()[0])
print(conn.execute("SELECT event_type FROM events ORDER BY ts LIMIT 1").fetchone()[0])
PY
)
    [ "${result[0]}" = "ts,agent,direction,summary,detail,session_id" ]
    [ "${result[1]}" = "id,ts,event_type,agent,target,direction,summary,detail,session_id,cmd_id,concepts,source_file,parent_event_id,importance,confidence,freshness,source_type,state,occurred_at,recorded_at,updated_at,raw_content" ]
    [ "${result[2]}" = "view" ]
    [ "${result[3]}" = "2" ]
    [ "${result[4]}" = "2026-05-01" ]
    [ "${result[5]}" = "explicit-session" ]
    [ "${result[6]}" = "2" ]
    [ "${result[7]}" = "conversation" ]
}

@test "memory_db_import builds lord ruling cache for inbound lord conversations" {
    cat > "$TEST_TMPDIR/archive/2026-05-25.jsonl" <<'EOF'
{"ts":"2026-05-25T20:00:00+09:00","agent":"lord","direction":"inbound","summary":"殿裁定その一","detail":"漢字LIKE検索対象"}
{"ts":"2026-05-25T20:01:00+09:00","agent":"shogun","direction":"response","summary":"将軍返答","detail":"キャッシュ対象外"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --lord-ruling-cache "$TEST_TMPDIR/data/lord_ruling_cache.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lord_ruling_cache=$TEST_TMPDIR/data/lord_ruling_cache.db"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/lord_ruling_cache.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
print(conn.execute("SELECT COUNT(*) FROM lord_rulings").fetchone()[0])
print(conn.execute("SELECT summary FROM lord_rulings").fetchone()[0])
PY
)
    [ "${result[0]}" = "1" ]
    [ "${result[1]}" = "殿裁定その一" ]
}

@test "memory_db_import creates FTS5 index and searches summary detail through MATCH" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"高速化相談","detail":"events detail LIKE scan を FTS5 に置き換える"}
{"ts":"2026-05-22T12:01:00+09:00","agent":"shogun","direction":"response","summary":"別件","detail":"通常の返答"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
fts_sql = conn.execute(
    "SELECT sql FROM sqlite_master WHERE type='table' AND name='events_fts'"
).fetchone()[0]
plan = " ".join(
    row[3]
    for row in conn.execute(
        """
        EXPLAIN QUERY PLAN
        SELECT e.id
        FROM events_fts
        JOIN events AS e ON e.rowid = events_fts.rowid
        WHERE events_fts MATCH 'FTS5'
        """
    )
)
rows = conn.execute(
    """
    SELECT e.summary, e.detail
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'FTS5'
    """
).fetchall()
print("USING fts5" in fts_sql)
print("VIRTUAL TABLE INDEX" in plan)
print(len(rows))
print(rows[0][0])
print("LIKE" in plan)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "1" ]
    [ "${result[3]}" = "高速化相談" ]
    [ "${result[4]}" = "False" ]
}

@test "memory_db_import search CLI returns FTS5 matches only" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"検索対象","detail":"parent_event_id と importance を検索品質に使う"}
{"ts":"2026-05-22T12:01:00+09:00","agent":"shogun","direction":"response","summary":"無関係","detail":"通常の返答"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --search "importance"
    [ "$status" -eq 0 ]
    [[ "$output" == *"検索対象"* ]]
    [[ "$output" != *"無関係"* ]]
}

@test "memory_db_import search CLI filters by target when requested" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","target":"hayate","direction":"inbound","summary":"hayate宛検索対象","detail":"sameuniquetargetneedle"}
{"ts":"2026-05-22T12:01:00+09:00","agent":"lord","target":"karo","direction":"inbound","summary":"karo宛検索対象","detail":"sameuniquetargetneedle"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --search "sameuniquetargetneedle" \
        --target "hayate"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hayate宛検索対象"* ]]
    [[ "$output" != *"karo宛検索対象"* ]]
}

@test "memory_db_import schema CLI emits markdown with event types and samples" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"schema sample","detail":"event_type distribution check"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --schema-output "$TEST_TMPDIR/memory-db-schema.md"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/memory-db-schema.md" ]
    [[ "$output" == *"schema=$TEST_TMPDIR/memory-db-schema.md"* ]]

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --schema
    [ "$status" -eq 0 ]
    [[ "$output" == *"# Memory DB Schema"* ]]
    [[ "$output" == *"## Event Type Distribution"* ]]
    [[ "$output" == *"| conversation | 1 |"* ]]
    [[ "$output" == *"## \`events\`"* ]]
    [[ "$output" == *"schema sample"* ]]

    run grep -F "schema sample" "$TEST_TMPDIR/memory-db-schema.md"
    [ "$status" -eq 0 ]
}

@test "memory_db_import search uses CJK LIKE fallback for long Japanese queries" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"日本語FTS改善","detail":"日本語の長文クエリではFTS5検索がタイムアウトする問題を改善する"}
{"ts":"2026-05-22T12:01:00+09:00","agent":"shogun","direction":"response","summary":"無関係","detail":"通常の返答"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --search "日本語の長いクエリでFTS5検索がタイムアウトする問題を改善する"
    [ "$status" -eq 0 ]
    [[ "$output" == *"日本語FTS改善"* ]]
    [[ "$output" != *"無関係"* ]]

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --search "FTS5検索"
    [ "$status" -eq 0 ]
    [[ "$output" == *"日本語FTS改善"* ]]
    [[ "$output" != *"無関係"* ]]
}

@test "memory_db_query runs SQL through Python sqlite3 with sqlite3 CLI-style output" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"query wrapper","detail":"Python sqlite3 wrapper output check"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run bash "$PROJECT_ROOT/scripts/memory_db_query.sh" \
        --db "$TEST_TMPDIR/data/memory.db" \
        "SELECT summary, target, parent_event_id FROM events ORDER BY ts"
    [ "$status" -eq 0 ]
    [ "$output" = "query wrapper|shogun|" ]
}

@test "memory_db_query can prefer ext4 cache generated through sqlite backup API" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"cache wrapper","detail":"ext4 cache read path"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    export SHOGUN_MEMORY_DB_QUERY_CACHE_NONDEFAULT=1
    export SHOGUN_MEMORY_DB_CACHE_PATH="$TEST_TMPDIR/cache/memory.db"
    run bash "$PROJECT_ROOT/scripts/memory_db_query.sh" \
        --db "$TEST_TMPDIR/data/memory.db" \
        "SELECT summary FROM events ORDER BY ts"
    [ "$status" -eq 0 ]
    [ "$output" = "cache wrapper" ]
    [ -s "$TEST_TMPDIR/cache/memory.db" ]
}

@test "three-layer tmp cleanup dry-run reports stale candidates without deleting" {
    mkdir -p "$TEST_TMPDIR/cache"
    touch "$TEST_TMPDIR/cache/.memory.db.old.tmp"
    touch "$TEST_TMPDIR/cache/.memory.db.old.tmp-journal"
    touch "$TEST_TMPDIR/cache/_tmp_bats_memory.db"
    touch -d '3 days ago' "$TEST_TMPDIR/cache/.memory.db.old.tmp"
    touch -d '3 days ago' "$TEST_TMPDIR/cache/.memory.db.old.tmp-journal"
    touch -d '3 days ago' "$TEST_TMPDIR/cache/_tmp_bats_memory.db"

    run bash "$PROJECT_ROOT/scripts/cleanup_three_layer_tmp.sh" \
        --dry-run \
        --ttl-hours 6 \
        --cache-dir "$TEST_TMPDIR/cache"
    [ "$status" -eq 0 ]
    [[ "$output" == *"candidates=3"* ]]
    [ -f "$TEST_TMPDIR/cache/.memory.db.old.tmp" ]
    [ -f "$TEST_TMPDIR/cache/.memory.db.old.tmp-journal" ]
    [ -f "$TEST_TMPDIR/cache/_tmp_bats_memory.db" ]
}

@test "gate_three_layer_health emits cache capacity section" {
    mkdir -p "$TEST_TMPDIR/cache"
    python3 - "$TEST_TMPDIR/cache/memory.db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE events (id TEXT PRIMARY KEY, state TEXT DEFAULT 'raw', raw_content TEXT)")
conn.execute("CREATE TABLE search_logs (ts TEXT, created_at TEXT)")
conn.executemany(
    "INSERT INTO events (id, state, raw_content) VALUES (?, ?, ?)",
    [
        ("event:raw", "raw", "raw content"),
        ("event:verified", "verified", "verified content"),
        ("event:candidate", "duplicate_candidate", "candidate content"),
    ],
)
conn.execute("INSERT INTO search_logs (ts, created_at) VALUES (datetime('now'), datetime('now'))")
conn.commit()
conn.close()
PY
    export SHOGUN_MEMORY_DB_CACHE_PATH="$TEST_TMPDIR/cache/memory.db"
    export SHOGUN_THREE_LAYER_CACHE_WARN_BYTES=999999999

    run bash "$PROJECT_ROOT/scripts/gates/gate_three_layer_health.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cache容量チェック"* ]]
    [[ "$output" == *"tmp残骸cleanup dry-run"* ]]
}

@test "memory_db_query supports FTS5 MATCH queries" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"FTS wrapper","detail":"uniqueftsneedle works through MATCH"}
{"ts":"2026-05-22T12:01:00+09:00","agent":"shogun","direction":"response","summary":"miss","detail":"ordinary response"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run bash "$PROJECT_ROOT/scripts/memory_db_query.sh" \
        --db "$TEST_TMPDIR/data/memory.db" \
        "SELECT e.summary FROM events_fts JOIN events AS e ON e.rowid = events_fts.rowid WHERE events_fts MATCH 'uniqueftsneedle'"
    [ "$status" -eq 0 ]
    [ "$output" = "FTS wrapper" ]
}

@test "memory_db_query default search filters by target" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","target":"hayate","direction":"inbound","summary":"hayate query wrapper","detail":"querytargetneedle"}
{"ts":"2026-05-22T12:01:00+09:00","agent":"lord","target":"karo","direction":"inbound","summary":"karo query wrapper","detail":"querytargetneedle"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    AGENT_ID=hayate run bash "$PROJECT_ROOT/scripts/memory_db_query.sh" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --search "querytargetneedle"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hayate query wrapper"* ]]
    [[ "$output" != *"karo query wrapper"* ]]
}

@test "memory_db_query allows SELECT and WITH SELECT but blocks write statements" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"guard row","detail":"SELECT-only guard"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run bash "$PROJECT_ROOT/scripts/memory_db_query.sh" \
        --db "$TEST_TMPDIR/data/memory.db" \
        "select summary from events"
    [ "$status" -eq 0 ]
    [ "$output" = "guard row" ]

    run bash "$PROJECT_ROOT/scripts/memory_db_query.sh" \
        --db "$TEST_TMPDIR/data/memory.db" \
        "WITH recent AS (SELECT summary FROM events) SELECT summary FROM recent"
    [ "$status" -eq 0 ]
    [ "$output" = "guard row" ]

    run bash "$PROJECT_ROOT/scripts/memory_db_query.sh" \
        --db "$TEST_TMPDIR/data/memory.db" \
        "delete from events"
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" == *"DELETE"* ]]

    for sql in \
        "insert into events (id, ts, event_type, summary) values ('x', '2026-05-22', 'test', 'x')" \
        "drop table events" \
        "alter table events add column blocked_text text" \
        "create table blocked_table (id text)"
    do
        run bash "$PROJECT_ROOT/scripts/memory_db_query.sh" \
            --db "$TEST_TMPDIR/data/memory.db" \
            "$sql"
        [ "$status" -ne 0 ]
        [[ "$output" == *"BLOCKED"* ]]
    done

    run bash "$PROJECT_ROOT/scripts/memory_db_query.sh" \
        --db "$TEST_TMPDIR/data/memory.db" \
        "SELECT summary FROM events;
UPDATE events SET summary = 'changed'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" == *"UPDATE"* ]]

    run bash "$PROJECT_ROOT/scripts/memory_db_query.sh" \
        --db "$TEST_TMPDIR/data/memory.db" \
        "WITH target AS (SELECT id FROM events) DELETE FROM events WHERE id IN (SELECT id FROM target)"
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" == *"only SELECT statements are allowed"* ]]
}

@test "memory_db_import row count matches non-empty archive JSONL lines" {
    cat > "$TEST_TMPDIR/archive/2026-05-01.jsonl" <<'EOF'
{"ts":"2026-05-01T00:00:00+09:00","direction":"inbound","summary":"a","detail":"a"}

{"ts":"2026-05-01T00:01:00+09:00","direction":"response","summary":"b","detail":"b"}
EOF
    cat > "$TEST_TMPDIR/archive/2026-05-02.jsonl" <<'EOF'
not-json
{"ts":"2026-05-02T00:00:00+09:00","direction":"outbound","summary":"c","detail":"c"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/archive" "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
from pathlib import Path
archive = Path(sys.argv[1])
expected = sum(
    1
    for path in archive.glob("*.jsonl")
    for line in path.read_text(encoding="utf-8").splitlines()
    if line.strip()
)
conn = sqlite3.connect(sys.argv[2])
actual = conn.execute("SELECT COUNT(*) FROM conversations").fetchone()[0]
events = conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
invalid = conn.execute("SELECT COUNT(*) FROM conversations WHERE direction='invalid'").fetchone()[0]
print(expected)
print(actual)
print(events)
print(invalid)
PY
)
    [ "${result[0]}" = "${result[1]}" ]
    [ "${result[0]}" = "${result[2]}" ]
    [ "${result[3]}" = "1" ]
}

@test "memory_db_import migrates existing conversations into events with cmd and concepts" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:56:54+09:00","agent":"shogun","direction":"response","summary":"cmd_2966 eventsテーブル拡張","detail":"multi_agent_shogun_memory.db とセマンティクスインデックスを連携する"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import json
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    "SELECT event_type, target, cmd_id, concepts FROM events"
).fetchone()
print(row[0])
print(row[1])
print(row[2])
print("local_memory_db" in json.loads(row[3]))
print("semantic_dictionary_design" in json.loads(row[3]))
print(conn.execute("SELECT COUNT(*) FROM conversations").fetchone()[0])
print(conn.execute("SELECT COUNT(*) FROM events").fetchone()[0])
PY
)
    [ "${result[0]}" = "conversation" ]
    [ "${result[1]}" = "lord" ]
    [ "${result[2]}" = "cmd_2966" ]
    [ "${result[3]}" = "True" ]
    [ "${result[4]}" = "True" ]
    [ "${result[5]}" = "${result[6]}" ]
}

@test "memory_db_import normalizes concepts into event_concepts junction table" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:56:54+09:00","agent":"shogun","direction":"response","summary":"cmd_2966 eventsテーブル拡張","detail":"multi_agent_shogun_memory.db とセマンティクスインデックスを連携する"}
{"ts":"2026-05-22T12:57:54+09:00","agent":"shogun","direction":"response","summary":"cmd_2970 FTS5","detail":"SQLite記憶DBをFTS5対応にする"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
tables = {
    row[0]
    for row in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'"
    )
}
cols = [row[1] for row in conn.execute("PRAGMA table_info(event_concepts)")]
print("event_concepts" in tables)
print(",".join(cols))
print(conn.execute("SELECT COUNT(*) FROM event_concepts").fetchone()[0] > 0)
print(conn.execute(
    "SELECT COUNT(*) FROM event_concepts WHERE concept_name='local_memory_db'"
).fetchone()[0] > 0)
print(conn.execute(
    """
    SELECT concept_name, COUNT(*)
    FROM event_concepts
    GROUP BY concept_name
    HAVING concept_name='local_memory_db'
    """
).fetchone()[1])
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM event_concepts AS ec
    JOIN events AS e ON e.id = ec.event_id
    WHERE ec.concept_name='local_memory_db'
      AND e.event_type='conversation'
    """
).fetchone()[0] > 0)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "event_id,concept_name" ]
    [ "${result[2]}" = "True" ]
    [ "${result[3]}" = "True" ]
    [ "${result[4]}" -ge 1 ]
    [ "${result[5]}" = "True" ]
}

@test "memory_db_import backfills empty event concepts in existing DB" {
    cat > "$TEST_TMPDIR/semantic-index.md" <<'EOF'
## local_memory_db — ローカル記憶DB
| field | value |
| aliases | SQLite記憶DB, multi_agent_shogun_memory.db |
EOF
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:56:54+09:00","agent":"shogun","direction":"response","summary":"cmd_2966 eventsテーブル拡張","detail":"multi_agent_shogun_memory.db とセマンティクスインデックスを連携する"}
{"ts":"2026-05-22T12:57:54+09:00","agent":"shogun","direction":"response","summary":"cmd_2970 FTS5","detail":"SQLite記憶DBをFTS5対応にする"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --semantic-index "$TEST_TMPDIR/semantic-index.md"
    [ "$status" -eq 0 ]

    python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("UPDATE events SET concepts = '[]'")
conn.execute("DELETE FROM event_concepts")
conn.commit()
PY

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --semantic-index "$TEST_TMPDIR/semantic-index.md" \
        --backfill-concepts
    [ "$status" -eq 0 ]
    [[ "$output" == *"scanned_empty=2"* ]]
    [[ "$output" == *"updated=2"* ]]
    [[ "$output" == *"improved_types=conversation"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import json
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
print(conn.execute("SELECT COUNT(*) FROM events WHERE concepts = '[]'").fetchone()[0])
print(conn.execute("SELECT COUNT(*) FROM event_concepts WHERE concept_name='local_memory_db'").fetchone()[0])
print(all(
    "local_memory_db" in json.loads(row[0])
    for row in conn.execute("SELECT concepts FROM events ORDER BY id")
))
PY
)
    [ "${result[0]}" = "0" ]
    [ "${result[1]}" = "2" ]
    [ "${result[2]}" = "True" ]
}

@test "memory_db_import imports bulletin_board entries as bulletin events" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF
    mkdir -p "$TEST_TMPDIR/queue/archive"
    cat > "$TEST_TMPDIR/queue/bulletin_board.yaml" <<'EOF'
entries:
- id: 'blt_test_open'
  content: |-
    GATE CLEAR cmd_2977: bulletin投入確認
  posted_by: 'karo'
  posted_at: '2026-05-22T15:00:00'
  requires_confirmation: false
  action_type: 'info'
  actioned_by: ''
  confirmed_by: []
  status: 'open'
EOF
    cat > "$TEST_TMPDIR/queue/archive/bulletin_20260521.yaml" <<'EOF'
entries:
- id: 'blt_test_archive'
  content: |-
    INSIGHT_REPEAT: source=semantic_stress_test pending_count=3
  posted_by: 'saizo'
  posted_at: '2026-05-21T15:00:00'
  requires_confirmation:
    - 'shogun'
  action_type: 'action_required'
  actioned_by: ''
  confirmed_by: []
  status: 'open'
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"bulletins=2"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
print(conn.execute("SELECT COUNT(*) FROM events WHERE event_type='conversation'").fetchone()[0])
print(conn.execute("SELECT COUNT(*) FROM events WHERE event_type='bulletin'").fetchone()[0])
row = conn.execute(
    "SELECT agent, direction, summary, cmd_id, importance FROM events WHERE id='bulletin:blt_test_open'"
).fetchone()
print("|".join(row))
print(conn.execute(
    "SELECT importance FROM events WHERE id='bulletin:blt_test_archive'"
).fetchone()[0])
PY
)
    [ "${result[0]}" = "1" ]
    [ "${result[1]}" = "2" ]
    [ "${result[2]}" = "karo|info|GATE CLEAR cmd_2977: bulletin投入確認|cmd_2977|normal" ]
    [ "${result[3]}" = "high" ]
}

@test "memory_db_import imports insights.yaml entries as insight events" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF
    mkdir -p "$TEST_TMPDIR/queue"
    cat > "$TEST_TMPDIR/queue/insights.yaml" <<'EOF'
insights:
- id: INS-test-pending
  ts: "2026-05-22T15:10:00+09:00"
  insight: "cmd_2978 insight投入テスト pending"
  priority: "medium"
  source: "manual"
  status: pending
- id: INS-test-resolved
  ts: "2026-05-22T15:11:00+09:00"
  insight: "resolved insight should remain searchable"
  priority: "low"
  source: "semantic_stress_test"
  status: resolved
  resolved_reason: "noise"
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"insights=2"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
print(conn.execute("SELECT COUNT(*) FROM events WHERE event_type='conversation'").fetchone()[0])
print(conn.execute("SELECT COUNT(*) FROM events WHERE event_type='insight'").fetchone()[0])
row = conn.execute(
    "SELECT agent, direction, summary, cmd_id, importance FROM events WHERE id='insight:INS-test-pending'"
).fetchone()
print("|".join(row))
print(conn.execute(
    "SELECT detail FROM events WHERE id='insight:INS-test-resolved'"
).fetchone()[0].replace("\n", "|"))
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'searchable'
      AND e.event_type = 'insight'
    """
).fetchone()[0])
PY
)
    [ "${result[0]}" = "1" ]
    [ "${result[1]}" = "2" ]
    [ "${result[2]}" = "manual|pending|cmd_2978 insight投入テスト pending|cmd_2978|high" ]
    [[ "${result[3]}" == *"resolved_reason: noise"* ]]
    [ "${result[4]}" = "1" ]
}

@test "memory_db_import imports skill execution log entries as skill_execution events" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF
    mkdir -p "$TEST_TMPDIR/logs"
    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'EOF'
executions:
- ts: "2026-05-22T18:00:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "PASS"
  used: "true"
  stumbling_points: "cmd_2992 report gate searchable"
  gate: "gate_report_format"
  source: "queue/reports/saizo_report_cmd_2992.yaml"
  skill_path: "/mnt/c/tools/multi-agent-shogun/skills/report-write/SKILL.md"
- ts: "2026-05-22T18:01:00+0900"
  skill: "verdict-check"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "binary check mismatch"
  gate: "gate_report_format"
  source: "queue/reports/saizo_report_cmd_2992.yaml"
  skill_path: "/mnt/c/tools/multi-agent-shogun/skills/verdict-check/SKILL.md"
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skill_executions=2"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
print(conn.execute("SELECT COUNT(*) FROM events WHERE event_type='skill_execution'").fetchone()[0])
row = conn.execute(
    "SELECT agent, target, direction, cmd_id, importance FROM events WHERE event_type='skill_execution' AND target='report-write'"
).fetchone()
print("|".join(row))
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'searchable'
      AND e.event_type='skill_execution'
    """
).fetchone()[0])
print(conn.execute(
    "SELECT importance FROM events WHERE event_type='skill_execution' AND target='verdict-check'"
).fetchone()[0])
PY
)
    [ "${result[0]}" = "2" ]
    [ "${result[1]}" = "saizo|report-write|PASS|cmd_2992|normal" ]
    [ "${result[2]}" = "1" ]
    [ "${result[3]}" = "high" ]
}

@test "memory_db_import imports completed cmd archive entries as cmd_archive events" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF
    mkdir -p "$TEST_TMPDIR/queue/archive/cmds"
    cat > "$TEST_TMPDIR/queue/archive/cmds/cmd_2992_done_20260522.yaml" <<'EOF'
commands:
  cmd_2992:
    id: cmd_2992
    title: "memory DB archive import"
    project: infra
    type: impl
    purpose: "completed cmd archive searchable purpose"
    acceptance_criteria:
    - "AC1: cmd archive imported"
    timestamp: "2026-05-22T18:05:00+09:00"
    status: done
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cmd_archives=1"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    "SELECT event_type, agent, target, direction, summary, cmd_id, importance FROM events WHERE event_type='cmd_archive'"
).fetchone()
print("|".join(row))
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'searchable'
      AND e.event_type='cmd_archive'
    """
).fetchone()[0])
PY
)
    [ "${result[0]}" = "cmd_archive|shogun|infra|done|memory DB archive import|cmd_2992|normal" ]
    [ "${result[1]}" = "1" ]
}

@test "memory_db_import imports pending_decisions.yaml entries as pending_decision events" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF
    mkdir -p "$TEST_TMPDIR/queue"
    cat > "$TEST_TMPDIR/queue/pending_decisions.yaml" <<'EOF'
summary:
  total: 1
  resolved: 0
  pending: 1
decisions:
- id: PD-999
  type: lord_decision
  summary: "cmd_2992 pending decision searchable"
  source_cmd: cmd_2992
  status: pending
  created_at: "2026-05-22T18:06:00+09:00"
  created_by: shogun
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pending_decisions=1"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    "SELECT event_type, agent, target, direction, summary, cmd_id, importance FROM events WHERE id='pending_decision:PD-999'"
).fetchone()
print("|".join(row))
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'searchable'
      AND e.event_type='pending_decision'
    """
).fetchone()[0])
PY
)
    [ "${result[0]}" = "pending_decision|shogun|cmd_2992|pending|cmd_2992 pending decision searchable|cmd_2992|high" ]
    [ "${result[1]}" = "1" ]
}

@test "memory_db_import imports doc dirs as document events" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF
    mkdir -p "$TEST_TMPDIR/docs/context" "$TEST_TMPDIR/docs/projects/infra"
    cat > "$TEST_TMPDIR/docs/context/test-memory-doc.md" <<'EOF'
# Context Document Heading

context document unique needle cmd_3011_exact_document
EOF
    cat > "$TEST_TMPDIR/docs/projects/infra/infra-note.md" <<'EOF'
# Infra Note

infra document searchable marker
EOF
    cat > "$TEST_TMPDIR/docs/projects/infra/lesson.yaml" <<'EOF'
id: L3011
summary: yaml lesson searchable marker
EOF
    cat > "$TEST_TMPDIR/docs/projects/infra/checklist.txt" <<'EOF'
txt checklist searchable marker
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --doc-dirs "$TEST_TMPDIR/docs/context,$TEST_TMPDIR/docs/projects/infra"
    [ "$status" -eq 0 ]
    [[ "$output" == *"documents=4"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
print(conn.execute("SELECT COUNT(*) FROM events WHERE event_type='document'").fetchone()[0])
row = conn.execute(
    """
    SELECT event_type, agent, direction, summary, cmd_id, source_file
    FROM events
    WHERE event_type='document' AND summary='Context Document Heading'
    """
).fetchone()
print("|".join(row))
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'cmd_3011_exact_document'
      AND e.event_type='document'
    """
).fetchone()[0])
PY
)
    [ "${result[0]}" = "4" ]
    [[ "${result[1]}" == "document|document|document|Context Document Heading|cmd_3011_exact_document|"* ]]
    [ "${result[2]}" = "1" ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --search "cmd_3011_exact_document"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context Document Heading"* ]]

    run env MEMORY_DB_QUERY_TARGET=hayate bash "$PROJECT_ROOT/scripts/memory_db_query.sh" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --search "cmd_3011_exact_document"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context Document Heading"* ]]
}

@test "memory_db_import uses WAL and preserves live inserts across rebuilds" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        bulletin \
        --entry-id "live-test" \
        --ts "2026-05-22T17:05:00" \
        --agent "hayate" \
        --content "cmd_2984 live insert during import test" \
        --source-file "queue/inbox/hayate.yaml"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
print(conn.execute("PRAGMA journal_mode").fetchone()[0])
print(conn.execute("SELECT COUNT(*) FROM conversations").fetchone()[0])
print(conn.execute("SELECT COUNT(*) FROM events WHERE id='bulletin:live-test'").fetchone()[0])
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'cmd_2984'
      AND e.id='bulletin:live-test'
    """
).fetchone()[0])
PY
)
    [ "${result[0]}" = "wal" ]
    [ "${result[1]}" = "1" ]
    [ "${result[2]}" = "1" ]
    [ "${result[3]}" = "1" ]
}

@test "memory_db_live_insert appends workaround events with event_type workaround" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        workaround \
        --cmd-id "cmd_2990" \
        --ts "2026-05-22T18:10:00Z" \
        --ninja "hayate" \
        --category "report_yaml_format" \
        --issue "manual workaround recorded" \
        --root-cause "manual fix applied" \
        --source-file "logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    """
    SELECT event_type, agent, target, direction, summary, replace(detail, char(10), '|'), cmd_id, importance, source_file
    FROM events
    WHERE id='workaround:cmd_2990:hayate:2026-05-22T18:10:00Z'
    """
).fetchone()
print("|".join(row))
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'workaround'
      AND e.event_type='workaround'
    """
).fetchone()[0])
PY
)
    [ "${result[0]}" = "workaround|karo|hayate|report_yaml_format|manual workaround recorded|manual workaround recorded|root_cause: manual fix applied|category: report_yaml_format|ninja: hayate|cmd_2990|high|logs/karo_workarounds.yaml" ]
    [ "${result[1]}" = "1" ]
}

@test "memory_db_import extracts obsidian links into event_links table" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"shogun","direction":"response","summary":"[[3層記憶モデル]]の設計","detail":"[[Obsidianリンク未連携]]と[[event_links因果辺]]を接続する。[[3層記憶モデル]]参照。"}
{"ts":"2026-05-22T12:01:00+09:00","agent":"lord","direction":"inbound","summary":"確認","detail":"[[event_links因果辺]]のクエリ動作確認"}
{"ts":"2026-05-22T12:02:00+09:00","agent":"shogun","direction":"response","summary":"リンクなし","detail":"通常のテキストのみ"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
# AC1: event_links table exists with correct columns
tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
cols = [row[1] for row in conn.execute("PRAGMA table_info(event_links)")]
print("event_links" in tables)
print(",".join(cols))
# AC2: obsidian links extracted
total = conn.execute("SELECT COUNT(*) FROM event_links").fetchone()[0]
print(total > 0)
row3 = conn.execute(
    "SELECT COUNT(*) FROM event_links WHERE target_concept='3層記憶モデル'"
).fetchone()[0]
print(row3)
link_type = conn.execute("SELECT DISTINCT link_type FROM event_links").fetchone()[0]
print(link_type)
# AC3: top-concept aggregation query
rows = conn.execute(
    "SELECT target_concept, COUNT(*) FROM event_links GROUP BY target_concept ORDER BY COUNT(*) DESC LIMIT 5"
).fetchall()
top_concept = rows[0][0]
top_count = rows[0][1]
print(top_concept)
print(top_count >= 2)
# no links for plain-text event
no_links_event_count = conn.execute(
    """
    SELECT COUNT(*) FROM events e
    WHERE e.summary='リンクなし'
      AND EXISTS (SELECT 1 FROM event_links el WHERE el.source_event_id = e.id)
    """
).fetchone()[0]
print(no_links_event_count == 0)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "source_event_id,target_concept,link_type" ]
    [ "${result[2]}" = "True" ]
    [ "${result[3]}" -ge 1 ]
    [ "${result[4]}" = "obsidian" ]
    [ "${result[5]}" = "event_links因果辺" ]
    [ "${result[6]}" = "True" ]
    [ "${result[7]}" = "True" ]
}

@test "memory_db_import adds state column with default raw to events table" {
    cat > "$TEST_TMPDIR/archive/2026-06-01.jsonl" <<'EOF'
{"ts":"2026-06-01T10:00:00+09:00","agent":"lord","direction":"inbound","summary":"state列テスト","detail":"eventsテーブルstate列追加確認"}
{"ts":"2026-06-01T10:01:00+09:00","agent":"shogun","direction":"response","summary":"state列応答","detail":"新規行のstateはrawである"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
cols = [row[1] for row in conn.execute("PRAGMA table_info(events)")]
print("state" in cols)
count_raw = conn.execute("SELECT COUNT(*) FROM events WHERE state = 'raw'").fetchone()[0]
count_all = conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
print(count_raw == count_all)
print(count_all)
row = conn.execute("SELECT state FROM events ORDER BY ts LIMIT 1").fetchone()
print(row[0])
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "2" ]
    [ "${result[3]}" = "raw" ]
}

@test "memory_db_import migrates existing DB by adding state column via ALTER TABLE" {
    cat > "$TEST_TMPDIR/archive/2026-06-01.jsonl" <<'EOF'
{"ts":"2026-06-01T10:00:00+09:00","agent":"lord","direction":"inbound","summary":"既存DB","detail":"state列なしのDBにstate列を追加する"}
EOF

    # Build initial DB without state column (simulate legacy DB)
    python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("PRAGMA journal_mode=WAL")
conn.execute(
    """
    CREATE TABLE events (
        id TEXT PRIMARY KEY,
        ts TEXT,
        event_type TEXT,
        agent TEXT,
        target TEXT,
        direction TEXT,
        summary TEXT,
        detail TEXT,
        session_id TEXT,
        cmd_id TEXT,
        concepts TEXT,
        source_file TEXT,
        parent_event_id INTEGER,
        importance TEXT
    )
    """
)
conn.execute(
    "INSERT INTO events (id, ts, event_type, summary, detail, importance) VALUES (?, ?, ?, ?, ?, ?)",
    ("legacy:1", "2026-05-01T00:00:00", "conversation", "既存行", "state列なし", "normal")
)
conn.execute("CREATE VIRTUAL TABLE events_fts USING fts5(summary, detail, content='events', content_rowid='rowid', tokenize='trigram')")
conn.execute("INSERT INTO events_fts(events_fts) VALUES ('rebuild')")
conn.commit()
PY

    # Verify no state column yet
    run python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
cols = [row[1] for row in conn.execute("PRAGMA table_info(events)")]
print("state" in cols)
PY
    [ "$output" = "False" ]

    # Run import: should migrate and add state column
    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
cols = [row[1] for row in conn.execute("PRAGMA table_info(events)")]
print("state" in cols)
count_raw = conn.execute("SELECT COUNT(*) FROM events WHERE state = 'raw'").fetchone()[0]
count_all = conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
print(count_raw == count_all)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
}

@test "memory_db_live_insert appends contradiction and duplicate candidates with candidate states" {
    cat > "$TEST_TMPDIR/archive/2026-06-03.jsonl" <<'EOF'
{"ts":"2026-06-03T10:00:00+09:00","agent":"lord","direction":"inbound","summary":"記憶候補テスト","detail":"候補イベントのstate確認"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        contradiction_candidate \
        --candidate-id "contradiction-test" \
        --ts "2026-06-03T19:50:00+09:00" \
        --contradiction-type "time_mismatch" \
        --source-event-id "event:a" \
        --conflicting-event-id "event:b" \
        --summary "時点違いの矛盾候補" \
        --detail "AとBは時点が違うため削除せず候補化する" \
        --source-file "tests/unit/test_memory_db.bats"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        duplicate_candidate \
        --candidate-id "duplicate-test" \
        --ts "2026-06-03T19:51:00+09:00" \
        --primary-event-id "event:a" \
        --duplicate-event-id "event:c" \
        --similarity "0.92" \
        --summary "重複候補" \
        --detail "AとCは同一内容の可能性がある" \
        --source-file "tests/unit/test_memory_db.bats"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
for event_id in ("contradiction_candidate:contradiction-test", "duplicate_candidate:duplicate-test"):
    row = conn.execute(
        "SELECT event_type, direction, state, summary, replace(detail, char(10), '|') FROM events WHERE id = ?",
        (event_id,),
    ).fetchone()
    print("|".join(row))
print(conn.execute("SELECT COUNT(*) FROM events WHERE state='contradiction_candidate'").fetchone()[0])
print(conn.execute("SELECT COUNT(*) FROM events WHERE state='duplicate_candidate'").fetchone()[0])
PY
)
    [ "${result[0]}" = "memory_candidate|time_mismatch|contradiction_candidate|時点違いの矛盾候補|AとBは時点が違うため削除せず候補化する|contradiction_type: time_mismatch|source_event_id: event:a|conflicting_event_id: event:b" ]
    [ "${result[1]}" = "memory_candidate|duplicate|duplicate_candidate|重複候補|AとCは同一内容の可能性がある|primary_event_id: event:a|duplicate_event_id: event:c|similarity: 0.92" ]
    [ "${result[2]}" = "1" ]
    [ "${result[3]}" = "1" ]
}

@test "memory_db_live_insert rejects unclassified contradiction candidates" {
    cat > "$TEST_TMPDIR/archive/2026-06-03.jsonl" <<'EOF'
{"ts":"2026-06-03T10:00:00+09:00","agent":"lord","direction":"inbound","summary":"記憶候補テスト","detail":"候補イベントのstate確認"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        contradiction_candidate \
        --candidate-id "bad-contradiction-test" \
        --ts "2026-06-03T19:52:00+09:00" \
        --contradiction-type "unknown" \
        --source-event-id "event:a" \
        --conflicting-event-id "event:b" \
        --summary "未分類の矛盾候補" \
        --detail "分類なしは記録しない" \
        --source-file "tests/unit/test_memory_db.bats"
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid contradiction_type"* ]]
}

@test "obsidian_promote_candidate backs up DB and marks high-value events as candidates" {
    python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE events (id TEXT PRIMARY KEY, summary TEXT, event_type TEXT, importance TEXT, state TEXT DEFAULT 'raw', updated_at TEXT)")
conn.execute("CREATE TABLE event_concepts (event_id TEXT, concept_name TEXT)")
conn.execute("CREATE TABLE event_links (source_event_id TEXT, target_concept TEXT, link_type TEXT)")
events = [
    ("event:promote", "昇格対象", "conversation", "high", "verified", None),
    ("event:freq", "頻度供給", "conversation", "high", "raw", None),
    ("event:low", "importance不足", "conversation", "normal", "verified", None),
    ("event:onelink", "リンク不足", "conversation", "high", "verified", None),
    ("event:existing", "既存候補除外", "conversation", "high", "obsidian_candidate", None),
]
conn.executemany("INSERT INTO events VALUES (?, ?, ?, ?, ?, ?)", events)
conn.executemany(
    "INSERT INTO event_concepts VALUES (?, ?)",
    [
        ("event:promote", "三層記憶"),
        ("event:freq", "三層記憶"),
        ("event:low", "三層記憶"),
        ("event:onelink", "三層記憶"),
        ("event:existing", "三層記憶"),
    ],
)
conn.executemany(
    "INSERT INTO event_links VALUES (?, ?, 'obsidian')",
    [
        ("event:promote", "リンクA"),
        ("event:promote", "リンクB"),
        ("event:low", "リンクA"),
        ("event:low", "リンクB"),
        ("event:onelink", "リンクA"),
        ("event:existing", "リンクA"),
        ("event:existing", "リンクB"),
    ],
)
conn.commit()
PY

    mkdir -p "$TEST_TMPDIR/backups"
    run bash "$PROJECT_ROOT/scripts/obsidian_promote_candidate.sh" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --backup-dir "$TEST_TMPDIR/backups" \
        --min-concept-frequency 3 \
        --min-links 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"backup=$TEST_TMPDIR/backups/memory.db.bak_obsidian_candidate_"* ]]
    [[ "$output" == *"updated=1"* ]]
    [[ "$output" == *"event:promote|high|links=2|concept_frequency=5|昇格対象"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" "$TEST_TMPDIR/backups" <<'PY'
import sqlite3
import sys
from pathlib import Path
conn = sqlite3.connect(sys.argv[1])
backup_paths = sorted(Path(sys.argv[2]).glob("memory.db.bak_obsidian_candidate_*"))
print(len(backup_paths))
print(conn.execute("SELECT state FROM events WHERE id='event:promote'").fetchone()[0])
print(conn.execute("SELECT state FROM events WHERE id='event:low'").fetchone()[0])
print(conn.execute("SELECT state FROM events WHERE id='event:onelink'").fetchone()[0])
print(conn.execute("SELECT state FROM events WHERE id='event:existing'").fetchone()[0])
backup_conn = sqlite3.connect(backup_paths[0])
print(backup_conn.execute("SELECT state FROM events WHERE id='event:promote'").fetchone()[0])
print(conn.execute("SELECT updated_at IS NOT NULL FROM events WHERE id='event:promote'").fetchone()[0])
PY
)
    [ "${result[0]}" = "1" ]
    [ "${result[1]}" = "obsidian_candidate" ]
    [ "${result[2]}" = "verified" ]
    [ "${result[3]}" = "verified" ]
    [ "${result[4]}" = "obsidian_candidate" ]
    [ "${result[5]}" = "verified" ]
    [ "${result[6]}" = "1" ]
}

@test "obsidian_promote_candidate dry-run lists candidates without backup or update" {
    python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE events (id TEXT PRIMARY KEY, summary TEXT, event_type TEXT, importance TEXT, state TEXT DEFAULT 'raw', updated_at TEXT)")
conn.execute("CREATE TABLE event_concepts (event_id TEXT, concept_name TEXT)")
conn.execute("CREATE TABLE event_links (source_event_id TEXT, target_concept TEXT, link_type TEXT)")
conn.executemany(
    "INSERT INTO events VALUES (?, ?, ?, ?, ?, ?)",
    [
        ("event:a", "dry対象", "conversation", "high", "raw", None),
        ("event:b", "頻度供給", "conversation", "high", "raw", None),
        ("event:c", "頻度供給2", "conversation", "high", "raw", None),
    ],
)
conn.executemany("INSERT INTO event_concepts VALUES (?, '候補概念')", [("event:a",), ("event:b",), ("event:c",)])
conn.executemany("INSERT INTO event_links VALUES (?, ?, 'obsidian')", [("event:a", "L1"), ("event:a", "L2")])
conn.commit()
PY

    mkdir -p "$TEST_TMPDIR/backups"
    run bash "$PROJECT_ROOT/scripts/obsidian_promote_candidate.sh" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --backup-dir "$TEST_TMPDIR/backups" \
        --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"candidates=1"* ]]
    [[ "$output" == *"dry_run=true"* ]]
    [[ "$output" == *"event:a|high|links=2|concept_frequency=3|dry対象"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" "$TEST_TMPDIR/backups" <<'PY'
import sqlite3
import sys
from pathlib import Path
conn = sqlite3.connect(sys.argv[1])
print(conn.execute("SELECT state FROM events WHERE id='event:a'").fetchone()[0])
print(len(list(Path(sys.argv[2]).glob("memory.db.bak_obsidian_candidate_*"))))
PY
)
    [ "${result[0]}" = "raw" ]
    [ "${result[1]}" = "0" ]
}

@test "memory_db_live_insert defines the complete event state set" {
    readarray -t result < <(python3 - "$PROJECT_ROOT/scripts/memory_db_live_insert.py" <<'PY'
import importlib.util
import sys
spec = importlib.util.spec_from_file_location("memory_db_live_insert", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(",".join(sorted(module.VALID_EVENT_STATES)))
PY
)
    [ "${result[0]}" = "archived,contradiction_candidate,duplicate_candidate,obsidian_candidate,obsidian_promoted,raw,stale_candidate,verified" ]
}

@test "update_event_state updates state and logs transition reason" {
    readarray -t result < <(python3 - "$PROJECT_ROOT/scripts/memory_db_live_insert.py" "$TEST_TMPDIR/data/memory.db" <<'PY'
import importlib.util
import sqlite3
import sys
spec = importlib.util.spec_from_file_location("memory_db_live_insert", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
conn = sqlite3.connect(sys.argv[2])
conn.execute("CREATE TABLE events (id TEXT PRIMARY KEY, summary TEXT, state TEXT DEFAULT 'raw', updated_at TEXT)")
conn.execute("INSERT INTO events (id, summary, state) VALUES ('event:1', '遷移対象', 'verified')")
with conn:
    print(module.update_event_state(conn, ["event:1"], "archived", "recall window exceeded", "unit_test"))
print(conn.execute("SELECT state FROM events WHERE id='event:1'").fetchone()[0])
print(conn.execute("SELECT from_state, to_state, reason, actor FROM event_state_transitions WHERE event_id='event:1'").fetchone())
print(conn.execute("SELECT updated_at IS NOT NULL FROM events WHERE id='event:1'").fetchone()[0])
PY
)
    [ "${result[0]}" = "1" ]
    [ "${result[1]}" = "archived" ]
    [ "${result[2]}" = "('verified', 'archived', 'recall window exceeded', 'unit_test')" ]
    [ "${result[3]}" = "1" ]
}

@test "memory_recall_control backs up DB and archives old verified events" {
    python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE events (id TEXT PRIMARY KEY, ts TEXT, summary TEXT, state TEXT DEFAULT 'raw', updated_at TEXT)")
conn.executemany(
    "INSERT INTO events VALUES (?, ?, ?, ?, ?)",
    [
        ("event:old", "2026-01-01T00:00:00+09:00", "古いverified", "verified", "2026-01-01T00:00:00+09:00"),
        ("event:new", "2026-06-01T00:00:00+09:00", "新しいverified", "verified", "2026-06-01T00:00:00+09:00"),
        ("event:raw", "2026-01-01T00:00:00+09:00", "rawは対象外", "raw", "2026-01-01T00:00:00+09:00"),
    ],
)
conn.commit()
PY

    mkdir -p "$TEST_TMPDIR/backups"
    run bash "$PROJECT_ROOT/scripts/memory_recall_control.sh" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --backup-dir "$TEST_TMPDIR/backups" \
        --older-than-days 30 \
        --reason "unit recall policy"
    [ "$status" -eq 0 ]
    [[ "$output" == *"backup=$TEST_TMPDIR/backups/memory.db.bak_recall_control_"* ]]
    [[ "$output" == *"updated=1"* ]]
    [[ "$output" == *"event:old|古いverified"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" "$TEST_TMPDIR/backups" <<'PY'
import sqlite3
import sys
from pathlib import Path
conn = sqlite3.connect(sys.argv[1])
backup_paths = sorted(Path(sys.argv[2]).glob("memory.db.bak_recall_control_*"))
print(len(backup_paths))
print(conn.execute("SELECT state FROM events WHERE id='event:old'").fetchone()[0])
print(conn.execute("SELECT state FROM events WHERE id='event:new'").fetchone()[0])
print(conn.execute("SELECT state FROM events WHERE id='event:raw'").fetchone()[0])
print(conn.execute("SELECT reason FROM event_state_transitions WHERE event_id='event:old'").fetchone()[0])
backup_conn = sqlite3.connect(backup_paths[0])
print(backup_conn.execute("SELECT state FROM events WHERE id='event:old'").fetchone()[0])
PY
)
    [ "${result[0]}" = "1" ]
    [ "${result[1]}" = "archived" ]
    [ "${result[2]}" = "verified" ]
    [ "${result[3]}" = "raw" ]
    [ "${result[4]}" = "unit recall policy" ]
    [ "${result[5]}" = "verified" ]
}

@test "memory_db_import records confidence freshness source_type defaults" {
    cat > "$TEST_TMPDIR/archive/2026-06-01.jsonl" <<'EOF'
{"ts":"2026-06-01T10:00:00+09:00","agent":"lord","direction":"inbound","summary":"属性列テスト","detail":"confidence freshness source_type のデフォルト確認"}
{"ts":"2026-06-01T10:01:00+09:00","agent":"shogun","direction":"response","summary":"属性列応答","detail":"importance と信頼度を分離する"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
cols = [row[1] for row in conn.execute("PRAGMA table_info(events)")]
print("confidence" in cols)
print("freshness" in cols)
print("source_type" in cols)
rows = conn.execute(
    "SELECT confidence, freshness, source_type FROM events ORDER BY ts"
).fetchall()
print(len(rows))
print(all(row == ("medium", "current", "fact") for row in rows))
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "True" ]
    [ "${result[3]}" = "2" ]
    [ "${result[4]}" = "True" ]
}

@test "memory_db_import migrates existing DB by adding confidence freshness source_type columns" {
    cat > "$TEST_TMPDIR/archive/2026-06-01.jsonl" <<'EOF'
{"ts":"2026-06-01T10:00:00+09:00","agent":"lord","direction":"inbound","summary":"既存DB属性列","detail":"属性列なしのDBへ追加"}
EOF

    python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("PRAGMA journal_mode=WAL")
conn.execute(
    """
    CREATE TABLE events (
        id TEXT PRIMARY KEY,
        ts TEXT,
        event_type TEXT,
        agent TEXT,
        target TEXT,
        direction TEXT,
        summary TEXT,
        detail TEXT,
        session_id TEXT,
        cmd_id TEXT,
        concepts TEXT,
        source_file TEXT,
        parent_event_id INTEGER,
        importance TEXT
    )
    """
)
conn.execute(
    "INSERT INTO events (id, ts, event_type, summary, detail, importance) VALUES (?, ?, ?, ?, ?, ?)",
    ("legacy:1", "2026-05-01T00:00:00+09:00", "conversation", "既存行", "属性列なし", "normal")
)
conn.execute("CREATE VIRTUAL TABLE events_fts USING fts5(summary, detail, content='events', content_rowid='rowid', tokenize='trigram')")
conn.execute("INSERT INTO events_fts(events_fts) VALUES ('rebuild')")
conn.commit()
PY

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
cols = [row[1] for row in conn.execute("PRAGMA table_info(events)")]
print("confidence" in cols)
print("freshness" in cols)
print("source_type" in cols)
defaults = conn.execute(
    "SELECT COUNT(*) FROM events WHERE confidence = 'medium' AND freshness = 'current' AND source_type = 'fact'"
).fetchone()[0]
count_all = conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
print(defaults == count_all)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "True" ]
    [ "${result[3]}" = "True" ]
}

@test "memory_db_import adds occurred_at recorded_at updated_at columns to events table" {
    cat > "$TEST_TMPDIR/archive/2026-06-01.jsonl" <<'EOF'
{"ts":"2026-06-01T10:00:00+09:00","agent":"lord","direction":"inbound","summary":"timestamp列テスト","detail":"3種タイムスタンプ列追加確認"}
{"ts":"2026-06-01T10:01:00+09:00","agent":"shogun","direction":"response","summary":"timestamp列応答","detail":"occurred_at recorded_at updated_at"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
cols = [row[1] for row in conn.execute("PRAGMA table_info(events)")]
print("occurred_at" in cols)
print("recorded_at" in cols)
print("updated_at" in cols)
# occurred_at と recorded_at は ts と同値
rows = conn.execute(
    "SELECT ts, occurred_at, recorded_at FROM events WHERE ts <> '' ORDER BY ts LIMIT 2"
).fetchall()
print(len(rows))
print(rows[0][0] == rows[0][1])
print(rows[0][0] == rows[0][2])
# updated_at は NULL
null_count = conn.execute(
    "SELECT COUNT(*) FROM events WHERE updated_at IS NULL"
).fetchone()[0]
print(null_count > 0)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "True" ]
    [ "${result[3]}" = "2" ]
    [ "${result[4]}" = "True" ]
    [ "${result[5]}" = "True" ]
    [ "${result[6]}" = "True" ]
}

@test "memory_db_import migrates existing DB by adding timestamp columns via ALTER TABLE" {
    cat > "$TEST_TMPDIR/archive/2026-06-01.jsonl" <<'EOF'
{"ts":"2026-06-01T10:00:00+09:00","agent":"lord","direction":"inbound","summary":"既存DBタイムスタンプ","detail":"timestamp列なしのDBへ追加"}
EOF

    # stateのみ存在するレガシーDB作成
    python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("PRAGMA journal_mode=WAL")
conn.execute(
    """
    CREATE TABLE events (
        id TEXT PRIMARY KEY,
        ts TEXT,
        event_type TEXT,
        agent TEXT,
        target TEXT,
        direction TEXT,
        summary TEXT,
        detail TEXT,
        session_id TEXT,
        cmd_id TEXT,
        concepts TEXT,
        source_file TEXT,
        parent_event_id INTEGER,
        importance TEXT,
        state TEXT DEFAULT 'raw'
    )
    """
)
conn.execute(
    "INSERT INTO events (id, ts, event_type, summary, detail, importance, state) VALUES (?, ?, ?, ?, ?, ?, ?)",
    ("legacy:1", "2026-05-01T00:00:00+09:00", "conversation", "既存行", "occurred_at未設定", "normal", "raw")
)
conn.execute("CREATE VIRTUAL TABLE events_fts USING fts5(summary, detail, content='events', content_rowid='rowid', tokenize='trigram')")
conn.execute("INSERT INTO events_fts(events_fts) VALUES ('rebuild')")
conn.commit()
PY

    # occurred_at列が存在しないことを確認
    run python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
cols = [row[1] for row in conn.execute("PRAGMA table_info(events)")]
print("occurred_at" in cols)
PY
    [ "$output" = "False" ]

    # importを実行 → occurred_at/recorded_at/updated_at が追加されバックフィルされる
    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
cols = [row[1] for row in conn.execute("PRAGMA table_info(events)")]
print("occurred_at" in cols)
print("recorded_at" in cols)
print("updated_at" in cols)
# 既存レガシー行はバックフィルされず、新規importされた行のみ確認
count_with_occurred = conn.execute(
    "SELECT COUNT(*) FROM events WHERE occurred_at IS NOT NULL AND ts <> ''"
).fetchone()[0]
count_with_ts = conn.execute(
    "SELECT COUNT(*) FROM events WHERE ts <> ''"
).fetchone()[0]
print(count_with_occurred == count_with_ts)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "True" ]
    [ "${result[3]}" = "True" ]
}
