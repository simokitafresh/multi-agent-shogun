#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export HOOK="$PROJECT_ROOT/.claude/hooks/pre-bash-combined.sh"
}

run_payload() {
    local command="$1"
    HOOK_PAYLOAD="$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command")" \
        run bash "$HOOK"
}

@test "queue task Python read-only open is allowed" {
    run_payload "python3 -c \"import yaml; print(yaml.safe_load(open('queue/tasks/hayate.yaml')))\""
    [ "$status" -eq 0 ]
}

@test "queue task Python explicit read mode is allowed" {
    run_payload "python3 -c \"import yaml; print(yaml.safe_load(open('queue/tasks/hayate.yaml', 'r')))\""
    [ "$status" -eq 0 ]
}

@test "queue task Python mutating open modes are blocked" {
    local mode
    for mode in w a x r+ w+ a+ x+; do
        run_payload "python3 -c \"open('queue/tasks/hayate.yaml', '$mode')\""
        [ "$status" -eq 2 ]
    done
}

@test "queue task pathlib write helpers are blocked" {
    run_payload "python3 -c \"from pathlib import Path; Path('queue/tasks/hayate.yaml').write_text('x')\""
    [ "$status" -eq 2 ]
    run_payload "python3 -c \"from pathlib import Path; Path('queue/tasks/hayate.yaml').write_bytes(b'x')\""
    [ "$status" -eq 2 ]
}

@test "queue task shell mutation paths remain blocked" {
    local command
    for command in \
        "echo x > queue/tasks/hayate.yaml" \
        "echo x | tee queue/tasks/hayate.yaml" \
        "sed -i 's/a/b/' queue/tasks/hayate.yaml"; do
        run_payload "$command"
        [ "$status" -eq 2 ]
    done
}
