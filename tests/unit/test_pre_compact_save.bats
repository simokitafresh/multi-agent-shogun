#!/usr/bin/env bats
# Tests for scripts/hooks/pre_compact_save.sh

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PRE_COMPACT_SAVE_SCRIPT="$PROJECT_ROOT/scripts/hooks/pre_compact_save.sh"
    [ -f "$PRE_COMPACT_SAVE_SCRIPT" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/pre_compact_save.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/hooks" "$TEST_TMPDIR/queue/compact_state"
    ln -s "$PRE_COMPACT_SAVE_SCRIPT" "$TEST_TMPDIR/scripts/hooks/pre_compact_save.sh"

    export MOCK_BIN="$TEST_TMPDIR/mock_bin"
    mkdir -p "$MOCK_BIN"
    cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"display-message"* ]]; then
    printf '%s\t%s\n' "${MOCK_AGENT_ID:-testbot}" "${MOCK_TASK:-}"
    exit 0
fi
exit 0
EOF
    chmod +x "$MOCK_BIN/tmux"
    export PATH="$MOCK_BIN:$PATH"
    export TMUX_PANE="%0"
    unset TMUX
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "CSH-001: pre_compact_save creates compact_state YAML with trigger and session_id" {
    export MOCK_AGENT_ID="testagent"
    run bash "$TEST_TMPDIR/scripts/hooks/pre_compact_save.sh" \
        <<< '{"trigger":"auto","session_id":"sess-abc123"}'
    [ "$status" -eq 0 ]
    local state_file="$TEST_TMPDIR/queue/compact_state/testagent.yaml"
    [ -f "$state_file" ]
    grep -q 'compact_trigger: auto' "$state_file"
    grep -q 'session_id: sess-abc123' "$state_file"
    grep -q 'agent: testagent' "$state_file"
}

@test "CSH-002: pre_compact_save handles empty stdin gracefully" {
    export MOCK_AGENT_ID="testagent"
    run bash "$TEST_TMPDIR/scripts/hooks/pre_compact_save.sh" <<< ''
    [ "$status" -eq 0 ]
    local state_file="$TEST_TMPDIR/queue/compact_state/testagent.yaml"
    [ -f "$state_file" ]
    grep -q 'compact_trigger: manual' "$state_file"
}

@test "CSH-003: pre_compact_save sanitizes agent_id with special chars" {
    export MOCK_AGENT_ID="my!agent@name"
    run bash "$TEST_TMPDIR/scripts/hooks/pre_compact_save.sh" \
        <<< '{"trigger":"manual","session_id":""}'
    [ "$status" -eq 0 ]
    local state_file="$TEST_TMPDIR/queue/compact_state/myagentname.yaml"
    [ -f "$state_file" ]
}
