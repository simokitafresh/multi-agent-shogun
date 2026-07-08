#!/usr/bin/env bats
# test_pre_bash_codd_greenfield_guard.bats - Guard 15: CoDD greenfield generate before extract BLOCK (LS036 L4, cmd_2891)

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/.claude/hooks/pre-bash-combined.sh"
    [ -f "$HOOK_SCRIPT" ] || return 1
}

setup() {
    TEST_DIR="$(mktemp -d)"
    mkdir -p "$TEST_DIR/existing_code" "$TEST_DIR/empty_project"
    echo "def foo(): pass" > "$TEST_DIR/existing_code/main.py"
}

teardown() {
    rm -rf "$TEST_DIR"
}

_run_hook() {
    local payload="$1"
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK_SCRIPT"
}

# --- DENY cases ---

@test "codd generate --wave on path with existing code and no prior extract is BLOCKED" {
    _run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"codd generate --wave 1 --path ${TEST_DIR}/existing_code\"}}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
    [[ "$output" == *"LS036"* ]]
    [[ "$output" == *"codd extract"* ]]
}

@test "codd generate --wave 2 (later wave, still no extract) is BLOCKED" {
    _run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"codd generate --wave 2 --path ${TEST_DIR}/existing_code\"}}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

# --- ALLOW cases ---

@test "codd generate --wave on empty/new project is ALLOWED (no existing code to extract)" {
    _run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"codd generate --wave 1 --path ${TEST_DIR}/empty_project\"}}"
    [ "$status" -eq 0 ]
}

@test "codd generate --wave is ALLOWED once codd extract already ran (.codd/extract exists)" {
    mkdir -p "${TEST_DIR}/existing_code/.codd/extract"
    _run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"codd generate --wave 1 --path ${TEST_DIR}/existing_code\"}}"
    [ "$status" -eq 0 ]
}

@test "codd extract itself is ALLOWED (not a generate --wave call)" {
    _run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"codd extract --path ${TEST_DIR}/existing_code --source-dirs src\"}}"
    [ "$status" -eq 0 ]
}

@test "codd require (brownfield-only per --help) is not touched by this guard" {
    _run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"codd require --path ${TEST_DIR}/existing_code\"}}"
    [ "$status" -eq 0 ]
}

@test "codd generate --help (no --wave) is ALLOWED" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"codd generate --help"}}'
    [ "$status" -eq 0 ]
}

@test "message merely mentioning codd generate --wave in text is ALLOWED" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"echo note: codd generate --wave was blocked earlier"}}'
    [ "$status" -eq 0 ]
}

@test "non-Bash tool payload is ALLOWED" {
    _run_hook '{"tool_name":"Read","tool_input":{"file_path":"foo.py"}}'
    [ "$status" -eq 0 ]
}
