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
    [[ "$output" == *"tests/unit/test_gate_report_format_pass_no_improvement.bats"* ]]
    [[ "$output" == *"tests/unit/test_gate_small_consolidated.bats"* ]]
}

@test "test_select maps gate script changes to cmd_complete_gate tests" {
    run bash "$TEST_SELECT" scripts/gates/gate_context_freshness.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"tests/unit/test_gate_context_freshness.bats"* ]]
    [[ "$output" != *"tests/unit/test_cmd_complete_gate.bats"* ]]
}

@test "test_select maps p-average gate changes to focused tests only" {
    run bash "$TEST_SELECT" scripts/gates/gate_p_average_freshness.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"tests/unit/test_gate_p_average_freshness.bats"* ]]
    [[ "$output" != *"tests/unit/test_gate_shogun_startup.bats"* ]]
    [[ "$output" != *"tests/unit/test_cmd_complete_gate.bats"* ]]
}

@test "test_select warns but succeeds when no mapping exists" {
    run bash "$TEST_SELECT" README.md
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: no test mapping for 'README.md'"* ]]
    [[ "$output" == *"WARN: all changed files have no test mapping"* ]]
}

@test "test_select explicitly skips skill markdown files without warnings" {
    run bash "$TEST_SELECT" skills/dream/SKILL.md
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN"* ]]
    [[ "$output" != *"tests/unit/"* ]]
}

@test "test_select maps context markdown changes to context gate tests" {
    run bash "$TEST_SELECT" context/infrastructure.md
    [ "$status" -eq 0 ]
    [[ "$output" == *"tests/unit/test_context_freshness_check.bats"* ]]
    [[ "$output" == *"tests/unit/test_gate_context_freshness.bats"* ]]
    [[ "$output" == *"tests/unit/test_gate_vercel_phase.bats"* ]]
    [[ "$output" != *"WARN"* ]]
}

@test "test_select maps docs rule markdown changes without warnings" {
    run bash "$TEST_SELECT" docs/rule/bash-conventions.md
    [ "$status" -eq 0 ]
    [[ "$output" == *"tests/unit/test_semantic_index_update.bats"* ]]
    [[ "$output" == *"tests/unit/test_context_freshness_check.bats"* ]]
    [[ "$output" != *"WARN"* ]]
}

@test "test_select maps docs research markdown changes without warnings" {
    run bash "$TEST_SELECT" docs/research/gunshi_idle_silent_failure_audit_20260605.md
    [ "$status" -eq 0 ]
    [[ "$output" == *"tests/unit/test_semantic_index_update.bats"* ]]
    [[ "$output" == *"tests/unit/test_gate_vercel_phase.bats"* ]]
    [[ "$output" != *"WARN: no test mapping"* ]]
}

@test "test_select maps gunshi instruction changes without warnings" {
    run bash "$TEST_SELECT" instructions/gunshi.md
    [ "$status" -eq 0 ]
    [[ "$output" == *"tests/unit/test_cli_adapter.bats"* ]]
    [[ "$output" == *"tests/unit/test_gate_gunshi_cs_checklist.bats"* ]]
    [[ "$output" == *"tests/unit/test_semantic_index_update.bats"* ]]
    [[ "$output" != *"WARN"* ]]
}
