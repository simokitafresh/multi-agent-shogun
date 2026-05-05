#!/usr/bin/env bats
# test_test_select.bats — scripts/test_select.sh focused regression tests

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_SELECT="$PROJECT_ROOT/scripts/test_select.sh"
    [ -f "$TEST_SELECT" ] || return 1
}

@test "test_select maps script changes to directly related tests" {
    run bash "$TEST_SELECT" scripts/test_select.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"tests/unit/test_test_select.bats"* ]]
}

@test "test_select maps gate script changes to gate tests" {
    run bash "$TEST_SELECT" scripts/gates/gate_report_format.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"tests/unit/test_gate_report_format_learning.bats"* ]]
    [[ "$output" == *"tests/unit/test_gate_report_format_pass_no_improvement.bats"* ]]
}

@test "test_select warns but succeeds when no mapping exists" {
    run bash "$TEST_SELECT" README.md
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: no test mapping for 'README.md'"* ]]
    [[ "$output" == *"WARN: all changed files have no test mapping"* ]]
}
