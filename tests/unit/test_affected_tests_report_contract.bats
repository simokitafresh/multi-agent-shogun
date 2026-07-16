#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export AFFECTED="$PROJECT_ROOT/scripts/affected_tests.sh"
}

assert_all_report_contract_fixtures_selected() {
    local changed="$1" actual expected path
    actual="$(bash "$AFFECTED" "$changed")"
    expected="$(grep -rl 'gate_report_format' "$PROJECT_ROOT/tests/unit"/test_*.bats | sort)"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        [[ "$actual" == *"$path"* ]] || {
            echo "missing affected test for $changed: $path" >&2
            return 1
        }
    done <<< "$expected"
}

@test "gate_report_format_main contract change selects every report-gate fixture" {
    assert_all_report_contract_fixtures_selected scripts/gates/gate_report_format_main.py
}

@test "report template producer change selects every report-gate fixture" {
    assert_all_report_contract_fixtures_selected scripts/deploy_task.sh
}
