#!/usr/bin/env bats
# test_pre_bash_wf_runner_block.bats - Guard 8: wf_runner.py BLOCK (LG025)

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/.claude/hooks/pre-bash-combined.sh"
    [ -f "$HOOK_SCRIPT" ] || return 1
}

_run_hook() {
    local payload="$1"
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK_SCRIPT"
}

# --- DENY cases ---

@test "wf_runner.py direct execution is BLOCKED" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"python3 outputs/scripts/wf_runner.py --csv-dir foo"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
    [[ "$output" == *"wf_runner"* ]]
    [[ "$output" == *"l1_alm_wf_engine.py"* ]]
}

@test "wf_runner.py with cd prefix is BLOCKED" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"cd /mnt/c/Python_app/DM-signal && python3 outputs/scripts/wf_runner.py --workers 2"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

# --- ALLOW cases ---

@test "l1_alm_wf_engine.py is allowed" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"python3 outputs/scripts/l1_alm_wf_engine.py --csv foo.csv"}}'
    [ "$status" -eq 0 ]
}

@test "normal python3 command is allowed" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"print(1+1)\""}}'
    [ "$status" -eq 0 ]
}

@test "inbox_write mentioning wf_runner.py in message is allowed" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"bash scripts/inbox_write.sh karo \"GP-179 wf_runner.py BLOCK hook完了\" analysis_result gunshi"}}'
    [ "$status" -eq 0 ]
}

@test "grep mentioning wf_runner.py is allowed" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"grep wf_runner.py docs/research/design.md"}}'
    [ "$status" -eq 0 ]
}
