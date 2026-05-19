#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export API_USAGE_SCRIPT="$PROJECT_ROOT/scripts/api_usage.sh"
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

@test "openai output reuses shared codex status for remaining budgets" {
    mkdir -p "$TEST_DIR/bin" "$TEST_DIR/home/.codex"
    touch "$TEST_DIR/home/.codex/state_5.sqlite"
    cat > "$TEST_DIR/bin/sqlite3" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
state="${TEST_DIR:?}/sqlite3_calls"
call=0
if [ -f "$state" ]; then
    call="$(cat "$state")"
fi
call=$((call + 1))
printf "%s" "$call" > "$state"
case "$call" in
    1|3) echo 70 ;;
    5) echo 120 ;;
    2|4) echo 2 ;;
    6) echo 3 ;;
    7) echo 1 ;;
    *) echo 0 ;;
esac
SH
    chmod +x "$TEST_DIR/bin/sqlite3"

    run env \
        PATH="$TEST_DIR/bin:$PATH" \
        HOME="$TEST_DIR/home" \
        TEST_DIR="$TEST_DIR" \
        CODEX_BUDGET_5H=100 \
        CODEX_BUDGET_7D=200 \
        bash "$API_USAGE_SCRIPT" openai

    [ "$status" -eq 0 ]
    [[ "$output" == *"| 5時間 | 70 | 2 |"* ]]
    [[ "$output" == *"| 24時間 | 70 | 2 |"* ]]
    [[ "$output" == *"| 7日間 | 120 | 3 |"* ]]
    [[ "$output" == *"- **5時間残量**: "* ]]
    [[ "$output" == *"- **7日間残量**: "* ]]
    [[ "$output" == *"- **アクティブセッション** (30分内): 1"* ]]
    [[ "$output" == *"Codex CLI ローカルDB + usage_monitor.sh"* ]]
}

@test "openai output explains sqlite3 preflight failure" {
    local safe_bin
    safe_bin="$(mktemp -d "$BATS_TMPDIR/nobin.XXXXXX")"
    ln -s "$(command -v bash)" "$safe_bin/bash"
    ln -s "$(command -v env)" "$safe_bin/env" 2>/dev/null || true
    for cmd in date awk cat; do
        local cmd_path
        cmd_path="$(command -v "$cmd" 2>/dev/null)" || true
        [ -n "$cmd_path" ] && ln -s "$cmd_path" "$safe_bin/$cmd" 2>/dev/null || true
    done

    run env \
        PATH="$safe_bin" \
        HOME="$TEST_DIR" \
        bash "$API_USAGE_SCRIPT" openai

    rm -rf "$safe_bin"

    [ "$status" -eq 0 ]
    [[ "$output" == *"# OpenAI (Codex) Usage"* ]]
    [[ "$output" == *"sqlite3"* ]]
}
