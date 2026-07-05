#!/usr/bin/env bats
# test_gate_three_layer_health.bats — three-layer health gate state semantics

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/three_layer_health.XXXXXX")"
    export TEST_DB="$TEST_TMPDIR/memory.db"
    export TEST_CACHE="$TEST_TMPDIR/cache.db"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

init_cache_db() {
    local state="$1"
    python3 - "$TEST_CACHE" "$state" <<'PY'
import sqlite3
import sys

db_path, state = sys.argv[1], sys.argv[2]
conn = sqlite3.connect(db_path)
conn.executescript("""
CREATE TABLE events (
    id TEXT PRIMARY KEY,
    state TEXT,
    raw_content TEXT
);
CREATE TABLE search_logs (
    id INTEGER PRIMARY KEY,
    ts TEXT,
    created_at TEXT
);
""")
conn.execute(
    "INSERT INTO events (id, state, raw_content) VALUES ('e1', ?, 'raw')",
    (state,),
)
conn.execute(
    "INSERT INTO search_logs (ts, created_at) VALUES (datetime('now'), datetime('now'))"
)
conn.commit()
conn.close()
PY
    : > "$TEST_DB"
}

run_gate() {
    env \
        SHOGUN_MEMORY_DB="$TEST_DB" \
        SHOGUN_MEMORY_DB_CACHE_PATH="$TEST_CACHE" \
        bash "$PROJECT_ROOT/scripts/gates/gate_three_layer_health.sh"
}

@test "promoted state with zero pending candidates is PASS" {
    init_cache_db "obsidian_promoted"

    run run_gate

    [ "$status" -eq 0 ]
    [[ "$output" == *"warn_bytes=5368709120"* ]]
    [[ "$output" == *"candidate候補生成件数: 0"* ]]
    [[ "$output" == *"state遷移件数(state!=raw): 1"* ]]
    [[ "$output" == *"STATUS: PASS"* ]]
    [ ! -e "$TEST_CACHE-journal" ]
    [ ! -e "$TEST_CACHE-wal" ]
    [ ! -e "$TEST_CACHE-shm" ]
}

@test "zero candidates and zero state transitions remains WARN" {
    init_cache_db "raw"

    run run_gate

    [ "$status" -eq 2 ]
    [[ "$output" == *"candidate候補生成件数: 0"* ]]
    [[ "$output" == *"state遷移件数(state!=raw): 0"* ]]
    [[ "$output" == *"STATUS: WARN"* ]]
}
