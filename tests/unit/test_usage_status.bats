#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_DIR
    TEST_DIR="$(mktemp -d "$BATS_TMPDIR/usage_status.XXXXXX")"
    cp "$PROJECT_ROOT/scripts/usage_status.sh" "$TEST_DIR/usage_status.sh"
    chmod +x "$TEST_DIR/usage_status.sh"
    export MCAS_STATUS_INTERVAL=0
    export MCAS_CACHE_DIR="$TEST_DIR"
    rm -f "$TEST_DIR/mcas_usage_status_cache_claude" "$TEST_DIR/mcas_usage_status_cache_codex"
}

teardown() {
    rm -rf "$TEST_DIR"
}

write_monitor() {
    local body="$1"
    cat > "$TEST_DIR/usage_monitor.sh" <<EOF
#!/usr/bin/env bash
$body
EOF
    chmod +x "$TEST_DIR/usage_monitor.sh"
}

@test "malformed non-empty status does not overwrite valid cache" {
    echo "5H:██░░░ 40% 10am 7D:█░░░░ 20% Fri" > $TEST_DIR/mcas_usage_status_cache_claude
    write_monitor 'printf "oops\n"'

    run bash "$TEST_DIR/usage_status.sh" claude

    [ "$status" -eq 0 ]
    [ "$output" = "5H:██░░░ 40% 10am 7D:█░░░░ 20% Fri" ]
    [ "$(cat $TEST_DIR/mcas_usage_status_cache_claude)" = "5H:██░░░ 40% 10am 7D:█░░░░ 20% Fri" ]
}

@test "malformed status without cache returns provider-specific fallback" {
    write_monitor 'printf "12\tsoon\tbad\n"'

    run bash "$TEST_DIR/usage_status.sh" codex

    [ "$status" -eq 0 ]
    [ "$output" = "5H:----- --% left -- 7D:----- --% left --" ]
    [ ! -f $TEST_DIR/mcas_usage_status_cache_codex ]
}

@test "valid status writes formatted cache" {
    write_monitor 'printf "12\t10am\t34\tFri\n"'

    run bash "$TEST_DIR/usage_status.sh" claude

    [ "$status" -eq 0 ]
    [[ "$output" == "5H:"*" 12% 10am 7D:"*" 34% Fri" ]]
    [ "$(cat $TEST_DIR/mcas_usage_status_cache_claude)" = "$output" ]
}
