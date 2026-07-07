#!/usr/bin/env bats
# Verifies Bash direct writes to logs/karo_workarounds.yaml are denied.

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/.claude/hooks/pre-bash-combined.sh"
    [ -f "$HOOK_SCRIPT" ] || return 1
}

_run_hook() {
    local cmd="$1"
    local payload
    payload="$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd")"
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK_SCRIPT"
}

@test "redirect append to karo_workarounds.yaml is denied" {
    _run_hook "echo '- cmd_id: cmd_bad' >> logs/karo_workarounds.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
    [[ "$output" == *"karo_workaround_log.sh"* ]]
}

@test "tee to karo_workarounds.yaml is denied" {
    _run_hook "echo test | tee logs/karo_workarounds.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "sed in-place edit to karo_workarounds.yaml is denied" {
    _run_hook "sed -i 's/brainwash_check:.*/brainwash_check:/' logs/karo_workarounds.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "awk rewrite of karo_workarounds.yaml is denied" {
    _run_hook "awk '{print}' logs/karo_workarounds.yaml > /tmp/karo_workarounds.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "yaml_field_set on karo_workarounds.yaml is denied" {
    _run_hook "bash scripts/lib/yaml_field_set.sh logs/karo_workarounds.yaml cmd_test brainwash_check ''"
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "karo_workaround_log.sh is allowed" {
    _run_hook "KARO_WA_BRAINWASH_CHECK='洗脳#2: 0→1件 PASS' bash scripts/karo_workaround_log.sh cmd_test hayate issue root report_yaml_format"
    [ "$status" -eq 0 ]
}

