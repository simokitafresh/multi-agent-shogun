#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SCRIPT_PATH="$PROJECT_ROOT/scripts/parity_check.sh"
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/parity_check.XXXXXX")"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "--help returns usage without touching missing default paths" {
    run env DM_SIGNAL_PATH="$TEST_TMPDIR/missing" ENV_PATH="$TEST_TMPDIR/missing/.env" EXPERIMENTS_DB="$TEST_TMPDIR/missing.db" \
        bash "$SCRIPT_PATH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: bash scripts/parity_check.sh"* ]]
    [[ "$output" == *"--all"* ]]
}

@test "no args returns usage with exit 1" {
    run bash "$SCRIPT_PATH"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: bash scripts/parity_check.sh"* ]]
}

@test "load_database_url strips CRLF from .env" {
    env_file="$TEST_TMPDIR/.env"
    printf 'DATABASE_URL=postgresql://example/db\r\n' > "$env_file"

    run env PARITY_CHECK_LIB_ONLY=1 ENV_PATH="$env_file" bash -lc '
        source "$1"
        load_database_url "$2"
    ' _ "$SCRIPT_PATH" "$env_file"

    [ "$status" -eq 0 ]
    [ "$output" = "postgresql://example/db" ]
}
