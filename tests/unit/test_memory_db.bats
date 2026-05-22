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
    [ "${result[1]}" = "id,ts,event_type,agent,target,direction,summary,detail,session_id,cmd_id,concepts,source_file" ]
    [ "${result[2]}" = "2" ]
    [ "${result[3]}" = "2026-05-01" ]
    [ "${result[4]}" = "explicit-session" ]
    [ "${result[5]}" = "2" ]
    [ "${result[6]}" = "conversation" ]
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
