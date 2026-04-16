#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SCRIPT_PATH="$PROJECT_ROOT/scripts/post_recalculate_checks.sh"
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/post_recalculate_checks.XXXXXX")"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "missing env file fails before DB access" {
    run env ENV_PATH="$TEST_TMPDIR/missing/.env" \
        DM_SIGNAL_PATH="$TEST_TMPDIR/missing" \
        bash "$SCRIPT_PATH"

    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL: backend/.env not found at"* ]]
}

@test "load_database_url strips CRLF from .env" {
    env_file="$TEST_TMPDIR/.env"
    printf 'DATABASE_URL=postgresql://example/db\r\n' > "$env_file"

    run env POST_RECALCULATE_CHECKS_LIB_ONLY=1 bash -lc '
        source "$1"
        load_database_url "$2"
    ' _ "$SCRIPT_PATH" "$env_file"

    [ "$status" -eq 0 ]
    [ "$output" = "postgresql://example/db" ]
}

@test "resolve_database_url strips CR from inherited env var" {
    run env POST_RECALCULATE_CHECKS_LIB_ONLY=1 DATABASE_URL=$'postgresql://example/db\r' bash -lc '
        source "$1"
        resolve_database_url
    ' _ "$SCRIPT_PATH"

    [ "$status" -eq 0 ]
    [ "$output" = "postgresql://example/db" ]
}
