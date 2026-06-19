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

@test "blocks Codex Stop hook" {
    cat > "$TEST_ROOT/hooks.json" <<'JSON'
{"hooks":{"PreToolUse":[],"PostToolUse":[],"Stop":[]}}
JSON

    run bash "$GATE" "$TEST_ROOT/hooks.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"forbidden event(s): Stop"* ]]
}

@test "blocks Codex UserPromptSubmit hook" {
    cat > "$TEST_ROOT/hooks.json" <<'JSON'
{"hooks":{"PreToolUse":[],"PostToolUse":[],"UserPromptSubmit":[]}}
JSON

    run bash "$GATE" "$TEST_ROOT/hooks.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"forbidden event(s): UserPromptSubmit"* ]]
}
