#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
    export SHOGUN_MEMORY_DB_CACHE_PATH="$TEST_TMPDIR/cache/memory.db"
    mkdir -p "$TEST_TMPDIR/cache"
    python3 - "$TEST_TMPDIR/source.db" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE probe (value TEXT)")
conn.execute("INSERT INTO probe VALUES ('source-db')")
conn.commit()
conn.close()
PY
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/scripts/lib/memory_db_cache.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

wait_for_file() {
    local path="$1" i=0
    while [ ! -s "$path" ] && [ "$i" -lt 50 ]; do
        sleep 0.05
        i=$((i + 1))
    done
    [ -s "$path" ]
}

@test "startup warm-up creates a missing cache asynchronously" {
    warm_memory_db_cache_async "$PROJECT_ROOT" "$TEST_TMPDIR/source.db"

    wait_for_file "$SHOGUN_MEMORY_DB_CACHE_PATH"
    run python3 - "$SHOGUN_MEMORY_DB_CACHE_PATH" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
print(conn.execute("SELECT value FROM probe").fetchone()[0])
conn.close()
PY
    [ "$status" -eq 0 ]
    [ "$output" = "source-db" ]
}

@test "concurrent warm-up is single-flight and read falls back without waiting" {
    create_memory_db_cache() {
        printf 'create\n' >> "$TEST_TMPDIR/create.calls"
        sleep 0.5
        cp "$2" "$SHOGUN_MEMORY_DB_CACHE_PATH"
    }

    warm_memory_db_cache_async "$PROJECT_ROOT" "$TEST_TMPDIR/source.db"
    warm_memory_db_cache_async "$PROJECT_ROOT" "$TEST_TMPDIR/source.db"
    sleep 0.1

    start_ms="$(date +%s%3N)"
    read_path="$(prepare_memory_db_for_read "$PROJECT_ROOT" "$TEST_TMPDIR/source.db")"
    elapsed_ms=$(( $(date +%s%3N) - start_ms ))

    [ "$read_path" = "$TEST_TMPDIR/source.db" ]
    [ "$elapsed_ms" -lt 400 ]
    wait_for_file "$SHOGUN_MEMORY_DB_CACHE_PATH"
    [ "$(wc -l < "$TEST_TMPDIR/create.calls")" -eq 1 ]
}

@test "restart_watchers starts common cache warm-up before watcher restart" {
    run grep -nE 'source .*memory_db_cache\.sh|warm_memory_db_cache_async' \
        "$PROJECT_ROOT/scripts/restart_watchers.sh"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]
}
