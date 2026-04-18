#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPT_PATH="$PROJECT_ROOT/scripts/statusline.sh"
    [ -f "$SCRIPT_PATH" ] || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/statusline.XXXXXX")"
    export MOCK_BIN="$TEST_TMPDIR/mock_bin"
    mkdir -p "$MOCK_BIN"
    cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${TMUX_LOG:?}"
exit 0
EOF
    chmod +x "$MOCK_BIN/tmux"
    export TMUX_LOG="$TEST_TMPDIR/tmux.log"
    export PATH="$MOCK_BIN:$PATH"
    export TMUX_PANE="%0"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "SL-001: valid percentage is rendered and sent to tmux" {
    run bash -c "printf '%s' '{\"context_window\":{\"used_percentage\":33.7}}' | '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    [ "$output" = "CTX:33%" ]
    run cat "$TMUX_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"@context_pct 33%"* ]]
    [[ "$output" == *"@last_active"* ]]
}

@test "SL-002: invalid json falls back to zero" {
    run bash -c "printf '%s' 'not-json' | '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    [ "$output" = "CTX:0%" ]
}

@test "SL-003: negative percentage is clamped to zero" {
    run bash -c "printf '%s' '{\"context_window\":{\"used_percentage\":-7}}' | '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    [ "$output" = "CTX:0%" ]
}
