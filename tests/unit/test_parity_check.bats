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

    # shellcheck disable=SC2016
    run env PARITY_CHECK_LIB_ONLY=1 ENV_PATH="$env_file" bash -lc '
        source "$1"
        load_database_url "$2"
    ' _ "$SCRIPT_PATH" "$env_file"

    [ "$status" -eq 0 ]
    [ "$output" = "postgresql://example/db" ]
}

@test "portfolio names with spaces are passed to Python as one argument" {
    env_file="$TEST_TMPDIR/.env"
    sqlite_file="$TEST_TMPDIR/experiments.db"
    py_path="$TEST_TMPDIR/python"
    mkdir -p "$py_path"
    printf 'DATABASE_URL=postgresql://example/db\n' > "$env_file"
    : > "$sqlite_file"
    cat > "$py_path/psycopg2.py" <<'PY'
class Cursor:
    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def execute(self, query, params=None):
        return None

    def fetchall(self):
        return []


class Connection:
    def cursor(self):
        return Cursor()

    def close(self):
        return None


def connect(url):
    return Connection()
PY

    run env PYTHONPATH="$py_path" ENV_PATH="$env_file" EXPERIMENTS_DB="$sqlite_file" \
        bash "$SCRIPT_PATH" "PF Name With Spaces"

    [ "$status" -eq 1 ]
    [[ "$output" == *"WARN: 'PF Name With Spaces' に一致するPFなし"* ]]
    [[ "$output" != *"WARN: 'PF' に一致するPFなし"* ]]
}
