#!/usr/bin/env bats
# test_pre_bash_guard4_shogun_to_karo.bats - Guard 4: shogun_to_karo.yaml sed/regex操作BLOCK
# cmd_reflux_insight_202607072348_kotaro: INS-20260707-151225361-ebe4対応。
# .replace(検知パターンがダブルクォート内の\エスケープバグでリテラルにマッチせず、
# python3のstr.replace()書換えが素通りしていた実装バグを修正(1行: "\.replace(" -> ".replace(")。

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

@test "sed on shogun_to_karo.yaml is BLOCKED" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"sed -i \"s/status: draft/status: pending/\" queue/shogun_to_karo.yaml"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "re.sub on shogun_to_karo.yaml is BLOCKED" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"import re; content=open('"'"'queue/shogun_to_karo.yaml'"'"').read(); content=re.sub('"'"'status: draft'"'"','"'"'status: pending'"'"',content); open('"'"'queue/shogun_to_karo.yaml'"'"','"'"'w'"'"').write(content)\""}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "awk on shogun_to_karo.yaml is BLOCKED" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"awk \"{gsub(/status: draft/,\\\"status: pending\\\")}1\" queue/shogun_to_karo.yaml"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "python3 str.replace() on shogun_to_karo.yaml is BLOCKED (regression: was silently allowed before fix)" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"content=open('"'"'queue/shogun_to_karo.yaml'"'"').read(); content=content.replace('"'"'status: draft'"'"','"'"'status: pending'"'"'); open('"'"'queue/shogun_to_karo.yaml'"'"','"'"'w'"'"').write(content)\""}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

# --- ALLOW cases ---

@test "unrelated python3 command is allowed" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"print(1+1)\""}}'
    [ "$status" -eq 0 ]
}

@test "grep mentioning shogun_to_karo.yaml is allowed" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"grep -n status queue/shogun_to_karo.yaml"}}'
    [ "$status" -eq 0 ]
}

@test "cat of shogun_to_karo.yaml is allowed" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"cat queue/shogun_to_karo.yaml"}}'
    [ "$status" -eq 0 ]
}
