#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
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
