#!/usr/bin/env bats
# test_bash_state_hook.bats - Bash hook tmux state updates

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/bash_state_hook.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/bin"
    export TMUX_LOG="$TEST_TMPDIR/tmux.log"
    cat > "$TEST_TMPDIR/bin/tmux" <<'EOF'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$TMUX_LOG"
EOF
    chmod +x "$TEST_TMPDIR/bin/tmux"
    export PATH="$TEST_TMPDIR/bin:$PATH"
    export TMUX_PANE="%42"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "PreToolUse updates agent_state and bash_running_since with one tmux invocation" {
    run bash -c 'printf "%s" "{\"hook_event_name\":\"PreToolUse\"}" | "$1"' _ "$PROJECT_ROOT/scripts/hooks/bash_state_hook.sh"

    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TMUX_LOG" | tr -d ' ')" -eq 1 ]
    grep -q '@agent_state bash_running' "$TMUX_LOG"
    grep -q '@bash_running_since' "$TMUX_LOG"
}

@test "PostToolUse restores agent_state and clears bash_running_since with one tmux invocation" {
    run bash -c 'printf "%s" "{\"hook_event_name\":\"PostToolUse\"}" | "$1"' _ "$PROJECT_ROOT/scripts/hooks/bash_state_hook.sh"

    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TMUX_LOG" | tr -d ' ')" -eq 1 ]
    grep -q '@agent_state active' "$TMUX_LOG"
    grep -q '@bash_running_since' "$TMUX_LOG"
}
