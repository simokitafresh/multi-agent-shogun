#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_mcp_access.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_mcp_access.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/bin" "$TEST_TMPDIR/cache"
    cp "$SRC_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_mcp_access.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_mcp_access.sh"
    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_mcp_access.sh"
    export GATE_MCP_ACCESS_CACHE_DIR="$TEST_TMPDIR/cache"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

write_tmux_mock() {
    local agent_id="$1"
    cat > "$TEST_TMPDIR/bin/tmux" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$agent_id'
printf 'called\n' >> "\$TEST_TMPDIR/tmux_calls.log"
EOF
    chmod +x "$TEST_TMPDIR/bin/tmux"
}

@test "shogun is allowed after tmux verification" {
    write_tmux_mock "shogun"

    run env PATH="$TEST_TMPDIR/bin:$PATH" TMUX_PANE="%1" bash "$TEST_GATE"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(wc -l < "$TEST_TMPDIR/tmux_calls.log")" -eq 1 ]
}

@test "non-shogun is denied and cached for subsequent calls" {
    write_tmux_mock "hayate"

    run env PATH="$TEST_TMPDIR/bin:$PATH" TMUX_PANE="%2" bash "$TEST_GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"agent_id=hayate"* ]]
    [ "$(wc -l < "$TEST_TMPDIR/tmux_calls.log")" -eq 1 ]

    rm -f "$TEST_TMPDIR/bin/tmux"
    run env PATH="$TEST_TMPDIR/bin:$PATH" TMUX_PANE="%2" bash "$TEST_GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"agent_id=hayate"* ]]
    [ "$(wc -l < "$TEST_TMPDIR/tmux_calls.log")" -eq 1 ]
}

@test "cached shogun value is not trusted for allow decision" {
    mkdir -p "$GATE_MCP_ACCESS_CACHE_DIR"
    printf 'shogun\n' > "$GATE_MCP_ACCESS_CACHE_DIR/_3.agent_id"
    write_tmux_mock "hayate"

    run env PATH="$TEST_TMPDIR/bin:$PATH" TMUX_PANE="%3" bash "$TEST_GATE"

    [ "$status" -eq 2 ]
    [[ "$output" == *"agent_id=hayate"* ]]
    [ "$(wc -l < "$TEST_TMPDIR/tmux_calls.log")" -eq 1 ]
}

@test "non-tmux environment is denied without cache dependency" {
    run env -u TMUX_PANE -u TMUX GATE_MCP_ACCESS_CACHE_DIR="$GATE_MCP_ACCESS_CACHE_DIR" bash "$TEST_GATE"

    [ "$status" -eq 2 ]
    [[ "$output" == *"agent_id未取得/非tmux環境"* ]]
}
