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

@test "memory_db_import creates conversations table with required columns" {
    cat > "$TEST_TMPDIR/archive/2026-05-01.jsonl" <<'EOF'
{"ts":"2026-05-01T00:00:00+09:00","agent":"lord","direction":"inbound","summary":"sum1","detail":"detail1"}
{"ts":"2026-05-01T00:01:00+09:00","agent":"shogun","direction":"response","summary":"sum2","detail":"detail2","session_id":"explicit-session"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"files=1 rows=2"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
cols = [row[1] for row in conn.execute("PRAGMA table_info(conversations)")]
print(",".join(cols))
print(conn.execute("SELECT COUNT(*) FROM conversations").fetchone()[0])
print(conn.execute("SELECT session_id FROM conversations ORDER BY ts LIMIT 1").fetchone()[0])
print(conn.execute("SELECT session_id FROM conversations ORDER BY ts DESC LIMIT 1").fetchone()[0])
PY
)
    [ "${result[0]}" = "ts,agent,direction,summary,detail,session_id" ]
    [ "${result[1]}" = "2" ]
    [ "${result[2]}" = "2026-05-01" ]
    [ "${result[3]}" = "explicit-session" ]
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
invalid = conn.execute("SELECT COUNT(*) FROM conversations WHERE direction='invalid'").fetchone()[0]
print(expected)
print(actual)
print(invalid)
PY
)
    [ "${result[0]}" = "${result[1]}" ]
    [ "${result[2]}" = "1" ]
}
