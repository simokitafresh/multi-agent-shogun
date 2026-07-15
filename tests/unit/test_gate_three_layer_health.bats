#!/usr/bin/env bats
# test_gate_three_layer_health.bats — three-layer health gate state semantics

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/three_layer_health.XXXXXX")"
    export TEST_DB="$TEST_TMPDIR/memory.db"
    export TEST_CACHE="$TEST_TMPDIR/cache.db"
    export TEST_CHAIN_STATE="$TEST_TMPDIR/chain-state"
    mkdir -p "$TEST_CHAIN_STATE"
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
        THREE_LAYER_CHAIN_LOG="$TEST_TMPDIR/three_layer_chain_async.log" \
        THREE_LAYER_CHAIN_STATE_DIR="$TEST_CHAIN_STATE" \
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

@test "chain ERROR followed by OK for same event is treated as resolved" {
    init_cache_db "obsidian_promoted"
    cat > "$TEST_TMPDIR/three_layer_chain_async.log" <<'EOF'
2026-07-07T21:39:56+09:00 ERROR layer2_semantic_index_update_failed event=knowledge:e1 source=test
2026-07-07T21:40:11+09:00 OK layer2_semantic_index_update event=knowledge:e1 source=test
EOF

    run run_gate

    [ "$status" -eq 0 ]
    [[ "$output" == *"未貫通件数=0"* ]]
    [[ "$output" == *"STATUS: PASS"* ]]
}

@test "chain ERROR without later OK remains unresolved" {
    init_cache_db "obsidian_promoted"
    cat > "$TEST_TMPDIR/three_layer_chain_async.log" <<'EOF'
2026-07-07T21:39:56+09:00 ERROR layer2_semantic_index_update_failed event=knowledge:e1 source=test
EOF

    run run_gate

    [ "$status" -eq 2 ]
    [[ "$output" == *"未貫通件数=1"* ]]
    [[ "$output" == *"STATUS: WARN"* ]]
}

@test "stale durable pending request is WARN" {
    init_cache_db "obsidian_promoted"
    printf '{}\n' > "$TEST_CHAIN_STATE/knowledge_stale.pending.json"
    touch -d '5 minutes ago' "$TEST_CHAIN_STATE/knowledge_stale.pending.json"

    run run_gate

    [ "$status" -eq 2 ]
    [[ "$output" == *"stale_pending=1"* ]]
    [[ "$output" == *"STATUS: WARN"* ]]
}

@test "fresh durable pending request is allowed while worker runs" {
    init_cache_db "obsidian_promoted"
    printf '{}\n' > "$TEST_CHAIN_STATE/knowledge_fresh.pending.json"

    run run_gate

    [ "$status" -eq 0 ]
    [[ "$output" == *"stale_pending=0"* ]]
    [[ "$output" == *"STATUS: PASS"* ]]
}

@test "durable failed result is WARN even if chain log is absent" {
    init_cache_db "obsidian_promoted"
    printf 'state=FAIL\nreason=test\n' > "$TEST_CHAIN_STATE/knowledge_failed.result"

    run run_gate

    [ "$status" -eq 2 ]
    [[ "$output" == *"failed_results=1"* ]]
    [[ "$output" == *"STATUS: WARN"* ]]
}
