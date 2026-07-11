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

setup_stage_fixture() {
    export GA228_STAGE_GUARD_REPO
    GA228_STAGE_GUARD_REPO="$(mktemp -d "$BATS_TEST_TMPDIR/ga228_stage.XXXXXX")"
    mkdir -p "$GA228_STAGE_GUARD_REPO/queue/tasks" "$GA228_STAGE_GUARD_REPO/context" "$GA228_STAGE_GUARD_REPO/scripts"
    (
        cd "$GA228_STAGE_GUARD_REPO"
        git init -q
        git config user.email test@example.com
        git config user.name 'Stage Guard Test'
        printf 'task: {status: idle}\n' > queue/tasks/hayate.yaml
        printf '# context\n' > context/example.md
        printf '#!/usr/bin/env bash\n' > scripts/example.sh
        git add queue/tasks/hayate.yaml context/example.md scripts/example.sh
        git commit -qm initial
        printf 'task: {status: in_progress}\n' > queue/tasks/hayate.yaml
        printf '# changed context\n' > context/example.md
        printf '#!/usr/bin/env bash\necho changed\n' > scripts/example.sh
    )
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

@test "GA-228 blocks git add before task YAML and context are mixed in stage" {
    setup_stage_fixture
    run_payload "git add queue/tasks/hayate.yaml context/example.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(GA-228)"* ]]
    [[ "$output" == *"context/example.md"* ]]
    run bash -c 'git -C "$1" diff --cached --quiet' _ "$GA228_STAGE_GUARD_REPO"
    [ "$status" -eq 0 ]
}

@test "GA-228 blocks a chained git add that would create the same mixed stage" {
    setup_stage_fixture
    run_payload "git add queue/tasks/hayate.yaml && git add context/example.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(GA-228)"* ]]
    run bash -c 'git -C "$1" diff --cached --quiet' _ "$GA228_STAGE_GUARD_REPO"
    [ "$status" -eq 0 ]
}

@test "GA-228 allows task YAML alone and operational YAML combinations" {
    setup_stage_fixture
    mkdir -p "$GA228_STAGE_GUARD_REPO/queue/reports" "$GA228_STAGE_GUARD_REPO/logs"
    printf 'status: pending\n' > "$GA228_STAGE_GUARD_REPO/queue/reports/hayate.yaml"
    printf '[]\n' > "$GA228_STAGE_GUARD_REPO/logs/hook_failures.yaml"
    run_payload "git add queue/tasks/hayate.yaml queue/reports/hayate.yaml logs/hook_failures.yaml"
    [ "$status" -eq 0 ]
}

@test "GA-228 allows a normal implementation-only git add" {
    setup_stage_fixture
    run_payload "git add scripts/example.sh"
    [ "$status" -eq 0 ]
}
