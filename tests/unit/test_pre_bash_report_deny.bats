#!/usr/bin/env bats
# test_pre_bash_report_deny.bats - unit tests for pre-bash-report-deny.sh hook
# Verifies: Bash redirect/tee/python3 to queue/reports/*.yaml is DENIED

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/scripts/hooks/pre-bash-report-deny.sh"
    [ -f "$HOOK_SCRIPT" ] || return 1
}

_run_hook() {
    local payload="$1"
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK_SCRIPT"
}

# --- DENY cases ---

@test "Bash redirect > to report YAML is DENIED" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"echo test > queue/reports/hanzo_report_cmd_100.yaml"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
    [[ "$output" == *"report_field_set.sh"* ]]
}

@test "Bash redirect >> to report YAML is DENIED" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"echo test >> queue/reports/saizo_report_cmd_200.yaml"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "Bash tee to report YAML is DENIED" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"echo test | tee queue/reports/kotaro_report_cmd_300.yaml"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "Bash python3 open() to report YAML is DENIED" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"open(\\\"queue/reports/hanzo_report_cmd_100.yaml\\\",\\\"w\\\")\""}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

# --- ALLOW cases ---

@test "report_field_set.sh is allowed" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"bash scripts/report_field_set.sh queue/reports/hanzo_report_cmd_100.yaml result.summary done"}}'
    [ "$status" -eq 0 ]
}

@test "Non-Bash tool is allowed" {
    _run_hook '{"tool_name":"Edit","tool_input":{"file_path":"queue/reports/hanzo_report_cmd_100.yaml"}}'
    [ "$status" -eq 0 ]
}

@test "Bash command to non-report file is allowed" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"echo test > /tmp/test.yaml"}}'
    [ "$status" -eq 0 ]
}

@test "Empty payload is allowed (no crash)" {
    _run_hook ''
    [ "$status" -eq 0 ]
}

@test "Empty command is allowed" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":""}}'
    [ "$status" -eq 0 ]
}
