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
        while [ ! -e "$TEST_TMPDIR/release.create" ]; do
            sleep 0.02
        done
        cp "$2" "$SHOGUN_MEMORY_DB_CACHE_PATH"
    }

    warm_memory_db_cache_async "$PROJECT_ROOT" "$TEST_TMPDIR/source.db"
    warm_memory_db_cache_async "$PROJECT_ROOT" "$TEST_TMPDIR/source.db"
    for _ in $(seq 1 100); do
        [ -s "$TEST_TMPDIR/create.calls" ] && break
        sleep 0.02
    done
    [ -s "$TEST_TMPDIR/create.calls" ]

    read_path="$(prepare_memory_db_for_read "$PROJECT_ROOT" "$TEST_TMPDIR/source.db")"
    touch "$TEST_TMPDIR/release.create"

    [ "$read_path" = "$TEST_TMPDIR/source.db" ]
    wait_for_file "$SHOGUN_MEMORY_DB_CACHE_PATH"
    [ "$(wc -l < "$TEST_TMPDIR/create.calls")" -eq 1 ]
}

@test "stale cache refresh serves the last complete snapshot without touching busy source" {
    create_memory_db_cache "$PROJECT_ROOT" "$TEST_TMPDIR/source.db"
    touch -d '2 minutes ago' "$SHOGUN_MEMORY_DB_CACHE_PATH"
    touch "$TEST_TMPDIR/source.db"
    refresh_memory_db_cache_async() {
        printf 'refresh\n' >> "$TEST_TMPDIR/refresh.calls"
    }

    read_path="$(prepare_memory_db_for_read "$PROJECT_ROOT" "$TEST_TMPDIR/source.db")"

    [ "$read_path" = "$SHOGUN_MEMORY_DB_CACHE_PATH" ]
    [ "$(wc -l < "$TEST_TMPDIR/refresh.calls")" -eq 1 ]
}

@test "stale cache command substitution returns before slow refresh child" {
    create_memory_db_cache "$PROJECT_ROOT" "$TEST_TMPDIR/source.db"
    touch -d '2 minutes ago' "$SHOGUN_MEMORY_DB_CACHE_PATH"
    touch "$TEST_TMPDIR/source.db"
    create_memory_db_cache() {
        sleep 2
    }

    local started elapsed_ms read_path
    started="$(date +%s%3N)"
    read_path="$(prepare_memory_db_for_read "$PROJECT_ROOT" "$TEST_TMPDIR/source.db")"
    elapsed_ms=$(( $(date +%s%3N) - started ))

    [ "$read_path" = "$SHOGUN_MEMORY_DB_CACHE_PATH" ]
    [ "$elapsed_ms" -lt 1000 ]
}

@test "ten concurrent stale readers never wait for refresh or select the source" {
    create_memory_db_cache "$PROJECT_ROOT" "$TEST_TMPDIR/source.db"
    touch -d '2 minutes ago' "$SHOGUN_MEMORY_DB_CACHE_PATH"
    touch "$TEST_TMPDIR/source.db"
    create_memory_db_cache() {
        sleep 2
    }
    export -f create_memory_db_cache

    local started elapsed_ms i
    started="$(date +%s%3N)"
    for i in $(seq 1 10); do
        (
            source "$PROJECT_ROOT/scripts/lib/memory_db_cache.sh"
            prepare_memory_db_for_read "$PROJECT_ROOT" "$TEST_TMPDIR/source.db"
        ) >"$TEST_TMPDIR/read.$i" &
    done
    wait
    elapsed_ms=$(( $(date +%s%3N) - started ))

    [ "$elapsed_ms" -lt 1500 ]
    for i in $(seq 1 10); do
        [ "$(cat "$TEST_TMPDIR/read.$i")" = "$SHOGUN_MEMORY_DB_CACHE_PATH" ]
    done
}

@test "restart_watchers flow creates a missing cache before touching watchers" {
    rm -f "$SHOGUN_MEMORY_DB_CACHE_PATH"

    run env \
        RESTART_WATCHERS_WARMUP_ONLY=1 \
        SHOGUN_MEMORY_DB_SOURCE_PATH="$TEST_TMPDIR/source.db" \
        SHOGUN_MEMORY_DB_CACHE_PATH="$SHOGUN_MEMORY_DB_CACHE_PATH" \
        bash "$PROJECT_ROOT/scripts/restart_watchers.sh"

    [ "$status" -eq 0 ]
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
