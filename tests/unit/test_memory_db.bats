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

@test "memory_db_import creates conversations and events tables with required columns" {
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
print(",".join(conversation_cols))
print(",".join(event_cols))
print(conn.execute("SELECT COUNT(*) FROM conversations").fetchone()[0])
print(conn.execute("SELECT session_id FROM conversations ORDER BY ts LIMIT 1").fetchone()[0])
print(conn.execute("SELECT session_id FROM conversations ORDER BY ts DESC LIMIT 1").fetchone()[0])
print(conn.execute("SELECT COUNT(*) FROM events").fetchone()[0])
print(conn.execute("SELECT event_type FROM events ORDER BY ts LIMIT 1").fetchone()[0])
PY
)
    [ "${result[0]}" = "ts,agent,direction,summary,detail,session_id" ]
    [ "${result[1]}" = "id,ts,event_type,agent,target,direction,summary,detail,session_id,cmd_id,concepts,source_file,parent_event_id,importance" ]
    [ "${result[2]}" = "2" ]
    [ "${result[3]}" = "2026-05-01" ]
    [ "${result[4]}" = "explicit-session" ]
    [ "${result[5]}" = "2" ]
    [ "${result[6]}" = "conversation" ]
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
