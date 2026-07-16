#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    GATE="$REPO_ROOT/scripts/gates/gate_memory_db_live_insert_async.sh"
    export TMPDIR="$BATS_TEST_TMPDIR/cache"
    mkdir -p "$TMPDIR"
}

@test "cache records expiry and replays the exact result" {
    run bash "$GATE"
    first_status="$status"
    first_output="$output"

    cache_file="$(find "$TMPDIR" -maxdepth 1 -name 'gate_memory_db_live_insert_async_*.cache' -print -quit)"
    [ -n "$cache_file" ]
    read -r _signature cached_rc cache_expires < "$cache_file"
    [[ "$cached_rc" =~ ^[01]$ ]]
    [[ "$cache_expires" =~ ^[0-9]+$ ]]

    run bash "$GATE"
    [ "$status" -eq "$first_status" ]
    [ "$output" = "$first_output" ]
}

@test "zero TTL bypasses replay and performs the full safety scan" {
    MEMORY_DB_LIVE_INSERT_GATE_CACHE_TTL=0 run bash "$GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: synchronous memory_db_live_insert.py calls are forbidden"* ]]
    [[ "$output" == *"scripts/memory_db_live_insert_async.py"* ]]
}

@test "clean fixture passes and its successful result is cached" {
    fixture="$BATS_TEST_TMPDIR/clean-repo"
    mkdir -p "$fixture/scripts/gates"
    cp "$GATE" "$fixture/scripts/gates/gate_memory_db_live_insert_async.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'printf safe' > "$fixture/scripts/harmless.sh"

    run bash "$fixture/scripts/gates/gate_memory_db_live_insert_async.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "OK: memory_db live inserts use async wrapper" ]

    run bash "$fixture/scripts/gates/gate_memory_db_live_insert_async.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "OK: memory_db live inserts use async wrapper" ]
}
