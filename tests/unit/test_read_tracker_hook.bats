#!/usr/bin/env bats
# test_read_tracker_hook.bats - unit tests for pre-write-read-tracker.sh hook

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/.claude/hooks/pre-write-read-tracker.sh"
    [ -f "$HOOK_SCRIPT" ] || return 1
}

setup() {
    export MOCK_AGENT_ID="test_read_tracker_$$"
    export LOG_FILE="/tmp/claude_read_log_${MOCK_AGENT_ID}.txt"
    rm -f "$LOG_FILE"
    # Create a temp file to simulate an existing file
    export EXISTING_FILE
    EXISTING_FILE="$(mktemp)"
    echo "existing content" > "$EXISTING_FILE"
}

teardown() {
    rm -f "$LOG_FILE" "$EXISTING_FILE"
}

# Helper: run hook with env-based tmux mock (avoids quoting issues with JSON)
_run_hook() {
    local payload="$1"
    local mock_id="${2:-$MOCK_AGENT_ID}"
    run env MOCK_AGENT_ID="$mock_id" HOOK_PAYLOAD="$payload" HOOK_SCRIPT="$HOOK_SCRIPT" bash -c '
        tmux() { echo "$MOCK_AGENT_ID"; }
        export -f tmux
        printf "%s" "$HOOK_PAYLOAD" | bash "$HOOK_SCRIPT"
    '
}

@test "Write to new file is not blocked (file does not exist)" {
    NEW_FILE="/tmp/test_read_tracker_nonexistent_$$_$(date +%s)"
    rm -f "$NEW_FILE"
    _run_hook '{"tool_name":"Write","tool_input":{"file_path":"'"$NEW_FILE"'"}}'
    [ "$status" -eq 0 ]
}

@test "Edit after Read is not blocked" {
    local payload_read='{"tool_name":"Read","tool_input":{"file_path":"'"$EXISTING_FILE"'"}}'
    local payload_edit='{"tool_name":"Edit","tool_input":{"file_path":"'"$EXISTING_FILE"'"}}'
    # Read first, then Edit — both must succeed
    run env MOCK_AGENT_ID="$MOCK_AGENT_ID" HOOK_SCRIPT="$HOOK_SCRIPT" \
        PAYLOAD_READ="$payload_read" PAYLOAD_EDIT="$payload_edit" bash -c '
        tmux() { echo "$MOCK_AGENT_ID"; }
        export -f tmux
        printf "%s" "$PAYLOAD_READ" | bash "$HOOK_SCRIPT"
        printf "%s" "$PAYLOAD_EDIT" | bash "$HOOK_SCRIPT"
    '
    [ "$status" -eq 0 ]
}

@test "Edit without Read is blocked for existing file" {
    _run_hook '{"tool_name":"Edit","tool_input":{"file_path":"'"$EXISTING_FILE"'"}}'
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "permissionDecision"
    echo "$output" | grep -q "deny"
}

@test "Write without Read is blocked for existing file" {
    _run_hook '{"tool_name":"Write","tool_input":{"file_path":"'"$EXISTING_FILE"'"}}'
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "deny"
}

@test "Read records file_path to log file" {
    _run_hook '{"tool_name":"Read","tool_input":{"file_path":"/some/test/file.txt"}}'
    [ "$status" -eq 0 ]
    [ -f "$LOG_FILE" ]
    grep -qFx "/some/test/file.txt" "$LOG_FILE"
}

@test "Empty payload exits cleanly" {
    run env MOCK_AGENT_ID="$MOCK_AGENT_ID" HOOK_SCRIPT="$HOOK_SCRIPT" bash -c '
        tmux() { echo "$MOCK_AGENT_ID"; }
        export -f tmux
        echo "" | bash "$HOOK_SCRIPT"
    '
    [ "$status" -eq 0 ]
}

@test "Agent ID fallback to unknown when tmux fails" {
    rm -f "/tmp/claude_read_log_unknown.txt"
    run env HOOK_SCRIPT="$HOOK_SCRIPT" \
        HOOK_PAYLOAD='{"tool_name":"Read","tool_input":{"file_path":"/tmp/test_fallback.txt"}}' bash -c '
        unset TMUX_PANE
        tmux() { return 1; }
        export -f tmux
        printf "%s" "$HOOK_PAYLOAD" | bash "$HOOK_SCRIPT"
    '
    [ "$status" -eq 0 ]
    [ -f "/tmp/claude_read_log_unknown.txt" ]
    grep -qFx "/tmp/test_fallback.txt" "/tmp/claude_read_log_unknown.txt"
    rm -f "/tmp/claude_read_log_unknown.txt"
}
