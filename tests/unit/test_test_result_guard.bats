#!/usr/bin/env bats
# test_test_result_guard.bats - PostToolUse Bash test-result guard

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/scripts/hooks/test_result_guard.sh"

    [ -f "$HOOK_SCRIPT" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

run_hook() {
    local payload="$1"
    run bash "$HOOK_SCRIPT" <<<"$payload"
}

assert_context_contains() {
    local expected="$1"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    context="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$context" == *"$expected"* ]]
}

@test "ignores non-Bash tools" {
    run_hook '{"tool_name":"Edit","tool_input":{"command":"pytest -q"},"tool_result":"1 failed"}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ignores non-test Bash commands" {
    local payload
    payload="$(jq -cn --arg cmd "git status" --arg result "1 failed, 2 skipped" '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:$result}')"
    run_hook "$payload"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "pytest skip emits SKIP guidance" {
    local payload
    payload="$(jq -cn --arg cmd "pytest -q" --arg result "================ 2 skipped, 8 passed in 0.10s ================" '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:$result}')"
    run_hook "$payload"
    assert_context_contains "ERROR: 2 test(s) SKIPPED"
}

@test "pytest failure emits FAIL guidance" {
    local payload
    payload="$(jq -cn --arg cmd "pytest -q" --arg result "================ 1 failed, 7 passed in 0.10s ================" '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:$result}')"
    run_hook "$payload"
    assert_context_contains "ERROR: 1 test(s) FAILED"
}

@test "bats fallback counts not ok lines" {
    local payload
    payload="$(jq -cn --arg cmd "bats tests/unit/test_example.bats" --arg result $'1..2\nok 1 first test\nnot ok 2 second test' '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:$result}')"
    run_hook "$payload"
    assert_context_contains "ERROR: 1 test(s) FAILED"
}

@test "npm test command detects jest skips from nested toolUseResult" {
    local payload
    payload="$(jq -cn --arg cmd "npm test -- --runInBand" '{tool_name:"Bash", tool_input:{command:$cmd}, toolUseResult:{stdout:"Test Suites: 1 skipped, 2 passed, 3 total"}}')"
    run_hook "$payload"
    assert_context_contains "ERROR: 1 test(s) SKIPPED"
}

@test "skip and fail can both be emitted" {
    local payload
    payload="$(jq -cn --arg cmd "pytest -q" --arg result "================ 1 failed, 2 skipped, 4 passed in 0.10s ================" '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:$result}')"
    run_hook "$payload"
    assert_context_contains "ERROR: 2 test(s) SKIPPED"
    assert_context_contains "ERROR: 1 test(s) FAILED"
}

@test "bats TAP line with skip in test name does not false-positive SKIP" {
    # BUG-H3-001: "ok 293 skip and fail can both be emitted" was misread as 293 skips
    local payload
    local tap_output
    tap_output=$'1..5\nok 1 first test\nok 2 second test\nok 3 skip and fail can both be emitted\nok 4 fourth test\nok 5 fifth test'
    payload="$(jq -cn --arg cmd "bats tests/unit/test_example.bats" --arg result "$tap_output" '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:$result}')"
    run_hook "$payload"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "bats TAP line with actual skip-directive annotation is correctly detected" {
    local payload
    local tap_output
    tap_output=$'1..3\nok 1 first test\nok 2 second test # skip reason here\nok 3 third test'
    payload="$(jq -cn --arg cmd "bats tests/unit/test_example.bats" --arg result "$tap_output" '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:$result}')"
    run_hook "$payload"
    assert_context_contains "ERROR: 1 test(s) SKIPPED"
}

@test "all-pass output stays silent" {
    local payload
    payload="$(jq -cn --arg cmd "pytest -q" --arg result "================ 8 passed in 0.10s ================" '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:$result}')"
    run_hook "$payload"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
