#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    HOOK="$ROOT/.claude/hooks/pre-bash-combined.sh"
}

@test "production hook decodes JSON escaped newlines before heavy classification" {
    command="bats tests/unit/test_heavy_job_classifier_newline.bats
python3 -c 'print(1)'
git diff --check"
    payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command")"

    run env HOOK_PAYLOAD="$payload" BATS_TEST_FILENAME="$BATS_TEST_FILENAME" bash "$HOOK"
    [ "$status" -eq 0 ]
}

@test "newline separates a filtered single-file bats command from later git commands" {
    command="bats tests/unit/test_ninja_monitor_clear_guard.bats --filter 'memory DB report_received'
bash -n scripts/ninja_monitor.sh
git add scripts/ninja_monitor.sh
git commit -m 'fix infra'"

    run heavy_job_classify "$command"
    [ "$status" -eq 0 ]
    [ "$output" = "light" ]
}

@test "newline-separated multi-file bats segment remains heavy" {
    command="git status
bats tests/unit/test_a.bats tests/unit/test_b.bats
git status"

    run heavy_job_classify "$command"
    [ "$status" -eq 0 ]
    [ "$output" = "heavy" ]
}
