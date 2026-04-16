#!/usr/bin/env bats
# test_gate_recalculate_completeness.bats — gate_recalculate_completeness.sh unit tests

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_recalculate_completeness.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_recalculate_completeness.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/bin"

    cp "$SRC_GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_recalculate_completeness.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_recalculate_completeness.sh"

    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_recalculate_completeness.sh"
    export TEST_CACHE="$TEST_TMPDIR/hostaddr.cache"
    export ORIG_PATH="$PATH"
    export PATH="$TEST_TMPDIR/bin:$PATH"
}

teardown() {
    export PATH="$ORIG_PATH"
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "load_database_url strips trailing CR from CRLF env files" {
    printf 'DATABASE_URL=postgres://user:pass@example.com/db\r\nOTHER_KEY=value\r\n' > "$TEST_TMPDIR/backend.env"

    run bash -lc "source \"$TEST_GATE\"; load_database_url \"$TEST_TMPDIR/backend.env\""

    [ "$status" -eq 0 ]
    [ "$output" = "postgres://user:pass@example.com/db" ]
}

@test "extract_db_host parses hostname and strips userinfo plus port" {
    run bash -lc "source \"$TEST_GATE\"; extract_db_host 'postgres://user:pass@db.example.com:5432/app?sslmode=require'"

    [ "$status" -eq 0 ]
    [ "$output" = "db.example.com" ]
}

@test "extract_db_host supports bracketed IPv6 hosts" {
    run bash -lc "source \"$TEST_GATE\"; extract_db_host 'postgres://user:pass@[2001:db8::10]:5432/app'"

    [ "$status" -eq 0 ]
    [ "$output" = "2001:db8::10" ]
}

@test "resolve_hostaddr uses fresh cache without calling getent" {
    cat > "$TEST_TMPDIR/bin/getent" <<'EOF'
#!/usr/bin/env bash
echo called >> "__CALLS__"
printf '203.0.113.10 STREAM db.example.com\n'
EOF
    sed -i "s|__CALLS__|$TEST_TMPDIR/getent_calls.log|g" "$TEST_TMPDIR/bin/getent"
    chmod +x "$TEST_TMPDIR/bin/getent"

    printf 'db.example.com|203.0.113.7|%s\n' "$(date +%s)" > "$TEST_CACHE"

    run bash -lc "source \"$TEST_GATE\"; resolve_hostaddr 'postgres://user:pass@db.example.com/app' \"$TEST_CACHE\" 3600"

    [ "$status" -eq 0 ]
    [ "$output" = "203.0.113.7" ]
    [ ! -f "$TEST_TMPDIR/getent_calls.log" ]
}

@test "resolve_hostaddr picks first STREAM address from getent and writes cache" {
    cat > "$TEST_TMPDIR/bin/getent" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
198.51.100.21 DGRAM db.example.com
198.51.100.11 STREAM db.example.com
198.51.100.12 STREAM db.example.com
OUT
EOF
    chmod +x "$TEST_TMPDIR/bin/getent"

    run bash -lc "source \"$TEST_GATE\"; resolve_hostaddr 'postgres://user:pass@db.example.com/app' \"$TEST_CACHE\" 3600"

    [ "$status" -eq 0 ]
    [ "$output" = "198.51.100.11" ]
    grep -q '^db.example.com|198.51.100.11|' "$TEST_CACHE"
}
