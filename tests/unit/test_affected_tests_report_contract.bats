#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export AFFECTED="$PROJECT_ROOT/scripts/affected_tests.sh"
}

assert_focused_report_contract_tests_selected() {
    local changed="$1" actual expected
    actual="$(bash "$AFFECTED" "$changed")"
    expected="$(bash "$PROJECT_ROOT/scripts/lib/report_contract_test_selector.sh" "$changed")"
    [ -n "$actual" ]
    [ "$actual" = "$expected" ]
}

@test "gate_report_format_main contract change selects focused 8-file suite" {
    assert_focused_report_contract_tests_selected scripts/gates/gate_report_format_main.py
    [ "$(bash "$AFFECTED" scripts/gates/gate_report_format_main.py | wc -l)" -eq 8 ]
}

@test "gate_report_format_combined contract change selects focused 8-file suite" {
    assert_focused_report_contract_tests_selected scripts/gates/gate_report_format_combined.py
    [ "$(bash "$AFFECTED" scripts/gates/gate_report_format_combined.py | wc -l)" -eq 8 ]
}

@test "report template producer change retains deploy-specific tests" {
    local actual
    actual="$(bash "$AFFECTED" scripts/deploy_task.sh)"
    [[ "$actual" == *"tests/unit/test_deploy_task.bats"* ]]
    [[ "$actual" == *"tests/unit/test_report_template_gate_compat.bats"* ]]
}
