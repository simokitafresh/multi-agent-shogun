#!/usr/bin/env bats
# test_necessity: Test-result hooks must classify terminal runner summaries, never numbered source listings that merely contain parser variable names.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CANONICAL="$ROOT/scripts/hooks/test_result_guard.sh"
    COMBINED="$ROOT/.claude/hooks/post-bash-combined.sh"
}

run_guard() {
    local hook="$1" fixture_output="$2"
    local payload
    payload="$(python3 - "$fixture_output" <<'PY'
import json, sys
print(json.dumps({
    "tool_name": "Bash",
    "tool_input": {"command": "pytest -q tests/unit/test_run_tests.py"},
    "tool_result": {"exit_code": 0, "stdout": sys.argv[1]},
}))
PY
)"
    run bash -c 'printf "%s" "$1" | HOOK_PAYLOAD="$1" bash "$2"' _ "$payload" "$hook"
}

@test "numbered source line containing failed variables is not a test failure" {
    fixture="801        failed, skipped, passed, total=(int(value or 0) for value in groups())"$'\n'". 1 passed in 0.10s"
    run_guard "$CANONICAL" "$fixture"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run_guard "$COMBINED" "$fixture"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Jest terminal failure summary remains blocked with the exact count" {
    fixture="Test Suites: 1 failed, 20 passed, 21 total"$'\n'"Tests: 3 failed, 123 passed, 126 total"
    run_guard "$CANONICAL" "$fixture"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERROR: 3 test(s) FAILED"* ]]
    run_guard "$COMBINED" "$fixture"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERROR: 3 test(s) FAILED"* ]]
}
