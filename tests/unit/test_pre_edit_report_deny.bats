#!/usr/bin/env bats
# test_pre_edit_report_deny.bats - unit tests for pre-edit-report-deny.sh hook
# Verifies: Edit/Write to queue/reports/*.yaml is DENIED (report_field_set.sh enforced)

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/.claude/hooks/pre-edit-report-deny.sh"
    [ -f "$HOOK_SCRIPT" ] || return 1
}

# Helper: run the hook with a JSON payload on stdin
_run_hook() {
    local payload="$1"
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK_SCRIPT"
}

# --- DENY cases ---

@test "Edit to queue/reports/hanzo_report_cmd_100.yaml is DENIED" {
    _run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/mnt/c/tools/multi-agent-shogun/queue/reports/hanzo_report_cmd_100.yaml"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"permissionDecision"*"deny"* ]]
    [[ "$output" == *"report_field_set.sh"* ]]
}

@test "Write to queue/reports/saizo_report_cmd_1536.yaml is DENIED" {
    _run_hook '{"tool_name":"Write","tool_input":{"file_path":"/mnt/c/tools/multi-agent-shogun/queue/reports/saizo_report_cmd_1536.yaml"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"permissionDecision"*"deny"* ]]
    [[ "$output" == *"report_field_set.sh"* ]]
}

@test "Edit to report YAML with relative path is DENIED" {
    _run_hook '{"tool_name":"Edit","tool_input":{"file_path":"queue/reports/kotaro_report_cmd_200.yaml"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

# --- DENY message includes command examples (AC2) ---

@test "DENY message includes report_field_set.sh usage examples" {
    _run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/mnt/c/tools/multi-agent-shogun/queue/reports/hanzo_report_cmd_100.yaml"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"report_field_set.sh"* ]]
    [[ "$output" == *"result.summary"* ]]
    [[ "$output" == *"binary_checks"* ]]
    [[ "$output" == *"verdict"* ]]
}

# --- ALLOW cases ---

@test "Edit to non-report YAML is allowed" {
    _run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/mnt/c/tools/multi-agent-shogun/queue/tasks/saizo.yaml"}}'
    [ "$status" -eq 0 ]
}

@test "Edit to file outside queue/reports/ is allowed" {
    _run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/mnt/c/tools/multi-agent-shogun/context/infrastructure.md"}}'
    [ "$status" -eq 0 ]
}

@test "Bash tool is not matched (report_field_set.sh uses Bash)" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"bash scripts/report_field_set.sh queue/reports/hanzo_report_cmd_100.yaml result.summary test"}}'
    [ "$status" -eq 0 ]
}

@test "Read tool on report YAML is allowed" {
    _run_hook '{"tool_name":"Read","tool_input":{"file_path":"/mnt/c/tools/multi-agent-shogun/queue/reports/hanzo_report_cmd_100.yaml"}}'
    [ "$status" -eq 0 ]
}

@test "Empty payload is allowed (no crash)" {
    _run_hook ''
    [ "$status" -eq 0 ]
}

@test "Whitespace-only payload is allowed (no crash)" {
    _run_hook '   '
    [ "$status" -eq 0 ]
}

@test "Invalid JSON payload is allowed (no crash)" {
    _run_hook 'not-json'
    [ "$status" -eq 0 ]
}

@test "Missing file_path in tool_input is allowed" {
    _run_hook '{"tool_name":"Edit","tool_input":{}}'
    [ "$status" -eq 0 ]
}
