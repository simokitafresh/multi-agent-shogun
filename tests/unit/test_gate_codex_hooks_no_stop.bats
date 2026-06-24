#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export GATE="$PROJECT_ROOT/scripts/gates/gate_codex_hooks_no_stop.sh"
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/gate_codex_hooks.XXXXXX")"
}

teardown() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

@test "passes PreToolUse and PostToolUse only" {
    cat > "$TEST_ROOT/hooks.json" <<'JSON'
{"hooks":{"PreToolUse":[],"PostToolUse":[]}}
JSON

    run bash "$GATE" "$TEST_ROOT/hooks.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "allows Codex UserPromptSubmit via one sequential adapter" {
    cat > "$TEST_ROOT/hooks.json" <<'JSON'
{"hooks":{"PreToolUse":[],"PostToolUse":[],"UserPromptSubmit":[{"hooks":[{"type":"command","command":"bash /repo/scripts/hooks/codex_user_prompt_submit.sh"}]}]}}
JSON

    run bash "$GATE" "$TEST_ROOT/hooks.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "blocks Codex UserPromptSubmit when split into concurrent Claude-style hooks" {
    cat > "$TEST_ROOT/hooks.json" <<'JSON'
{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"bash scripts/log_terminal_input.sh"},{"type":"command","command":"bash scripts/hooks/prompt_state_inject.sh"}]}]}}
JSON

    run bash "$GATE" "$TEST_ROOT/hooks.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"sequential adapter"* ]]
}

@test "blocks Codex Stop hook" {
    cat > "$TEST_ROOT/hooks.json" <<'JSON'
{"hooks":{"PreToolUse":[],"PostToolUse":[],"Stop":[]}}
JSON

    run bash "$GATE" "$TEST_ROOT/hooks.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"forbidden event(s): Stop"* ]]
}

@test "blocks Codex SessionStart without adapter" {
    cat > "$TEST_ROOT/hooks.json" <<'JSON'
{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash scripts/hooks/session_start_inject.sh"}]}]}}
JSON

    run bash "$GATE" "$TEST_ROOT/hooks.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"codex_session_start.sh adapter"* ]]
}
