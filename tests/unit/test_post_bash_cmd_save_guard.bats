#!/usr/bin/env bats
# test_necessity: cmd_save/cmd_publish BLOCK guidance is injected only for a direct bash execution whose non-zero result contains a BLOCK record.
# regression_justification: filename references and stale BLOCK text previously caused two false-positive injections.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    HOOK="$PROJECT_ROOT/.claude/hooks/post-bash-combined.sh"
}

run_hook() {
    run env HOOK_PAYLOAD="$1" bash "$HOOK"
}

@test "filename reference plus BLOCK output does not inject" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"sed -n 1,20p scripts/cmd_save.sh"},"tool_result":{"exit_code":0,"stdout":"BLOCK: old cmd_save.sh log"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "successful cmd_publish plus stale BLOCK output does not inject" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"bash scripts/cmd_publish.sh cmd_4098"},"tool_result":{"exit_code":0,"stdout":"published\nBLOCK: older failure"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "direct bash cmd_save BLOCK result injects guidance" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"bash scripts/cmd_save.sh cmd_4098"},"tool_result":{"exit_code":1,"stderr":"BLOCK: acceptance criteria missing"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'cmd_save.sh BLOCK'* ]]
    [[ "$output" == *'BLOCK: acceptance criteria missing'* ]]
}

@test "direct env bash cmd_publish BLOCK result injects guidance" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"/usr/bin/env bash scripts/cmd_publish.sh cmd_4098"},"tool_result":{"exit_code":2,"stderr":"BLOCK: publish denied"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'cmd_save.sh BLOCK'* ]]
}

@test "nonzero execution without BLOCK record does not inject" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"bash scripts/cmd_save.sh cmd_4098"},"tool_result":{"exit_code":1,"stderr":"unexpected failure"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
